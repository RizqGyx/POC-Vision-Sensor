#if os(macOS)
import AVFoundation
import AppKit
import Vision
import SwiftUI

final class VisionCamera: NSObject, ObservableObject {
    let session = AVCaptureSession()
    var onSample: ((VisionSample) -> Void)?
    @Published var skeleton: [CGPoint] = []
    @Published var skeletonSegments: [SkeletonSegment] = []
    private let queue = DispatchQueue(label: "vision.camera.queue")
    private let request = VNDetectHumanBodyPoseRequest()

    func start() {
        queue.async {
            guard self.session.inputs.isEmpty else { self.session.startRunning(); return }
            guard let device = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: device) else { return }
            self.session.beginConfiguration(); self.session.sessionPreset = .high
            guard self.session.canAddInput(input) else { self.session.commitConfiguration(); return }; self.session.addInput(input)
            let output = AVCaptureVideoDataOutput(); output.setSampleBufferDelegate(self, queue: self.queue)
            guard self.session.canAddOutput(output) else { self.session.commitConfiguration(); return }; self.session.addOutput(output)
            self.session.commitConfiguration(); self.session.startRunning()
        }
    }
    func stop() { queue.async { self.session.stopRunning() } }
}

extension VisionCamera: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from _: AVCaptureConnection) {
        let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .up)
        do { try handler.perform([request]) } catch { return }
        guard let observation = request.results?.first else { return }
        let joints: [VNHumanBodyPoseObservation.JointName] = [.leftHip, .rightHip, .leftShoulder, .rightShoulder, .leftKnee, .rightKnee, .leftAnkle, .rightAnkle]
        var points: [CGPoint] = []; var hips: [VNRecognizedPoint] = []
        var recognized: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
        for joint in joints {
            guard let point = try? observation.recognizedPoint(joint), point.confidence >= 0.2 else { continue }
            points.append(CGPoint(x: point.location.x, y: point.location.y))
            recognized[joint] = CGPoint(x: point.location.x, y: point.location.y)
            if joint == .leftHip || joint == .rightHip { hips.append(point) }
        }
        guard hips.count == 2 else { return }
        let x = (hips[0].location.x + hips[1].location.x) / 2, y = (hips[0].location.y + hips[1].location.y) / 2
        let confidence = (hips[0].confidence + hips[1].confidence) / 2
        let links: [(VNHumanBodyPoseObservation.JointName, VNHumanBodyPoseObservation.JointName)] = [
            (.leftShoulder, .rightShoulder), (.leftShoulder, .leftHip), (.rightShoulder, .rightHip),
            (.leftHip, .rightHip), (.leftHip, .leftKnee), (.leftKnee, .leftAnkle),
            (.rightHip, .rightKnee), (.rightKnee, .rightAnkle)
        ]
        let segments = links.compactMap { start, end -> SkeletonSegment? in
            guard let startPoint = recognized[start], let endPoint = recognized[end] else { return nil }
            return SkeletonSegment(start: startPoint, end: endPoint)
        }
        DispatchQueue.main.async { self.skeleton = points; self.skeletonSegments = segments; self.onSample?(VisionSample(centerX: x, centerY: y, confidence: confidence)) }
    }
}

struct SkeletonSegment: Identifiable {
    let id = UUID()
    let start: CGPoint
    let end: CGPoint
}

struct CameraPreview: NSViewRepresentable {
    @ObservedObject var camera: VisionCamera
    func makeNSView(context: Context) -> PreviewView { let view = PreviewView(); view.previewLayer.session = camera.session; return view }
    func updateNSView(_: PreviewView, context _: Context) {}
}
final class PreviewView: NSView {
    /// Keep an explicit reference: NSView does not create a backing layer until
    /// `wantsLayer` is enabled, so force-casting `layer` can crash at launch.
    let previewLayer = AVCaptureVideoPreviewLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = previewLayer
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer = previewLayer
    }

    override func layout() {
        super.layout()
        previewLayer.frame = bounds
    }
}
#endif
