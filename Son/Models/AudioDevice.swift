import CoreAudio

struct AudioDevice: Identifiable, Equatable {
    enum Direction {
        case input
        case output
    }

    let id: AudioObjectID
    let uid: String
    let name: String
    let direction: Direction
}
