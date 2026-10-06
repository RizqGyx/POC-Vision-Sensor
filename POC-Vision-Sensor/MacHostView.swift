#if os(macOS)
import SwiftUI
import AppKit

struct MacHostView: View {
    @EnvironmentObject private var trial: TrialCoordinator
    @State private var debugOpen = false

    var body: some View {
        HStack(spacing: 0) {
            controls.frame(width: 255).padding(20).background(Color(nsColor: .windowBackgroundColor))
            Divider()
            VStack(spacing: 14) {
                HStack { Label(trial.phoneConnected ? "iPhone Connected" : "No iPhone Connected", systemImage: trial.phoneConnected ? "iphone.gen3.radiowaves.left.and.right" : "iphone.slash").foregroundStyle(trial.phoneConnected ? .green : .secondary); Spacer(); Text(trial.mode.rawValue).foregroundStyle(.secondary) }
                camera
                VStack(spacing: 6) {
                    Text(trial.state.rawValue).font(.caption).foregroundStyle(.secondary)
                    Text(trial.cue?.rawValue ?? "READY").font(.system(size: 58, weight: .bold, design: .rounded))
                    if let detected = trial.detected { Text("Detected: \(detected.rawValue)").font(.title3) }
                    if let result = trial.result { Text(result.rawValue).font(.title2.bold()).foregroundStyle(result == .success ? .green : .orange) }
                    else { Text(trial.visionStatus).font(.headline).foregroundStyle(.secondary) }
                    if trial.mode == .visionAndPhone { Text(trial.phoneSupport).font(.caption.weight(.semibold)).foregroundStyle(trial.phoneSupport == "IMU SUPPORT" ? .green : .secondary) }
                }
                Button(trial.isCalibrating ? "Calibrating…" : "Start Trial") { trial.beginSession() }.buttonStyle(.borderedProminent).disabled(trial.isCalibrating)
                DisclosureGroup("Debug panel", isExpanded: $debugOpen) { DebugPanel() }.frame(maxWidth: .infinity, alignment: .leading)
            }.padding(20).frame(minWidth: 600)
        }.frame(minWidth: 880, minHeight: 650)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Movement Detection POC").font(.title2.bold())
            Picker("Mode", selection: $trial.mode) { ForEach(TestMode.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.radioGroup)
            Picker("Test", selection: $trial.sessionKind) { ForEach(SessionKind.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
            if trial.sessionKind == .single { Picker("Movement", selection: $trial.selectedMovement) { ForEach(Movement.allCases) { Text($0.rawValue).tag($0) } } }
            else { Stepper("\(trial.randomTrialCount) trials", value: $trial.randomTrialCount, in: 1...50) }
            Divider()
            Button("Calibrate (2 sec)") { trial.calibrate() }.disabled(trial.isCalibrating)
            Text(trial.baseline == nil ? "Calibration required" : "Baseline ready").font(.caption).foregroundStyle(trial.baseline == nil ? .orange : .green)
            Spacer()
            Text("Session: \(trial.records.count) trials").font(.caption)
            Button("Export CSV") { exportCSV(trial.csv()) }.disabled(trial.records.isEmpty)
            Button("Reset Session", role: .destructive) { trial.resetSession() }.disabled(trial.records.isEmpty)
        }
    }
    private var camera: some View {
        ZStack {
            CameraPreview(camera: trial.camera).clipShape(RoundedRectangle(cornerRadius: 14))
            GeometryReader { proxy in
                ForEach(trial.camera.skeletonSegments) { segment in
                    Path { path in
                        path.move(to: CGPoint(x: segment.start.x * proxy.size.width, y: (1 - segment.start.y) * proxy.size.height))
                        path.addLine(to: CGPoint(x: segment.end.x * proxy.size.width, y: (1 - segment.end.y) * proxy.size.height))
                    }
                    .stroke(.green, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                }
                ForEach(Array(trial.camera.skeleton.enumerated()), id: \.offset) { _, point in Circle().fill(.green).frame(width: 9, height: 9).position(x: point.x * proxy.size.width, y: (1 - point.y) * proxy.size.height) }
            }
        }.aspectRatio(16 / 9, contentMode: .fit).background(.black).clipShape(RoundedRectangle(cornerRadius: 14))
    }
    private func exportCSV(_ text: String) { let panel = NSSavePanel(); panel.nameFieldStringValue = "movement-trials.csv"; guard panel.runModal() == .OK, let url = panel.url else { return }; try? text.write(to: url, atomically: true, encoding: .utf8) }
}

private struct DebugPanel: View {
    @EnvironmentObject private var trial: TrialCoordinator
    var body: some View {
        let dx = (trial.lastVisionSample?.centerX ?? 0) - (trial.baseline?.centerX ?? 0), dy = (trial.lastVisionSample?.centerY ?? 0) - (trial.baseline?.centerY ?? 0)
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 5) {
            row("Body center", "\(value(trial.lastVisionSample?.centerX)), \(value(trial.lastVisionSample?.centerY))")
            row("Baseline", "\(value(trial.baseline?.centerX)), \(value(trial.baseline?.centerY))")
            row("Displacement", "x \(value(dx)) · y \(value(dy))")
            row("Threshold", "lateral \(value(trial.lateralThreshold)) · vertical \(value(trial.verticalThreshold))")
            row("Candidate", trial.candidate?.rawValue ?? "—")
            row("iPhone packets", "\(trial.packetsReceived)")
            row("iPhone onset", trial.phoneMotionDetected ? "MOTION DETECTED" : "waiting")
            row("Acceleration", value(trial.latestMotion?.accelerationMagnitude))
            row("Rotation", value(trial.latestMotion?.rotationMagnitude))
            row("Vertical peak", value(trial.phoneVerticalPeak))
            row("Horizontal peak", value(trial.phoneHorizontalPeak))
        }.font(.caption.monospaced())
    }
    @ViewBuilder private func row(_ key: String, _ value: String) -> some View { GridRow { Text(key).foregroundStyle(.secondary); Text(value) } }
    private func value(_ number: CGFloat?) -> String { number.map { String(format: "%.3f", Double($0)) } ?? "—" }
    private func value(_ number: Double?) -> String { number.map { String(format: "%.3f", $0) } ?? "—" }
}
#endif
