//
//  VirtualEspressoMachineApp.swift
//  VirtualEspressoMachine
//

import SwiftUI

@main
struct VirtualEspressoMachineApp: App {
    var body: some Scene {
        WindowGroup {
            TabView {
                // Tab 1: Your new Landscape Barista HUD
                BaristaHUDView()
                    .tabItem {
                        Label("Barista HUD", systemImage: "gauge.with.dots.needle.bottom.50percent")
                    }
                
                // Tab 2: Profile Catalog & Machine State
                ContentView()
                    .tabItem {
                        Label("Machine & Profiles", systemImage: "cup.and.saucer.fill")
                    }
            }
        }
    }
}
