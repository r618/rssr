//
//  OPMLController.m
//  rssr
//
//  Created by Rupert Pole on 26/10/15.
//
//

#import "OPMLController.h"
#import "OPMLOutlineXMLElement.h"
#import "FeedController.h"
#import "FMDBController.h"
#import "NSString+MD5.h"
#import "DateFormatter.h"

const NSString *userOutlinesFilename  = @"rssr_subscriptions.opml";
const NSString *cacheDirectoryName    = @"rssr_offline";

extern NSInteger processingScopeItems;
extern NSString *searchedString;
extern NSUInteger searchedScope;

@interface OPMLController ()
{
    NSString *documentsDirectoryPath;
}

@end

@implementation OPMLController

+ (OPMLController*)sharedInstance
{
    static dispatch_once_t once;
    static id sharedInstance;
    dispatch_once(&once, ^{
        
        sharedInstance = [[self alloc] init];
        
    });
    
    return sharedInstance;
}

// TODO: error checking

-(instancetype)init
{
    if ( self = [super init] )
    {
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        self->documentsDirectoryPath = [paths firstObject];
        
        NSError *error;
        
        NSString *filePath = [self->documentsDirectoryPath stringByAppendingPathComponent:(NSString*)userOutlinesFilename];
        
        if ( ![[NSFileManager defaultManager] fileExistsAtPath:filePath] )
        {
            self.userOutlineDocument = [[OPMLOutline alloc] initWithBlankOutline];
            
            [self saveUserOutlineDocument:error];
        }
        else
        {
            // KissXML/libxml2 issue ?
            // ..... <body> non_zero_length_sequence_of_white_chars <body> gives element, but empty, and childrenCount is 1 and everything explodes
            // resaving does not help, so
            // but if it is that empty hybrid we can remove it
            // the element seems to have name "text", has description the white content (?)
            
            // TODO: check for the body children and if they are not outlines then warn user and .. resolve
            
            NSData *data = [NSData dataWithContentsOfFile:filePath];
            
            OPMLOutline *o = [[OPMLOutline alloc] initWithOPMLData:data error:&error];
            
            if ( o )
            {
                if ( o.bodyNode.childCount == 1 )
                {
                    DDXMLNode *potentialHybrid = o.bodyNode.children[0];
                    
                    if ( ![[potentialHybrid name] isEqualToString:@"outline"] )
                        // unknown element
                        [potentialHybrid detach];
                    
                    [[o XMLString] writeToFile:filePath atomically:YES encoding:NSUTF8StringEncoding error:&error];
                }
                
                self.userOutlineDocument = o;
            }
            else
            {
                // TODO: move out of property and warn user and .. resolve
                
                NSLog(@"%@, %@, %@, %@", [error localizedDescription], [error localizedFailureReason], [error localizedRecoveryOptions], [error localizedRecoverySuggestion]);
                
                self.userOutlineDocument = [[OPMLOutline alloc] initWithBlankOutline];
            }
        }
    }
    
    return self;
}

#pragma mark - document serialization

// TODO: update date modified

-(BOOL)saveUserOutlineDocument:(NSError*)error
{
    NSString *data = [self.userOutlineDocument XMLString];
    if ( data )
    {
        NSString *filePath = [self->documentsDirectoryPath stringByAppendingPathComponent:(NSString*)userOutlinesFilename];
        
        return [data writeToFile:filePath atomically:YES encoding:NSUTF8StringEncoding error:&error];
    }
    
    return NO;
}

-(OPMLOutline*)defaultOutlineDocument :(NSError*)error
{
    NSString *resourcePath = [[NSBundle mainBundle] pathForResource:@"default_feeds" ofType:@"opml"];
    
    return [[OPMLOutline alloc] initWithOPMLData:[NSData dataWithContentsOfFile:resourcePath] error:&error];
}

#pragma mark - outline's items serialization

