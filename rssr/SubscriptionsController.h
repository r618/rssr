//
//  SubscriptionsController.h
//  rssr
//
//  Created by Rupert Pole on 09/11/15.
//
//
// provides interface for view controller/s
// uses and hides from view controller/s OPMLController and FeedController
//
#import <Foundation/Foundation.h>
#import "OPMLController.h"
#import "OPMLOutlineXMLElement.h"
#import "MWFeedParser.h"

@interface SubscriptionsController : NSObject

+ (SubscriptionsController*)sharedInstance;

// [main] Outline document
-(OPMLOutline*)userOutlineDocument;
-(OPMLOutline*)defaultOutlineDocument :(NSError*)error;


/// CRUD of outline on main document

// TODO: should retuen NSError, really
// Create
-(OPMLOutlineXMLElement*)createOutlineFromOutline:(OPMLOutlineXMLElement*)outline underParent:(OPMLOutlineXMLElement*)parent message:(NSString**)message;

-(OPMLOutlineXMLElement*)createOutlineWithText:(NSString*)outlineText underParent:(OPMLOutlineXMLElement*)parent message:(NSString**)message;

-(OPMLOutlineXMLElement*)createOutlineFromURL:(NSString *)url underParent:(OPMLOutlineXMLElement*)parent message:(NSString**)message;


// Read
// tries to find final feed url in existing document
-(OPMLOutlineXMLElement*)outlineFromLink:(NSString*)link;

// Update

// Delete
// deletes cache recursively
-(void)deleteOutline:(OPMLOutlineXMLElement*)outlineToBeRemoved;


// refreshes cache with dl content
-(void)refreshFeeds:(OPMLOutlineXMLElement*)ofOutline progressFeedCallbackPre:(void (^)(NSString*))progressFeedCallbackPre progressFeedCallback:(void (^)(NSString*))progressFeedCallback;

@property(atomic) BOOL isRefreshing;

// trims items by scope
-(void)trimItems;

// refreshes the tree with counts
-(void)refreshCounts:(OPMLOutlineXMLElement*)ofOutline progress:(void (^)(NSUInteger))progress;

-(NSUInteger)subscriptionsCount:(OPMLOutlineXMLElement*)ofOutline;


/// parses xmlUrl and adds children as <item ... s to the outline
-(void)loadAllItems:(OPMLOutlineXMLElement*)outline isTemporary:(BOOL)temporary;


/// updates "read" attribue on an item and saves it
-(void)markItemAsRead:(OPMLOutlineXMLElement*)item;

/// updates "bookmark" attribue on an item and saves it
-(BOOL)markItemBookmarked:(OPMLOutlineXMLElement*)item clear:(BOOL)clear;

/// populates outline with only todays items
-(void)loadTodayItems:(OPMLOutlineXMLElement*)fromOutline :(OPMLOutlineXMLElement*)toOutline;

/// populates outline with only unread items
-(void)loadUnreadItems:(OPMLOutlineXMLElement*)toOutline;

/// populates outline with only bookmarked items
-(void)loadBookmarkedItems:(OPMLOutlineXMLElement*)toOutline;

// clears current searchedItemsCounts
-(void)clearSearch;

/// populates outline with only items matching current searchedString and searchedScope
-(void)loadSearchedItems:(OPMLOutlineXMLElement*)fromOutline :(OPMLOutlineXMLElement*)toOutline;;


/// Settings ----------------------------------------
-(void)markAllItemsAsRead;
-(void)clearCache;
-(void)mergeDocument:(OPMLOutline*)withOPMLOutlineDocument;


@end
