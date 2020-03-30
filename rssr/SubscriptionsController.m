//
//  SubscriptionsController.m
//  rssr
//
//  Created by Rupert Pole on 09/11/15.
//
//

#import "SubscriptionsController.h"
#import "FeedController.h"
#import <UIKit/UIKit.h>
#import "SVProgressHUD.h"

NSDate *lastFullUpdate;
extern NSInteger processingScopeItems;

@implementation SubscriptionsController
{
    NSUInteger processingProgress;
    NSRegularExpression *dateEqRExpression;
    dispatch_group_t dispatchGroup;
    
    // retain references to parsers since they are nonblocking
    NSMutableArray *feedControllers;
}

+ (SubscriptionsController*)sharedInstance
{
    static dispatch_once_t once;
    static id sharedInstance;
    
    dispatch_once(&once, ^{
        
        sharedInstance = [[self alloc] init];
    });
    
    return sharedInstance;
}

-(instancetype)init
{
    if ( self = [super init] )
    {
        NSError *error;
        NSString *pattern = @"date=\"[^\"]*\"";
        self->dateEqRExpression = [NSRegularExpression regularExpressionWithPattern:pattern
                                                                            options:0
                                                                              error:&error];
        self->dispatchGroup = dispatch_group_create();
        self->feedControllers = [[NSMutableArray alloc] init];
        
        self.isRefreshing = NO;
    }
    
    return self;
}
#pragma mark - document serialization

-(BOOL)saveUserOutlineDocument:(NSError*)error
{
    // reflect the actual today count 
    NSUInteger todayCount_new_all = [[[[self userOutlineDocument].bodyNode attributeForName:@"todayItemsCount"] stringValue] integerValue];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [[UIApplication sharedApplication] setApplicationIconBadgeNumber:todayCount_new_all];
    });

    return [[OPMLController sharedInstance] saveUserOutlineDocument:error];
}

-(OPMLOutline*)userOutlineDocument
{
    return [OPMLController sharedInstance].userOutlineDocument;
}

-(OPMLOutline*)defaultOutlineDocument:(NSError*)error
{
    return [[OPMLController sharedInstance] defaultOutlineDocument:error];
}


#pragma mark - CRUD / Create of outline on main document

-(OPMLOutlineXMLElement*)createOutlineFromOutline:(OPMLOutlineXMLElement*)outline underParent:(OPMLOutlineXMLElement*)parent message:(NSString**)message
{
    @synchronized (self)
    {
        // check if subscription already exists
        
        NSString *link = [[outline attributeForName:@"xmlUrl"] stringValue];
        
        if ( [self outlineFromLink:link] )
        {
            if ( message )
                *message = [NSString stringWithFormat:@"%@ - %@", NSLocalizedString(@"Subscription already exists", nil), link];
            return nil;
        }
            
        OPMLOutlineXMLElement *newOutline = [self newOutlineUnderParent:parent withText:[[outline attributeForName:@"text"] stringValue]];
        
        NSMutableArray *attributes = [NSMutableArray new];
        
        for (DDXMLNode *el in outline.attributes )
        {
            DDXMLNode *n = [DDXMLNode attributeWithName:[el name] stringValue:[el stringValue]];
            [attributes addObject:n];
        }
        
        [newOutline setAttributes:attributes];
        
        
        // refresh items on a copy to not poison the outline tree
        OPMLOutlineXMLElement *newOutline_copy = [newOutline copy];
        
        [self refreshFeedItems:newOutline_copy isTemporary:NO progressFeedCallbackPre:nil progressFeedCallback:nil];
        
        dispatch_group_wait(self->dispatchGroup, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(600.0 * NSEC_PER_SEC)));
        
        [self->feedControllers removeAllObjects];
        
        if ( [newOutline_copy childCount] < 1 )
        {
            [newOutline detach];
            
            if (message)
                *message = [NSString stringWithFormat:@"%@ %@ %@"
                        , NSLocalizedString(@"The feed on ", nil)
                        , link
                        , NSLocalizedString(@"has no articles", nil)
                        ];
            return nil;
        }
        
        
        //  update counts
        //      previous count = 0
        //      update parents
        
        NSUInteger allCount, todayCount, unreadCount, bookmarkedCount, searchedCount;
        [self itemsCount:newOutline progress:nil allItemsCount:&allCount todayItemsCount:&todayCount unreadItemsCount:&unreadCount bookmarkedItemsCount:&bookmarkedCount searchedItemsCount:&searchedCount];
        
        [self updateCount_Up:(OPMLOutlineXMLElement *)[newOutline parent] attributeName:@"allItemsCount" byValue:allCount];
        [self updateCount_Up:(OPMLOutlineXMLElement *)[newOutline parent] attributeName:@"todayItemsCount" byValue:todayCount];
        [self updateCount_Up:(OPMLOutlineXMLElement *)[newOutline parent] attributeName:@"unreadItemsCount" byValue:unreadCount];
        [self updateCount_Up:(OPMLOutlineXMLElement *)[newOutline parent] attributeName:@"bookmarkedItemsCount" byValue:bookmarkedCount];
        [self updateCount_Up:(OPMLOutlineXMLElement *)[newOutline parent] attributeName:@"searchedItemsCount" byValue:searchedCount];
        
        // save document
        
        NSError *error;
        if (![self saveUserOutlineDocument:error])
        {
            if (message)
                *message = [error localizedDescription];
            return nil;
        }
    
        return newOutline;
    }
}

