//
//  FMDBController.m
//  rssr
//
//  Created by Rupert Pole on 22/12/15.
//
//

#import "FMDBController.h"
#import "OPMLOutlineXMLElement.h"

@interface FMDBController ()
{
    NSString *documentsDirectoryPath;
}

@end

@implementation FMDBController

+(FMDBController*)sharedInstance
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
        // create sqlite db if it does not exist
        
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        self->documentsDirectoryPath = [paths firstObject];
        
        
        self->_dbFilePath = [self->documentsDirectoryPath stringByAppendingPathComponent:@"rssr.sqlite"];
        
        if ( ! (self.dbQueue = [FMDatabaseQueue databaseQueueWithPath:self->_dbFilePath]) )
        {
            NSLog(@"OPEN %@ failed", self->_dbFilePath);
            
            return nil;
        }
        
        // did get the 100 error unknown - is this directly related ?
        // [self.db setShouldCacheStatements:YES];
        
        
        self.dbDateFormatter = [[NSDateFormatter alloc] init];
        self.dbDateFormatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
        self.dbDateFormatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
        self.dbDateFormatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US"];
    }
    
    return self;
}


-(void)dealloc
{
    // close
    [self.dbQueue close];
}


-(void)createTable:(NSString*)name result:(void (^)(BOOL))result
{
    
    [self.dbQueue inDatabase:^(FMDatabase *db) {
        
        [db executeUpdate:[NSString stringWithFormat:@"create table if not exists %@ ( link TEXT primary key, title TEXT, identifier TEXT, date INTEGER, updated INTEGER, summary TEXT, content TEXT, author TEXT, bookmarked TEXT, read TEXT, retrieved INTEGER, reserved1 TEXT, reserved2 TEXT, reserved3 TEXT, reserved4 TEXT, reserved5 TEXT )", name]];
        
        if ( [db lastErrorCode] )
        {
            NSLog(@"%d %@", [db lastErrorCode], [db lastErrorMessage] );
            if ( result )
                result(NO);
        }
        
        [db executeUpdate:[NSString stringWithFormat:@"create index if not exists idx_date_%@ ON %@ ( date )", name, name]];
        if ( [db lastErrorCode] )
        {
            NSLog(@"%d %@", [db lastErrorCode], [db lastErrorMessage] );
            if ( result )
                result(NO);
        }

        [db executeUpdate:[NSString stringWithFormat:@"create index if not exists idx_title_%@ ON %@ ( title )", name, name]];
        if ( [db lastErrorCode] )
        {
            NSLog(@"%d %@", [db lastErrorCode], [db lastErrorMessage] );
            if ( result )
                result(NO);
        }

        [db executeUpdate:[NSString stringWithFormat:@"create index if not exists idx_bookmarked_%@ ON %@ ( bookmarked )", name, name]];
        if ( [db lastErrorCode] )
        {
            NSLog(@"%d %@", [db lastErrorCode], [db lastErrorMessage] );
            if ( result )
                result(NO);
        }

        [db executeUpdate:[NSString stringWithFormat:@"create index if not exists idx_read_%@ ON %@ ( read )", name, name]];
        if ( [db lastErrorCode] )
        {
            NSLog(@"%d %@", [db lastErrorCode], [db lastErrorMessage] );
            if ( result )
                result(NO);
        }
        
    }];
    
    
    if ( result )
        result(YES);
}

@end
