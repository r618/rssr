//
//  FeedController.m
//  rssr
//
//  Created by Rupert Pole on 08/11/15.
//
//

#import "FeedController.h"
#import <UIKit/UIKit.h>
#import "XMLTag.h"
#import "DateFormatter.h"

@interface FeedController ()
{
    BOOL extractJustFeedInfo; // for entering new feed / page
    FeedParserCompletionHandler feedParserCompletionHandler;
}

@property (strong) MWFeedInfo *feedInfo;
@property (strong) OPMLOutlineXMLElement *feedOutline;

@end

@implementation FeedController

-(void)parseFeed:(OPMLOutlineXMLElement*)ofOutline withCompletionHandler:(FeedParserCompletionHandler)completionHandler
{
    self.feedOutline = ofOutline;
    self->feedParserCompletionHandler = completionHandler;
    
    NSURL *feedURL = [NSURL URLWithString:[[self.feedOutline attributeForName:@"xmlUrl"] stringValue]];
    NSMutableURLRequest *request = [self feedRequestFromURL:feedURL];
    MWFeedParser *feedParser = [[MWFeedParser alloc] initWithFeedRequest:request];
    
    feedParser.delegate = self;
    feedParser.feedParseType = ParseTypeFull; // Parse feed info and all items; as of 02.2014 is the same as ParseTypeItemsOnly ( and ParseTypeInfoOnly haz no items )
    feedParser.connectionType = ConnectionTypeAsynchronously;
    
    self->extractJustFeedInfo = NO;
    
    [feedParser parse];
}














#pragma mark - MWFeedParser delegate

- (void)feedParserDidStart:(MWFeedParser *)parser
{
    RSLog(@"Started Parsing: %@", parser.url);
}

- (void)feedParser:(MWFeedParser *)parser didParseFeedInfo:(MWFeedInfo *)info
{
    // RSLog(@"Parsed Feed Info: title: %@, link: %@, summary: %@, url: %@", info.title, info.link, info.summary, info.url );
    
    self.feedInfo = info;
    
    if ( self->extractJustFeedInfo == YES )
        [parser stopParsing];
}

- (void)feedParser:(MWFeedParser *)parser didParseFeedItem:(MWFeedItem *)item
{
    // RSLog(@"Feed Item: “%@”", item.title);
    
    if ( self->extractJustFeedInfo == YES )
        return;

    // insert new parsed semi outline as a child to self.viewOutline
    OPMLOutlineXMLElement *newNode = [[OPMLOutlineXMLElement alloc] initWithName:@"item"];
    [self.feedOutline addChild:newNode];
    
    // setup its attributes
    NSString *_date = [[DateFormatter sharedInstance].dateFormatter stringFromDate:item.date];
    NSString *_updated = [[DateFormatter sharedInstance].dateFormatter stringFromDate:item.updated];
    NSString *_retrieved = [[DateFormatter sharedInstance].dateFormatter stringFromDate:[NSDate date]];
    
    NSArray * attributes = @[
                             [DDXMLNode attributeWithName:@"title" stringValue:item.title]
                             , [DDXMLNode attributeWithName:@"identifier" stringValue:item.identifier]
                             , [DDXMLNode attributeWithName:@"link" stringValue:item.link]
                             , [DDXMLNode attributeWithName:@"date" stringValue:_date]
                             , [DDXMLNode attributeWithName:@"updated" stringValue:_updated]
                             , [DDXMLNode attributeWithName:@"summary" stringValue:item.summary]
                             , [DDXMLNode attributeWithName:@"content" stringValue:item.content]
                             , [DDXMLNode attributeWithName:@"author" stringValue:item.author]
                             , [DDXMLNode attributeWithName:@"retrieved" stringValue:_retrieved]
                             ];
    // TODO: enclosures
    // Enclosures: Holds 1 or more item enclosures (i.e. podcasts, mp3. pdf, etc)
    //  - NSArray of NSDictionaries with the following keys:
    //     url: where the enclosure is located (NSString)
    //     length: how big it is in bytes (NSNumber)
    //     type: what its type is, a standard MIME type  (NSString)
    //for (NSDictionary *d in item.enclosures)
    //{
    //}
    
    [newNode setAttributes:attributes];
}

- (void)feedParserDidFinish:(MWFeedParser *)parser
{
    RSLog(@"Finished Parsing %@ %@", parser.url, (parser.stopped ? @" (Stopped)" : @""));
    
    if ( self->feedParserCompletionHandler )
    {
        self->feedParserCompletionHandler(nil);
        self.feedOutline = nil;
    }
}

