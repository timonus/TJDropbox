//
//  TJDropboxAuthenticationViewController.h
//  TJDropbox
//
//  Created by Tim Johnsen on 4/11/16.
//  Copyright © 2016 tijo. All rights reserved.
//

#import <UIKit/UIKit.h>

// Notes:
// - Intentionally uses UIWebView since it works on iOS 7 and the API is much simpler.
// - Presentation is up to you, though I'd recommend pushing in a navigation controller or embedding in a navigation controller and presenting modally.
// - This is by no means the only way to authenticate using TJDropbox. You could roll your own auth view controller, use SFSafariViewController, or get your token from somewhere else. This is provided so people don't have to write boilerplate for auth.

NS_ASSUME_NONNULL_BEGIN

@protocol TJDropboxAuthenticationViewControllerDelegate;

API_DEPRECATED("Deprecated due to UIWebViewDeprecation. Use TJDropboxAuthenticator instead.", ios(2.0, 12.0)) @interface TJDropboxAuthenticationViewController : UIViewController

- (instancetype)initWithCoder:(NSCoder *)aDecoder NS_UNAVAILABLE;
- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;

- (instancetype)initWithClientIdentifier:(NSString *const)clientIdentifier delegate:(id<TJDropboxAuthenticationViewControllerDelegate>)delegate NS_DESIGNATED_INITIALIZER;

// Exposed publicly in case you want to provide 1Password auth or something similar.
// Do not change this web view's delegate, it's required for auth to work.
@property (nonatomic, strong, readonly) UIWebView *webView;

@end

API_DEPRECATED("Deprecated due to UIWebViewDeprecation. Use TJDropboxAuthenticator instead.", ios(2.0, 12.0)) @protocol TJDropboxAuthenticationViewControllerDelegate <NSObject>

- (void)dropboxAuthenticationViewController:(TJDropboxAuthenticationViewController *)viewController didAuthenticateWithAccessToken:(NSString *const)accessToken;

@end

NS_ASSUME_NONNULL_END
