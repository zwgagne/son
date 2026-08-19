import AppKit
import SwiftUI

struct AudioPopoverView: View {
    @EnvironmentObject private var devices: AudioDeviceService
    @EnvironmentObject private var applications: ApplicationAudioService

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("son")
                .font(.headline)

            MasterVolumeRow()

            if !applications.applications.isEmpty {
                Divider()
                ForEach(applications.applications) { application in
                    ApplicationVolumeRow(application: application)
                }
            }

            Divider()

            DeviceMenuRow(
                title: "Sortie",
                systemImage: "speaker.wave.2",
                devices: devices.outputDevices,
                selectedID: devices.defaultOutputID,
                onSelect: devices.selectOutput
            )

            DeviceMenuRow(
                title: "Entrée",
                systemImage: "mic",
                devices: devices.inputDevices,
                selectedID: devices.defaultInputID,
                onSelect: devices.selectInput
            )

            if let error = applications.lastError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "power")
                        .font(.system(size: 10, weight: .medium))
                        .frame(width: 12)

                    Text("Quitter son")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("q")
        }
        .padding(14)
        .frame(width: 300)
    }
}
private struct MasterVolumeRow: View {
    @EnvironmentObject private var devices: AudioDeviceService

    var body: some View {
        HStack(spacing: 10) {
            Button(action: devices.toggleOutputMute) {
                Image(systemName: devices.outputMuted || devices.outputVolume == 0
                      ? "speaker.slash.fill"
                      : "speaker.fill")
                    .frame(width: 16)
            }
            .buttonStyle(.plain)
            .help(devices.outputMuted ? "Réactiver le son" : "Couper le son")

            Slider(
                value: Binding(
                    get: { Double(devices.outputVolume) },
                    set: { devices.setOutputVolume(Float($0)) }
                ),
                in: 0...1
            )
            .disabled(!devices.canSetOutputVolume)

            Image(systemName: "speaker.wave.3.fill")
                .foregroundStyle(.secondary)
        }
    }
}
