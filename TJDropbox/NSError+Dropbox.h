//
//  NSError+Dropbox.h
//  TJDropbox
//
//  Created by Stephen O'Connor on 04/06/16.
//

#import <Foundation/Foundation.h>

@interface NSError (Dropbox)

@property (nonatomic, readonly) BOOL TJ_isNotFoundError;

@end