-(void)cacheItems:(OPMLOutlineXMLElement*)ofElement
{
    // need table name..
    NSString *tableName = [self tableName:ofElement];
    
    if (!tableName)
        return;
    
    [[FMDBController sharedInstance] createTable:tableName result:^(BOOL result)
    {
        if ( result )
        {
            [[FMDBController sharedInstance].dbQueue inTransaction:^(FMDatabase *db, BOOL *rollback)
            {
                for (DDXMLElement *el in ofElement.children)
                {
                    if ( [[el name] isEqualToString:@"item"] )
                    {
                        // date format for sqlite
                        NSDate *date = [[DateFormatter sharedInstance].dateFormatter dateFromString:[[el attributeForName:@"date"] stringValue]];
                        NSDate *updated = [[DateFormatter sharedInstance].dateFormatter dateFromString:[[el attributeForName:@"updated"] stringValue]];
                        NSDate *retrieved = [[DateFormatter sharedInstance].dateFormatter dateFromString:[[el attributeForName:@"retrieved"] stringValue]];
                        
                        // link is PK, if empty ( some feeds just dont give a fuck), try identifier
                        NSString *link = [[el attributeForName:@"link"] stringValue];
                        if (!link)
                            link = [[el attributeForName:@"identifier"] stringValue];
                        
                        if (!link)
                        {
                            // this feed is serious fucktard
                            // TODO: skip atricle, but we should warn the user
                            continue;
                        }
                        
                        // (link, title, identifier, date, updated, summary, content, author, bookmarked, read, retrieved)
                        
                        [db executeUpdate:[NSString stringWithFormat:@"insert or ignore into %@ values ( ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ? )", tableName]
                         , link
                         , [[el attributeForName:@"title"] stringValue]
                         , [[el attributeForName:@"identifier"] stringValue]
                         , date
                         , updated
                         , [[el attributeForName:@"summary"] stringValue]
                         , [[el attributeForName:@"content"] stringValue]
                         , [[el attributeForName:@"author"] stringValue]
                         , @"false"
                         , @"false"
                         , retrieved
                         , nil, nil, nil, nil, nil
                         ];
                        
                        if ( [db lastErrorCode] )
                        {
                            NSLog(@"DB error outline: %@", ofElement);
                            *rollback = YES;
                        }
                    }
                }
                
            }];
        }
    }];
    
    [self trimItems:ofElement];
}

-(void)trimItems:(OPMLOutlineXMLElement *)ofOutline
{
    // do maintenance processingScopeItems
    // need table name..
    
    NSString *tableName = [self tableName:ofOutline];
    
    if (!tableName)
        return;
    
    // get top processingScopeItems rows without bookmarks and check the date on last item
    // if it is today leave all items
    // if it is before, delete all items with smaller date
    
    NSDateComponents *components = [[NSCalendar currentCalendar] components:NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit fromDate:[NSDate date]];
    
    [[FMDBController sharedInstance].dbQueue inDatabase:^(FMDatabase *db)
     {
         FMResultSet *rs = [db executeQuery:[NSString stringWithFormat:@"select date from %@ where bookmarked='false' ORDER BY DATE DESC", tableName] ];
         
         if ( [db lastErrorCode] )
         {
             NSLog(@"DB error outline: %@", ofOutline);
             [rs close];
             return ;
         }
         
         NSUInteger itemsCount = 0;
         
         NSDate *firstItemDayStart = nil;
         NSDate *lastItemDateInScope = nil;
         
         while ( [rs next] )
         {
             itemsCount++;
             
             if ( itemsCount == 1 )
                 firstItemDayStart = [[NSCalendar currentCalendar] dateFromComponents:components]; // [[NSCalendar currentCalendar] startOfDayForDate:[NSDate date]]; iOS8
             
             if ( itemsCount == processingScopeItems )
                 lastItemDateInScope = [rs dateForColumnIndex:0];
         }
         
         [rs close];
         
         if ( firstItemDayStart )
         {
             // for the same/first day leave all
             // otherwise select limit
             
             NSDate * lastItemInScopeDayStart = nil;
             
             if ( lastItemDateInScope )
             {
                 NSDateComponents *components = [[NSCalendar currentCalendar] components:NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit fromDate:lastItemDateInScope];
                 
                 lastItemInScopeDayStart = [[NSCalendar currentCalendar] dateFromComponents:components];
             }
             
             if ( ![lastItemInScopeDayStart isEqualToDate:firstItemDayStart] )
             {
                 [db executeUpdate:[NSString stringWithFormat:@"delete from %@ where bookmarked='false' and retrieved not in (select retrieved from %@ order by retrieved desc limit ?)", tableName, tableName], [NSNumber numberWithLong:processingScopeItems]];
                 
                 if ( [db lastErrorCode] )
                     NSLog(@"DB error outline: %@", ofOutline);
             }
         }
         else
         {
             // "heuristics"
             // no date(s) of items - delete by retrieved date ( which is always set )
             
             [db executeUpdate:[NSString stringWithFormat:@"delete from %@ where bookmarked='false' and retrieved not in (select retrieved from %@ order by retrieved desc limit ?)", tableName, tableName], [NSNumber numberWithLong:processingScopeItems]];
             
             if ( [db lastErrorCode] )
                 NSLog(@"DB error outline: %@", ofOutline);
         }
     }];
}


