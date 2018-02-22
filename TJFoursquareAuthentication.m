//
//  TJFoursquareAuthentication.m
//  Quotidian
//
//  Created by Tim Johnsen on 2/16/18.
//

#import "TJFoursquareAuthentication.h"
#import <SafariServices/SafariServices.h>

@interface TJFoursquareAuthentication ()

@property (nonatomic, copy, class) NSString *tj_clientIdentifier;
@property (nonatomic, strong, class) NSURL *tj_redirectURI;
@property (nonatomic, copy, class) NSString *tj_clientSecret;
@property (nonatomic, copy, class) void (^tj_completion)(NSString *accessToken);

@end

@implementation TJFoursquareAuthentication

#pragma mark - Properties

static NSString *_tj_clientIdentifier;
static NSURL *_tj_redirectURI;
static NSString *_tj_clientSecret;
static void (^_tj_completion)(NSString *accessToken);

+ (void)setTj_clientIdentifier:(NSString *)tj_clientIdentifier
{
    _tj_clientIdentifier = tj_clientIdentifier;
}

+ (void)setTj_redirectURI:(NSURL *)tj_redirectURI
{
    _tj_redirectURI = tj_redirectURI;
}

+ (void)setTj_clientSecret:(NSString *)tj_clientSecret
{
    _tj_clientSecret = tj_clientSecret;
}

+ (void)setTj_completion:(void (^)(NSString *))tj_completion
{
    _tj_completion = tj_completion;
}

+ (NSString *)tj_clientIdentifier
{
    return _tj_clientIdentifier;
}

+ (NSURL *)tj_redirectURI
{
    return _tj_redirectURI;
}

+ (NSString *)tj_clientSecret
{
    return _tj_clientSecret;
}

+ (void (^)(NSString *))tj_completion
{
    return _tj_completion;
}

#pragma mark - Authentication

+ (void)authenticateWithClientIdentifier:(NSString *const)clientIdentifier
                             redirectURI:(NSURL *const)redirectURI
                            clientSecret:(NSString *const)clientSecret
                              completion:(void (^)(NSString *))completion
{
    [self setTj_clientIdentifier:clientIdentifier];
    [self setTj_redirectURI:redirectURI];
    [self setTj_clientSecret:clientSecret];
    [self setTj_completion:completion];
    
    NSURLComponents *const urlComponents = [NSURLComponents componentsWithString:@"foursquareauth://authorize"];
    urlComponents.queryItems = @[[NSURLQueryItem queryItemWithName:@"client_id" value:clientIdentifier],
                                 [NSURLQueryItem queryItemWithName:@"v" value:@"20130509"],
                                 [NSURLQueryItem queryItemWithName:@"redirect_uri" value:redirectURI.absoluteString],
                                 ];
    NSURL *const url = urlComponents.URL;
    
    if (@available(iOS 10.0, *)) {
        [[UIApplication sharedApplication] openURL:url
                                           options:@{}
                                 completionHandler:^(BOOL success) {
                                     if (!success) {
                                         [self authenticateUsingSafariWithClientIdentifier:clientIdentifier
                                                                               redirectURI:redirectURI
                                                                              clientSecret:clientSecret
                                                                                completion:completion];
                                     }
                                 }];
    } else if ([[UIApplication sharedApplication] canOpenURL:url]) {
        [[UIApplication sharedApplication] openURL:url];
    } else {
        [self authenticateUsingSafariWithClientIdentifier:clientIdentifier
                                              redirectURI:redirectURI
                                             clientSecret:clientSecret
                                               completion:completion];
    }
}

