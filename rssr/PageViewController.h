//
//  PageViewController.h
//  rssr
//
//  Created by Rupert Pole on 07/12/15.
//
//

#import <UIKit/UIKit.h>
#import "DetailViewController.h"
#import "MasterViewController.h"
#import "PageViewModelController.h"

@interface PageViewController : UIPageViewController<UIPageViewControllerDelegate, UIWebViewDelegate>

// (fucking) navigation bar not working from detail
@property (strong, nonatomic) IBOutlet UIBarButtonItem *actionButton;
- (IBAction)action:(UIBarButtonItem *)sender;

@property (strong, nonatomic) IBOutlet UIBarButtonItem *stepperBarButtonItem;
@property (strong, nonatomic) IBOutlet UIStepper *stepperBarButton;
- (IBAction)stepperValueChanged:(UIStepper *)sender;

// set from outside for the first page (no transition events)
@property (strong, nonatomic) DetailViewController *currentlyDisplayedDetailViewController;

// read from outside while e.g. refreshing
@property (strong, nonatomic) NSString* currentLink;

@property (strong, nonatomic) IBOutlet UIBarButtonItem *organizeBarButtonItem;
- (IBAction)organize:(UIBarButtonItem *)sender;


@property (strong, nonatomic) IBOutlet UIBarButtonItem *restoreItemBarButtonItem;
- (IBAction)restoreItem:(UIBarButtonItem *)sender;

-(void)setDataSource:(PageViewModelController*)ds type:(DisplayedDataType)type;

@property (readonly, nonatomic) DisplayedDataType displayedDataType;

@property (strong, nonatomic) IBOutlet UIBarButtonItem *favIconBarBurronItem;

-(BOOL)isLocalContent;

@end
