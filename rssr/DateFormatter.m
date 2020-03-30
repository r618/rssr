//
//  DateFormatter.m
//  rssr
//
//  Created by Martin Cvengroš on 01/01/2017.
//
//

#import "DateFormatter.h"

@implementation DateFormatter

+ (DateFormatter*)sharedInstance
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
       	self.dateFormatter = [[NSDateFormatter alloc] init];
        // Dec 22, 2011, 4:48:40 PM for UX
        [self.dateFormatter setDateStyle:NSDateFormatterMediumStyle];
        [self.dateFormatter setTimeStyle:NSDateFormatterMediumStyle];
    }
    
    return self;
}

@end
