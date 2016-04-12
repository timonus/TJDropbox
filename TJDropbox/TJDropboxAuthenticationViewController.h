//
//  TJDropboxAuthenticationViewController.h
//  TJDropbox
//
//  Created by Tim Johnsen on 4/11/16.
//  Copyright © 2016 tijo. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@protocol TJDropboxAuthenticationViewControllerDelegate;

@interface TJDropboxAuthenticationViewController : UIViewController

- (instancetype)initWithCoder:(NSCoder *)aDecoder NS_UNAVAILABLE;
- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;

- (instancetype)initWithClientIdentifier:(NSString *const)clientIdentifier redirectURL:(NSURL *const)redirectURL delegate:(id<TJDropboxAuthenticationViewControllerDelegate>)delegate NS_DESIGNATED_INITIALIZER;

@end

@protocol TJDropboxAuthenticationViewControllerDelegate <NSObject>

- (void)dropboxAuthenticationViewControllerDidAuthenticateWithAccessToken:(NSString *const)accessToken;

@end

NS_ASSUME_NONNULL_END