-(void)loadAllItems:(OPMLOutlineXMLElement*)toOutline
{
    // need table name..
    NSString *tableName = [self tableName:toOutline];
    
    if (!tableName)
        return;
    
    // augment each item with original feed link to retain some connection to parent / see markitemAsRead for Today's item which lost it
    
    NSString *parentXmlUrl = [[toOutline attributeForName:@"xmlUrl"] stringValue];
    NSString *parentTitle = [[toOutline attributeForName:@"text"] stringValue];
    if (!parentTitle)
        parentTitle = [[toOutline attributeForName:@"title"] stringValue];
    NSString *parentHtmlUrl = [[toOutline attributeForName:@"htmlUrl"] stringValue];
    
    [[FMDBController sharedInstance].dbQueue inDatabase:^(FMDatabase *db)
    {
        FMResultSet *s = [db executeQuery:[NSString stringWithFormat:@"select * from %@ ORDER BY DATE DESC", tableName]];
        
        if ( [db lastErrorCode] )
        {
            NSLog(@"DB error outline: %@", toOutline);
            return;
        }
        
        while ( [s next] )
        {
            OPMLOutlineXMLElement *newNode = [[OPMLOutlineXMLElement alloc] initWithName:@"item"];
            
            NSString *link = [s stringForColumnIndex:0];
            NSString *title = [s stringForColumnIndex:1];
            NSString *identifier = [s stringForColumnIndex:2];
            NSString *date = [[DateFormatter sharedInstance].dateFormatter stringFromDate:[s dateForColumnIndex:3]];
            NSString *updated = [[DateFormatter sharedInstance].dateFormatter stringFromDate:[s dateForColumnIndex:4]];
            NSString *summary = [s stringForColumnIndex:5];
            NSString *content = [s stringForColumnIndex:6];
            NSString *author = [s stringForColumnIndex:7];
            NSString *bookmarked = [s stringForColumnIndex:8];
            NSString *read =[s stringForColumnIndex:9];
            
            NSArray * attributes = @[
                                     [DDXMLNode attributeWithName:@"title" stringValue:title]
                                     , [DDXMLNode attributeWithName:@"identifier" stringValue:identifier]
                                     , [DDXMLNode attributeWithName:@"link" stringValue:link]
                                     , [DDXMLNode attributeWithName:@"date" stringValue:date]
                                     , [DDXMLNode attributeWithName:@"updated" stringValue:updated]
                                     , [DDXMLNode attributeWithName:@"summary" stringValue:summary]
                                     , [DDXMLNode attributeWithName:@"content" stringValue:content]
                                     , [DDXMLNode attributeWithName:@"author" stringValue:author]
                                     , [DDXMLNode attributeWithName:@"bookmarked" stringValue:bookmarked]
                                     , [DDXMLNode attributeWithName:@"read" stringValue:read]
                                     , [DDXMLNode attributeWithName:@"parentXmlUrl" stringValue:parentXmlUrl]
                                     , [DDXMLNode attributeWithName:@"parentHtmlUrl" stringValue:parentHtmlUrl]
                                     , [DDXMLNode attributeWithName:@"parentTitle" stringValue:parentTitle]
                                     ];
            
            [newNode setAttributes:attributes];
            
            [toOutline addChild:newNode];
        }
        
        [s close];
    }];
}