- (void)feedParser:(MWFeedParser *)parser didFailWithError:(NSError *)error
{
    RSLog(@"Finished Parsing With Error: %@", error);
    
    NSString *message;
    
    if ( [[self.feedOutline children] count] == 0 )
    {
        message = [NSString stringWithFormat:@"== :: == :: Feed %@ failed to load ", parser.url];
    }
    else
    {
        // Failed but some items parsed
        message = [NSString stringWithFormat:@"The feed with link %@ failed to load all items", [[self.feedOutline attributeForName:@"xmlUrl"] stringValue]];
    }
    
    NSLog(@"%@", message);
    
    if (self->feedParserCompletionHandler)
    {
        self->feedParserCompletionHandler(message);
        self.feedOutline = nil;
    }
}




// ----------------------------------------------------------------------------------------------------------------------------
#pragma mark - web scraping - feed link retrieval (Vienna)

-(MWFeedInfo*)tryToExtractFeedInfo:(NSString*)fromLink
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
    });

    // Validate the subscription, possibly replacing the feedURLString with a real one if
    // it originally pointed to a web page.
    NSURL *feedURL = [self verifiedFeedURLFromURL:[NSURL URLWithString:[fromLink stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]]];
    
    MWFeedInfo *result = nil;
    
    if ( feedURL )
    {
        // Replace feed:// with http:// for parser
        //if ([feedURLString hasPrefix:@"feed://"])
        //    feedURLString = [NSString stringWithFormat:@"http://%@", [feedURLString substringFromIndex:7]];
        // ( this is from Vienna, MWFeedParser replaces on url assignment )
        
        NSMutableURLRequest *request = [self feedRequestFromURL:feedURL];
        MWFeedParser *feedParser = [[MWFeedParser alloc] initWithFeedRequest:request];
        feedParser.delegate = self;
        feedParser.feedParseType = ParseTypeFull; // Parse feed info and all items; as of 02.2014 is the same as ParseTypeItemsOnly ( and ParseTypeInfoOnly haz no items )
        feedParser.connectionType = ConnectionTypeSynchronously;
        
        self->extractJustFeedInfo = YES;
        self.feedInfo = nil;
        self->feedParserCompletionHandler = nil;

        [feedParser parse];
        
        if ( !self.feedInfo )
        {
            // if feed cannot be parsed chances are that https will work - the gog.com case
            // try again with https
            
            NSString *feedURLString = [NSString stringWithFormat:@"https://%@", [feedURL.absoluteString substringFromIndex:7]];
            feedURL = [NSURL URLWithString:feedURLString];
            request = [self feedRequestFromURL:feedURL];
            
            feedParser = [[MWFeedParser alloc] initWithFeedRequest:request];
            feedParser.delegate = self;
            feedParser.feedParseType = ParseTypeFull; // Parse feed info and all items; as of 02.2014 is the same as ParseTypeItemsOnly ( and ParseTypeInfoOnly haz no items )
            feedParser.connectionType = ConnectionTypeSynchronously;
            
            self->extractJustFeedInfo = YES;
            self.feedInfo = nil;
            self->feedParserCompletionHandler = nil;
            
            [feedParser parse];
        }
        
        result = self.feedInfo;
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
    });

    return result;
}

/*!
 * Verifies the specified URL. This is the auto-discovery phase that is described at
 * http://diveintomark.org/archives/2002/08/15/ultraliberal_rss_locator
 *
 * Basically we examine the data at the specified URL and if it is an RSS feed
 * then OK. Otherwise if it looks like an HTML page, we scan for links in the
 * page text.
 *
 *  @param feedURLString A pointer to the NSString containing the URL to verify
 *
 *  @return A pointer to an NSString containing a verified URL
 */
