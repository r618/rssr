//
//  SettingsTableViewController.h
//  rssr
//
//  Created by Rupert Pole on 11/12/15.
//
//

#import <UIKit/UIKit.h>
#import <MessageUI/MFMailComposeViewController.h>

@interface SettingsTableViewController : UITableViewController<MFMailComposeViewControllerDelegate, UIAlertViewDelegate>

@property (strong, nonatomic) IBOutlet UISlider *sliderScope;
- (IBAction)sliderScopeChanged:(UISlider *)sender;

@property (weak, nonatomic) IBOutlet UILabel *subscriptionsCount;
@property (weak, nonatomic) IBOutlet UILabel *itemsCount;

@end
