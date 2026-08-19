import CoreAudio
import Foundation

final class AppAudioPipeline {
    enum PipelineError: LocalizedError {
        case noProcesses
        case tapCreation(OSStatus)
        case tapUID
        case aggregateCreation(OSStatus)
        case audioIO(String)

        var errorDescription: String? {
            switch self {
            case .noProcesses:
                return "aucun processus audio actif"
            case .tapCreation(let status):
                return "création du point de capture (\(status))"
            case .tapUID:
                return "identifiant du point de capture indisponible"
            case .aggregateCreation(let status):
                return "création du périphérique audio (\(status))"
            case .audioIO(let message):
                return "démarrage du routage audio (\(message))"
            }
        }
    }

    private var tapID = kAudioObjectUnknown
    private var aggregateDeviceID = kAudioObjectUnknown
    private var loopback: AudioLoopback?
    private var isStopped = false

    var volume: Float {
        get { loopback?.gain ?? 1 }
        set { loopback?.gain = min(max(newValue, 0), 1) }
    }

    init(
        name: String,
        processObjectIDs: [AudioObjectID],
        outputDevice: AudioDevice,
        volume: Float
    ) throws {
        guard !processObjectIDs.isEmpty else { throw PipelineError.noProcesses }

        let description = CATapDescription(stereoMixdownOfProcesses: processObjectIDs)
        description.name = "son — \(name)"
        description.isPrivate = true
        description.muteBehavior = .mutedWhenTapped

        let tapStatus = AudioHardwareCreateProcessTap(description, &tapID)
        guard tapStatus == noErr else { throw PipelineError.tapCreation(tapStatus) }

        do {
            guard let tapUID = CoreAudioProperty.string(objectID: tapID, selector: kAudioTapPropertyUID) else {
                throw PipelineError.tapUID
            }

            let aggregateUID = "com.zwgagne.Son.\(UUID().uuidString)"
            let aggregateDescription: [String: Any] = [
                kAudioAggregateDeviceNameKey: "son — \(name)",
                kAudioAggregateDeviceUIDKey: aggregateUID,
                kAudioAggregateDeviceMainSubDeviceKey: outputDevice.uid,
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceTapAutoStartKey: true,
                kAudioAggregateDeviceSubDeviceListKey: [
                    [kAudioSubDeviceUIDKey: outputDevice.uid]
                ],
                kAudioAggregateDeviceTapListKey: [
                    [
                        kAudioSubTapUIDKey: tapUID,
                        kAudioSubTapDriftCompensationKey: true
                    ]
                ]
            ]

            let aggregateStatus = AudioHardwareCreateAggregateDevice(
                aggregateDescription as CFDictionary,
                &aggregateDeviceID
            )
            guard aggregateStatus == noErr else {
                throw PipelineError.aggregateCreation(aggregateStatus)
            }

            self.loopback = try AudioLoopback(
                deviceID: aggregateDeviceID,
                gain: min(max(volume, 0), 1)
            )
            guard self.loopback != nil else {
                throw PipelineError.audioIO("erreur inconnue")
            }
        } catch {
            stop()
            throw error
        }
    }

    deinit {
        stop()
    }

    func stop() {
        guard !isStopped else { return }
        isStopped = true
        loopback?.stop()
        loopback = nil
        if aggregateDeviceID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = kAudioObjectUnknown
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = kAudioObjectUnknown
        }
    }
}
