//
//  DateFormatter.h
//  rssr
//
//  Created by Martin Cvengroš on 01/01/2017.
//
//

#import <Foundation/Foundation.h>

@interface DateFormatter : NSObject

+ (DateFormatter*)sharedInstance;

@property (strong, nonatomic) NSDateFormatter *dateFormatter;

@end