-(OPMLOutlineXMLElement*)createOutlineWithText:(NSString*)outlineText underParent:(OPMLOutlineXMLElement*)parent message:(NSString**)message
{
    @synchronized (self)
    {
        // dont at least add folder with same name at the same level
        
        NSUInteger folderCount = 0;
        for (DDXMLElement * el in parent.children)
        {
            if ( [[[el attributeForName:@"text"] stringValue] isEqualToString:outlineText] && ![el attributeForName:@"xmlUrl"] )
            {
                folderCount++;
            }
        }
        
        if ( folderCount > 0 )
        {
            if (message)
                *message = NSLocalizedString(@"Folder with the name already exists here", nil);
            return nil;
        }
        
        OPMLOutlineXMLElement *newOutline = [self newOutlineUnderParent:parent withText:outlineText];
        
        
        // save document
        
        NSError *error;
        if (![self saveUserOutlineDocument:error])
        {
            if (message)
                *message = [error localizedDescription];
            return nil;
        }
        
        return newOutline;
    }
}

-(OPMLOutlineXMLElement*)createOutlineFromURL:(NSString *)url underParent:(OPMLOutlineXMLElement*)parent message:(NSString**)message
{
    @synchronized (self)
    {
        MWFeedInfo *feedInfo = [self tryToExtractFeedInfo:url];
        
        if ( !feedInfo )
        {
            if (message)
                *message = [NSString stringWithFormat:@"%@ %@"
                       , NSLocalizedString(@"no feed on link / page", nil)
                       , url
                       ];
            
            return nil;
        }
        
        // check if subscription already exists
        
        NSString *link = [feedInfo.url absoluteString];
        
        if ( [self outlineFromLink:link] )
        {
            if (message)
                *message = [NSString stringWithFormat:@"%@ - %@ (%@)"
                       , NSLocalizedString(@"Subscription already exists", nil)
                       , feedInfo.title
                       , feedInfo.link
                       ];
            return nil;
        }
        
        OPMLOutlineXMLElement *newOutline = [self newOutlineUnderParent:parent withText:feedInfo.title];
        
        NSArray * attributes = @[
                                 [DDXMLNode attributeWithName:@"text" stringValue:feedInfo.title],
                                 [DDXMLNode attributeWithName:@"title" stringValue:feedInfo.title],
                                 [DDXMLNode attributeWithName:@"htmlUrl" stringValue:feedInfo.link],
                                 [DDXMLNode attributeWithName:@"xmlUrl" stringValue:[feedInfo.url absoluteString]],
                                 // TODO: type is set to rss here, which might not always be true; for correct type we would have to modify MWFeedParser to return also the type of the feed being parsed
                                 [DDXMLNode attributeWithName:@"type" stringValue:@"rss"],
                                 [DDXMLNode attributeWithName:@"description" stringValue:feedInfo.summary]
                                 ];
        
        [newOutline setAttributes:attributes];
        
        [newOutline setElementType:OPMLOutlineXMLElementTypeRSS];
        
        // refresh items on a copy to not poison the outline tree
        OPMLOutlineXMLElement *newOutline_copy = [newOutline copy];
        
        [self refreshFeedItems:newOutline_copy isTemporary:NO progressFeedCallbackPre:nil progressFeedCallback:nil];
        
        dispatch_group_wait(self->dispatchGroup, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(600.0 * NSEC_PER_SEC)));
        
        [self->feedControllers removeAllObjects];
        
        if ( [newOutline_copy childCount] < 1 )
        {
            [newOutline detach];
            
            if (message)
                *message = [NSString stringWithFormat:@"%@ %@ %@"
                            , NSLocalizedString(@"The feed on ", nil)
                            , feedInfo.link
                            , NSLocalizedString(@"has no articles", nil)
                            ];
            return nil;
        }
        
        
        //  update counts
        //      previous count = 0
        //      update parents
        
        NSUInteger allCount, todayCount, unreadCount, bookmarkedCount, searchedCount;
        [self itemsCount:newOutline progress:nil allItemsCount:&allCount todayItemsCount:&todayCount unreadItemsCount:&unreadCount bookmarkedItemsCount:&bookmarkedCount searchedItemsCount:&searchedCount];
        
        [self updateCount_Up:(OPMLOutlineXMLElement *)[newOutline parent] attributeName:@"allItemsCount" byValue:allCount];
        [self updateCount_Up:(OPMLOutlineXMLElement *)[newOutline parent] attributeName:@"todayItemsCount" byValue:todayCount];
        [self updateCount_Up:(OPMLOutlineXMLElement *)[newOutline parent] attributeName:@"unreadItemsCount" byValue:unreadCount];
        [self updateCount_Up:(OPMLOutlineXMLElement *)[newOutline parent] attributeName:@"bookmarkedItemsCount" byValue:bookmarkedCount];
        [self updateCount_Up:(OPMLOutlineXMLElement *)[newOutline parent] attributeName:@"searchedItemsCount" byValue:searchedCount];
        
        // save document
        NSError *error;
        if (![self saveUserOutlineDocument:error])
        {
            if (message)
                *message = [NSLocalizedString(@"Error saving outlines", nil) stringByAppendingString:[error localizedDescription]];
            return nil;
        }
        
        return newOutline;
    }
}

