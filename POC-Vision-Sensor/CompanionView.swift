#if os(iOS)
import SwiftUI

struct CompanionView: View {
    @EnvironmentObject private var trial: TrialCoordinator
    @State private var placement: PhonePlacement = .waistCenter
    var body: some View {
        NavigationStack {
            Form {
                Section("Connection") { Label(trial.phoneConnected ? "Connected to Vision Host" : "Searching for Mac host", systemImage: "dot.radiowaves.left.and.right").foregroundStyle(trial.phoneConnected ? .green : .primary); Text("Keep this app open while testing.").font(.footnote).foregroundStyle(.secondary) }
                Section("Sensor placement") { Picker("Placement", selection: $placement) { ForEach(PhonePlacement.allCases) { Text($0.rawValue).tag($0) } }; Text("First experiment: Waist Center. The phone confirms motion only; it never assigns LEFT, RIGHT, JUMP, or DUCK.").font(.footnote).foregroundStyle(.secondary) }
                Section("Live motion") { LabeledContent("Acceleration magnitude", value: String(format: "%.3f g", trial.latestMotion?.accelerationMagnitude ?? 0.0)); LabeledContent("Rotation magnitude", value: String(format: "%.3f rad/s", trial.latestMotion?.rotationMagnitude ?? 0.0)) }
            }.navigationTitle("Motion Companion")
        }
    }
}

#endif
