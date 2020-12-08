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

typedef NS_CLOSED_ENUM(NSUInteger, TJDropboxSharedLinkType) {
    TJDropboxSharedLinkTypeDefault,
    TJDropboxSharedLinkTypeShort, // Uses deprecated endpoint to generate db.tt links
    TJDropboxSharedLinkTypeDirect // Changes result hosts to dl.dropboxusercontent.com
};

typedef NS_CLOSED_ENUM(NSUInteger, TJDropboxThumbnailSize) {
    TJDropboxThumbnailSize32Square,
    TJDropboxThumbnailSize64Square,
    TJDropboxThumbnailSize128Square,
    TJDropboxThumbnailSize640x480,
    TJDropboxThumbnailSize1024x768
};

@interface TJDropbox : NSObject

// Authentication

/// Used to return the URL used to initate OAuth with Dropbox
+ (NSURL *)tokenAuthenticationURLWithClientIdentifier:(NSString *const)clientIdentifier
                                          redirectURL:(nullable NSURL *)redirectURL
                                         codeVerifier:(nullable NSString *const)codeVerifier;

/// Provides "default" app URL scheme that auth redirects back to (used by @c +tokenAuthenticationURLWithClientIdentifier: and @c +accessTokenFromURL:withClientIdentifier: internally).
+ (NSURL *)defaultTokenAuthenticationRedirectURLWithClientIdentifier:(NSString *const)clientIdentifier;

/// Used to extract the access token returned from Dropbox OAuth
+ (nullable NSString *)accessTokenFromURL:(NSURL *const)url withRedirectURL:(NSURL *const)redirectURL;
+ (nullable NSString *)accessTokenFromURL:(NSURL *const)url withClientIdentifier:(NSString *const)clientIdentifier;

+ (void)accessTokenFromCode:(NSString *const)code
       withClientIdentifier:(NSString *const)clientIdentifier
               codeVerifier:(NSString *const)codeVerifier
                redirectURL:(NSURL *const)redirectURL
                 completion:(void (^const)(NSString *_Nullable, NSError *_Nullable))completion; /// PKCE variant (more secure)

/// Check if there was an authentication error (also happens when the user presses cancel on the website)
+ (BOOL)isAuthenticationErrorURL:(NSURL *const)url withRedirectURL:(NSURL *const)redirectURL;
+ (BOOL)isAuthenticationErrorURL:(NSURL *const)url withClientIdentifier:(NSString *const)clientIdentifier;

/// Used to return the URL used to initiate authentication with the installed Dropbox app
+ (NSURL *)dropboxAppAuthenticationURLWithClientIdentifier:(NSString *const)clientIdentifier
                                              codeVerifier:(nullable NSString *const)codeVerifier;

/// Used to extract the access token from Dropbox app authentication
+ (nullable NSString *)accessTokenFromDropboxAppAuthenticationURL:(NSURL *const)url;

/// Revokes an access token.
+ (void)revokeToken:(NSString *const)token withCallback:(void (^const)(BOOL success, NSError *_Nullable error))completion;

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

