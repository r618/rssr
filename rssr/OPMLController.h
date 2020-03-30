//
//  OPMLController.h
//  rssr
//
//  Created by Rupert Pole on 26/10/15.
//
//
// outline/feed content serialization
#import <Foundation/Foundation.h>
#import "OPMLOutline.h"


// possible extern reference
// FOUNDATION_EXPORT NSString *const userOutlinesFilename;
// (extern 4 if not c/c++)

@interface OPMLController : NSObject

@property (strong, nonatomic) OPMLOutline *userOutlineDocument;

+ (OPMLController*)sharedInstance;



/// ---------- document serialization ----------
-(BOOL)saveUserOutlineDocument:(NSError*)error;
-(OPMLOutline*)defaultOutlineDocument :(NSError*)error;






/// items cache
-(void)cacheItems:(OPMLOutlineXMLElement*)ofElement;

/// does maintenance based on processingScopeItems
-(void)trimItems:(OPMLOutlineXMLElement*)ofOutline;

-(void)loadAllItems:(OPMLOutlineXMLElement*)toOutline;
-(void)loadBookmarkedItems:(OPMLOutlineXMLElement*)toOutline;
-(void)loadSearchedItems:(OPMLOutlineXMLElement*)ofOutline toParent:(OPMLOutlineXMLElement*)parent;
-(void)loadTodayItems:(OPMLOutlineXMLElement*)ofOutline toParent:(OPMLOutlineXMLElement*)parent;
-(void)loadUnreadItems:(OPMLOutlineXMLElement*)toOutline;

-(void)countCachedItems:(OPMLOutlineXMLElement*)ofOutline
			   allCount:(NSUInteger*)allCount
			 todayCount:(NSUInteger*)todayCount
			unreadCount:(NSUInteger*)unreadCount
		bookmarkedCount:(NSUInteger*)bookmarkedCount
		  searchedCount:(NSUInteger*)searchedCount
;


-(void)markItemAsRead:(OPMLOutlineXMLElement*)item;
-(void)markItemBookmarked:(OPMLOutlineXMLElement*)item clear:(BOOL)clear;

-(void)setAttribute:(NSString*)attributeName value:(NSString*)attributeValue node:(OPMLOutlineXMLElement*)node;

-(void)markOutlineAsRead:(OPMLOutlineXMLElement*)outline;
/// outline deletion - deletes table with all items
-(void)deleteOutline:(OPMLOutlineXMLElement*)outline;

-(void)clearCache;

@end
