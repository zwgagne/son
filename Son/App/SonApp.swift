import SwiftUI

@main
struct SonApp: App {
    @StateObject private var devices = AudioDeviceService()
    @StateObject private var applications = ApplicationAudioService()

    var body: some Scene {
        MenuBarExtra("son", systemImage: devices.outputMuted ? "speaker.slash.fill" : "speaker.wave.2.fill") {
            AudioPopoverView()
                .environmentObject(devices)
                .environmentObject(applications)
                .onAppear {
                    applications.useOutputDevice(devices.selectedOutputDevice)
                    devices.refresh()
                    applications.refresh()
                }
                .onChange(of: devices.defaultOutputID) { _, _ in
                    applications.useOutputDevice(devices.selectedOutputDevice)
                }
        }
        .menuBarExtraStyle(.window)
    }
}