// Helper

-(OPMLOutlineXMLElement*)newOutlineUnderParent:(OPMLOutlineXMLElement*)parent withText:(NSString*)text
{
    // figure out position of the new element in alphabetic ordering
    
    NSUInteger row = 0;
    NSUInteger i = 0;
    NSComparisonResult cmpresult = NSOrderedSame;
    NSString *textAttributeValue;
    
    for (i = 0; i < parent.childCount; ++i)
    {
        textAttributeValue = [[(DDXMLElement*)[parent.children objectAtIndex:i] attributeForName:@"text"] stringValue];
        
        cmpresult = [text localizedCompare:textAttributeValue];
        
        if ( cmpresult == NSOrderedAscending || cmpresult == NSOrderedSame )
        {
            row = i;
            break;
        }
    }
    
    // it is last and still bigger
    if ( i == parent.childCount && cmpresult == NSOrderedDescending )
    {
        row = parent.childCount;
    }
    
    // create new element
    
    OPMLOutlineXMLElement *newOutline;
    
    if ( row < parent.childCount )
    {
        OPMLOutlineXMLElement *sibling = (OPMLOutlineXMLElement*)[parent.children objectAtIndex:row];
        newOutline = [self.userOutlineDocument insertNewSiblingNodeOf:sibling withText:text inFront:YES];
    }
    else
    {
        newOutline = [self.userOutlineDocument insertNewChildNodeOf:parent withText:text];
    }
    
    [newOutline setElementType:OPMLOutlineXMLElementTypeDefault];
    
    return  newOutline;
}



#pragma mark - CRUD / Read of outline on main document

-(OPMLOutlineXMLElement*)outlineFromLink:(NSString*)link
{
    // @synchronized (self)
    {
        return [self outlineFromLink_Impl:link parent:(OPMLOutlineXMLElement*)self.userOutlineDocument.bodyNode];
    }
}

-(OPMLOutlineXMLElement*)outlineFromLink_Impl:(NSString*)link parent:(OPMLOutlineXMLElement*)parent
{
    for ( OPMLOutlineXMLElement *el in parent.children )
    {
        if ( [[el name] isEqualToString:@"outline"] )
        {
            if ( [[[el attributeForName:@"xmlUrl"] stringValue] isEqualToString:link] )
            {
                return el;
            }
            else
            {
                OPMLOutlineXMLElement *o = [self outlineFromLink_Impl:link parent:el];
                if ( o )
                    return o;
            }
        }
    }
    
    return nil;
}

#pragma mark - CRUD / Update of outline on main document

#pragma mark - CRUD / Delete of outline on main document

-(void)deleteOutline:(OPMLOutlineXMLElement*)outlineToBeDeleted
{
    @synchronized (self)
    {
        for (DDXMLElement *el in outlineToBeDeleted.children )
        {
            [self deleteOutline:(OPMLOutlineXMLElement *)el];
        }
        
        // update DB
        // delete table if it is not folder...
        if ( [[outlineToBeDeleted attributeForName:@"xmlUrl"] stringValue] )
            [[OPMLController sharedInstance] deleteOutline:outlineToBeDeleted];
        
        // update document
        NSInteger count = [[[outlineToBeDeleted attributeForName:@"allItemsCount"] stringValue] intValue];
        [self updateCount_Up:(OPMLOutlineXMLElement *)[outlineToBeDeleted parent] attributeName:@"allItemsCount" byValue:-count];
        
        count = [[[outlineToBeDeleted attributeForName:@"todayItemsCount"] stringValue] intValue];
        [self updateCount_Up:(OPMLOutlineXMLElement *)[outlineToBeDeleted parent] attributeName:@"todayItemsCount" byValue:-count];
        
        count = [[[outlineToBeDeleted attributeForName:@"unreadItemsCount"] stringValue] intValue];
        [self updateCount_Up:(OPMLOutlineXMLElement *)[outlineToBeDeleted parent] attributeName:@"unreadItemsCount" byValue:-count];
        
        count = [[[outlineToBeDeleted attributeForName:@"bookmarkedItemsCount"] stringValue] intValue];
        [self updateCount_Up:(OPMLOutlineXMLElement *)[outlineToBeDeleted parent] attributeName:@"bookmarkedItemsCount" byValue:-count];

        count = [[[outlineToBeDeleted attributeForName:@"searchedItemsCount"] stringValue] intValue];
        [self updateCount_Up:(OPMLOutlineXMLElement *)[outlineToBeDeleted parent] attributeName:@"searchedItemsCount" byValue:-count];
        
        [outlineToBeDeleted detach];
        
        [self saveUserOutlineDocument:nil];
    }
}


#pragma mark - CRUD of outline on main document - update counts

