# Advanced Auth

TJDropbox is designed to be pretty flexible when it comes to authentication. Once can simply use `TJDropboxAuthenticationViewController` as a catch-all, but I'd suggest doing the following for the best user experience.

1. Try to authenticate using the Dropbox app
2. Use `SFSafariViewController` if it's available
3. Use `TJDropboxAuthenticationViewController` as a last resort.

The reasoning for this suggestion is that users are likely already authenticated in the Dropbox app or in `SFSafariViewController`, so they don't need to re-enter their credentials. Here's a breakdown of how to implement this.

## Using the Dropbox App

TJDropbox provides two methods for authenticating users using the Dropbox app, if installed.

First, you'll need to get the URL you'll use to authenticate and check if the OS can open in. You'll need to add `dbapi-2` to your info plist's `LSApplicationQueriesSchemes` array in order for this to work in iOS 9 and aboe.

```objc
NSString *clientIdentifier = /* fill this in */;
NSURL *authURL = [TJDropbox dropboxAppAuthenticationURLWithClientIdentifier:clientIdentifier];

if ([[UIApplication sharedApplication] canOpenURL:authURL]) {
    [[UIApplication sharedApplication] openURL:authURL];
} else {
    // Use another authentication method...
}
```

You'll then need to register your app with a URL scheme that the Dropbox app is capable of handling, outlined in the 'Set up a URL scheme' section [here](https://github.com/dropbox/SwiftyDropbox#configure-your-project).

Once this is done, you need to intercept URLs coming from the Dropbox app back into yours, like so.

```objc
- (BOOL)application:(UIApplication *)application handleOpenURL:(NSURL *)url
{
    BOOL didHandle = NO;
    NSString *accessToken = [TJDropbox accessTokenFromDropboxAppAuthenticationURL:url];
    if (accessToken) {
        // Success! You've authenticated. Store the token and use it.
        didHandle = YES;
    } else {
        // Handle other incoming URLs if need be
    }
    
    return didHandle;
}
```

## Using `ASWebAuthenticationSession`/`SFAuthenticationSession` (iOS 12/11 and above)

Using `ASWebAuthenticationSession` (iOS 12+) or `SFAuthenticationSession` (iOS 11+) to authenticate users via TJDropbox is very easy. You should register a URL scheme for your app as described [here](https://github.com/dropbox/SwiftyDropbox#configure-your-project) (also needed to authentication with the Dropbox app) then use the following snippet.

```objc
NSString *clientIdentifier = /* fill this in */;
NSURL *authURL = [TJDropbox tokenAuthenticationURLWithClientIdentifier:clientIdentifier];
NSStringr *callbackScheme = [NSString stringWithFormat:@"db-%@", clientIdentifier];

// or SFAuthenticationSession
[[[ASWebAuthenticationSession alloc] initWithURL:authURL callbackURLScheme:callbackScheme completionHandler:^(NSURL *callbackURL, NSError *error) {
    NSString *accessToken = [TJDropbox accessTokenFromURL:callbackURL withClientIdentifier:clientIdentifier];
    if (accessToken) {
        // Completed with token!
    } else {
        // Completed without token, something went wrong.
    }
}] start];
```

## Using `SFSafariViewController` (iOS 9 and above)

Using `SFSafariViewController` for Dropbox authentication is useful if the user is already signed in within their browser. It is superseded by `ASWebAuthenticationSession`/`SFAuthenticationSession` in later iOS versions, but useful for older OSes. You should register a URL scheme for your app as described [here](https://github.com/dropbox/SwiftyDropbox#configure-your-project) (also needed to authentication with the Dropbox app) then use the following snippet.

```objc
NSURL *authURL = [TJDropbox tokenAuthenticationURLWithClientIdentifier:clientIdentifier];
SFSafariViewController *safariViewController = [[SFSafariViewController alloc] initWithURL:authURL];
// Present safariViewController modally
```

Then you'll need to intercept URLs coming into your app from this `SFSafariViewController` redirecting to your app's URL scheme.

```objc
- (BOOL)application:(UIApplication *)application handleOpenURL:(NSURL *)url
{
    BOOL didHandle = NO;
    NSString *accessToken = [TJDropbox accessTokenFromURL:url withClientIdentifier:/*client identifier*/];
    if (accessToken) {
        // Success! You've authenticated. Store the token and use it.
        didHandle = YES;
    } else {
        // Handle other incoming URLs if need be
    }
    
    return didHandle;
}
```

You can also used similar steps to perform auth with Safari.app by calling `-openURL:` with `authURL`.

## Using `TJDropboxAuthenticationViewController` (iOS 8 and above)

Using `TJDropboxAuthenticationViewController` is outlined [here](../README.md#auth).

## Putting them together

Here's sample code for using all three of these methods.

In the place where you initiate authentication.

```objc
- (void)authenticate
{
    NSString *clientIdentifier = /* your client identifier */;
    NSURL *appAuthURL = [TJDropbox dropboxAppAuthenticationURLWithClientIdentifier:clientIdentifier];   
    if ([[UIApplication sharedApplication] canOpenURL:appAuthURL]) {
        [[UIApplication sharedApplication] openURL:appAuthURL];
    } else if ([SFAuthenticationSession class]) {
        [[[SFAuthenticationSession alloc] initWithURL:authURL callbackURLScheme:callbackScheme completionHandler:^(NSURL *callbackURL, NSError *error) {
        NSString *accessToken = [TJDropbox accessTokenFromURL:callbackURL withClientIdentifier:clientIdentifier];
        if (accessToken) {
            // Completed with token!
        } else {
            // Completed without token, something went wrong.
        }
        }] start];
    } else if ([SFSafariViewController class]) {
        NSURL *authURL = [TJDropbox tokenAuthenticationURLWithClientIdentifier:clientIdentifier];
        SFSafariViewController *safariViewController = [[SFSafariViewController alloc] initWithURL:authURL];
        // Present safariViewController modally
    } else {
        TJDropboxAuthenticationViewController *authViewController = [[TJDropboxAuthenticationViewController alloc] initWithClientIdentifier:clientIdentifier delegate:self];
        // Push authViewController onto the nav stack or embed in a nav controller and present modally
    }
}

- (void)dropboxAuthenticationViewController:(TJDropboxAuthenticationViewController *)viewController didAuthenticateWithAccessToken:(NSString *)accessToken
{
    // Huzzah! You're authenticated.
    // Store the token and dismiss your view controller
}
```

In your app delegate

```
- (BOOL)application:(UIApplication *)application handleOpenURL:(NSURL *)url
{
    BOOL didHandle = NO;
    NSString *dropboxAppAccessToken = [TJDropbox accessTokenFromDropboxAppAuthenticationURL:url];
    NSString *dropboxWebAccessToken = [TJDropbox accessTokenFromURL:url withClientIdentifier:/*client identifier*/];
    if (dropboxAppAccessToken) {
        // Success! You've authenticated. Store the token and use it.
        didHandle = YES;
    } else if (dropboxWebAccessToken) {
        // Success! You've authenticated. Store the token and use it.
        // Also, dismiss your SFSafariViewController.
        didHandle = YES;
    } else {
        // Handle other incoming URLs if need be
    }
    
    return didHandle;
}
```
