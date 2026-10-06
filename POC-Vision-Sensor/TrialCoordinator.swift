import Foundation
import SwiftUI
import Combine

@MainActor
final class TrialCoordinator: ObservableObject {
    @Published var state: DetectionState = .idle
    @Published var selectedMovement: Movement = .left
    @Published var cue: Movement?
    @Published var detected: Movement?
    @Published var result: TrialResult?
    @Published var mode: TestMode = .visionOnly
    @Published var sessionKind: SessionKind = .single
    @Published var randomTrialCount = 10
    @Published var records: [TrialRecord] = []
    @Published var baseline: VisionSample?
    @Published var lastVisionSample: VisionSample?
    @Published var candidate: Movement?
    @Published var visionStatus = "BODY NOT DETECTED"
    @Published var isCalibrating = false
    @Published var phoneConnected = false
    @Published var latestMotion: MotionPacket?
    @Published var packetsReceived = 0
    @Published var phoneMotionDetected = false
    @Published var responseWindow: Double = 2
    @Published var observationWindow: Double = 0.4
    @Published var lateralThreshold: CGFloat = 0.09
    @Published var verticalThreshold: CGFloat = 0.08
    @Published var phoneAccelerationThreshold: Double = 0.12
    @Published var phoneRotationThreshold: Double = 0.60
    @Published var phoneVerticalPeak: Double = 0
    @Published var phoneHorizontalPeak: Double = 0
    @Published var phoneSupport = "—"

    let connectivity = PhoneConnectivity()
    #if os(macOS)
    let camera = VisionCamera()
    #else
    let motion = MotionSensor()
    #endif
    private var calibrationSamples: [VisionSample] = []
    private var observationSamples: [VisionSample] = []
    private var runningTask: Task<Void, Never>?
    private var sessionRemaining = 0
    private var lastPhoneMotionOnset: Date?

    func startServices() {
        connectivity.onConnectionChanged = { [weak self] connected in Task { @MainActor in self?.phoneConnected = connected } }
        #if os(macOS)
        connectivity.onPacket = { [weak self] packet in Task { @MainActor in self?.receive(packet) } }
        connectivity.startHost()
        camera.onSample = { [weak self] sample in Task { @MainActor in self?.receive(sample) } }
        camera.start()
        #else
        connectivity.startCompanion()
        motion.onPacket = { [weak self] packet in
            Task { @MainActor in
                self?.latestMotion = packet
                self?.connectivity.send(packet)
            }
        }
        motion.start()
        #endif
    }

    func stopServices() {
        runningTask?.cancel()
        connectivity.stop()
        #if os(macOS)
        camera.stop()
        #else
        motion.stop()
        #endif
    }

