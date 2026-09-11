//
//  VirtualEspressoMachineApp.swift
//  VirtualEspressoMachine
//

import SwiftUI
import MeticulousProfile

@main
struct VirtualEspressoMachineApp: App {
    //    var body: some Scene {
    //        WindowGroup {
    //            BaristaHUDSimulatorView()
    //        }
    //    }
    //}
    
    // Loads recipes from your Meticulous bundle / store
    @State private var profileStore = ProfileStore()
    @State private var activeProfile: Profile?
    
    var body: some Scene {
        WindowGroup {
            ProfileConsoleView(
                profiles: profileStore.profiles,
                onSelectProfile: { profile in
                    print("Barista committed profile: \(profile.name) (ID: \(profile.id))")
                    activeProfile = profile
                    // Ready to transition to BaristaHUDView!
                },
                onCustomizeProfile: { profile in
                    print("Tweak requested for: \(profile.name)")
                }
            )
            .preferredColorScheme(.dark)
        }
    }
}