-(void)loadBookmarkedItems:(OPMLOutlineXMLElement*)toOutline
{
    // need table name..
    NSString *tableName = [self tableName:toOutline];
    
    if (!tableName)
        return;
    
    NSString *parentXmlUrl = [[toOutline attributeForName:@"xmlUrl"] stringValue];
    NSString *parentTitle = [[toOutline attributeForName:@"text"] stringValue];
    if (!parentTitle)
        parentTitle = [[toOutline attributeForName:@"title"] stringValue];
    NSString *parentHtmlUrl = [[toOutline attributeForName:@"htmlUrl"] stringValue];
    
    [[FMDBController sharedInstance].dbQueue inDatabase:^(FMDatabase *db)
    {
        FMResultSet *s = [db executeQuery:[NSString stringWithFormat:@"select * from %@ where bookmarked='true' ORDER BY DATE DESC", tableName]
                          ];
        
        if ( [db lastErrorCode] )
        {
            NSLog(@"DB error outline: %@", toOutline);
            return;
        }
        
        while ( [s next] )
        {
            OPMLOutlineXMLElement *newNode = [[OPMLOutlineXMLElement alloc] initWithName:@"item"];
            
            NSString *link = [s stringForColumnIndex:0];
            NSString *title = [s stringForColumnIndex:1];
            NSString *identifier = [s stringForColumnIndex:2];
            NSString *date = [[DateFormatter sharedInstance].dateFormatter stringFromDate:[s dateForColumnIndex:3]];
            NSString *updated = [[DateFormatter sharedInstance].dateFormatter stringFromDate:[s dateForColumnIndex:4]];
            NSString *summary = [s stringForColumnIndex:5];
            NSString *content = [s stringForColumnIndex:6];
            NSString *author = [s stringForColumnIndex:7];
            NSString *bookmarked = [s stringForColumnIndex:8];
            NSString *read =[s stringForColumnIndex:9];
            
            NSArray * attributes = @[
                                     [DDXMLNode attributeWithName:@"title" stringValue:title]
                                     , [DDXMLNode attributeWithName:@"identifier" stringValue:identifier]
                                     , [DDXMLNode attributeWithName:@"link" stringValue:link]
                                     , [DDXMLNode attributeWithName:@"date" stringValue:date]
                                     , [DDXMLNode attributeWithName:@"updated" stringValue:updated]
                                     , [DDXMLNode attributeWithName:@"summary" stringValue:summary]
                                     , [DDXMLNode attributeWithName:@"content" stringValue:content]
                                     , [DDXMLNode attributeWithName:@"author" stringValue:author]
                                     , [DDXMLNode attributeWithName:@"bookmarked" stringValue:bookmarked]
                                     , [DDXMLNode attributeWithName:@"read" stringValue:read]
                                     , [DDXMLNode attributeWithName:@"parentXmlUrl" stringValue:parentXmlUrl]
                                     , [DDXMLNode attributeWithName:@"parentHtmlUrl" stringValue:parentHtmlUrl]
                                     , [DDXMLNode attributeWithName:@"parentTitle" stringValue:parentTitle]
                                     ];
            
            [newNode setAttributes:attributes];
            
            [toOutline addChild:newNode];
        }
        
        [s close];
    }];
}


-(void)loadSearchedItems:(OPMLOutlineXMLElement*)ofOutline toParent:(OPMLOutlineXMLElement*)parent
{
    // need table name..
    NSString *tableName = [self tableName:ofOutline];
    
    if (!tableName)
        return;
    
    if ( !searchedString || searchedString.length < 1 )
        return;
    
    NSString *parentXmlUrl = [[ofOutline attributeForName:@"xmlUrl"] stringValue];
    NSString *parentTitle = [[ofOutline attributeForName:@"text"] stringValue];
    if (!parentTitle)
        parentTitle = [[ofOutline attributeForName:@"title"] stringValue];
    NSString *parentHtmlUrl = [[ofOutline attributeForName:@"htmlUrl"] stringValue];
    
    [[FMDBController sharedInstance].dbQueue inDatabase:^(FMDatabase *db)
    {
        FMResultSet *s = nil;
        if ( searchedScope == 0 )
            s = [db executeQuery:[NSString stringWithFormat:@"select * from %@ where title like ? ORDER BY DATE DESC", tableName]
                          , [[@"%" stringByAppendingString:searchedString] stringByAppendingString:@"%"]
                          ];
        else if ( searchedScope == 1 )
            s = [db executeQuery:[NSString stringWithFormat:@"select * from %@ where title like ? OR summary like ? OR content like ? OR author like ? ORDER BY DATE DESC", tableName]
             , [[@"%" stringByAppendingString:searchedString] stringByAppendingString:@"%"]
             , [[@"%" stringByAppendingString:searchedString] stringByAppendingString:@"%"]
             , [[@"%" stringByAppendingString:searchedString] stringByAppendingString:@"%"]
             , [[@"%" stringByAppendingString:searchedString] stringByAppendingString:@"%"]
             ];
        else
            @throw @"not supported search scope";
        
        if ( [db lastErrorCode] )
        {
            NSLog(@"DB error outline: %@", ofOutline);
            return;
        }
        
        while ( [s next] )
        {
            OPMLOutlineXMLElement *newNode = [[OPMLOutlineXMLElement alloc] initWithName:@"item"];
            
            NSString *link = [s stringForColumnIndex:0];
            NSString *title = [s stringForColumnIndex:1];
            NSString *identifier = [s stringForColumnIndex:2];
            NSString *date = [[DateFormatter sharedInstance].dateFormatter stringFromDate:[s dateForColumnIndex:3]];
            NSString *updated = [[DateFormatter sharedInstance].dateFormatter stringFromDate:[s dateForColumnIndex:4]];
            NSString *summary = [s stringForColumnIndex:5];
            NSString *content = [s stringForColumnIndex:6];
            NSString *author = [s stringForColumnIndex:7];
            NSString *bookmarked = [s stringForColumnIndex:8];
            NSString *read =[s stringForColumnIndex:9];
            
            NSArray * attributes = @[
                                     [DDXMLNode attributeWithName:@"title" stringValue:title]
                                     , [DDXMLNode attributeWithName:@"identifier" stringValue:identifier]
                                     , [DDXMLNode attributeWithName:@"link" stringValue:link]
                                     , [DDXMLNode attributeWithName:@"date" stringValue:date]
                                     , [DDXMLNode attributeWithName:@"updated" stringValue:updated]
                                     , [DDXMLNode attributeWithName:@"summary" stringValue:summary]
                                     , [DDXMLNode attributeWithName:@"content" stringValue:content]
                                     , [DDXMLNode attributeWithName:@"author" stringValue:author]
                                     , [DDXMLNode attributeWithName:@"bookmarked" stringValue:bookmarked]
                                     , [DDXMLNode attributeWithName:@"read" stringValue:read]
                                     , [DDXMLNode attributeWithName:@"parentXmlUrl" stringValue:parentXmlUrl]
                                     , [DDXMLNode attributeWithName:@"parentHtmlUrl" stringValue:parentHtmlUrl]
                                     , [DDXMLNode attributeWithName:@"parentTitle" stringValue:parentTitle]
                                     ];
            
            [newNode setAttributes:attributes];
            
            [parent addChild:newNode];
        }
        
        [s close];
    }];
}


