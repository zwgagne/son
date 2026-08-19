import AudioToolbox
import CoreAudio
import Foundation

final class AudioDeviceService: ObservableObject {
    @Published private(set) var inputDevices: [AudioDevice] = []
    @Published private(set) var outputDevices: [AudioDevice] = []
    @Published private(set) var defaultInputID = kAudioObjectUnknown
    @Published private(set) var defaultOutputID = kAudioObjectUnknown
    @Published var outputVolume: Float = 1
    @Published var outputMuted = false
    @Published private(set) var canSetOutputVolume = false

    private let systemObjectID = AudioObjectID(kAudioObjectSystemObject)
    private let listenerQueue = DispatchQueue.main
    private var systemListener: AudioObjectPropertyListenerBlock?
    private var outputControlListener: AudioObjectPropertyListenerBlock?
    private var observedOutputDeviceID = kAudioObjectUnknown
    private var refreshScheduled = false
    private var volumeBeforeMute: Float = 0.5

    var selectedInputDevice: AudioDevice? {
        inputDevices.first { $0.id == defaultInputID }
    }

    var selectedOutputDevice: AudioDevice? {
        outputDevices.first { $0.id == defaultOutputID }
    }

    init() {
        registerSystemListeners()
        refresh()
    }

    deinit {
        unregisterSystemListeners()
        unregisterOutputControlListeners()
    }

