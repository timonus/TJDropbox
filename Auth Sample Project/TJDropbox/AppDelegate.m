//
//  AppDelegate.m
//  TJDropbox
//
//  Created by Tim Johnsen on 4/11/16.
//  Copyright © 2016 tijo. All rights reserved.
//

#import "AppDelegate.h"
#import "TJDropboxAuthenticationViewController.h"

@interface AppDelegate () <TJDropboxAuthenticationViewControllerDelegate>

@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    UINavigationController *const navigationController = [[UINavigationController alloc] init];
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.rootViewController = navigationController;
    [self.window makeKeyAndVisible];
    
#warning Fill these in
    static NSString *const clientIdentifier = nil;
    static NSString *const redirectURLString = nil;
    
    TJDropboxAuthenticationViewController *const authenticationController = [[TJDropboxAuthenticationViewController alloc] initWithClientIdentifier:clientIdentifier redirectURL:[NSURL URLWithString:redirectURLString] delegate:self];
    [navigationController pushViewController:authenticationController animated:NO];
    
    return YES;
}

#pragma mark - TJDropboxAuthenticationViewControllerDelegate

- (void)dropboxAuthenticationViewController:(TJDropboxAuthenticationViewController *)viewController didAuthenticateWithAccessToken:(NSString *const)accessToken
{
    NSLog(@"Authenticated with token %@", accessToken);
    
    UIAlertController *const alertController = [UIAlertController alertControllerWithTitle:@"Authenticated!" message:[NSString stringWithFormat:@"Token = %@", accessToken] preferredStyle:UIAlertControllerStyleAlert];
    [alertController addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [self.window.rootViewController presentViewController:alertController animated:YES completion:nil];
}

@end
