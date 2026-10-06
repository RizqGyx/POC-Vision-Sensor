import Foundation
import Network

/// Local-only Bonjour + TCP transport, replacing deprecated MultipeerConnectivity APIs.
final class PhoneConnectivity {
    private let queue = DispatchQueue(label: "vision.motion.network")
    private let serviceType = "_visionmotion._tcp"
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var companionConnection: NWConnection?
    private var hostConnections: [NWConnection] = []
    var onConnectionChanged: ((Bool) -> Void)?
    var onPacket: ((MotionPacket) -> Void)?

    func startHost() {
        queue.async { [weak self] in
            guard let self else { return }
            do {
                let listener = try NWListener(using: .tcp, on: .any)
                listener.service = NWListener.Service(name: "Vision Host", type: self.serviceType)
                listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
                listener.stateUpdateHandler = { [weak self] state in if case .failed = state { self?.notifyConnection(false) } }
                self.listener = listener
                listener.start(queue: self.queue)
            } catch { self.notifyConnection(false) }
        }
    }

    func startCompanion() {
        queue.async { [weak self] in
            guard let self else { return }
            let browser = NWBrowser(for: .bonjour(type: self.serviceType, domain: nil), using: .tcp)
            browser.browseResultsChangedHandler = { [weak self] results, _ in
                guard let self, self.companionConnection == nil, let endpoint = results.first?.endpoint else { return }
                self.connectCompanion(to: endpoint)
            }
            browser.stateUpdateHandler = { [weak self] state in if case .failed = state { self?.notifyConnection(false) } }
            self.browser = browser
            browser.start(queue: self.queue)
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.listener?.cancel(); self.listener = nil
            self.browser?.cancel(); self.browser = nil
            self.companionConnection?.cancel(); self.companionConnection = nil
            self.hostConnections.forEach { $0.cancel() }; self.hostConnections = []
            self.notifyConnection(false)
        }
    }

    func send(_ packet: MotionPacket) {
        guard let payload = try? JSONEncoder().encode(packet), payload.count <= Int(UInt32.max) else { return }
        var size = UInt32(payload.count).bigEndian
        let header = withUnsafeBytes(of: &size) { Data($0) }
        let message = header + payload
        queue.async { [weak self] in
            guard let self else { return }
            let recipients = self.companionConnection.map { [$0] } ?? self.hostConnections
            recipients.forEach { $0.send(content: message, completion: .contentProcessed { _ in }) }
        }
    }

    private func connectCompanion(to endpoint: NWEndpoint) {
        let connection = NWConnection(to: endpoint, using: .tcp)
        companionConnection = connection
        configure(connection, isHostConnection: false)
        connection.start(queue: queue)
    }

    private func accept(_ connection: NWConnection) {
        hostConnections.append(connection)
        configure(connection, isHostConnection: true)
        connection.start(queue: queue)
    }

    private func configure(_ connection: NWConnection, isHostConnection: Bool) {
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            switch state {
            case .ready: self.notifyConnection(true); self.receiveHeader(on: connection, isHostConnection: isHostConnection)
            case .failed, .cancelled: self.remove(connection, isHostConnection: isHostConnection)
            default: break
            }
        }
    }

    private func receiveHeader(on connection: NWConnection, isHostConnection: Bool) {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, complete, error in
            guard let self, let data, data.count == 4, !complete, error == nil else { self?.remove(connection, isHostConnection: isHostConnection); return }
            let length = data.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            guard length > 0, length < 65_536 else { self.remove(connection, isHostConnection: isHostConnection); return }
            self.receiveBody(on: connection, bytes: Int(length), isHostConnection: isHostConnection)
        }
    }

    private func receiveBody(on connection: NWConnection, bytes: Int, isHostConnection: Bool) {
        connection.receive(minimumIncompleteLength: bytes, maximumLength: bytes) { [weak self] data, _, complete, error in
            guard let self, let data, data.count == bytes, !complete, error == nil else { self?.remove(connection, isHostConnection: isHostConnection); return }
            if let packet = try? JSONDecoder().decode(MotionPacket.self, from: data) { self.onPacket?(packet) }
            self.receiveHeader(on: connection, isHostConnection: isHostConnection)
        }
    }

    private func remove(_ connection: NWConnection, isHostConnection: Bool) {
        connection.cancel()
        if isHostConnection { hostConnections.removeAll { $0 === connection } }
        else if companionConnection === connection { companionConnection = nil }
        notifyConnection(companionConnection != nil || !hostConnections.isEmpty)
    }

    private func notifyConnection(_ connected: Bool) { DispatchQueue.main.async { self.onConnectionChanged?(connected) } }
}
