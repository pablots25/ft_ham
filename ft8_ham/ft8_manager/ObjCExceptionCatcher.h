//
//  ObjCExceptionCatcher.h
//  ft8_ham
//
//  Converts Objective-C NSExceptions (uncatchable from Swift) into NSErrors.
//  Needed for AVFoundation calls like -[AVAudioPlayerNode play] which throw
//  NSException instead of returning errors.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ObjCExceptionCatcher : NSObject

/// Runs `tryBlock`. Returns YES on success; on an NSException returns NO and
/// populates `error` with the exception name and reason.
+ (BOOL)catchException:(void (NS_NOESCAPE ^)(void))tryBlock
                 error:(NSError *_Nullable *_Nullable)error;

@end

NS_ASSUME_NONNULL_END
