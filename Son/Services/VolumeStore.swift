import Foundation

final class VolumeStore {
    private let defaults: UserDefaults
    private let prefix = "application-volume."

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func volume(for applicationID: String) -> Float {
        let key = prefix + applicationID
        guard defaults.object(forKey: key) != nil else { return 1 }
        return min(max(defaults.float(forKey: key), 0), 1)
    }

    func setVolume(_ volume: Float, for applicationID: String) {
        defaults.set(min(max(volume, 0), 1), forKey: prefix + applicationID)
    }
}
