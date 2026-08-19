import XCTest
@testable import Son

final class VolumeStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "VolumeStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testDefaultVolumeIsFull() {
        XCTAssertEqual(VolumeStore(defaults: defaults).volume(for: "music"), 1)
    }

    func testVolumeIsPersisted() {
        let store = VolumeStore(defaults: defaults)
        store.setVolume(0.35, for: "teams")
        XCTAssertEqual(store.volume(for: "teams"), 0.35, accuracy: 0.001)
    }

    func testVolumeIsClamped() {
        let store = VolumeStore(defaults: defaults)
        store.setVolume(2, for: "music")
        XCTAssertEqual(store.volume(for: "music"), 1)
        store.setVolume(-1, for: "music")
        XCTAssertEqual(store.volume(for: "music"), 0)
    }
}
