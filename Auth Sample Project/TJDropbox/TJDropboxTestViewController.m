//
//  TJDropboxTestViewController.m
//  TJDropbox
//
//  Created by Tim Johnsen on 4/27/16.
//  Copyright © 2016 tijo. All rights reserved.
//

#import "TJDropboxTestViewController.h"

#import "TJDropbox.h"
#import "TJDropboxAuthenticationViewController.h"

#import "SSKeychain.h" // Imported to demonstrate saving to keychain, not required

#warning Fill these in
static NSString *const kClientIdentifier = nil;
static NSString *const kRedirectURLString = nil;

@interface TJDropboxTestViewController () <TJDropboxAuthenticationViewControllerDelegate>

@property (nonatomic, strong) IBOutlet UIButton *authButton;
@property (nonatomic, strong) IBOutlet UITextView *outputTextView;

@property (nonatomic, copy) NSString *accessToken;

@end

@implementation TJDropboxTestViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.title = @"TJDropbox Test";
    
    if (self.accessToken.length > 0) {
        [self.authButton setTitle:@"Sign out" forState:UIControlStateNormal];
    } else {
        [self.authButton setTitle:@"Sign in" forState:UIControlStateNormal];
    }
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    if (kClientIdentifier.length == 0 || kRedirectURLString.length == 0) {
        UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"Missing credentials" message:@"You must fill in kClientIdentifier and kRedirectURLString to use the sample app" preferredStyle:UIAlertControllerStyleAlert];
        [alertController addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
            exit(0);
        }]];
        [self presentViewController:alertController animated:YES completion:nil];
    }
}

- (IBAction)authButtonTapped:(id)sender
{
    if (self.accessToken.length > 0) {
        self.accessToken = nil;
    } else {
        TJDropboxAuthenticationViewController *authenticationController = [[TJDropboxAuthenticationViewController alloc] initWithClientIdentifier:kClientIdentifier delegate:self];
        [self.navigationController pushViewController:authenticationController animated:YES];
    }
}

- (void)dropboxAuthenticationViewController:(TJDropboxAuthenticationViewController *)viewController didAuthenticateWithAccessToken:(NSString *const)accessToken
{
    [self.navigationController popViewControllerAnimated:YES];
    
    self.accessToken = accessToken;
    NSLog(@"Authenticated with token %@", accessToken);
    UIAlertController *const alertController = [UIAlertController alertControllerWithTitle:@"Authenticated!" message:[NSString stringWithFormat:@"Token = %@", accessToken] preferredStyle:UIAlertControllerStyleAlert];
    [alertController addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alertController animated:YES completion:nil];
}

- (NSString *)accessToken
{
    return [SSKeychain passwordForService:@"dropbox" account:@"account"];
}

- (void)setAccessToken:(NSString *)accessToken
{
    if (accessToken.length > 0) {
        [self.authButton setTitle:@"Sign out" forState:UIControlStateNormal];
        [SSKeychain setPassword:accessToken forService:@"dropbox" account:@"account"];
    } else {
        [self.authButton setTitle:@"Sign in" forState:UIControlStateNormal];
        [SSKeychain deletePasswordForService:@"dropbox" account:@"account"];
    }
}

- (IBAction)uploadButtonTapped:(id)sender
{
    if (self.accessToken.length > 0) {
        NSString *filename = [NSString stringWithFormat:@"test-%lu.txt", (unsigned long)CACurrentMediaTime()];
        NSString *localPath = [NSHomeDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"Library/Caches/%@", filename]];
        NSString *remotePath = [NSString stringWithFormat:@"/%@", filename];
        [@"Hello World!" writeToFile:localPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        
        [TJDropbox uploadFileAtPath:localPath toPath:remotePath credential:[[TJDropboxCredential alloc] initWithAccessToken:self.accessToken] completion:^(NSDictionary * _Nullable parsedResponse, NSError * _Nullable error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (error) {
                    self.outputTextView.text = [error description];
                } else {
                    self.outputTextView.text = [parsedResponse description];
                }
            });
        }];
    } else {
        UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"Not signed in" message:@"You must sign in to upload a file" preferredStyle:UIAlertControllerStyleAlert];
        [alertController addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alertController animated:YES completion:nil];
    }
}

@end
