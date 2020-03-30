//
//  RSSRURLProtocol.m
//  rssr
//
//  Created by Rupert Pole on 25/12/15.
//
//

#import "RSSRURLProtocol.h"
#import "FeedController.h"

extern BOOL linkClicked; // link clicked on UIWebView

// UIImage image formats: https://developer.apple.com/library/ios/documentation/UIKit/Reference/UIImage_Class/index.html#//apple_ref/doc/uid/TP40006890-CH3-SW3

// document formats: https://developer.apple.com/library/ios/qa/qa1630/_index.html

// media formats: https://developer.apple.com/library/ios/documentation/AVFoundation/Reference/AVFoundation_Constants/index.html#//apple_ref/doc/constant_group/File_Format_UTIs

NSArray *imageFileExtensions;
NSArray *documentFileExtensions;
NSArray *mediaFileExtensions;
NSArray *resourceFileExtensions;
NSArray *mediaLocations;

@interface RSSRURLProtocol ()
{
    NSURLConnection *connection;
}

@end

@implementation RSSRURLProtocol

+(void)initialize
{
    imageFileExtensions = [NSArray arrayWithObjects:@"tiff", @"tif", @"jpg", @"jpeg", @"gif", @"png", @"bmp", @"BMPf", @"ico", @"cur", @"xbm", @"img", nil];
    
    documentFileExtensions = [NSArray arrayWithObjects:@"xls", @"key.zip", @"numbers.zip", @"pages.zip", @"pdf", @"ppt", @"doc", @"rtf", @"rtfd.zip", @"key", @"numbers", @"pages", nil];
    
    mediaFileExtensions = [NSArray arrayWithObjects:@"3gp", @"3gpp", @"sdv", @"3g2", @"3gp2", @"aifc", @"cdda", @"aif", @"aiff", @"caf", @"m4v", @"mp4", @"m4a", @"mov", @"qt", @"wav", @"wave", @"bwf", @"amr", @"ac3", @"mp3", @"au", @"snd", nil];
    
    // allow youtube, vimeo embeds
    mediaLocations = [NSArray arrayWithObjects:@"youtube", @"vimeo", @"gravatar", nil];
}

-(BOOL)mediaExtensionShouldBeRecognized:(NSString*)extension
{
    for (NSString *ext in imageFileExtensions) {
        if ( [[ext lowercaseString] isEqualToString:extension] )
            return YES;
    }
    
    for (NSString *ext in mediaFileExtensions) {
        if ( [[ext lowercaseString] isEqualToString:extension] )
            return YES;
    }

    return NO;
}

-(BOOL)documentExtensionShouldBeRecognized:(NSString*)extension
{
    for (NSString *ext in documentFileExtensions) {
        if ( [[ext lowercaseString] isEqualToString:extension] )
            return YES;
    }
    
    return NO;
}

-(BOOL)mediaLocationsShouldBeRecognized:(NSString*)url
{
    for (NSString *loc in mediaLocations) {
        if ( [url rangeOfString:loc].length > 0 )
            return YES;
    }
    
    return NO;
}




+ (BOOL)canInitWithRequest:(NSURLRequest *)request
{
    // dont handle self initiated connection
    if ( [NSURLProtocol propertyForKey:@"RSSRURLProtocolHandled" inRequest:request] ) {
        return NO;
    }
    
    return YES;
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    return request;
}

+ (BOOL)requestIsCacheEquivalent:(NSURLRequest *)a toRequest:(NSURLRequest *)b {
    return [super requestIsCacheEquivalent:a toRequest:b];
}

- (void)startLoading
{
    NSMutableURLRequest *newRequest = [self.request mutableCopy];
    [NSURLProtocol setProperty:@"YES" forKey:@"RSSRURLProtocolHandled" inRequest:newRequest];
    
    // allow all app logic originating requests
    // deny at least (some) web resource/s for UIWebView
    self->connection = [NSURLConnection connectionWithRequest:newRequest delegate:self];
    
    if ( [newRequest valueForHTTPHeaderField:@"rssr-app-request"] )
    {
        // app request; webview when loading with loadHTMLString will not call this ( no baseURL )
        RSLog(@"ALLOW ALL: initial app request %@", [newRequest URL]);
    }
    else
    {
        // request originating somewhere else, i.e. uiwebview page resource load or page loaded from clicked link
        if ( linkClicked )
        {
            // this should be hopefully newly clicked page
            RSLog(@"ALLOW ALL: link clicked request %@", [newRequest URL]);
        }
        else
        {
            // this should be UIWebView or other request from app such as site icon -
            // - dont allow anything other than media ( no js, css etc )
            
            NSString *extension = [[newRequest URL] pathExtension];
            
            if ( [self mediaExtensionShouldBeRecognized:extension]
                || [self documentExtensionShouldBeRecognized:extension]
                
                // || [self mediaLocationsShouldBeRecognized:[[newRequest URL] host]]
                // TODO: media should be more comprehensive i.e. it's not enough just not block youtube.com video - its neede JS and all to properly display in UIWEbView... ?
                
                || [[[newRequest URL] scheme] isEqualToString:@"file"]
                || [[[newRequest URL] scheme] isEqualToString:@"data"]
                || [[[newRequest URL] scheme] isEqualToString:@"applewebdata"]
                || [[newRequest URL].absoluteString rangeOfString:@"gravatar"].length > 0
                // || [[newRequest URL].absoluteString containsString:@"gravatar"]
                
                )
            {
                RSLog(@"ALLOW media %@", [newRequest URL] );
            }
            else
            {
                RSLog(@"DENY resource %@ %@", [newRequest URL], extension );
                [self->connection cancel];
            }
        }
    }
}

- (void)stopLoading {
    [self->connection cancel];
    self->connection = nil;
}



// basic client transparent loading

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
    [self.client URLProtocol:self didLoadData:data];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    [self.client URLProtocol:self didFailWithError:error];
    self->connection = nil;
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageAllowed];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    [self.client URLProtocolDidFinishLoading:self];
    self->connection = nil;
}

@end