-(void)loadTodayItems:(OPMLOutlineXMLElement*)ofOutline toParent:(OPMLOutlineXMLElement*)parent
{
    // need table name..
    NSString *tableName = [self tableName:ofOutline];
    
    if (!tableName)
        return;
    
    NSString *parentXmlUrl = [[ofOutline attributeForName:@"xmlUrl"] stringValue];
    NSString *parentTitle = [[ofOutline attributeForName:@"text"] stringValue];
    if (!parentTitle)
        parentTitle = [[ofOutline attributeForName:@"title"] stringValue];
    NSString *parentHtmlUrl = [[ofOutline attributeForName:@"htmlUrl"] stringValue];
    
    // ( https://github.com/mattt/CupertinoYankee/blob/master/CupertinoYankee/NSDate%2BCupertinoYankee.m - )
    
    NSDateComponents *components = [[NSCalendar currentCalendar] components:NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit fromDate:[NSDate date]];
    
    NSDate *todayStart = [[NSCalendar currentCalendar] dateFromComponents:components]; // [[NSCalendar currentCalendar] startOfDayForDate:[NSDate date]]; iOS8
    
    components = [[NSDateComponents alloc] init];
    components.day = 1;
    NSDate *todayEnd = [[NSCalendar currentCalendar] dateByAddingComponents:components toDate:todayStart options:NSCalendarMatchNextTime];
    // [[NSCalendar currentCalendar] nextDateAfterDate:todayStart matchingComponents:components options:NSCalendarMatchNextTime]; // iOS 8+
    
    [[FMDBController sharedInstance].dbQueue inDatabase:^(FMDatabase *db)
    {
    
        FMResultSet *s = [db executeQuery:[NSString stringWithFormat:@"select * from %@ where date between ? AND ? ORDER BY DATE DESC", tableName]
                          , todayStart
                          , todayEnd
                          ];

        if ( [db lastErrorCode] )
        {
            NSLog(@"DB error outline: %@", ofOutline);
            return;
        }
        
        while ( [s next] )
        {
            OPMLOutlineXMLElement *newNode = [[OPMLOutlineXMLElement alloc] initWithName:@"item"];
            
            NSString *link = [s stringForColumnIndex:0];
            NSString *title = [s stringForColumnIndex:1];
            NSString *identifier = [s stringForColumnIndex:2];
            NSString *date = [[DateFormatter sharedInstance].dateFormatter stringFromDate:[s dateForColumnIndex:3]];
            NSString *updated = [[DateFormatter sharedInstance].dateFormatter stringFromDate:[s dateForColumnIndex:4]];
            NSString *summary = [s stringForColumnIndex:5];
            NSString *content = [s stringForColumnIndex:6];
            NSString *author = [s stringForColumnIndex:7];
            NSString *bookmarked = [s stringForColumnIndex:8];
            NSString *read =[s stringForColumnIndex:9];
            
            NSArray * attributes = @[
                                     [DDXMLNode attributeWithName:@"title" stringValue:title]
                                     , [DDXMLNode attributeWithName:@"identifier" stringValue:identifier]
                                     , [DDXMLNode attributeWithName:@"link" stringValue:link]
                                     , [DDXMLNode attributeWithName:@"date" stringValue:date]
                                     , [DDXMLNode attributeWithName:@"updated" stringValue:updated]
                                     , [DDXMLNode attributeWithName:@"summary" stringValue:summary]
                                     , [DDXMLNode attributeWithName:@"content" stringValue:content]
                                     , [DDXMLNode attributeWithName:@"author" stringValue:author]
                                     , [DDXMLNode attributeWithName:@"bookmarked" stringValue:bookmarked]
                                     , [DDXMLNode attributeWithName:@"read" stringValue:read]
                                     , [DDXMLNode attributeWithName:@"parentXmlUrl" stringValue:parentXmlUrl]
                                     , [DDXMLNode attributeWithName:@"parentHtmlUrl" stringValue:parentHtmlUrl]
                                     , [DDXMLNode attributeWithName:@"parentTitle" stringValue:parentTitle]
                                     ];
            
            [newNode setAttributes:attributes];
            
            [parent addChild:newNode];
        }
        
        [s close];
    }];
}

