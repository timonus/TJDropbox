//
//  AppDelegate.m
//  TJDropbox
//
//  Created by Tim Johnsen on 4/11/16.
//  Copyright © 2016 tijo. All rights reserved.
//

#import "AppDelegate.h"
#import "TJDropboxTestViewController.h"

@interface AppDelegate ()

@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    UINavigationController *navigationController = [[UINavigationController alloc] init];
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.rootViewController = navigationController;
    [self.window makeKeyAndVisible];
    
    TJDropboxTestViewController *testViewController = [[TJDropboxTestViewController alloc] initWithNibName:@"TJDropboxTestViewController" bundle:nil];
    [navigationController pushViewController:testViewController animated:YES];
    
    return YES;
}

@end
