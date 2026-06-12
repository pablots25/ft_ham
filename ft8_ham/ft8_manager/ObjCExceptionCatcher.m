//
//  ObjCExceptionCatcher.m
//  ft8_ham
//

#import "ObjCExceptionCatcher.h"

@implementation ObjCExceptionCatcher

+ (BOOL)catchException:(void (NS_NOESCAPE ^)(void))tryBlock
                 error:(NSError *_Nullable *_Nullable)error {
    @try {
        tryBlock();
        return YES;
    } @catch (NSException *exception) {
        if (error) {
            NSString *reason = exception.reason ?: @"unknown reason";
            *error = [NSError errorWithDomain:@"ObjCException"
                                         code:1
                                     userInfo:@{
                                         NSLocalizedDescriptionKey :
                                             [NSString stringWithFormat:@"%@: %@",
                                                                        exception.name, reason]
                                     }];
        }
        return NO;
    }
}

@end