-(void)refreshFeeds:(OPMLOutlineXMLElement*)ofOutline
    progressFeedCallbackPre:(void (^)(NSString*))progressFeedCallbackPre
    progressFeedCallback:(void (^)(NSString*))progressFeedCallback
{
    @synchronized (self)
    {
        self.isRefreshing = YES;
        dispatch_async(dispatch_get_main_queue(), ^{
            [UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
        });

        // wait for all refreshes on dispatch_group
        
        
        // on a copy to not poison the outline tree
        [self refreshFeedsRecursively:[ofOutline copy] progressFeedCallbackPre:progressFeedCallbackPre progressFeedCallback:progressFeedCallback];
            
        
        // dispatch_group_wait(self->dispatchGroup, DISPATCH_TIME_FOREVER);
        // wait up to 10 minutes
        dispatch_group_wait(self->dispatchGroup, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(600.0 * NSEC_PER_SEC)));
        
        [self->feedControllers removeAllObjects];
        
        OPMLOutlineXMLElement *body = (OPMLOutlineXMLElement*)[self userOutlineDocument].bodyNode;
        if ( [body isEqual:ofOutline] )
            lastFullUpdate = [NSDate date];
        
        
        self.isRefreshing = NO;
        dispatch_async(dispatch_get_main_queue(), ^{
            [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
        });
    }
}

-(void)refreshFeedsRecursively:(OPMLOutlineXMLElement*)fromOutline progressFeedCallbackPre:(void (^)(NSString*))progressFeedCallbackPre progressFeedCallback:(void (^)(NSString*))progressFeedCallback
{
    if ( [[fromOutline name] isEqualToString:@"outline"] )
    {
        // refresh only links, not directories
        if ( [[fromOutline attributeForName:@"xmlUrl"] stringValue] )
        {
            [self refreshFeedItems:fromOutline isTemporary:NO progressFeedCallbackPre:progressFeedCallbackPre progressFeedCallback:progressFeedCallback];
        }
    }
    
    for (DDXMLElement *el in fromOutline.children )
    {
        [self refreshFeedsRecursively:(OPMLOutlineXMLElement *)el progressFeedCallbackPre:progressFeedCallbackPre progressFeedCallback:progressFeedCallback];
    }
}

-(void)refreshFeedItems:(OPMLOutlineXMLElement*)outline isTemporary:(BOOL)temporary
    progressFeedCallbackPre:(void (^)(NSString*))progressFeedCallbackPre
   progressFeedCallback:(void (^)(NSString*))progressFeedCallback
{
    dispatch_group_enter(self->dispatchGroup);
    
    __block FeedController *fc = [[FeedController alloc] init];
    [self->feedControllers addObject:fc];
    
    [fc parseFeed:outline withCompletionHandler:^(NSString *message) {
        
        if ( progressFeedCallbackPre )
            progressFeedCallbackPre( [[outline attributeForName:@"text"] stringValue] );

        if (!temporary)
            [[OPMLController sharedInstance] cacheItems:outline];
        
        // some crash checking
        // still crashing here afer a few hours left idle and update on open...
        if ( [self->feedControllers containsObject:fc] )
            [self->feedControllers removeObject:fc];
        
        if ( progressFeedCallback )
            progressFeedCallback( [[outline attributeForName:@"text"] stringValue] );
        
        dispatch_group_leave(self->dispatchGroup);
    }];
}

/*
 some helper from SO
void runOnMainQueueWithoutDeadlocking(void (^block)(void))
{
    if ([NSThread isMainThread])
    {
        block();
    }
    else
    {
        dispatch_sync(dispatch_get_main_queue(), block);
    }
}
*/

-(void)refreshCounts:(OPMLOutlineXMLElement*)ofOutline progress:(void (^)(NSUInteger))progress
{
    @synchronized (self)
    {
        // update counts if called from lower outline
        NSUInteger allCount_current = [[[ofOutline attributeForName:@"allItemsCount"] stringValue] intValue];
        NSUInteger todayCount_current = [[[ofOutline attributeForName:@"todayItemsCount"] stringValue] intValue];
        NSUInteger unreadCount_current = [[[ofOutline attributeForName:@"unreadItemsCount"] stringValue] intValue];
        NSUInteger searchedCount_current = [[[ofOutline attributeForName:@"searchedItemsCount"] stringValue] intValue];

        NSUInteger allCount, todayCount, unreadCount, bookmarkedCount, searchedCount;
        [self itemsCount:ofOutline progress:progress allItemsCount:&allCount todayItemsCount:&todayCount unreadItemsCount:&unreadCount bookmarkedItemsCount:&bookmarkedCount searchedItemsCount:&searchedCount];
        
        NSUInteger allCount_new = [[[ofOutline attributeForName:@"allItemsCount"] stringValue] intValue];
        NSUInteger todayCount_new = [[[ofOutline attributeForName:@"todayItemsCount"] stringValue] intValue];
        NSUInteger unreadCount_new = [[[ofOutline attributeForName:@"unreadItemsCount"] stringValue] intValue];
        NSUInteger searchedCount_new = [[[ofOutline attributeForName:@"searchedItemsCount"] stringValue] intValue];
        
        NSUInteger diff = allCount_new - allCount_current;
        
        if ( diff )
            [self updateCount_Up:(OPMLOutlineXMLElement *)[ofOutline parent] attributeName:@"allItemsCount" byValue:diff];
        
        diff = todayCount_new - todayCount_current;
        
        if ( diff )
            [self updateCount_Up:(OPMLOutlineXMLElement *)[ofOutline parent] attributeName:@"todayItemsCount" byValue:diff];

        diff = unreadCount_new - unreadCount_current;
        
        if ( diff )
            [self updateCount_Up:(OPMLOutlineXMLElement *)[ofOutline parent] attributeName:@"unreadItemsCount" byValue:diff];
        
        diff = searchedCount_new - searchedCount_current;
        
        if ( diff )
            [self updateCount_Up:(OPMLOutlineXMLElement *)[ofOutline parent] attributeName:@"searchedItemsCount" byValue:diff];
        
        // save the counts..
        [self saveUserOutlineDocument:nil];
        
        //NSDate *itemDate = [[DateFormatter sharedInstance].dateFormatter dateFromString:@"13.12.2015 14:28:00"];
        //[self scheduleAlarmForDate:itemDate count:todayCount_new];
    }
}


// test

- (void)scheduleAlarmForDate:(NSDate*)theDate count:(NSUInteger)count
{
    UIApplication* app = [UIApplication sharedApplication];
    NSArray*    oldNotifications = [app scheduledLocalNotifications];
    
    // Clear out the old notification before scheduling a new one.
    if ([oldNotifications count] > 0)
        [app cancelAllLocalNotifications];
    
    // Create a new notification.
    UILocalNotification* alarm = [[UILocalNotification alloc] init];
    if (alarm)
    {
        alarm.fireDate = theDate;
        alarm.timeZone = [NSTimeZone defaultTimeZone];
        alarm.repeatInterval = 0;
        // alarm.soundName = @"alarmsound.caf";
        // alarm.alertBody = @"Time to wake up!";
        alarm.applicationIconBadgeNumber = count;
        
        [app scheduleLocalNotification:alarm];
    }
}


#pragma mark - Cache loading and counting

// count the items from DB
// sideeffects - updates attributes

-(void)itemsCount:(OPMLOutlineXMLElement*)ofOutline
            progress:(void (^)(NSUInteger))progress
       allItemsCount:(NSUInteger*)allItemsCount
     todayItemsCount:(NSUInteger*)todayItemsCount
    unreadItemsCount:(NSUInteger*)unreadItemsCount
bookmarkedItemsCount:(NSUInteger*)bookmarkedItemsCount
  searchedItemsCount:(NSUInteger*)searchedItemsCount
{
    // @synchronized (self)
    {
        NSUInteger resultAll = 0, resultToday = 0, resultUnread = 0, resultBookmarked = 0, resultSearched = 0;
        
        self->processingProgress = 0;
        
        [self itemsCount_Impl:(OPMLOutlineXMLElement*) ofOutline
                     progress:progress
                allItemsCount:&resultAll
              todayItemsCount:&resultToday
             unreadItemsCount:&resultUnread
         bookmarkedItemsCount:&resultBookmarked
           searchedItemsCount:&resultSearched
         ];
        
        *allItemsCount = resultAll;
        *todayItemsCount = resultToday;
        *unreadItemsCount = resultUnread;
        *bookmarkedItemsCount = resultBookmarked;
        *searchedItemsCount = resultSearched;
    }
}

-(void)itemsCount_Impl:(OPMLOutlineXMLElement*)ofOutline
              progress:(void (^)(NSUInteger))progress
         allItemsCount:(NSUInteger*)allItemsCount
       todayItemsCount:(NSUInteger*)todayItemsCount
      unreadItemsCount:(NSUInteger*)unreadItemsCount
  bookmarkedItemsCount:(NSUInteger*)bookmarkedItemsCount
	searchedItemsCount:(NSUInteger*)searchedItemsCount
{
    NSUInteger resultAll = 0, resultToday = 0, resultUnread = 0, resultBookmarked = 0, resultSearched = 0;
    
    [[OPMLController sharedInstance] countCachedItems:ofOutline
                                             allCount:&resultAll
                                           todayCount:&resultToday
                                          unreadCount:&resultUnread
                                      bookmarkedCount:&resultBookmarked
										searchedCount:&resultSearched
     ];
    
    self->processingProgress += resultAll;
    
    if ( progress )
        progress( self->processingProgress );
    
    NSUInteger allItems_rec = 0, todayItems_rec = 0, unreadItems_rec = 0, bookmarkedItems_rec = 0, searchedItems_rec = 0;
    
    for (OPMLOutlineXMLElement *el in ofOutline.children)
    {
        if ( [[el name] isEqualToString:@"outline"] )
        {
            [self itemsCount_Impl:el
                         progress:progress
                    allItemsCount:&allItems_rec
                  todayItemsCount:&todayItems_rec
                 unreadItemsCount:&unreadItems_rec
             bookmarkedItemsCount:&bookmarkedItems_rec
               searchedItemsCount:&searchedItems_rec
             ];
        }
    }
    
    resultAll += allItems_rec;
    resultToday += todayItems_rec;
    resultUnread += unreadItems_rec;
    resultBookmarked += bookmarkedItems_rec;
    resultSearched += searchedItems_rec;
    
    if ( allItemsCount )
    {
        *allItemsCount += resultAll;
        
        [[OPMLController sharedInstance] setAttribute:@"allItemsCount" value:[NSString stringWithFormat:@"%ld", (unsigned long)resultAll] node:ofOutline];
    }
    
    if ( todayItemsCount )
    {
        *todayItemsCount += resultToday;
        
        [[OPMLController sharedInstance] setAttribute:@"todayItemsCount" value:[NSString stringWithFormat:@"%ld", (unsigned long)resultToday] node:ofOutline];
    }
    
    if ( unreadItemsCount )
    {
        *unreadItemsCount += resultUnread;
        
        [[OPMLController sharedInstance] setAttribute:@"unreadItemsCount" value:[NSString stringWithFormat:@"%ld", (unsigned long)resultUnread] node:ofOutline];
    }
    
    if ( bookmarkedItemsCount )
    {
        *bookmarkedItemsCount += resultBookmarked;
        
        [[OPMLController sharedInstance] setAttribute:@"bookmarkedItemsCount" value:[NSString stringWithFormat:@"%ld", (unsigned long)resultBookmarked] node:ofOutline];
    }
    
    if ( searchedItemsCount )
    {
        *searchedItemsCount += resultSearched;
        
        [[OPMLController sharedInstance] setAttribute:@"searchedItemsCount" value:[NSString stringWithFormat:@"%ld", (unsigned long)resultSearched] node:ofOutline];
    }
}

#pragma mark - Cache & FeedController wrapper

-(NSUInteger)subscriptionsCount:(OPMLOutlineXMLElement*)ofOutline
{
    @synchronized (self)
    {
        NSUInteger result = 0;
        
        if ( [[ofOutline attributeForName:@"xmlUrl"] stringValue] )
            result++;
        
        for (OPMLOutlineXMLElement *el in ofOutline.children )
            result += [self subscriptionsCount:el];
        
        return result;
    }
}

-(void)loadAllItems:(OPMLOutlineXMLElement*)toOutline isTemporary:(BOOL)temporary
{
    // @synchronized (self)
    {
        // if the items of outline exists in the cache return them
        if (!temporary)
        {
            [[OPMLController sharedInstance] loadAllItems:toOutline];
        }
        else
        {
            // TODO: remove temporary load, used only for preview

            // otherwise populate temporary feed
            [self refreshFeedItems:toOutline isTemporary:YES progressFeedCallbackPre:nil progressFeedCallback:nil];
            dispatch_group_wait(self->dispatchGroup, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(600.0 * NSEC_PER_SEC)));
            
            [self->feedControllers removeAllObjects];
        }
    }
}

