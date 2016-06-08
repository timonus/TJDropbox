//
//  NSError+Dropbox.m
//  TJDropbox
//
//  Created by Stephen O'Connor on 04/06/16.
//

#import "NSError+Dropbox.h"

@implementation NSError (Dropbox)

- (BOOL)TJ_isNotFoundError
{
    NSDictionary *dropboxError = self.userInfo[@"dropboxError"];
    if (dropboxError) {
        
        NSString *key = dropboxError[@".tag"];
        NSDictionary *info = nil;
        if ((info = dropboxError[key])) {
            
            id object;
            
            if ((object = info[@".tag"])) {
                
                if ([object isKindOfClass:[NSString class]]) {
                    
                    if ([(NSString*)object isEqualToString:@"not_found"]) {
                        return YES;
                    }
                }
            }
        }
    }
    return NO;
}

@end
