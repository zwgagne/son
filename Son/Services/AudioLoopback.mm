#import "AudioLoopback.h"
#import <Accelerate/Accelerate.h>

#include <algorithm>
#include <atomic>
#include <cstring>

static NSString * const AudioLoopbackErrorDomain = @"com.zwgagne.Son.AudioLoopback";

static OSStatus SonAudioIOProc(
    AudioObjectID deviceID,
    const AudioTimeStamp *,
    const AudioBufferList *inputData,
    const AudioTimeStamp *,
    AudioBufferList *outputData,
    const AudioTimeStamp *,
    void *clientData
) noexcept;

@interface AudioLoopback ()
- (OSStatus)renderInput:(const AudioBufferList *)inputData
                 output:(AudioBufferList *)outputData;
@end

@implementation AudioLoopback {
    AudioObjectID _deviceID;
    AudioDeviceIOProcID _ioProcID;
    std::atomic<float> _gainStorage;
    std::atomic<bool> _running;
}

- (nullable instancetype)initWithDeviceID:(AudioObjectID)deviceID
                                      gain:(float)gain
                                     error:(NSError * _Nullable * _Nullable)error {
    self = [super init];
    if (self == nil) {
        return nil;
    }

    _deviceID = deviceID;
    _ioProcID = nullptr;
    _gainStorage.store(std::clamp(gain, 0.0f, 1.0f), std::memory_order_relaxed);
    _running.store(false, std::memory_order_relaxed);

    OSStatus status = AudioDeviceCreateIOProcID(
        _deviceID,
        SonAudioIOProc,
        (__bridge void *)self,
        &_ioProcID
    );
    if (status == noErr) {
        status = AudioDeviceStart(_deviceID, _ioProcID);
    }

    if (status != noErr) {
        if (_ioProcID != nullptr) {
            AudioDeviceDestroyIOProcID(_deviceID, _ioProcID);
            _ioProcID = nullptr;
        }
        if (error != nullptr) {
            *error = [NSError errorWithDomain:AudioLoopbackErrorDomain
                                         code:status
                                     userInfo:@{NSLocalizedDescriptionKey:
                                         [NSString stringWithFormat:@"Core Audio error %d", status]}];
        }
        return nil;
    }

    _running.store(true, std::memory_order_release);
    return self;
}

- (void)dealloc {
    [self stop];
}

- (float)gain {
    return _gainStorage.load(std::memory_order_relaxed);
}

- (void)setGain:(float)gain {
    _gainStorage.store(std::clamp(gain, 0.0f, 1.0f), std::memory_order_relaxed);
}

- (void)stop {
    if (!_running.exchange(false, std::memory_order_acq_rel)) {
        return;
    }

    AudioDeviceStop(_deviceID, _ioProcID);
    AudioDeviceDestroyIOProcID(_deviceID, _ioProcID);
    _ioProcID = nullptr;
}

- (OSStatus)renderInput:(const AudioBufferList *)inputData
                 output:(AudioBufferList *)outputData {
    if (inputData == nullptr || outputData == nullptr) {
        return noErr;
    }

    const UInt32 bufferCount = std::min(inputData->mNumberBuffers, outputData->mNumberBuffers);
    const float gain = _gainStorage.load(std::memory_order_relaxed);

    for (UInt32 index = 0; index < bufferCount; ++index) {
        const AudioBuffer &input = inputData->mBuffers[index];
        AudioBuffer &output = outputData->mBuffers[index];
        if (input.mData == nullptr || output.mData == nullptr) {
            continue;
        }

        const UInt32 byteCount = std::min(input.mDataByteSize, output.mDataByteSize);
        if (gain <= 0.0f) {
            std::memset(output.mData, 0, output.mDataByteSize);
        } else if (gain >= 1.0f) {
            std::memcpy(output.mData, input.mData, byteCount);
        } else {
            const vDSP_Length sampleCount = byteCount / sizeof(Float32);
            const Float32 *source = static_cast<const Float32 *>(input.mData);
            Float32 *destination = static_cast<Float32 *>(output.mData);
            vDSP_vsmul(source, 1, &gain, destination, 1, sampleCount);
        }
    }

    return noErr;
}

@end

static OSStatus SonAudioIOProc(
    AudioObjectID,
    const AudioTimeStamp *,
    const AudioBufferList *inputData,
    const AudioTimeStamp *,
    AudioBufferList *outputData,
    const AudioTimeStamp *,
    void *clientData
) noexcept {
    AudioLoopback *loopback = (__bridge AudioLoopback *)clientData;
    return [loopback renderInput:inputData output:outputData];
}
