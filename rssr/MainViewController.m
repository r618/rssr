//
//  MainViewController.m
//  rssr
//
//  Created by Rupert Pole on 17/11/15.
//
//

#import "MainViewController.h"
#import "MasterViewController.h"
#import "SubscriptionsController.h"
#import "TDBadgedCell.h"
#import "SVProgressHUD.h"
#import "FontAwesomeKit/FAKFontAwesome.h"
#import "DSFavIconManager.h"
#import "PageViewController.h"
#import "FeedController.h"
#import "DateFormatter.h"

extern NSDate *lastFullUpdate;
NSString *statusText; // preserve status across views
extern BOOL firstLaunch;
BOOL tooltipsMainCompleted;
BOOL tooltipsMasterCompleted;
BOOL tooltipsDetail_1_Completed;
BOOL tooltipsDetail_2_Completed;
BOOL tooltipsDetail_3_Completed;
BOOL tooltipsDetail_4_Completed;

@interface MainViewController ()
{
    UILabel *statusLabel;
}
@end

@implementation MainViewController

#pragma mark - UIViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    // setup 'status' label view
    // toolbar.tintColor == nil -> is dark   ?
    // toolbar.tintColor != nil -> is bright ?
    
    UIColor *tintColor = self.navigationController.toolbar.tintColor ? [UIColor darkTextColor] : [UIColor whiteColor];
    
    self->statusLabel = [[UILabel alloc] init];
    [self->statusLabel setBackgroundColor:[UIColor clearColor]];
    [self->statusLabel setTextColor:tintColor];
    [self->statusLabel setTextAlignment:NSTextAlignmentCenter];
    [self->statusLabel setShadowColor:[UIColor colorWithWhite:0.0 alpha:0.5]];
    [self->statusLabel setShadowOffset:CGSizeMake(0,-1)];
    [self->statusLabel setFont:[UIFont systemFontOfSize:14.0]];

    [self.uiBarButtonItem setCustomView:self->statusLabel];

    
    // call this whounce
    [DSFavIconManager sharedInstance].useAppleTouchIconForHighResolutionDisplays = YES;
    
    
    // refresh control
    self.refreshControl = [[UIRefreshControl alloc] init];
    
    [self.refreshControl addTarget:self action:@selector(refresh:) forControlEvents:UIControlEventValueChanged];
    
//    UILabel *messageLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, self.view.bounds.size.height)];
//    
//    messageLabel.text = @"No data is currently available. Please pull down to refresh.";
//    messageLabel.textColor = [UIColor blackColor];
//    messageLabel.numberOfLines = 0;
//    messageLabel.textAlignment = NSTextAlignmentCenter;
//    messageLabel.font = [UIFont fontWithName:@"Optima-Regular" size:20];
//    [messageLabel sizeToFit];
//    
//    self.tableView.backgroundView = messageLabel;
//    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;

    // refresh UI if background fetch and this view is still visible when opened
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshCounts) name:@"itemsChanged" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(statusChanged:) name:@"statusChanged" object:nil];
    
    self.title = @"rssr"; // RssЯ
    
    FAKFontAwesome *rssIcon = [FAKFontAwesome rssIconWithSize:16];
    // [rssIcon addAttribute:NSForegroundColorAttributeName value:self.navigationController.navigationBar.tintColor];
    
    NSMutableAttributedString *attString = [[NSMutableAttributedString alloc] init];
    [attString appendAttributedString:[rssIcon attributedString]];
    [attString addAttribute:NSForegroundColorAttributeName value:tintColor range:NSMakeRange(0, 1)];
    
    NSShadow *shadow = [[NSShadow alloc] init];
    [shadow setShadowColor:[UIColor colorWithWhite:.0f alpha:1.f]];
    [shadow setShadowOffset:CGSizeMake(0, -1)];
    [attString addAttribute:NSShadowAttributeName value:shadow range:NSMakeRange(0,1)];
    
    
    
    NSString *titleString = @"  rssr";
    NSMutableAttributedString *attString2 = [[NSMutableAttributedString alloc] initWithString:titleString attributes:nil];
    [attString2 addAttribute:NSForegroundColorAttributeName value:tintColor range:NSMakeRange(0, [titleString length])];
    [attString2 addAttribute:NSShadowAttributeName value:shadow range:NSMakeRange(0, [titleString length])];
    
    [attString appendAttributedString:attString2];
    
    
    UILabel *titleLabel = [[UILabel alloc] init];
    [titleLabel setTextAlignment:NSTextAlignmentCenter];
    [titleLabel setBackgroundColor:[UIColor clearColor]];
    [titleLabel setOpaque:NO];
    
    titleLabel.attributedText = attString; // [rssIcon attributedString]
    
    [titleLabel sizeToFit];
    
    self.navigationItem.titleView = titleLabel;
}