+ (NSURLRequest *)requestToDownloadFileAtPath:(NSString *const)path accessToken:(NSString *const)accessToken;
+ (void)downloadFileAtPath:(NSString *const)remotePath toPath:(NSString *const)localPath accessToken:(NSString *const)accessToken completion:(void (^const)(NSDictionary *_Nullable parsedResponse, NSError *_Nullable error))completion;
+ (void)downloadFileAtPath:(NSString *const)remotePath toPath:(NSString *const)localPath accessToken:(NSString *const)accessToken progressBlock:(void (^_Nullable const)(CGFloat progress))progressBlock completion:(void (^const)(NSDictionary *_Nullable parsedResponse, NSError *_Nullable error))completion;
+ (void)uploadFileAtPath:(NSString *const)localPath toPath:(NSString *const)remotePath accessToken:(NSString *const)accessToken completion:(void (^const)(NSDictionary *_Nullable parsedResponse, NSError *_Nullable error))completion;
+ (void)uploadFileAtPath:(NSString *const)localPath toPath:(NSString *const)remotePath overwriteExisting:(const BOOL)overwriteExisting muteDesktopNotifications:(const BOOL)muteDesktopNotifications accessToken:(NSString *const)accessToken progressBlock:(void (^_Nullable const)(CGFloat progress))progressBlock completion:(void (^const)(NSDictionary *_Nullable parsedResponse, NSError *_Nullable error))completion;
/// Intended for files larger than 150MB. Performs chunked uploads, 10MB per chunk.
+ (void)uploadLargeFileAtPath:(NSString *const)localPath toPath:(NSString *const)remotePath accessToken:(NSString *const)accessToken completion:(void (^const)(NSDictionary *_Nullable parsedResponse, NSError *_Nullable error))completion;
+ (void)uploadLargeFileAtPath:(NSString *const)localPath toPath:(NSString *const)remotePath overwriteExisting:(const BOOL)overwriteExisting muteDesktopNotifications:(const BOOL)muteDesktopNotifications accessToken:(NSString *const)accessToken progressBlock:(void (^_Nullable const)(CGFloat progress))progressBlock completion:(void (^const)(NSDictionary *_Nullable parsedResponse, NSError *_Nullable error))completion;
+ (void)createFolderAtPath:(NSString *const)path accessToken:(NSString *const)accessToken completion:(void (^const)(NSDictionary *_Nullable parsedResponse, NSError *_Nullable error))completion;
+ (void)saveContentsOfURL:(NSURL *const)url toPath:(NSString *const)path accessToken:(NSString *const)accessToken completion:(void (^const)(NSDictionary *_Nullable parsedResponse, NSError *_Nullable error))completion;
+ (void)deleteFileAtPath:(NSString *const)path accessToken:(NSString *const)accessToken completion:(void (^const)(NSDictionary *_Nullable parsedResponse, NSError *_Nullable error))completion;

+ (void)moveFileAtPath:(NSString *const)fromPath toPath:(NSString *const)toPath accessToken:(NSString *const)accessToken completion:(void (^const)(NSDictionary *_Nullable parsedResponse, NSError *_Nullable error))completion;

// Previews

+ (NSURLRequest *)requestToDownloadThumbnailAtPath:(NSString *const)path size:(const TJDropboxThumbnailSize)thumbnailSize accessToken:(NSString *const)accessToken;
+ (void)downloadThumbnailAtPath:(NSString *const)remotePath toPath:(NSString *const)localPath size:(const TJDropboxThumbnailSize)thumbnailSize accessToken:(NSString *const)accessToken completion:(void (^const)(NSDictionary * _Nullable, NSError * _Nullable))completion;

// Search

+ (void)searchForFilesAtPath:(NSString *const)path matchingQuery:(NSString *const)query options:(NSDictionary *const)additionalOptions accessToken:(NSString *const)accessToken completion:(void (^const)(NSArray *_Nullable entries, NSError *_Nullable error))completion;

// Sharing

+ (void)getSharedLinkForFileAtPath:(NSString *const)path accessToken:(NSString *const)accessToken completion:(void (^const)(NSString *_Nullable urlString))completion;
+ (void)getSharedLinkForFileAtPath:(NSString *const)path linkType:(const TJDropboxSharedLinkType)linkType uploadOrSaveInProgress:(const BOOL)uploadOrSaveInProgress accessToken:(NSString *const)accessToken completion:(void (^const)(NSString *_Nullable urlString))completion;

// Users

+ (void)getSpaceUsageForUserWithAccessToken:(NSString *const)accessToken completion:(void (^const)(NSDictionary *_Nullable parsedResponse, NSError *_Nullable error))completion;

// Request Management

+ (void)cancelAllRequests;

@end

@interface NSError (TJDropbox)

@property (nonatomic, readonly) BOOL tj_isPathNotFoundError;
@property (nonatomic, readonly) BOOL tj_isInvalidAccessTokenError;
@property (nonatomic, readonly) BOOL tj_isInsufficientSpaceError;

@end

NS_ASSUME_NONNULL_END
