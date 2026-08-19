import CoreAudio
import SwiftUI

struct DeviceMenuRow: View {
    let title: String
    let systemImage: String
    let devices: [AudioDevice]
    let selectedID: AudioObjectID
    let onSelect: (AudioDevice) -> Void

    private var selectedName: String {
        devices.first { $0.id == selectedID }?.name ?? "Aucun"
    }

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 18)

            Text(title)
                .font(.subheadline)

            Spacer(minLength: 8)

            Menu {
                ForEach(devices) { device in
                    Button {
                        onSelect(device)
                    } label: {
                        if device.id == selectedID {
                            Label(device.name, systemImage: "checkmark")
                        } else {
                            Text(device.name)
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(selectedName)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }
}
