//
//  TJDropboxAuthenticationViewController.m
//  TJDropbox
//
//  Created by Tim Johnsen on 4/11/16.
//  Copyright © 2016 tijo. All rights reserved.
//

#import "TJDropboxAuthenticationViewController.h"

@interface TJDropboxAuthenticationViewController ()

@property (nonatomic, copy) NSString *clientIdentifier;
@property (nonatomic, strong) NSURL *redirectURL;
@property (nonatomic, weak) id<TJDropboxAuthenticationViewControllerDelegate> delegate;

@end

@implementation TJDropboxAuthenticationViewController

- (instancetype)initWithClientIdentifier:(NSString *const)clientIdentifier redirectURL:(NSURL *const)redirectURL delegate:(id<TJDropboxAuthenticationViewControllerDelegate>)delegate
{
    if (self = [super initWithNibName:nil bundle:nil]) {
        self.clientIdentifier = clientIdentifier;
        self.redirectURL = redirectURL;
        self.delegate = delegate;
        
        self.title = @"Sign in with Dropbox";
    }
    return self;
}

@end