-(void)loadUnreadItems:(OPMLOutlineXMLElement*)toOutline
{
    // need table name..
    NSString *tableName = [self tableName:toOutline];
    
    if (!tableName)
        return;
    
    NSString *parentXmlUrl = [[toOutline attributeForName:@"xmlUrl"] stringValue];
    NSString *parentTitle = [[toOutline attributeForName:@"text"] stringValue];
    if (!parentTitle)
        parentTitle = [[toOutline attributeForName:@"title"] stringValue];
    NSString *parentHtmlUrl = [[toOutline attributeForName:@"htmlUrl"] stringValue];
    
    [[FMDBController sharedInstance].dbQueue inDatabase:^(FMDatabase *db)
     {
        FMResultSet *s = [db executeQuery:[NSString stringWithFormat:@"select * from %@ where read = 'false' ORDER BY DATE DESC", tableName]
                          ];
        
        if ( [db lastErrorCode] )
        {
            NSLog(@"DB error outline: %@", toOutline);
            return;
        }
        
        while ( [s next] )
        {
            OPMLOutlineXMLElement *newNode = [[OPMLOutlineXMLElement alloc] initWithName:@"item"];
            
            NSString *link = [s stringForColumnIndex:0];
            NSString *title = [s stringForColumnIndex:1];
            NSString *identifier = [s stringForColumnIndex:2];
            NSString *date = [[DateFormatter sharedInstance].dateFormatter stringFromDate:[s dateForColumnIndex:3]];
            NSString *updated = [[DateFormatter sharedInstance].dateFormatter stringFromDate:[s dateForColumnIndex:4]];
            NSString *summary = [s stringForColumnIndex:5];
            NSString *content = [s stringForColumnIndex:6];
            NSString *author = [s stringForColumnIndex:7];
            NSString *bookmarked = [s stringForColumnIndex:8];
            NSString *read =[s stringForColumnIndex:9];
            
            NSArray * attributes = @[
                                     [DDXMLNode attributeWithName:@"title" stringValue:title]
                                     , [DDXMLNode attributeWithName:@"identifier" stringValue:identifier]
                                     , [DDXMLNode attributeWithName:@"link" stringValue:link]
                                     , [DDXMLNode attributeWithName:@"date" stringValue:date]
                                     , [DDXMLNode attributeWithName:@"updated" stringValue:updated]
                                     , [DDXMLNode attributeWithName:@"summary" stringValue:summary]
                                     , [DDXMLNode attributeWithName:@"content" stringValue:content]
                                     , [DDXMLNode attributeWithName:@"author" stringValue:author]
                                     , [DDXMLNode attributeWithName:@"bookmarked" stringValue:bookmarked]
                                     , [DDXMLNode attributeWithName:@"read" stringValue:read]
                                     , [DDXMLNode attributeWithName:@"parentXmlUrl" stringValue:parentXmlUrl]
                                     , [DDXMLNode attributeWithName:@"parentHtmlUrl" stringValue:parentHtmlUrl]
                                     , [DDXMLNode attributeWithName:@"parentTitle" stringValue:parentTitle]
                                     ];
            
            [newNode setAttributes:attributes];
            
            [toOutline addChild:newNode];
        }
         
         [s close];
     }];
}