// call on processing scope changed explicitely
-(void)trimItems
{
    @synchronized (self)
    {
        if ( processingScopeItems == -1 )
            return;
        
        // update DB
        [self trimItems_Impl:(OPMLOutlineXMLElement*)self.userOutlineDocument.bodyNode];
        
        // update document
        NSUInteger i1, i2, i3, i4, i5;
        [self itemsCount:(OPMLOutlineXMLElement*)self.userOutlineDocument.bodyNode progress:nil allItemsCount:&i1 todayItemsCount:&i2 unreadItemsCount:&i3 bookmarkedItemsCount:&i4 searchedItemsCount:&i5];
        
        [self saveUserOutlineDocument:nil];
    }
}

-(void)trimItems_Impl:(OPMLOutlineXMLElement*)ofOutline
{
    if ( [[ofOutline name] isEqualToString:@"outline"] )
        [[OPMLController sharedInstance] trimItems:ofOutline];
    
    for ( DDXMLElement *el in ofOutline.children )
        [self trimItems_Impl:(OPMLOutlineXMLElement *)el];
}

-(MWFeedInfo*)tryToExtractFeedInfo:(NSString*)fromLink
{
    FeedController *fc = [[FeedController alloc] init];
    return [fc tryToExtractFeedInfo:fromLink];
}

