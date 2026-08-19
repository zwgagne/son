import AppKit
import CoreAudio

struct AudioApplication: Identifiable {
    let id: String
    let name: String
    let icon: NSImage?
    let processObjectIDs: [AudioObjectID]
    let processIdentifiers: [pid_t]
    var volume: Float
}
