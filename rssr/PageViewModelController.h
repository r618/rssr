//
//  PageViewModelController.h
//  rssr
//
//  Created by Rupert Pole on 03/12/15.
//
//

#import <UIKit/UIKit.h>
#import "OPMLOutlineXMLElement.h"


@class DetailViewController;
@class PageViewController;

@interface PageViewModelController : NSObject <UIPageViewControllerDataSource>

+ (PageViewModelController*)sharedInstance;

- (DetailViewController *)viewControllerAtIndex:(NSUInteger)index storyboard:(UIStoryboard *)storyboard;
- (NSUInteger)indexOfViewController:(DetailViewController *)viewController;

@property (strong, nonatomic) PageViewController *pageViewControllerDelegate;


-(void)setOutline:(OPMLOutlineXMLElement *)outlineWithItems;

-(void)clearOutline;
@end