-(void)markItemAsRead:(OPMLOutlineXMLElement*)item
{
    // @synchronized (self)
    {
        // no need to update if already read
        if ( ![[[item attributeForName:@"read"] stringValue] isEqualToString:@"true"] )
        {
            // update DB
            [[OPMLController sharedInstance] markItemAsRead:item];

            // update document

            // find original parent
            OPMLOutlineXMLElement *p = [self outlineFromLink:[[item attributeForName:@"parentXmlUrl"] stringValue]];
            
            [self updateCount_Up:p attributeName:@"unreadItemsCount" byValue:-1];
            
            [self saveUserOutlineDocument:nil];
        }
    }
}

-(BOOL)markItemBookmarked:(OPMLOutlineXMLElement*)item clear:(BOOL)clear
{
    // @synchronized (self)
    {
        NSString *currentState = [[item attributeForName:@"bookmarked"] stringValue];
        OPMLOutlineXMLElement *parent = [self outlineFromLink:[[item attributeForName:@"parentXmlUrl"] stringValue]];
        
        if ( clear )
        {
            if ( [currentState isEqualToString:@"true"] )
            {
                // update DB
                [[OPMLController sharedInstance] markItemBookmarked:item clear:YES];

                // update document
                [self updateCount_Up:parent attributeName:@"bookmarkedItemsCount" byValue:-1];
                
                [self saveUserOutlineDocument:nil];

                return YES;
            }
        }
        else
        {
            if (!currentState || [currentState isEqualToString:@"false"] )
            {
                // update DB
                [[OPMLController sharedInstance] markItemBookmarked:item clear:NO];

                // update document
                [self updateCount_Up:parent attributeName:@"bookmarkedItemsCount" byValue:1];
                
                [self saveUserOutlineDocument:nil];

                return YES;
            }
        }
        
        return NO;
    }
}