-(void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];

    if ( statusText )
        [self statusChanged:[NSNotification notificationWithName:@"viewShownNotif" object:nil userInfo:@{@"status" : statusText}]];

    [self reloadTableView];
    
    // tooltips
    
    if ( firstLaunch )
    {
        if (!tooltipsMainCompleted)
        {
            if (!self.tooltipManager)
            {
                self.tooltipManager = [[JDFSequentialTooltipManager alloc] initWithHostView:self.view];
            
                NSIndexPath *ip = [NSIndexPath indexPathForRow:0 inSection:0];
                TDBadgedCell *cell = [self.tableView cellForRowAtIndexPath:ip];
                UIView *view = cell.textLabel;

                [self.tooltipManager addTooltipWithTargetView:view
                                                     hostView:self.view
                                                  tooltipText:@"Start here to add a subscription\n\n(tap to dismiss this help text)"
                                               arrowDirection:JDFTooltipViewArrowDirectionUp
                                                        width:200.0f
                                          showCompletionBlock:^{
                                              ;
                                          }
                                          hideCompletionBlock:^{
                                              tooltipsMainCompleted = YES;
                                          }
                 ];
                
                [self.tooltipManager showNextTooltip];
            }
        }
    }
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
}

-(void)statusChanged:(NSNotification*)notification
{
    statusText = [notification.userInfo objectForKey:@"status"];

    // dont touch if detail / PageViewController is visible in this NC ( 'iPhone' )
    if ( [self.navigationController.topViewController isKindOfClass:[PageViewController class]] )
        return;

    if ( notification.userInfo )
    {
        [self->statusLabel setText:statusText];
        [self->statusLabel sizeToFit];
        
        [self.navigationController setToolbarHidden:NO animated:YES];
    }
    else
    {
        self->statusLabel.text = @"";
        [self->statusLabel sizeToFit];
        
        [self.navigationController setToolbarHidden:YES animated:YES];
    }
}

-(void)reloadTableView
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.tableView reloadData];
    });
}

-(void)refreshCounts
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        
        OPMLOutlineXMLElement *body = (OPMLOutlineXMLElement*)[[SubscriptionsController sharedInstance] userOutlineDocument].bodyNode;
        
        NSUInteger allCount = [[[body attributeForName:@"allItemsCount"] stringValue] integerValue];
        
        [[SubscriptionsController sharedInstance] refreshCounts:body
                                                       progress:^void (NSUInteger _progress) {
                                                           
                                                           dispatch_async(dispatch_get_main_queue(), ^{
                                                               NSString *status = [NSString stringWithFormat:@"%@ %ld / %ld", NSLocalizedString(@"Processing", nil), (unsigned long)_progress, (unsigned long)allCount];
                                                               [[NSNotificationCenter defaultCenter] postNotificationName:@"statusChanged" object:nil userInfo:@{@"status":status}];
                                                           });
                                                       }];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            
            [[NSNotificationCenter defaultCenter] postNotificationName:@"statusChanged" object:nil userInfo:nil];
            
            [self reloadTableView];
        });
    });
}

#pragma mark - Table view data source

