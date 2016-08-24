# TJDropbox

TJDropbox is a Dropbox v2 client library written in Objective-C. Dropbox provides a v2 SDK for iOS, but it's [only compatible with Swift](https://www.dropboxforum.com/hc/en-us/community/posts/204715229-To-use-API-v2-in-iOS-platform-we-need-an-objective-C-version). If you're migrating from Dropbox's v1 SDK to v2 and don't want to adopt Swift, this is a way to do so. I developed this in order to port [Close-up](https://itunes.apple.com/app/id515789135) to Dropbox v2.

## Installation

You can use TJDropbox by adding all the source files from the TJDropbox/ directory to your project, or with [CocoaPods](https://cocoapods.org).

## Migrating Dropbox SDK v1 Tokens

If you're updating from the v1 Dropbox SDK to TJDropbox, the `+migrateV1TokenToV2Token:accessTokenSecret:appKey:appSecret:completion:` method can be used to migrate your access token.

```objc
- (void)migrate
{
    NSString *userId = [[[DBSession sharedSession] userIds] firstObject];;
    MPOAuthCredentialConcreteStore *store = [[DBSession sharedSession] credentialStoreForUserId:userId];
    NSString *v1AccessToken = store.accessToken;
    NSString *v1AccessTokenSecret = store.accessTokenSecret;
    
    if (v1AccessToken && v1AccessTokenSecret) {
        [TJDropbox migrateV1TokenToV2Token:v1AccessToken accessTokenSecret:v1AccessTokenSecret appKey:/*app key*/ appSecret:/*app secret*/ completion:^(NSString *token, NSError *error) {
            if (token) {
                // Store token for use with TJDropbox!
            }
        }];
    }
}
```

TJDropbox doesn't store any credentials and is largely stateless, so storing the resulting token is up to you. I'd recommend using the keychain or `NSUserDefaults`.

## <a name="auth">Authenticating</a>

Authentication with TJDropbox is pretty flexible. The simplest way to do it would be to show an instance of the provided `TJDropboxAuthenticationViewController` class.

```objc
- (void)authenticate
{
	TJDropboxAuthenticationViewController *authViewController = [[TJDropboxAuthenticationViewController alloc] initWithClientIdentifier:/*identifier*/ redirectURL:/*redirect URL*/ delegate:self];
	
	// Present modally...
	UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:authViewController];
	// You should add a bar button item to the auth view controller to allow users to dismiss it
	[self presentViewController:navigationController animated:YES completion:nil];
	
	// ...or push onto nav stack
	[self.navigationController pushViewController:authViewController animated:YES];
}

- (void)dropboxAuthenticationViewController:(TJDropboxAuthenticationViewController *)viewController didAuthenticateWithAccessToken:(NSString *)accessToken
{
	// Store token for use with TJDropbox!
}
```

However, you can also use `SFSafariViewController`, authenticate with the Dropbox app, or write your own auth using the `+tokenAuthenticationURLWithClientIdentifier:redirectURL:` and `+accessTokenFromURL:withRedirectURL:` utility methods. Advanced auth is detailed [here](Docs/advanced-auth.md).

Just as with migrating a v1 token to v2, TJDropbox doesn't store the credentials, that's up to you.

## Provided Request Types

Once authenticated, TJDropbox is capable of doing the following things

- Listing the contents of a folder
- Downloading files
- Uploading files
- Saving files from URLs
- Moving files (thanks @horseshoe7)
- Deleting files
- Getting info about files (thanks @horseshoe7)
- Getting shareable links to files
- Getting a user's total space and available space (thanks @onfoot)

The methods for these are all listed in TJDropbox.h.

## Custom Requests

Though TJDropbox only supports a few types of requests for now, internally it has formatters for any Dropbox API request you'd like and handlers for parsing results. Most notably:

- `+apiRequestWithPath:accessToken:parameters:` formats RPC requests to the api.dropboxapi.com host.
- `+performAPIRequest:withCompletion:` can be used to execute an RPC request.
- `+contentRequestWithPath:accessToken:parameters:` formats content requests to the content.dropboxapi.com host.
- `+resultDataForContentRequestResponse:` can be used to extract the result API information from a content request.
- `+processResultJSONData:response:error:parsedResult:` can be used to process the results from either an RPC or content request.

All the externally exposed methods in TJDropbox are built on top of these utilities, and they can be used to add new functionality to TJDropbox. Requests and pull requests are very welcome!

## Architecture notes

- I wanted to give people who use this library control, which is why auth is largely up to you (though you can use `TJDropboxAuthenticationViewController`) and storing of tokens is up to you. I don't want to tell you how to manage that stuff, your app may have it's own special needs.
- At the moment, callbacks from TJDropbox methods will come back on threads other than the main thread. That means you'll need to dispatch back to the main thread sometimes, beware!
- I believe in [using boring tech](http://mcfunley.com/choose-boring-technology). This is, after all, an Objective-C port of something that there's a Swift version of. There are no external dependencies or craziness, it's just built on top of foundation classes and has little magic to it. I'd prefer to keep it simple.
- TJDropbox supports iOS 8 and above. It could be modified to support iOS 7 and above, for now the use of `NSURLQueryItem` is the only thing I think is blocking that.

## Todo

- Better sample project
- More documentation
- Carthage support
- Tests

## Apps using TJDropbox

- [Close-up](https://itunes.apple.com/app/id515789135)
- [Songbook Simple 2.0](http://itunes.apple.com/app/id728359573)
- [Muse Monitor](https://itunes.apple.com/app/id988527143)