    func refresh() {
        let deviceIDs = CoreAudioProperty.objectIDs(
            objectID: AudioObjectID(kAudioObjectSystemObject),
            selector: kAudioHardwarePropertyDevices
        )

        let newInputDevices = deviceIDs.compactMap { makeDevice(id: $0, direction: .input) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let newOutputDevices = deviceIDs.compactMap { makeDevice(id: $0, direction: .output) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let newDefaultInputID = defaultDevice(selector: kAudioHardwarePropertyDefaultInputDevice)
        let newDefaultOutputID = defaultDevice(selector: kAudioHardwarePropertyDefaultOutputDevice)

        if inputDevices != newInputDevices { inputDevices = newInputDevices }
        if outputDevices != newOutputDevices { outputDevices = newOutputDevices }
        if defaultInputID != newDefaultInputID { defaultInputID = newDefaultInputID }
        if defaultOutputID != newDefaultOutputID { defaultOutputID = newDefaultOutputID }
        observeOutputControls(on: newDefaultOutputID)
        refreshOutputControls()
    }

    func selectInput(_ device: AudioDevice) {
        setDefaultDevice(device.id, selector: kAudioHardwarePropertyDefaultInputDevice)
        refresh()
    }

    func selectOutput(_ device: AudioDevice) {
        setDefaultDevice(device.id, selector: kAudioHardwarePropertyDefaultOutputDevice)
        setDefaultDevice(device.id, selector: kAudioHardwarePropertyDefaultSystemOutputDevice)
        refresh()
    }

    func setOutputVolume(_ newValue: Float) {
        guard defaultOutputID != kAudioObjectUnknown else { return }
        var value = min(max(newValue, 0), 1)
        let status = CoreAudioProperty.set(
            objectID: defaultOutputID,
            selector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            scope: kAudioDevicePropertyScopeOutput,
            value: &value
        )
        if status == noErr {
            if outputVolume != value { outputVolume = value }
            if value > 0 { volumeBeforeMute = value }
        }
    }

    func toggleOutputMute() {
        guard defaultOutputID != kAudioObjectUnknown else { return }
        var muted: UInt32 = outputMuted ? 0 : 1
        let muteStatus = CoreAudioProperty.set(
            objectID: defaultOutputID,
            selector: kAudioDevicePropertyMute,
            scope: kAudioDevicePropertyScopeOutput,
            value: &muted
        )

        if muteStatus == noErr {
            let newMuted = muted != 0
            if outputMuted != newMuted { outputMuted = newMuted }
        } else if outputMuted || outputVolume == 0 {
            setOutputVolume(max(volumeBeforeMute, 0.25))
            if outputMuted { outputMuted = false }
        } else {
            volumeBeforeMute = outputVolume
            setOutputVolume(0)
            if !outputMuted { outputMuted = true }
        }
    }

    private func makeDevice(id: AudioObjectID, direction: AudioDevice.Direction) -> AudioDevice? {
        let scope: AudioObjectPropertyScope = direction == .input
            ? kAudioDevicePropertyScopeInput
            : kAudioDevicePropertyScopeOutput
        guard !CoreAudioProperty.objectIDs(
            objectID: id,
            selector: kAudioDevicePropertyStreams,
            scope: scope
        ).isEmpty,
        let uid = CoreAudioProperty.string(objectID: id, selector: kAudioDevicePropertyDeviceUID),
        let name = CoreAudioProperty.string(objectID: id, selector: kAudioObjectPropertyName)
        else { return nil }

        return AudioDevice(id: id, uid: uid, name: name, direction: direction)
    }

    private func defaultDevice(selector: AudioObjectPropertySelector) -> AudioObjectID {
        CoreAudioProperty.uint32(
            objectID: systemObjectID,
            selector: selector
        ) ?? kAudioObjectUnknown
    }

    private func setDefaultDevice(_ id: AudioObjectID, selector: AudioObjectPropertySelector) {
        var value = id
        CoreAudioProperty.set(
            objectID: systemObjectID,
            selector: selector,
            scope: kAudioObjectPropertyScopeGlobal,
            value: &value
        )
    }

    private func refreshOutputControls() {
        guard defaultOutputID != kAudioObjectUnknown else { return }
        let selector = kAudioHardwareServiceDeviceProperty_VirtualMainVolume
        let newCanSetOutputVolume = CoreAudioProperty.isSettable(
            objectID: defaultOutputID,
            selector: selector,
            scope: kAudioDevicePropertyScopeOutput
        )
        if canSetOutputVolume != newCanSetOutputVolume {
            canSetOutputVolume = newCanSetOutputVolume
        }
        if let volume = CoreAudioProperty.float32(
            objectID: defaultOutputID,
            selector: selector,
            scope: kAudioDevicePropertyScopeOutput
        ) {
            if abs(outputVolume - volume) > 0.0001 { outputVolume = volume }
            if volume > 0 { volumeBeforeMute = volume }
        }
        let hardwareMute = CoreAudioProperty.uint32(
            objectID: defaultOutputID,
            selector: kAudioDevicePropertyMute,
            scope: kAudioDevicePropertyScopeOutput
        )
        let newMuted: Bool = hardwareMute.map { $0 != 0 } ?? (outputVolume == 0)
        if outputMuted != newMuted { outputMuted = newMuted }
    }

    private func registerSystemListeners() {
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.scheduleRefresh()
        }
        systemListener = listener

        for selector in [
            kAudioHardwarePropertyDevices,
            kAudioHardwarePropertyDefaultInputDevice,
            kAudioHardwarePropertyDefaultOutputDevice,
            kAudioHardwarePropertyDefaultSystemOutputDevice
        ] {
            var address = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectAddPropertyListenerBlock(systemObjectID, &address, listenerQueue, listener)
        }
    }

    private func unregisterSystemListeners() {
        guard let systemListener else { return }
        for selector in [
            kAudioHardwarePropertyDevices,
            kAudioHardwarePropertyDefaultInputDevice,
            kAudioHardwarePropertyDefaultOutputDevice,
            kAudioHardwarePropertyDefaultSystemOutputDevice
        ] {
            var address = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(systemObjectID, &address, listenerQueue, systemListener)
        }
        self.systemListener = nil
    }

    private func observeOutputControls(on deviceID: AudioObjectID) {
        guard observedOutputDeviceID != deviceID else { return }
        unregisterOutputControlListeners()
        observedOutputDeviceID = deviceID
        guard deviceID != kAudioObjectUnknown else { return }

        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.scheduleRefresh()
        }
        outputControlListener = listener
        for selector in [
            kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            kAudioDevicePropertyMute
        ] {
            var address = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectAddPropertyListenerBlock(deviceID, &address, listenerQueue, listener)
        }
    }

    private func unregisterOutputControlListeners() {
        guard observedOutputDeviceID != kAudioObjectUnknown,
              let outputControlListener else {
            observedOutputDeviceID = kAudioObjectUnknown
            return
        }
        for selector in [
            kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            kAudioDevicePropertyMute
        ] {
            var address = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(
                observedOutputDeviceID,
                &address,
                listenerQueue,
                outputControlListener
            )
        }
        self.outputControlListener = nil
        observedOutputDeviceID = kAudioObjectUnknown
    }

    private func scheduleRefresh() {
        guard !refreshScheduled else { return }
        refreshScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.refreshScheduled = false
            self.refresh()
        }
    }
}