-(void)countCachedItems:(OPMLOutlineXMLElement*)ofOutline
               allCount:(NSUInteger*)allCount
             todayCount:(NSUInteger*)todayCount
            unreadCount:(NSUInteger*)unreadCount
        bookmarkedCount:(NSUInteger*)bookmarkedCount
          searchedCount:(NSUInteger*)searchedCount
{
    // need table name..
    
    if ( [[ofOutline name] isEqualToString:@"body"] )
        return;
    
    NSString *tableName = [self tableName:ofOutline];
    
    if (!tableName)
        return;
    
    *allCount = *todayCount = *unreadCount = 0;
    
    [[FMDBController sharedInstance].dbQueue inTransaction:^(FMDatabase *db, BOOL *rollback)
    {
        FMResultSet *s0 = [db executeQuery:[NSString stringWithFormat:@"select count(*) from %@", tableName]
                          ];
        
        if ( [db lastErrorCode] )
        {
            NSLog(@"DB error outline: %@", ofOutline);
            return;
        }
        
        if ( [s0 next] )
        {
            (*allCount) = [s0 intForColumnIndex:0];
            
            // bookmarks
            
            FMResultSet *s1 = [db executeQuery:[NSString stringWithFormat:@"select count(*) from %@ where bookmarked='true'", tableName]
                 ];
            
            if ( [db lastErrorCode] )
                NSLog(@"DB error outline: %@", ofOutline);
            
            if ( [s1 next] )
                (*bookmarkedCount) = [s1 intForColumnIndex:0];
            
            [s1 close];
            
            
            // search
            if ( searchedString.length > 0 )
            {
                FMResultSet *s3 = nil;
                
                if ( searchedScope == 0 )
                    s3 = [db executeQuery:[NSString stringWithFormat:@"select count(*) from %@ where title LIKE ? ", tableName]
                     , [[@"%" stringByAppendingString:searchedString] stringByAppendingString:@"%"]
                     ];
                else if ( searchedScope == 1 )
                    s3 = [db executeQuery:[NSString stringWithFormat:@"select count(*) from %@ where title LIKE ? OR summary like ? OR content like ? OR author like ?", tableName]
                          , [[@"%" stringByAppendingString:searchedString] stringByAppendingString:@"%"]
                          , [[@"%" stringByAppendingString:searchedString] stringByAppendingString:@"%"]
                          , [[@"%" stringByAppendingString:searchedString] stringByAppendingString:@"%"]
                          , [[@"%" stringByAppendingString:searchedString] stringByAppendingString:@"%"]
                          ];
                else
                    @throw @"not supported search scope";
                
                if ( [db lastErrorCode] )
                    NSLog(@"DB error outline: %@", ofOutline);
                
                if ( [s3 next] )
                    (*searchedCount) = [s3 intForColumnIndex:0];
                
                [s3 close];
            }
            
            
            // today
            NSDateComponents *components = [[NSCalendar currentCalendar] components:NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit fromDate:[NSDate date]];
            
            NSDate *todayStart = [[NSCalendar currentCalendar] dateFromComponents:components]; // [[NSCalendar currentCalendar] startOfDayForDate:[NSDate date]]; iOS8
            
            components = [[NSDateComponents alloc] init];
            components.day = 1;
            NSDate *todayEnd = [[NSCalendar currentCalendar] dateByAddingComponents:components toDate:todayStart options:NSCalendarMatchNextTime];
            // [[NSCalendar currentCalendar] nextDateAfterDate:todayStart matchingComponents:components options:NSCalendarMatchNextTime]; iOS 8+
            
            FMResultSet *s4 = [db executeQuery:[NSString stringWithFormat:@"select count(*) from %@ where date between ? AND ?", tableName]
                 , todayStart
                 , todayEnd
                 ];
            
            if ( [db lastErrorCode] )
                NSLog(@"DB error outline: %@", ofOutline);
            
            if ( [s4 next] )
                (*todayCount) = [s4 intForColumnIndex:0];
            
            [s4 close];
            
            // unread
            FMResultSet *s5 = [db executeQuery:[NSString stringWithFormat:@"select count(*) from %@ where read = 'false'", tableName]
                 ];
            
            if ( [db lastErrorCode] )
                NSLog(@"DB error outline: %@", ofOutline);

            if ( [s5 next] )
                (*unreadCount) = [s5 intForColumnIndex:0];
            
            [s5 close];
        }
        
        [s0 close];
    }];
}

#pragma mark - item serialization

-(void)markItemAsRead:(OPMLOutlineXMLElement*)item
{
    OPMLOutlineXMLElement *parent = (OPMLOutlineXMLElement*)[item parent];
    
    // need table name..
    NSString *tableName = [self tableName:parent];
    
    if (!tableName)
    {
        // empty parent might be from Today view ........................... - ( with body as parent )
        // try augmented feed name
        
        NSString *tableName2 = [[item attributeForName:@"parentXmlUrl"] stringValue];
        
        if (!tableName2)
            return;
        
        tableName = [@"items_" stringByAppendingString:[tableName2 MD5String]];
    }
    
    [[FMDBController sharedInstance].dbQueue inTransaction:^(FMDatabase *db, BOOL *rollback)
    {
        [db executeUpdate:[NSString stringWithFormat:@"update %@ set read='true' where link = ?", tableName]
         , [[item attributeForName:@"link"] stringValue]];
        
        if ( [db lastErrorCode] )
        {
            NSLog(@"DB error outline: %@", parent);
            *rollback = YES;
        }
    }];
}

