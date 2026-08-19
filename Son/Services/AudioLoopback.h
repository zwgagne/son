#import <Foundation/Foundation.h>
#import <CoreAudio/CoreAudio.h>

NS_ASSUME_NONNULL_BEGIN

/// Runs real-time IO on an aggregate device and applies gain while copying its
/// captured input buffers to its physical output buffers.
@interface AudioLoopback : NSObject

@property (atomic) float gain;

- (nullable instancetype)initWithDeviceID:(AudioObjectID)deviceID
                                      gain:(float)gain
                                     error:(NSError * _Nullable * _Nullable)error;
- (void)stop;

@end

NS_ASSUME_NONNULL_END
