import AppKit
import CoreAudio
import Foundation

final class ApplicationAudioService: ObservableObject {
    @Published private(set) var applications: [AudioApplication] = []
    @Published private(set) var lastError: String?

    private let volumeStore: VolumeStore
    private let systemObjectID = AudioObjectID(kAudioObjectSystemObject)
    private let listenerQueue = DispatchQueue.main
    private var pipelines: [String: AppAudioPipeline] = [:]
    private var lastNonZeroVolumes: [String: Float] = [:]
    private var systemListener: AudioObjectPropertyListenerBlock?
    private var processListener: AudioObjectPropertyListenerBlock?
    private var observedProcessObjectIDs = Set<AudioObjectID>()
    private var activeApplicationIDs = Set<String>()
    private var removalTasks: [String: DispatchWorkItem] = [:]
    private var refreshScheduled = false
    private var outputDevice: AudioDevice?
    private let removalGracePeriod: TimeInterval = 2

    init(volumeStore: VolumeStore = VolumeStore()) {
        self.volumeStore = volumeStore
        registerSystemListener()
        refresh()
    }

    deinit {
        unregisterSystemListener()
        unregisterProcessListeners()
        removalTasks.values.forEach { $0.cancel() }
        pipelines.values.forEach { $0.stop() }
    }

    func useOutputDevice(_ device: AudioDevice?) {
        guard outputDevice?.id != device?.id else { return }
        outputDevice = device
        rebuildPipelines()
    }