+ (void)authenticateUsingSafariWithClientIdentifier:(NSString *const)clientIdentifier
                                        redirectURI:(NSURL *const)redirectURI
                                       clientSecret:(NSString *const)clientSecret
                                         completion:(void (^)(NSString *))completion
{
    NSURLComponents *const urlComponents = [NSURLComponents componentsWithString:@"https://foursquare.com/oauth2/authenticate"];
    urlComponents.queryItems = @[[NSURLQueryItem queryItemWithName:@"client_id" value:clientIdentifier],
                                 [NSURLQueryItem queryItemWithName:@"response_type" value:@"code"],
                                 [NSURLQueryItem queryItemWithName:@"redirect_uri" value:redirectURI.absoluteString],
                                 ];
    NSURL *const url = urlComponents.URL;
    if (@available(iOS 11.0, *)) {
        // Reference needs to be held as long as this is in progress, otherwise the UI disappears.
        static SFAuthenticationSession *session = nil;
        
        session = [[SFAuthenticationSession alloc] initWithURL:url
                                             callbackURLScheme:redirectURI.scheme
                                             completionHandler:^(NSURL * _Nullable callbackURL, NSError * _Nullable error) {
                                                 // Process results.
                                                 [self tryHandleAuthenticationCallbackWithURL:callbackURL
                                                                             clientIdentifier:clientIdentifier
                                                                                  redirectURI:redirectURI
                                                                                 clientSecret:clientSecret
                                                                                   completion:completion];
                                                 // Break reference so session is deallocated.
                                                 session = nil;
                                             }];
        [(SFAuthenticationSession *)session start];
    } else {
        [[UIApplication sharedApplication] openURL:url];
    }
}

+ (BOOL)tryHandleAuthenticationCallbackWithURL:(NSURL *const)url
{
    return [self tryHandleAuthenticationCallbackWithURL:url
                                       clientIdentifier:[self tj_clientIdentifier]
                                            redirectURI:[self tj_redirectURI]
                                           clientSecret:[self tj_clientSecret]
                                             completion:[self tj_completion]];
}

+ (BOOL)tryHandleAuthenticationCallbackWithURL:(NSURL *const)url
                              clientIdentifier:(NSString *const)clientIdentifier
                                   redirectURI:(NSURL *const)redirectURI
                                  clientSecret:(NSString *const)clientSecret
                                    completion:(void (^)(NSString *))completion
{
    BOOL handledURL = NO;
    if ([url.absoluteString hasPrefix:redirectURI.absoluteString]) {
        NSURLComponents *const components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:YES];
        NSString *code = nil;
        for (NSURLQueryItem *queryItem in components.queryItems) {
            if ([queryItem.name isEqualToString:@"code"]) {
                code = queryItem.value;
                break;
            }
        }
        
        if (code) {
            NSURLComponents *urlComponents = [NSURLComponents componentsWithString:@"https://foursquare.com/oauth2/access_token"];
            urlComponents.queryItems = @[[NSURLQueryItem queryItemWithName:@"client_id" value:clientIdentifier],
                                         [NSURLQueryItem queryItemWithName:@"client_secret" value:clientSecret],
                                         [NSURLQueryItem queryItemWithName:@"grant_type" value:@"authorization_code"],
                                         [NSURLQueryItem queryItemWithName:@"redirect_uri" value:redirectURI.absoluteString],
                                         [NSURLQueryItem queryItemWithName:@"code" value:code],
                                         ];
            [[[NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration ephemeralSessionConfiguration]] dataTaskWithURL:urlComponents.URL
                                                                                                              completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                                                                                                                  NSString *accessToken = nil;
                                                                                                                  if (data.length > 0) {
                                                                                                                      const id jsonObject = [NSJSONSerialization JSONObjectWithData:data
                                                                                                                                                                            options:0
                                                                                                                                                                              error:nil];
                                                                                                                      if ([jsonObject isKindOfClass:[NSDictionary class]]) {
                                                                                                                          accessToken = jsonObject[@"access_token"];
                                                                                                                      }
                                                                                                                  }
                                                                                                                  dispatch_async(dispatch_get_main_queue(), ^{
                                                                                                                      completion(accessToken);
                                                                                                                  });
                                                                                                              }] resume];
        } else {
            completion(nil);
        }
        
        [self setTj_clientIdentifier:nil];
        [self setTj_redirectURI:nil];
        [self setTj_clientSecret:nil];
        [self setTj_completion:nil];
        
        handledURL = YES;
    }
    return handledURL;
}

@end
