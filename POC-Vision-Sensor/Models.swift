import Foundation

enum Movement: String, CaseIterable, Codable, Identifiable {
    case left = "LEFT", right = "RIGHT", jump = "JUMP", duck = "DUCK"
    var id: String { rawValue }
}

enum DetectionState: String { case idle = "IDLE", ready = "READY", cueShown = "CUE SHOWN", waitingForMovement = "WAITING FOR MOVEMENT", movementCandidate = "MOVEMENT CANDIDATE", confirmingMovement = "CONFIRMING MOVEMENT", result = "RESULT" }
enum TrialResult: String, Codable { case success = "SUCCESS", wrong = "WRONG MOVEMENT", miss = "MISS" }
enum TestMode: String, CaseIterable, Codable, Identifiable { case visionOnly = "Vision Only", visionAndPhone = "Vision + iPhone"; var id: String { rawValue } }
enum SessionKind: String, CaseIterable, Identifiable { case single = "Single movement", random = "Random session"; var id: String { rawValue } }
enum PhonePlacement: String, CaseIterable, Codable, Identifiable { case waistCenter = "Waist Center", abdomen = "Abdomen", chest = "Chest", rightPocket = "Right Pocket", leftPocket = "Left Pocket"; var id: String { rawValue } }

struct MotionPacket: Codable {
    var timestamp: Date
    var userAccelerationX: Double; var userAccelerationY: Double; var userAccelerationZ: Double
    var rotationX: Double; var rotationY: Double; var rotationZ: Double
    var roll: Double; var pitch: Double; var yaw: Double
    var gravityX: Double; var gravityY: Double; var gravityZ: Double
    var accelerationMagnitude: Double; var rotationMagnitude: Double
    /// User acceleration projected onto the gravity axis and its perpendicular plane.
    var verticalAcceleration: Double; var horizontalAcceleration: Double
}

struct VisionSample { var timestamp = Date(); var centerX: CGFloat; var centerY: CGFloat; var confidence: Float }
struct TrialRecord: Identifiable, Codable { var id = UUID(); var expected: Movement; var detected: Movement?; var result: TrialResult; var testMode: TestMode; var cueTimestamp: Date; var detectionTimestamp: Date? }
