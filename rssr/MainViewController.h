//
//  MainViewController.h
//  rssr
//
//  Created by Rupert Pole on 17/11/15.
//
//

#import <UIKit/UIKit.h>
#import "JDFTooltips.h"

@interface MainViewController : UITableViewController

@property (weak, nonatomic) IBOutlet UIBarButtonItem *uiBarButtonItem;

@property (nonatomic, strong) JDFSequentialTooltipManager *tooltipManager;

@end
