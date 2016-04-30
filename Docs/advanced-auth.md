# Advanced Auth

TJDropbox is designed to be pretty flexible when it comes to authentication. Once can simply use `TJDropboxAuthenticationViewController` as a catch-all, but I'd suggest doing the following for the best user experience.

1. Try to authenticate using the Dropbox app
2. Use `SFSafariViewController` if it's available
3. Use `TJDropboxAuthenticationViewController` as a last resort.

The reasoning for this suggestion is that users are likely already authenticated in the Dropbox app or in `SFSafariViewController`, so they don't need to re-enter their credentials. Here's a breakdown of how to implement this.

## Using the Dropbox App

TJDropbox provides two methods for authenticating users using the Dropbox app, if installed.

First, you'll need to get the URL you'll use to authenticate and check if the OS can open in. You'll need to add `dbapi-2` to your info plist's `LSApplicationQueriesSchemes` array in order for this to work in iOS 9 and aboe.

```
NSString *clientIdentifier = /* fill this in */;
NSURL *authURL = [TJDropbox dropboxAppAuthenticationURLWithClientIdentifier:clientIdentifier];

if ([[UIApplication sharedApplication] canOpenURL:authURL]) {
	[[UIApplication sharedApplication] openURL:authURL];
} else {
	// Use another authentication method...
}
```

You'll then need to register your app with a URL scheme that the Dropbox app is capable of handling, outlined in the 'Set up a URL scheme' section [here](https://www.dropbox.com/developers/documentation/swift#tutorial).

Once this is done, you need to intercept URLs coming from the Dropbox app back into yours, like so.

```
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

## Using SFSafariViewController

Using `SFSafariViewController` for Dropbox authentication is useful if the user is already signed in within their browser. It's a bit involved, here's how to do it.

First, you'll need to put up a static web page that redirects Dropbox's authentication redirects to your app's URL scheme and register the URL for that page as a redirect URI for your app. The contents of this page should look like this.

```
<html>
    <head>
        <title>Redirecting</title>
    </head>
    <body>
        <script>
            var fragment = window.location.hash;
            window.location = '**your-apps-url-scheme**://dropboxauth' + fragment;
        </script>
    </body>
</html>
```

You should replace `your-apps-url-scheme` with the scheme you registered in the Dropbox app auth step.

Next, you'll need to create and present an `SFSafariViewController` with the auth URL provided by TJDropbox.

```
NSURL *redirectURL = /* URL to static page from prior step */;
if ([SFSafariViewController class]) {
	NSURL *authURL = [TJDropbox tokenAuthenticationURLWithClientIdentifier:clientIdentifier redirectURL:redirectURL];
	SFSafariViewController *safariViewController = [[SFSafariViewController alloc] initWithURL:authURL];
	// Present safariViewController modally
} else {
	// Use another authentication method...
}
```

Then you'll need to intercept URLs coming into your app from this `SFSafariViewController` redirecting to your app's URL scheme.

```
- (BOOL)application:(UIApplication *)application handleOpenURL:(NSURL *)url
{
	BOOL didHandle = NO;
	NSURL *redirectURL = [NSURL URLWithString:@"**your-apps-url-scheme**://dropboxauth"];
	NSString *accessToken = [TJDropbox accessTokenFromURL:url withRedirectURL:];
	if (accessToken) {
		// Success! You've authenticated. Store the token and use it.
		didHandle = YES;
	} else {
		// Handle other incoming URLs if need be
	}
	
	return didHandle;
}
```

## Using TJDropboxAuthenticationViewController

Using `TJDropboxAuthenticationViewController` is outlined [here](../README.md#auth).

## Putting them together

Here's sample code for using all three of these methods.

In the place where you initiate authentication.

```
- (void)authenticate
{
	NSString *clientIdentifier = /* your client identifier */;
	NSURL *redirectURL = /* your redirect URL */;
	NSURL *appAuthURL = [TJDropbox dropboxAppAuthenticationURLWithClientIdentifier:clientIdentifier];	
	if ([[UIApplication sharedApplication] canOpenURL:appAuthURL]) {
		[[UIApplication sharedApplication] openURL:appAuthURL];
	} else if ([SFSafariViewController class]) {
		NSURL *authURL = [TJDropbox tokenAuthenticationURLWithClientIdentifier:clientIdentifier redirectURL:redirectURL];
		SFSafariViewController *safariViewController = [[SFSafariViewController alloc] initWithURL:authURL];
		// Present safariViewController modally
	} else {
		TJDropboxAuthenticationViewController *authViewController = [[TJDropboxAuthenticationViewController alloc] initWithClientIdentifier:clientIdentifier redirectURL:redirectURL delegate:self];
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
	NSURL *redirectURL = [NSURL URLWithString:@"**your-apps-url-scheme**://dropboxauth"];
	NSString *dropboxWebAccessToken = [TJDropbox accessTokenFromURL:url withRedirectURL:redirectURL];
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

And a page you'll need hosted somewhere on the web.

```
<html>
    <head>
        <title>Redirecting</title>
    </head>
    <body>
        <script>
            var fragment = window.location.hash;
            window.location = '**your-apps-url-scheme**://dropboxauth' + fragment;
        </script>
    </body>
</html>
```
