//
//  POC_Vision_SensorApp.swift
//  POC-Vision-Sensor
//
//  Created by Muhammad Rizki on 06/10/26.
//

import SwiftUI

@main
struct POCVisionSensorApp: App {
    @StateObject private var coordinator = TrialCoordinator()
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(coordinator)
        }
    }
}