// flattens all today items under one root which is hopefully this
-(void)loadTodayItems:(OPMLOutlineXMLElement*)fromOutline :(OPMLOutlineXMLElement*)toOutline
{
    // @synchronized (self)
    {
        for (DDXMLElement *el in fromOutline.children )
        {
            NSString *link = [[el attributeForName:@"xmlUrl"] stringValue];
            
            if ( link )
            {
                [[OPMLController sharedInstance] loadTodayItems:(OPMLOutlineXMLElement*)el toParent:toOutline];
            }
            
            [self loadTodayItems:(OPMLOutlineXMLElement*)el :toOutline];
        }
    }
}


-(void)loadUnreadItems:(OPMLOutlineXMLElement*)toOutline
{
    // @synchronized (self)
    {
        [[OPMLController sharedInstance] loadUnreadItems:toOutline];
    }
}

-(void)loadBookmarkedItems:(OPMLOutlineXMLElement*)toOutline
{
    // @synchronized (self)
    {
        [[OPMLController sharedInstance] loadBookmarkedItems:toOutline];
    }
}

-(void)clearSearch
{
    @synchronized (self)
    {
        // update DB
        [self clearSearch_Impl:(OPMLOutlineXMLElement*)self.userOutlineDocument.bodyNode];

        // update document - done above
        
        [self saveUserOutlineDocument:nil];
    }
}

-(void)clearSearch_Impl:(OPMLOutlineXMLElement*)outline
{
    [[OPMLController sharedInstance] setAttribute:@"searchedItemsCount" value:@"0" node:outline];
    
    for (OPMLOutlineXMLElement *el in outline.children )
    {
        if ( [[el name] isEqualToString:@"outline"] )
        {
            // update DB
            // not needed - not in DB
            
            // update document
            [[OPMLController sharedInstance] setAttribute:@"searchedItemsCount" value:@"0" node:el];
            
            [self clearSearch_Impl:el];
        }
    }
}

// flattens all searched items under one root which is hopefully this
-(void)loadSearchedItems:(OPMLOutlineXMLElement*)fromOutline :(OPMLOutlineXMLElement*)toOutline;
{
    // @synchronized (self)
    {
        for (DDXMLElement *el in fromOutline.children )
        {
            NSString *link = [[el attributeForName:@"xmlUrl"] stringValue];
            
            if ( link )
            {
                [[OPMLController sharedInstance] loadSearchedItems:(OPMLOutlineXMLElement*)el toParent:toOutline];
            }
            
            [self loadSearchedItems:(OPMLOutlineXMLElement*)el :toOutline];
        }
    }
}

#pragma mark - Settings


// updates DB - UI refreshes itself by calling itemsCount
-(void)markAllItemsAsRead
{
    @synchronized (self)
    {
        // update DB
        [self markAllItemsAsRead_Imp:(OPMLOutlineXMLElement*)self.userOutlineDocument.bodyNode];

        // update document - done above
        [self saveUserOutlineDocument:nil];
        
        [SVProgressHUD showSuccessWithStatus:nil];
    }
}

-(void)markAllItemsAsRead_Imp:(OPMLOutlineXMLElement*)outline
{
    // update document for settings which does not refresh from DB
    [[OPMLController sharedInstance] setAttribute:@"unreadItemsCount" value:@"0" node:outline];
    
    for (OPMLOutlineXMLElement *el in outline.children )
    {
        if ( [[el name] isEqualToString:@"outline"] )
        {
            // update DB
            [[OPMLController sharedInstance] markOutlineAsRead:el];
            
            // update document
            [[OPMLController sharedInstance] setAttribute:@"unreadItemsCount" value:@"0" node:el];
            
            [self markAllItemsAsRead_Imp:el];
        }
    }
}


-(void)clearCache
{
    @synchronized (self)
    {
        [SVProgressHUD showWithStatus:NSLocalizedString(@"Clearing cache..", nil)];
        
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{

            // update DB
            [[OPMLController sharedInstance] clearCache];

            // update document
            NSUInteger i1, i2, i3, i4, i5;
            [self itemsCount:(OPMLOutlineXMLElement*)self.userOutlineDocument.bodyNode progress:nil allItemsCount:&i1 todayItemsCount:&i2 unreadItemsCount:&i3 bookmarkedItemsCount:&i4 searchedItemsCount:&i5];
            
            [self saveUserOutlineDocument:nil];

            [[NSURLCache sharedURLCache] removeAllCachedResponses];
            
            lastFullUpdate = [NSDate distantPast];

            [[NSNotificationCenter defaultCenter] postNotificationName:@"itemsChanged" object:nil];
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [SVProgressHUD showSuccessWithStatus:NSLocalizedString(@"Cleared.", nil)];
            });
        });
    }
}

#pragma mark - merge