    func refresh() {
        let processObjectIDs = CoreAudioProperty.objectIDs(
            objectID: systemObjectID,
            selector: kAudioHardwarePropertyProcessObjectList
        ).sorted()
        synchronizeProcessListeners(with: processObjectIDs)

        let previousIDs = Dictionary(uniqueKeysWithValues: applications.map { ($0.id, $0.processObjectIDs) })
        let discoveredApplications = discoverApplications(from: processObjectIDs)
        activeApplicationIDs = Set(discoveredApplications.map(\.id))

        for application in discoveredApplications {
            removalTasks.removeValue(forKey: application.id)?.cancel()
        }

        var displayedApplications = discoveredApplications
        for application in applications where !activeApplicationIDs.contains(application.id) {
            scheduleRemovalIfNeeded(for: application.id)
            displayedApplications.append(application)
        }
        displayedApplications.sort {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        for application in discoveredApplications where application.volume < 0.999 {
            if previousIDs[application.id] != application.processObjectIDs {
                pipelines.removeValue(forKey: application.id)?.stop()
            }
            startPipelineIfNeeded(for: application)
        }

        if !applicationsMatch(applications, displayedApplications) {
            applications = displayedApplications
        }
    }

    func setVolume(_ volume: Float, for applicationID: String) {
        let value = min(max(volume, 0), 1)
        guard let index = applications.firstIndex(where: { $0.id == applicationID }) else { return }
        if value > 0 { lastNonZeroVolumes[applicationID] = value }
        applications[index].volume = value
        volumeStore.setVolume(value, for: applicationID)

        if value >= 0.999 {
            pipelines.removeValue(forKey: applicationID)?.stop()
            lastError = nil
        } else if let pipeline = pipelines[applicationID] {
            pipeline.volume = value
        } else {
            startPipelineIfNeeded(for: applications[index])
        }
    }

    func toggleMute(for applicationID: String) {
        guard let application = applications.first(where: { $0.id == applicationID }) else { return }
        if application.volume == 0 {
            setVolume(lastNonZeroVolumes[applicationID] ?? 1, for: applicationID)
        } else {
            lastNonZeroVolumes[applicationID] = application.volume
            setVolume(0, for: applicationID)
        }
    }

    private func discoverApplications(from processObjectIDs: [AudioObjectID]) -> [AudioApplication] {
        struct AudioProcessInfo {
            let objectID: AudioObjectID
            let pid: pid_t
            let bundleID: String
            let app: NSRunningApplication
        }

        let ownPID = Foundation.ProcessInfo.processInfo.processIdentifier
        let processes: [AudioProcessInfo] = processObjectIDs.compactMap { objectID in
            guard CoreAudioProperty.uint32(
                objectID: objectID,
                selector: kAudioProcessPropertyIsRunningOutput
            ) == 1,
            let rawPID = CoreAudioProperty.uint32(objectID: objectID, selector: kAudioProcessPropertyPID)
            else { return nil }

            let pid = pid_t(bitPattern: rawPID)
            guard pid != ownPID, let app = NSRunningApplication(processIdentifier: pid) else { return nil }
            let bundleID = CoreAudioProperty.string(
                objectID: objectID,
                selector: kAudioProcessPropertyBundleID
            ) ?? app.bundleIdentifier ?? "pid.\(pid)"
            return AudioProcessInfo(objectID: objectID, pid: pid, bundleID: bundleID, app: app)
        }

        return Dictionary(grouping: processes, by: \.bundleID)
            .map { bundleID, group in
                let app = group.compactMap(\.app).first
                let fallback = bundleID.split(separator: ".").last.map(String.init) ?? "Application"
                return AudioApplication(
                    id: bundleID,
                    name: app?.localizedName ?? fallback,
                    icon: app?.icon,
                    processObjectIDs: group.map(\.objectID).sorted(),
                    processIdentifiers: group.map(\.pid).sorted(),
                    volume: volumeStore.volume(for: bundleID)
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func registerSystemListener() {
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.scheduleRefresh()
        }
        systemListener = listener
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(systemObjectID, &address, listenerQueue, listener)
    }

    private func unregisterSystemListener() {
        guard let systemListener else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(systemObjectID, &address, listenerQueue, systemListener)
        self.systemListener = nil
    }

    private func synchronizeProcessListeners(with processObjectIDs: [AudioObjectID]) {
        let currentIDs = Set(processObjectIDs)
        let removedIDs = observedProcessObjectIDs.subtracting(currentIDs)
        let addedIDs = currentIDs.subtracting(observedProcessObjectIDs)

        if processListener == nil {
            processListener = { [weak self] _, _ in
                self?.scheduleRefresh()
            }
        }
        guard let processListener else { return }

        for objectID in removedIDs {
            var address = processRunningOutputAddress
            AudioObjectRemovePropertyListenerBlock(objectID, &address, listenerQueue, processListener)
        }
        for objectID in addedIDs {
            var address = processRunningOutputAddress
            AudioObjectAddPropertyListenerBlock(objectID, &address, listenerQueue, processListener)
        }
        observedProcessObjectIDs = currentIDs
    }

    private func unregisterProcessListeners() {
        guard let processListener else { return }
        for objectID in observedProcessObjectIDs {
            var address = processRunningOutputAddress
            AudioObjectRemovePropertyListenerBlock(objectID, &address, listenerQueue, processListener)
        }
        observedProcessObjectIDs.removeAll()
        self.processListener = nil
    }

    private var processRunningOutputAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunningOutput,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
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

    private func scheduleRemovalIfNeeded(for applicationID: String) {
        guard removalTasks[applicationID] == nil else { return }
        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.removalTasks[applicationID] = nil
            guard !self.activeApplicationIDs.contains(applicationID) else { return }
            self.pipelines.removeValue(forKey: applicationID)?.stop()
            let remaining = self.applications.filter { $0.id != applicationID }
            if !self.applicationsMatch(self.applications, remaining) {
                self.applications = remaining
            }
        }
        removalTasks[applicationID] = task
        DispatchQueue.main.asyncAfter(deadline: .now() + removalGracePeriod, execute: task)
    }

    private func applicationsMatch(_ lhs: [AudioApplication], _ rhs: [AudioApplication]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).allSatisfy { left, right in
            left.id == right.id &&
            left.name == right.name &&
            left.processObjectIDs == right.processObjectIDs &&
            left.processIdentifiers == right.processIdentifiers &&
            abs(left.volume - right.volume) < 0.0001
        }
    }

    private func startPipelineIfNeeded(for application: AudioApplication) {
        guard pipelines[application.id] == nil, let outputDevice else { return }
        do {
            let pipeline = try AppAudioPipeline(
                name: application.name,
                processObjectIDs: application.processObjectIDs,
                outputDevice: outputDevice,
                volume: application.volume
            )
            pipelines[application.id] = pipeline
            lastError = nil
        } catch {
            lastError = "Impossible de contrôler \(application.name) : \(error.localizedDescription)"
        }
    }

    private func rebuildPipelines() {
        pipelines.values.forEach { $0.stop() }
        pipelines.removeAll()
        for application in applications where application.volume < 0.999 {
            startPipelineIfNeeded(for: application)
        }
    }
}
