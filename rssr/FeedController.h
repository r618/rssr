//
//  FeedController.h
//  rssr
//
//  Created by Rupert Pole on 08/11/15.
//
//
// feed parsing and net access

#import <Foundation/Foundation.h>
#import "MWFeedParser.h"
#import "OPMLOutlineXMLElement.h"

// Debug Logging
#if 0 // Set to 1 to enable debug logging
#define RSLog(format, ...) NSLog( (@"%s:%d " format), __PRETTY_FUNCTION__, __LINE__, ## __VA_ARGS__);
#else
#define RSLog(format, ...)
#endif

typedef void(^FeedParserCompletionHandler)(NSString* message);

@interface FeedController : NSObject<MWFeedParserDelegate>

/// parses xmlUrl and adds children as <item ... s to the outline
-(void)parseFeed:(OPMLOutlineXMLElement*)ofOutline withCompletionHandler:(FeedParserCompletionHandler)completionHandler;

/// tries to find final feed url in existing document
-(MWFeedInfo*)tryToExtractFeedInfo:(NSString*)fromLink;

@end