-(void)mergeDocument:(OPMLOutline *)withOPMLOutlineDocument
{
    @synchronized (self)
    {
        [SVProgressHUD showWithStatus:NSLocalizedString(@"Merging..", nil)];
        
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            
            // update DB + feeds
            [self mergeSubscriptions:(OPMLOutlineXMLElement *)withOPMLOutlineDocument.bodyNode :(OPMLOutlineXMLElement *)self.userOutlineDocument.bodyNode];
            
            // update document
            NSUInteger i1, i2, i3, i4, i5;
            [self itemsCount:(OPMLOutlineXMLElement*)self.userOutlineDocument.bodyNode progress:nil allItemsCount:&i1 todayItemsCount:&i2 unreadItemsCount:&i3 bookmarkedItemsCount:&i4 searchedItemsCount:&i5];
            
            [self saveUserOutlineDocument:nil];
            
            [[NSNotificationCenter defaultCenter] postNotificationName:@"itemsChanged" object:nil];
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [SVProgressHUD showSuccessWithStatus:NSLocalizedString(@"Subs merged.", nil)];
            });
        });
    }
}

-(void)mergeSubscriptions:(OPMLOutlineXMLElement*)fromParent :(OPMLOutlineXMLElement*)toParent
{
    [self mergeDirectories:fromParent :toParent];
    
    [self mergeOutlines:fromParent :toParent];
}

// create / mimic merger directory structure
-(void)mergeDirectories:(OPMLOutlineXMLElement*)fromParent :(OPMLOutlineXMLElement*)toParent
{
    for (OPMLOutlineXMLElement *el in fromParent.children )
    {
        // small sanity check
        if ( [[el name] isEqualToString:@"outline"] )
        {
            NSString *link = [[el attributeForName:@"xmlUrl"] stringValue];
            if (!link)
            {
                NSString* newDirName = [[el attributeForName:@"text"] stringValue];
                
                OPMLOutlineXMLElement* existingDirectory = [self directoryWithText:newDirName :toParent];
                OPMLOutlineXMLElement* newDirectory = nil;
                
                if (!existingDirectory)
                    newDirectory = [self createOutlineWithText:newDirName underParent:toParent message:nil];
                else
                    newDirectory = existingDirectory;
                
                [self mergeDirectories:(OPMLOutlineXMLElement *)el :newDirectory];
            }
        }
    }
}

// if feed from merger already exist, skip if at right place or move it to new place
// if not create it at place where it is in merger
-(void)mergeOutlines:(OPMLOutlineXMLElement*)fromParent :(OPMLOutlineXMLElement*)toParent
{
    for (OPMLOutlineXMLElement *el in fromParent.children )
    {
        // small sanity check
        if ( [[el name] isEqualToString:@"outline"] )
        {
            NSString *link = [[el attributeForName:@"xmlUrl"] stringValue];
            if (link)
            {
                OPMLOutlineXMLElement* existingOutline = [self outlineFromLink:link];
                
                if (existingOutline)
                {
                    NSString *parentLabel =[[(OPMLOutlineXMLElement*)existingOutline.parent attributeForName:@"text"] stringValue];
                    
                    if (
                        ![parentLabel isEqualToString:[[toParent attributeForName:@"text"] stringValue]]
                        )
                    {
                        [existingOutline detach];
                        [self createOutlineFromOutline:existingOutline underParent:toParent message:nil];
                    }
                }
                else
                {
                    [self createOutlineFromURL:link underParent:toParent message:nil];
                }
            }
            else
            {
                // directories should be already in sync
                // find synced first
                OPMLOutlineXMLElement* contParent = nil;
                for (OPMLOutlineXMLElement *el2 in toParent.children)
                {
                    if (
                        [[[el2 attributeForName:@"text"] stringValue] isEqualToString:[[el attributeForName:@"text"] stringValue]]
                        )
                    {
                        contParent = el2;
                        break;
                    }
                }
                
                if (!contParent)
                {
                    RSLog(@"WE ARE NOT IN SYNC");
                    continue;
                }
                
                [self mergeOutlines: el :contParent];
            }
        }
    }
}



-(OPMLOutlineXMLElement*)directoryWithText:(NSString*)text :(OPMLOutlineXMLElement*)underParent
{
    for (DDXMLElement *el in underParent.children )
    {
        if ( [[el name] isEqualToString:@"outline"] )
        {
            if ( [[[el attributeForName:@"text"] stringValue] isEqualToString:text] && ![el attributeForName:@"xmlUrl"] )
                return (OPMLOutlineXMLElement*)el;
        }
    }
    
    return nil;
}

#pragma mark - Utility

// updates count from outline up

-(void)updateCount_Up:(OPMLOutlineXMLElement*)ofOutline attributeName:(NSString*)attributeName byValue:(NSInteger)value
{
    if ( [[ofOutline name] isEqualToString:@"outline"] || [[ofOutline name] isEqualToString:@"body"] )
    {
        NSInteger count = [[[ofOutline attributeForName:attributeName] stringValue] intValue];
        
        count += value;
        
        // ....
        if ( count < 0 )
            count = 0;
        
        [[OPMLController sharedInstance] setAttribute:attributeName value:[NSString stringWithFormat:@"%ld", (unsigned long)count] node:ofOutline];
        [self updateCount_Up:(OPMLOutlineXMLElement*)[ofOutline parent] attributeName:attributeName byValue:value];
    }
}

@end