-(NSURL *)verifiedFeedURLFromURL:(NSURL *)rssFeedURL
{
    // If the URL starts with feed or ends with a feed extension then we're going
    // assume it's a feed.
    if ([rssFeedURL.scheme isEqualToString:@"feed"]) {
        return rssFeedURL;
    }
    
    if ([rssFeedURL.pathExtension isEqualToString:@"rss"] || [rssFeedURL.pathExtension isEqualToString:@"rdf"] || [rssFeedURL.pathExtension isEqualToString:@"xml"]) {
        return rssFeedURL;
    }
    
    // OK. Now we're at the point where can't be reasonably sure that
    // the URL points to a feed. Time to look at the content.
    if (rssFeedURL.scheme == nil)
    {
        rssFeedURL = [NSURL URLWithString:[@"http://" stringByAppendingString:rssFeedURL.absoluteString]];
    }
    
    // Use this rather than [NSData dataWithContentsOfURL:],
    // because that method will not necessarily unzip gzipped content from server.
    // Thanks to http://www.omnigroup.com/mailman/archive/macosx-dev/2004-March/051547.html
    NSMutableURLRequest *request = [self feedRequestFromURL:rssFeedURL];
    
    NSData * urlContent = [NSURLConnection sendSynchronousRequest:request returningResponse:NULL error:NULL];
    if (urlContent == nil)
        return rssFeedURL;
    
    NSMutableArray * linkArray = [NSMutableArray arrayWithCapacity:10];
    // Get all the feeds on the page. If there's more than one, use the first one.
    // TODO : if there are multiple feeds, we should put up an UI inviting the user to pick one
    // That would require modifying extractFeeds to provide URL strings and titles
    // as feeds' links are often advertised in the HTML head
    // as <link rel="alternate" type="application/rss+xml" title="..." href="...">
    if ([self extractFeeds:urlContent toArray:linkArray])
    {
        NSString * feedPart = linkArray.firstObject;
        if (![feedPart hasPrefix:@"http:"] && ![feedPart hasPrefix:@"https:"])
        {
            rssFeedURL = [NSURL URLWithString:feedPart relativeToURL:rssFeedURL];
        }
        else {
            rssFeedURL = [NSURL URLWithString:feedPart];
        }
    }
    return rssFeedURL.absoluteURL;
}


/* extractFeeds
 * Given a block of XML data, determine whether this is HTML format and, if so,
 * extract all RSS links in the data. Returns YES if we found any feeds, or NO if
 * this was not HTML.
 */
-(BOOL)extractFeeds:(NSData *)xmlData toArray:(NSMutableArray *)linkArray
{
    BOOL success = NO;
    @try {
        NSArray * arrayOfTags = [XMLTag parserFromData:xmlData];
        if (arrayOfTags != nil)
        {
            for (XMLTag * tag in arrayOfTags)
            {
                NSString * tagName = [tag name];
                
                if ([tagName isEqualToString:@"rss"] || [tagName isEqualToString:@"rdf:rdf"] || [tagName isEqualToString:@"feed"])
                {
                    success = NO;
                    break;
                }
                if ([tagName isEqualToString:@"link"])
                {
                    NSDictionary * tagAttributes = [tag attributes];
                    NSString * linkType = [tagAttributes objectForKey:@"type"];
                    
                    // We're looking for the link tag. Specifically we're looking for the one which
                    // has application/rss+xml or atom+xml type. There may be more than one which is why we're
                    // going to be returning an array.
                    if ([linkType isEqualToString:@"application/rss+xml"])
                    {
                        NSString * href = [tagAttributes objectForKey:@"href"];
                        if (href != nil)
                            [linkArray addObject:href];
                    }
                    else if ([linkType isEqualToString:@"application/atom+xml"])
                    {
                        NSString * href = [tagAttributes objectForKey:@"href"];
                        if (href != nil)
                            [linkArray addObject:href];
                    }
                }
                if ([tagName isEqualToString:@"/head"])
                    break;
                success = [linkArray count] > 0;
            }
        }
    }
    @catch (NSException *error) {
        success = NO;
    }
    return success;
}

// ----------------------------------------------------------------------------------------------------------------------------
#pragma mark - Application specific non cached with timeout request. - to be allowed by RSSRURLProtocol
// create a request for RSS parser,
// rssr-app-request header field for url protocol handler
-(NSMutableURLRequest*)feedRequestFromURL:(NSURL*)url
{
    // Create default request with no caching, via MWFeedParser
    NSMutableURLRequest *result = [[NSMutableURLRequest alloc] initWithURL:url
                                                            cachePolicy:NSURLRequestReloadIgnoringLocalAndRemoteCacheData
                                                        timeoutInterval:60];
    
    [result setValue:@"rssr-app-feed" forHTTPHeaderField:@"User-Agent"];
    [result setValue:@"YES" forHTTPHeaderField:@"rssr-app-request"];
    
    // TODO: needed ? ( Vienna )
    // [result setValue:@"application/rss+xml,application/rdf+xml,application/atom+xml,text/xml,application/xml,application/xhtml+xml;q=0.9,text/html;q=0.8,*/*;q=0.5" forHTTPHeaderField:@"Accept"];
    
    return result;
}

@end
