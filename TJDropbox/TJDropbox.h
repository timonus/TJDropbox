//
//  TJDropbox.h
//  TJDropbox
//
//  Created by Tim Johnsen on 4/11/16.
//  Copyright © 2016 tijo. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

// Dropbox v2 HTTP API reference: https://www.dropbox.com/developers/documentation/http/documentation

// Notes:
// - Completion blocks aren't called on main thread.

NS_ASSUME_NONNULL_BEGIN

extern NSString *const TJDropboxErrorDomain;
extern NSString *const TJDropboxErrorUserInfoKeyResponse; // For errors with TJDropboxErrorDomain, userInfo may contain an NSURLResponse under this field.
extern NSString *const TJDropboxErrorUserInfoKeyDropboxError; // For error with TJDropboxErrorDomain, userInfo may contain a Dropbox API error response dictionary under this field.
extern NSString *const TJDropboxErrorUserInfoKeyErrorString; // For error with TJDropboxErrorDomain, userInfo may contain a string under this field.

typedef NS_ENUM(NSUInteger, TJDropboxSharedLinkType) {
    TJDropboxSharedLinkTypeDefault,
    TJDropboxSharedLinkTypeShort, // Uses deprecated endpoint to generate db.tt links
    TJDropboxSharedLinkTypeDirect // Changes result hosts to dl.dropboxusercontent.com
};

@interface TJDropbox : NSObject

// Authentication

/// Used to return the URL used to initate OAuth with Dropbox
+ (NSURL *)tokenAuthenticationURLWithClientIdentifier:(NSString *const)clientIdentifier redirectURL:(NSURL *const)redirectURL;

/// Used to extract the access token returned from Dropbox OAuth
+ (nullable NSString *)accessTokenFromURL:(NSURL *const)url withRedirectURL:(NSURL *const)redirectURL;

/// Used to return the URL used to initiate authentication with the installed Dropbox app
+ (NSURL *)dropboxAppAuthenticationURLWithClientIdentifier:(NSString *const)clientIdentifier;

/// Used to extract the access token from Dropbox app authentication
+ (nullable NSString *)accessTokenFromDropboxAppAuthenticationURL:(NSURL *const)url;

/// Used to migrate a v1 access token to a v2 access token
+ (void)migrateV1TokenToV2Token:(NSString *const)accessToken accessTokenSecret:(NSString *const)accessTokenSecret appKey:(NSString *const)appKey appSecret:(NSString *const)appSecret completion:(void (^const)(NSString *_Nullable token, NSError *_Nullable error))completion;

// Account Info

+ (void)getAccountInformationWithAccessToken:(NSString *const)accessToken completion:(void (^const)(NSDictionary *_Nullable parsedResponse, NSError *_Nullable error))completion;

// File Inspection

// Note: The Dropbox API uses an empty string to denote the root path instead of "/"
+ (void)listFolderWithPath:(NSString *const)path accessToken:(NSString *const)accessToken completion:(void (^const)(NSArray<NSDictionary *> *_Nullable entries, NSString *_Nullable cursor, NSError *_Nullable error))completion;

+ (void)listFolderWithPath:(NSString *const)path cursor:(nullable NSString *const)cursor includeDeleted:(const BOOL)includeDeleted accessToken:(NSString *const)accessToken completion:(void (^const)(NSArray<NSDictionary *> *_Nullable entries, NSString *_Nullable cursor, NSError *_Nullable error))completion;

+ (void)getFileInfoAtPath:(NSString *const)remotePath accessToken:(NSString *const)accessToken completion:(void (^const)(NSDictionary *_Nullable entry, NSError *_Nullable error))completion;

// File Manipulation

+ (void)downloadFileAtPath:(NSString *const)remotePath toPath:(NSString *const)localPath accessToken:(NSString *const)accessToken completion:(void (^const)(NSDictionary *_Nullable parsedResponse, NSError *_Nullable error))completion;
+ (void)downloadFileAtPath:(NSString *const)remotePath toPath:(NSString *const)localPath accessToken:(NSString *const)accessToken progressBlock:(void (^_Nullable const)(CGFloat progress))progressBlock completion:(void (^const)(NSDictionary *_Nullable parsedResponse, NSError *_Nullable error))completion;
+ (void)uploadFileAtPath:(NSString *const)localPath toPath:(NSString *const)remotePath accessToken:(NSString *const)accessToken completion:(void (^const)(NSDictionary *_Nullable parsedResponse, NSError *_Nullable error))completion;
+ (void)uploadFileAtPath:(NSString *const)localPath toPath:(NSString *const)remotePath accessToken:(NSString *const)accessToken progressBlock:(void (^_Nullable const)(CGFloat progress))progressBlock completion:(void (^const)(NSDictionary *_Nullable parsedResponse, NSError *_Nullable error))completion;
/// Intended for files larger than 150MB. Performs chunked uploads, 5MB per chunk.
+ (void)uploadLargeFileAtPath:(NSString *const)localPath toPath:(NSString *const)remotePath accessToken:(NSString *const)accessToken completion:(void (^const)(NSDictionary *_Nullable parsedResponse, NSError *_Nullable error))completion;
+ (void)saveContentsOfURL:(NSURL *const)url toPath:(NSString *const)path accessToken:(NSString *const)accessToken completion:(void (^const)(NSDictionary *_Nullable parsedResponse, NSError *_Nullable error))completion;
+ (void)deleteFileAtPath:(NSString *const)path accessToken:(NSString *const)accessToken completion:(void (^const)(NSDictionary *_Nullable parsedResponse, NSError *_Nullable error))completion;

+ (void)moveFileAtPath:(NSString *const)fromPath toPath:(NSString *const)toPath accessToken:(NSString *const)accessToken completion:(void (^const)(NSDictionary *_Nullable parsedResponse, NSError *_Nullable error))completion;

// Sharing

+ (void)getSharedLinkForFileAtPath:(NSString *const)path accessToken:(NSString *const)accessToken completion:(void (^const)(NSString *_Nullable urlString))completion;
+ (void)getSharedLinkForFileAtPath:(NSString *const)path linkType:(const TJDropboxSharedLinkType)linkType uploadOrSaveInProgress:(const BOOL)uploadOrSaveInProgress accessToken:(NSString *const)accessToken completion:(void (^const)(NSString *_Nullable urlString))completion;

// Users

+ (void)getSpaceUsageForUserWithAccessToken:(NSString *const)accessToken completion:(void (^const)(NSDictionary *_Nullable parsedResponse, NSError *_Nullable error))completion;

// Request Management

+ (void)cancelAllRequests;

@end

@interface NSError (TJDropbox)

@property (nonatomic, assign, readonly) BOOL tj_isPathNotFoundError;
@property (nonatomic, assign, readonly) BOOL tj_isInvalidAccessTokenError;

@end

NS_ASSUME_NONNULL_END