    func calibrate() {
        guard !isCalibrating else { return }
        isCalibrating = true; calibrationSamples = []; visionStatus = "Stand neutral for 2 seconds"
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !calibrationSamples.isEmpty else { isCalibrating = false; visionStatus = "BODY NOT DETECTED"; return }
            let x = calibrationSamples.map(\.centerX).reduce(0, +) / CGFloat(calibrationSamples.count)
            let y = calibrationSamples.map(\.centerY).reduce(0, +) / CGFloat(calibrationSamples.count)
            baseline = VisionSample(centerX: x, centerY: y, confidence: calibrationSamples.map(\.confidence).reduce(0, +) / Float(calibrationSamples.count))
            isCalibrating = false; state = .ready; visionStatus = "CALIBRATED"
        }
    }

    func beginSession() {
        sessionRemaining = sessionKind == .random ? randomTrialCount : 1
        startTrial()
    }

    private func startTrial() {
        guard baseline != nil else { calibrate(); return }
        runningTask?.cancel()
        runningTask = Task { @MainActor in
            result = nil; detected = nil; candidate = nil; cue = nil; state = .ready
            for number in stride(from: 3, through: 1, by: -1) { visionStatus = "GET READY · \(number)"; try? await Task.sleep(for: .seconds(1)); guard !Task.isCancelled else { return } }
            try? await Task.sleep(for: .seconds(Double.random(in: 0.5...1.5)))
            cue = sessionKind == .single ? selectedMovement : Movement.allCases.randomElement()!
            state = .cueShown; visionStatus = "MOVE NOW"; observationSamples = []; resetPhoneEvidence()
            try? await Task.sleep(for: .milliseconds(150)); guard !Task.isCancelled else { return }
            state = .waitingForMovement
            try? await Task.sleep(for: .seconds(responseWindow)); guard !Task.isCancelled, state != .result else { return }
            finish(detected: nil)
        }
    }

    func receive(_ sample: VisionSample) {
        lastVisionSample = sample
        guard sample.confidence >= 0.35 else { visionStatus = "LOW CONFIDENCE"; return }
        visionStatus = isCalibrating ? "CALIBRATING" : "BODY DETECTED"
        if isCalibrating { calibrationSamples.append(sample); return }
        guard state == .waitingForMovement || state == .movementCandidate, let base = baseline else { return }
        let dx = sample.centerX - base.centerX, dy = sample.centerY - base.centerY
        guard abs(dx) >= lateralThreshold || abs(dy) >= verticalThreshold else {
            if state == .movementCandidate { observationSamples.append(sample) }
            return
        }
        if state == .waitingForMovement {
            beginObservation(firstVisionSample: sample, initiatedByPhone: false)
        } else {
            // Keep every frame in the window. The decisive movement may happen
            // after a small opposite-direction preparatory motion.
            observationSamples.append(sample)
        }
    }

    private func beginObservation(firstVisionSample: VisionSample?, initiatedByPhone: Bool) {
        guard state == .waitingForMovement else { return }
        state = .movementCandidate
        observationSamples = firstVisionSample.map { [$0] } ?? []
        if initiatedByPhone { visionStatus = "IPHONE ONSET · OBSERVING VISION" }
        Task { @MainActor in
            // IMU arrives before pose displacement; grant Vision a slightly fuller window after that onset.
            try? await Task.sleep(for: .seconds(initiatedByPhone ? max(observationWindow, 0.5) : observationWindow))
            guard self.state == .movementCandidate else { return }
            self.confirmObservation()
        }
    }

    private func confirmObservation() {
        guard let base = baseline, !observationSamples.isEmpty else { return }
        state = .confirmingMovement
        let displacements = observationSamples.map { ($0.centerX - base.centerX, $0.centerY - base.centerY) }
        let leftPeak = displacements.map(\.0).min() ?? 0
        let rightPeak = displacements.map(\.0).max() ?? 0
        let duckPeak = displacements.map(\.1).min() ?? 0
        let jumpPeak = displacements.map(\.1).max() ?? 0
        let movement: Movement?
        let candidates: [(Movement, CGFloat)] = [(.left, -leftPeak), (.right, rightPeak), (.duck, -duckPeak), (.jump, jumpPeak)]
        if let dominant = candidates.max(by: { $0.1 < $1.1 }), dominant.1 >= (dominant.0 == .left || dominant.0 == .right ? lateralThreshold : verticalThreshold) {
            movement = dominant.0
        } else { movement = nil }
        candidate = movement
        if let movement {
            phoneSupport = supportDescription(for: movement)
            finish(detected: movement)
        } else { state = .waitingForMovement }
    }

    private func finish(detected movement: Movement?) {
        runningTask?.cancel(); detected = movement; state = .result
        let trialResult: TrialResult = movement == nil ? .miss : movement == cue ? .success : .wrong
        result = trialResult
        if let expected = cue { records.append(TrialRecord(expected: expected, detected: movement, result: trialResult, testMode: mode, cueTimestamp: Date(), detectionTimestamp: movement == nil ? nil : Date())) }
        visionStatus = trialResult.rawValue
        sessionRemaining -= 1
        if sessionRemaining > 0 {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.2))
                guard self.sessionRemaining > 0 else { return }
                self.startTrial()
            }
        }
    }
    private var hasRecentPhoneMotion: Bool {
        guard let lastPhoneMotionOnset else { return false }
        return Date().timeIntervalSince(lastPhoneMotionOnset) < 0.5
    }

    private func receive(_ packet: MotionPacket) {
        latestMotion = packet
        packetsReceived += 1
        let meaningful = packet.accelerationMagnitude >= phoneAccelerationThreshold || packet.rotationMagnitude >= phoneRotationThreshold
        if meaningful { lastPhoneMotionOnset = Date() }
        phoneMotionDetected = hasRecentPhoneMotion
        guard mode == .visionAndPhone else { return }
        if state == .movementCandidate {
            phoneVerticalPeak = max(phoneVerticalPeak, abs(packet.verticalAcceleration))
            phoneHorizontalPeak = max(phoneHorizontalPeak, packet.horizontalAcceleration)
        } else if state == .waitingForMovement, meaningful {
            // IMU onset reduces camera-only latency; Vision still has sole authority for movement meaning.
            resetPhoneEvidence()
            phoneVerticalPeak = abs(packet.verticalAcceleration)
            phoneHorizontalPeak = packet.horizontalAcceleration
            beginObservation(firstVisionSample: nil, initiatedByPhone: true)
        }
    }

    private func resetPhoneEvidence() { phoneVerticalPeak = 0; phoneHorizontalPeak = 0; phoneSupport = "—" }
    private func supportDescription(for movement: Movement) -> String {
        let supported: Bool
        switch movement {
        case .jump, .duck: supported = phoneVerticalPeak >= phoneAccelerationThreshold
        case .left, .right: supported = phoneHorizontalPeak >= phoneAccelerationThreshold
        }
        return supported ? "IMU SUPPORT" : "VISION ONLY EVIDENCE"
    }
    func resetSession() { records = []; result = nil; detected = nil; cue = nil; state = baseline == nil ? .idle : .ready }
    func csv() -> String {
        let formatter = ISO8601DateFormatter()
        let rows = records.map { record in
            let detected = record.detected?.rawValue ?? ""
            let timestamp = record.detectionTimestamp.map { formatter.string(from: $0) } ?? ""
            return "\(record.id.uuidString),\(record.expected.rawValue),\(detected),\(record.result.rawValue),\(record.testMode.rawValue),\(formatter.string(from: record.cueTimestamp)),\(timestamp)"
        }
        return (["trialID,expectedMovement,detectedMovement,result,testMode,cueTimestamp,detectionTimestamp"] + rows).joined(separator: "\n")
    }
}
