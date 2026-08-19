import SwiftUI

struct ApplicationVolumeRow: View {
    @EnvironmentObject private var audio: ApplicationAudioService
    let application: AudioApplication

    var body: some View {
        HStack(spacing: 9) {
            Group {
                if let icon = application.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: "app.fill")
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 18, height: 18)

            Text(application.name)
                .font(.subheadline)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 74, alignment: .leading)

            Slider(
                value: Binding(
                    get: { Double(application.volume) },
                    set: { audio.setVolume(Float($0), for: application.id) }
                ),
                in: 0...1
            )

            Button {
                audio.toggleMute(for: application.id)
            } label: {
                Image(systemName: application.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .frame(width: 17)
            }
            .buttonStyle(.plain)
            .help(application.volume == 0 ? "Réactiver \(application.name)" : "Couper \(application.name)")
        }
    }
}
