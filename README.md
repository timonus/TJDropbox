# TJDropbox

TJDropbox is a Dropbox v2 client library written in Objective-C. When Dropbox originally announced their v2 API they included [only a Swift client library]((https://www.dropboxforum.com/hc/en-us/community/posts/204715229-To-use-API-v2-in-iOS-platform-we-need-an-objective-C-version)), and at the time I wrote TJDropbox as an Objective-C alternative to it to migrate my app [Close-up](https://itunes.apple.com/app/id515789135) to Dropbox v2. Since then, Dropbox has released an [Objective-C v2 SDK](https://github.com/dropbox/dropbox-sdk-obj-c). If you’re migrating away from Dropbox’s v1 SDK to v2 and are considering alternatives to Dropbox’s first party solution, TJDropbox is a pretty well featured replacement with no dependencies and very few source files.

## Installation

You can use TJDropbox by adding all the source files from the TJDropbox/ directory to your project, or with [CocoaPods](https://cocoapods.org).

## <a name="auth">Authenticating</a>

Authentication with TJDropbox is pretty flexible. The simplest way to do it would be to use the provided `TJDropboxAuthenticator` class.

```objc
- (void)authenticate
{
    [TJDropboxAuthenticator authenticateWithClientIdentifier:/*Dropbox client identifier*/
                                         bypassingNativeAuth:NO
                                                  completion:^(NSString *accessToken) {
        if (accessToken) {
            // Auth succeeded, store token.
        } else {
            // Auth did not succeed.
        }
    }];
}
```

Be sure to call `+tryHandleAuthenticationCallbackWithURL:` from your app delegate's `-application:openURL:options:` method for this to work. `TJDropboxAuthenticator` attempts auth using the following methods in order of preference.

1. The Dropbox app (bypassed if `bypassingNativeAuth` is `NO`)
2. `ASWebAuthenticationSession` in iOS 12+.
3. `SFAuthenticationSession` in iOS 11+.
4. Auth in Safari.app

That being said, you can also authenticate manually using the utility methods TJDropbox provides. Advanced auth is detailed [here](Docs/advanced-auth.md).

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
- Creating folders (thanks @blach)

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

- I wanted to give people who use this library control, which is why auth is largely up to you (though you can use `TJDropboxAuthenticationViewController`) and storing of tokens is up to you. I don't want to tell you how to manage that stuff, your app may have its own special needs.
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
- [Textastic](https://www.textasticapp.com)
- [Songbook Simple 2.0](http://itunes.apple.com/app/id728359573)
- [Muse Monitor](https://itunes.apple.com/app/id988527143)
