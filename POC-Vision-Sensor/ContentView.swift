//
//  ContentView.swift
//  POC-Vision-Sensor
//
//  Created by Muhammad Rizki on 06/10/26.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var coordinator: TrialCoordinator

    var body: some View {
        Group {
            #if os(macOS)
            MacHostView()
            #else
            CompanionView()
            #endif
        }
        .task { coordinator.startServices() }
        .onDisappear { coordinator.stopServices() }
    }
}
