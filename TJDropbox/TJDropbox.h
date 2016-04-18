//
//  TJDropbox.h
//  TJDropbox
//
//  Created by Tim Johnsen on 4/11/16.
//  Copyright © 2016 tijo. All rights reserved.
//

#import <Foundation/Foundation.h>

// Dropbox v2 HTTP API reference: https://www.dropbox.com/developers/documentation/http/documentation

// Notes:
// - Completion blocks aren't called on main thread.

NS_ASSUME_NONNULL_BEGIN

extern NSString *const TJDropboxErrorDomain;
extern NSString *const TJDropboxErrorUserInfoKeyResponse;
extern NSString *const TJDropboxErrorUserInfoKeyDropboxError;
extern NSString *const TJDropboxErrorUserInfoKeyErrorString;

@interface TJDropbox : NSObject

// Authentication

/// Used to return the URL used to initate OAuth with Dropbox
+ (NSURL *)tokenAuthenticationURLWithClientIdentifier:(NSString *const)clientIdentifier redirectURL:(NSURL *const)redirectURL;

/// Used to extract the access token returned from Dropbox OAuth
+ (nullable NSString *)accessTokenFromURL:(NSURL *const)url withRedirectURL:(NSURL *const)redirectURL;

// File Inspection

// Note: The Dropbox API uses an empty string to denote the root path instead of "/"
+ (void)listFolderWithPath:(NSString *const)path accessToken:(NSString *const)accessToken completion:(void (^const)(NSArray<NSDictionary *> *_Nullable entries, NSError *_Nullable error))completion;

// File Manipulation

+ (void)downloadFileAtPath:(NSString *const)remotePath toPath:(NSString *const)localPath accessToken:(NSString *const)accessToken completion:(void (^const)(NSDictionary *_Nullable parsedResponse, NSError *_Nullable error))completion;
+ (void)uploadFileAtPath:(NSString *const)localPath toPath:(NSString *const)remotePath accessToken:(NSString *const)accessToken completion:(void (^const)(NSDictionary *_Nullable parsedResponse, NSError *_Nullable error))completion;
+ (void)deleteFileAtPath:(NSString *const)path accessToken:(NSString *const)accessToken completion:(void (^const)(NSDictionary *_Nullable parsedResponse, NSError *_Nullable error))completion;

// Sharing

+ (void)getSharedLinkForFileAtPath:(NSString *const)path accessToken:(NSString *const)accessToken completion:(void (^const)(NSString *_Nullable urlString))completion;

@end

NS_ASSUME_NONNULL_END
