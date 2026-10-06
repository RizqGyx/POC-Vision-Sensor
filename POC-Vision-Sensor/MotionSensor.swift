#if os(iOS)
import CoreMotion
import Foundation

final class MotionSensor {
    private let manager = CMMotionManager()
    var onPacket: ((MotionPacket) -> Void)?
    func start() {
        guard manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let motion else { return }
            let a = motion.userAcceleration, r = motion.rotationRate, g = motion.gravity, attitude = motion.attitude
            let accelerationMagnitude = sqrt(a.x * a.x + a.y * a.y + a.z * a.z)
            let rotationMagnitude = sqrt(r.x * r.x + r.y * r.y + r.z * r.z)
            let gravityMagnitude = sqrt(g.x * g.x + g.y * g.y + g.z * g.z)
            let gravityProjection = gravityMagnitude > 0.001 ? (a.x * g.x + a.y * g.y + a.z * g.z) / gravityMagnitude : 0
            // Positive means acceleration opposite gravity (up); horizontal is orientation-independent.
            let verticalAcceleration = -gravityProjection
            let horizontalAcceleration = sqrt(max(0, accelerationMagnitude * accelerationMagnitude - gravityProjection * gravityProjection))
            self?.onPacket?(MotionPacket(timestamp: Date(), userAccelerationX: a.x, userAccelerationY: a.y, userAccelerationZ: a.z, rotationX: r.x, rotationY: r.y, rotationZ: r.z, roll: attitude.roll, pitch: attitude.pitch, yaw: attitude.yaw, gravityX: g.x, gravityY: g.y, gravityZ: g.z, accelerationMagnitude: accelerationMagnitude, rotationMagnitude: rotationMagnitude, verticalAcceleration: verticalAcceleration, horizontalAcceleration: horizontalAcceleration))
        }
    }
    func stop() { manager.stopDeviceMotionUpdates() }
}
#endif