-(void)markItemBookmarked:(OPMLOutlineXMLElement*)item clear:(BOOL)clear
{
    OPMLOutlineXMLElement *parent = (OPMLOutlineXMLElement*)[item parent];
    
    // need table name..
    NSString *tableName = [self tableName:parent];
    
    if (!tableName)
    {
        NSString *tableName2 = [[item attributeForName:@"parentXmlUrl"] stringValue];
        
        if (!tableName2)
            return;
        
        tableName = [@"items_" stringByAppendingString:[tableName2 MD5String]];
    }
    
    [[FMDBController sharedInstance].dbQueue inTransaction:^(FMDatabase *db, BOOL *rollback)
    {
        [db executeUpdate:[NSString stringWithFormat:@"update %@ set bookmarked=? where link = ?", tableName]
         , clear ? @"false" : @"true"
         , [[item attributeForName:@"link"] stringValue]];
        
        if ( [db lastErrorCode] )
            NSLog(@"DB error outline: %@", parent);
    }];
}

#pragma mark - outline

-(void)markOutlineAsRead:(OPMLOutlineXMLElement*)outline
{
    NSString *tableName = [self tableName:outline];
    
    if (!tableName)
        return;
    
    [[FMDBController sharedInstance].dbQueue inTransaction:^(FMDatabase *db, BOOL *rollback)
     {
         [db executeUpdate:[NSString stringWithFormat:@"update %@ set read='true'", tableName]];
         
         if ( [db lastErrorCode] )
         {
             NSLog(@"DB error outline: %@", outline);
             *rollback = YES;
         }
     }];
}

-(void)deleteOutline:(OPMLOutlineXMLElement*)outline
{
    // need table name..
    NSString *tableName = [self tableName:outline];
    
    if (!tableName)
        return;
    
    [[FMDBController sharedInstance].dbQueue inDatabase:^(FMDatabase *db)
    {
        [db executeUpdate:[NSString stringWithFormat:@"drop table %@", tableName]];
        
        // TODO: optimize on slow devices - this is slow when DB is bigger
        [db executeUpdate:@"VACUUM"];
    }];
}

-(void)clearCache
{
    NSMutableArray *tableNames = [NSMutableArray array];
    
    // iterate over all tables and delete content
    [[FMDBController sharedInstance].dbQueue inDatabase:^(FMDatabase *db)
    {
        FMResultSet *schema = [db getSchema];
        
        if ( [db lastErrorCode] )
            return;
        
        while ( [schema next] )
        {
            NSString *type = [schema stringForColumnIndex:0];
            if ( [type isEqualToString:@"table"] )
            {
                NSString *tableName = [schema stringForColumnIndex:1];
                [tableNames addObject:tableName];
            }
        }
        
        [schema close];
        
        for (NSString *tableName in tableNames)
        {
            [db executeUpdate:[NSString stringWithFormat:@"delete from %@ where bookmarked='false'", tableName]];
        }
        
        [db executeUpdate:@"VACUUM"];
    }];
}

#pragma mark - Helpers

-(NSString*)tableName:(OPMLOutlineXMLElement*)ofOutline
{
    NSString *tableName = [[ofOutline attributeForName:@"xmlUrl"] stringValue];
    
    if (!tableName)
        // empty link - is a directory ( or body )
        return nil;
    
    return [@"items_" stringByAppendingString:[tableName MD5String]];
}

// TODO: call this form everywhere

-(void)setAttribute:(NSString*)attributeName value:(NSString*)attributeValue node:(OPMLOutlineXMLElement*)node
{
    // Cannot add an attribute with a parent; detach or copy first'
    DDXMLNode *attribute = [node attributeForName:attributeName];
    
    NSMutableArray *attributes = [NSMutableArray new];
    
    for (DDXMLNode *el in node.attributes )
    {
        [el detach];
        [attributes addObject:el];
    }
    
    if ( !attribute )
        [attributes insertObject:[DDXMLNode attributeWithName:attributeName stringValue:attributeValue] atIndex:0];
    else
    {
        [attribute setStringValue:attributeValue];
    }
    
    [node setAttributes:attributes];
}
@end
