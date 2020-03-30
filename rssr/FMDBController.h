//
//  FMDBController.h
//  rssr
//
//  Created by Rupert Pole on 22/12/15.
//
//

#import <Foundation/Foundation.h>
#import "FMDB.h"

@interface FMDBController : NSObject

+(FMDBController*)sharedInstance;

@property (nonatomic,strong) FMDatabaseQueue *dbQueue;
@property (nonatomic,strong) NSDateFormatter *dbDateFormatter;
@property (nonatomic, strong, readonly) NSString *dbFilePath;

-(void)createTable:(NSString*)name result:(void (^)(BOOL))result;

@end
