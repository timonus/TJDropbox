//
//  TJDropboxAuthenticationViewController.m
//  TJDropbox
//
//  Created by Tim Johnsen on 4/11/16.
//  Copyright © 2016 tijo. All rights reserved.
//

#import "TJDropboxAuthenticationViewController.h"
#import "TJDropbox.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-implementations"

@interface TJDropboxAuthenticationViewController () <UIWebViewDelegate>

@property (nonatomic, copy) NSString *clientIdentifier;
@property (nonatomic, weak) id<TJDropboxAuthenticationViewControllerDelegate> delegate;

@property (nonatomic, strong, readwrite) UIWebView *webView;

@end

@implementation TJDropboxAuthenticationViewController

- (instancetype)initWithClientIdentifier:(NSString *const)clientIdentifier delegate:(id<TJDropboxAuthenticationViewControllerDelegate>)delegate
{
    if (self = [super initWithNibName:nil bundle:nil]) {
        self.clientIdentifier = clientIdentifier;
        self.delegate = delegate;
        
        self.title = @"Sign in with Dropbox";
    }
    return self;
}

#pragma mark - UIViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.webView = [[UIWebView alloc] initWithFrame:self.view.bounds];
    self.webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.webView.delegate = self;
    [self.view addSubview:self.webView];
    
    NSURL *const url = [TJDropbox tokenAuthenticationURLWithClientIdentifier:self.clientIdentifier];
    [self.webView loadRequest:[NSURLRequest requestWithURL:url]];
}

#pragma mark - UIWebViewDelegate

- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType
{
    BOOL shouldStartLoad = YES;
    
    NSString *const accessToken = [TJDropbox accessTokenFromURL:request.URL withClientIdentifier:self.clientIdentifier];
    if (accessToken.length > 0) {
        shouldStartLoad = NO;
        [self.delegate dropboxAuthenticationViewController:self didAuthenticateWithAccessToken:accessToken];
    }
    
    return shouldStartLoad;
}

@end

#pragma clang diagnostic pop