-(void)refresh:(id)sender
{
    if ( [SubscriptionsController sharedInstance].isRefreshing )
    {
        [self.refreshControl endRefreshing];
        return;
    }
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        
        OPMLOutlineXMLElement *body = (OPMLOutlineXMLElement*)[[SubscriptionsController sharedInstance] userOutlineDocument].bodyNode;
        
        NSLog(@"== :: == :: MainVC refreshFeeds.");
        
        [[SubscriptionsController sharedInstance] refreshFeeds:body
                                          progressFeedCallbackPre:^(NSString * progressFeedName)
         {
             dispatch_async(dispatch_get_main_queue(), ^{
                 NSString *status = [NSString stringWithFormat:@"%@ %@", NSLocalizedString(@"Updating", nil), progressFeedName];
                 [[NSNotificationCenter defaultCenter] postNotificationName:@"statusChanged" object:nil userInfo:@{@"status":status}];
             });
         }
                                              progressFeedCallback:^(NSString * progressFeedName)
        {
            dispatch_async(dispatch_get_main_queue(), ^{
                NSString *status = [NSString stringWithFormat:@"%@ %@", NSLocalizedString(@"Updated", nil), progressFeedName];
                [[NSNotificationCenter defaultCenter] postNotificationName:@"statusChanged" object:nil userInfo:@{@"status":status}];
            });
        }];

        NSUInteger allCount = [[[body attributeForName:@"allItemsCount"] stringValue] integerValue];

        [[SubscriptionsController sharedInstance] refreshCounts:body
                                                       progress:^void (NSUInteger _progress) {

                                                           dispatch_async(dispatch_get_main_queue(), ^{
                                                               NSString *status = [NSString stringWithFormat:@"%@ %ld / %ld", NSLocalizedString(@"Processing", nil), (unsigned long)_progress, (unsigned long)allCount];
                                                               [[NSNotificationCenter defaultCenter] postNotificationName:@"statusChanged" object:nil userInfo:@{@"status":status}];
                                                           });
                                                       }];

        NSLog(@"== :: == :: MainVC refreshFeeds ended.");
        
        dispatch_async(dispatch_get_main_queue(), ^{

            [[NSNotificationCenter defaultCenter] postNotificationName:@"statusChanged" object:nil userInfo:nil];

            [self.refreshControl endRefreshing];

            [self reloadTableView];
        });
    });
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 6;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return 1;
}

-(NSString*)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    switch (section)
    {
        // last update text for Today
        case 1: {
            NSString *lastUpdateString = nil;

            if ([lastFullUpdate isEqualToDate:[NSDate distantPast]] || !lastFullUpdate)
                lastUpdateString = NSLocalizedString(@"never", nil);
            else {
                // difference between today and lastFullUpdate in days
                // consider today difference, yesterday difference and the rest
                
                NSInteger daysDifference = 0;
                
                NSDateComponents *dateComponents = [[NSCalendar currentCalendar] components:NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit fromDate:lastFullUpdate toDate:[NSDate date] options:0];

                daysDifference = [dateComponents day];
                
                // if diff is 0, but days don't match ( not enought time has passed yet ), consider it a new day
                
                // TODO: note - this is supposed the start of the day is at midnight
                // i have no idea how to proceed if it were customisable for now...
                
                if ( daysDifference == 0 )
                {
                    NSDateComponents *compsLastFullUpdate = [[NSCalendar currentCalendar] components:NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit fromDate:lastFullUpdate];
    
                    NSDateComponents *compsToday = [[NSCalendar currentCalendar] components:NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit fromDate:[NSDate date]];
                    
                    if ( [compsLastFullUpdate year] == [compsToday year]
                        && [compsLastFullUpdate month] == [compsToday month]
                        && [compsLastFullUpdate day] != [compsToday day]
                        )
                        daysDifference = 1;
                }

                NSDateFormatter *timeFormatter = [NSDateFormatter new];
                timeFormatter.dateFormat = @"HH:mm:ss";

                switch (daysDifference) {
                    case 0:
                        lastUpdateString = [@"today, " stringByAppendingString:[timeFormatter stringFromDate:lastFullUpdate]];
                        break;

                    case 1:
                        lastUpdateString = [@"yesterday, " stringByAppendingString:[timeFormatter stringFromDate:lastFullUpdate]];
                        break;

                    default:
                        lastUpdateString = [[DateFormatter sharedInstance].dateFormatter stringFromDate:lastFullUpdate];
                        break;
                }
            }

            return [NSString stringWithFormat:@"Last full update: %@", lastUpdateString];
        }

            break;

        default:
            break;
    }

    return nil;
}


- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    TDBadgedCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Cell" forIndexPath:indexPath];
    NSString *title;
    
    OPMLOutlineXMLElement *body = (OPMLOutlineXMLElement*)[[SubscriptionsController sharedInstance] userOutlineDocument].bodyNode;
    
    NSUInteger cnt = 0;
    
    switch (indexPath.section)
    {
        case 0:
            title = [@"📜  " stringByAppendingString:NSLocalizedString(@"Subscriptions", nil)];
            cnt = [[[body attributeForName:@"allItemsCount"] stringValue] integerValue];
            [cell setAccessoryType:UITableViewCellAccessoryDisclosureIndicator];
            break;
            
        case 1:
            title = [@"🆕  " stringByAppendingString:NSLocalizedString(@"Today", nil)];
            cnt = [[[body attributeForName:@"todayItemsCount"] stringValue] integerValue];
            cnt ? [cell setAccessoryType:UITableViewCellAccessoryDisclosureIndicator] : [cell setAccessoryType:UITableViewCellAccessoryNone];
            break;
            
        case 2:
            title = [@"📰  " stringByAppendingString:NSLocalizedString(@"Unread", nil)];
            cnt = [[[body attributeForName:@"unreadItemsCount"] stringValue] integerValue];
            cnt ? [cell setAccessoryType:UITableViewCellAccessoryDisclosureIndicator] : [cell setAccessoryType:UITableViewCellAccessoryNone];
            break;
            
        case 3:
            title = [@"🔖  " stringByAppendingString:NSLocalizedString(@"Bookmarked", nil)];
            cnt = [[[body attributeForName:@"bookmarkedItemsCount"] stringValue] integerValue];
            cnt ? [cell setAccessoryType:UITableViewCellAccessoryDisclosureIndicator] : [cell setAccessoryType:UITableViewCellAccessoryNone];
            break;
            
        case 4:
			title = [@"🔎  " stringByAppendingString:NSLocalizedString(@"Search", nil)];
            cnt = [[[body attributeForName:@"searchedItemsCount"] stringValue] integerValue];
            [cell setAccessoryType:UITableViewCellAccessoryDisclosureIndicator];
			break;
            
		case 5:
			title = [@"⚙  " stringByAppendingString:NSLocalizedString(@"Settings", nil)]; // ✔️
			cnt = 0;
            [cell setAccessoryType:UITableViewCellAccessoryDisclosureIndicator];
			break;
			
        default:
            break;
    }
    
    cell.textLabel.text = title;
    
    if ( cnt )
    {
        cell.badgeString = [NSString stringWithFormat:@"%lu", (unsigned long)cnt];
        cell.badge.fontSize = 14;
        cell.badge.radius = 6.;
        cell.badgeRightOffset = 12.;
        cell.badgeLeftOffset = 12.;
        
        [cell setNeedsLayout];
    }
    else
    {
        cell.badgeString = nil;
    }
    
    cell.detailTextLabel.text = nil;
    
    if ( [cell accessoryType] == UITableViewCellAccessoryNone )
        [cell setUserInteractionEnabled:NO];
    else
        [cell setUserInteractionEnabled:YES];
    
    return cell;
}

/*
// Override to support conditional editing of the table view.
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    // Return NO if you do not want the specified item to be editable.
    return YES;
}
*/

/*
// Override to support editing the table view.
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        // Delete the row from the data source
        [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
    } else if (editingStyle == UITableViewCellEditingStyleInsert) {
        // Create a new instance of the appropriate class, insert it into the array, and add a new row to the table view
    }   
}
*/

/*
// Override to support rearranging the table view.
- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)fromIndexPath toIndexPath:(NSIndexPath *)toIndexPath {
}
*/

/*
// Override to support conditional rearranging of the table view.
- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    // Return NO if you do not want the item to be re-orderable.
    return YES;
}
*/

#pragma mark - Navigation

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    //storyboards should use segues and override prepareForSegue instead
    //but here we need custom logic to determine which segue to use
    
    if ( indexPath.section == 4 )
        [self performSegueWithIdentifier:@"showSearch" sender:self];
    else if ( indexPath.section == 5 )
        [self performSegueWithIdentifier:@"showSettings" sender:self];
    else
        [self performSegueWithIdentifier:@"showMaster" sender:self];
}

- (BOOL)shouldPerformSegueWithIdentifier:(NSString *)identifier sender:(id)sender
{
    //ignore segue from cell since we we are calling manually in didSelectRowAtIndexPath
    return (sender == self);
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    NSIndexPath *indexPath = [self.tableView indexPathForSelectedRow];
    
    if ( indexPath.section < 4 )
    {
        // load outlines into masterviewcontroller
        
        MasterViewController *vc = [segue destinationViewController];
        
        vc.viewOutline = (OPMLOutlineXMLElement*)[[SubscriptionsController sharedInstance] userOutlineDocument].bodyNode;
        
        switch (indexPath.section)
        {
            case 0:
                vc.displayedDataType = DisplayedDataType_Subscriptions;
                
                break;
                
            case 1:
                vc.displayedDataType = DisplayedDataType_Today;
                
                break;
                
            case 2:
                vc.displayedDataType = DisplayedDataType_Unread;
                
                break;
                
            case 3:
                vc.displayedDataType = DisplayedDataType_Bookmarks;
                
                break;
            case 4:
                vc.displayedDataType = DisplayedDataType_SearchResults;
                
                break;
                
            default:
                break;
        }
    }
}

@end
