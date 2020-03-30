//
//  SearchTableViewController.m
//  rssr
//
//  Created by Martin Cvengroš on 25/12/2016.
//
//

#import "SearchTableViewController.h"
#import "SubscriptionsController.h"
#import "TDBadgedCell.h"
#import "DSFavIconManager.h"
#import "UIImage+Utils.h"
#import "PageViewController.h"
#import "SVProgressHUD.h"
#import "AppDelegate.h"

NSString *searchedString;
NSUInteger searchedScope;

@interface SearchTableViewController ()
{
    OPMLOutlineXMLElement *searchedItems;
}
@end

@implementation SearchTableViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    // Uncomment the following line to preserve selection between presentations.
    // self.clearsSelectionOnViewWillAppear = NO;
    
    // Uncomment the following line to display an Edit button in the navigation bar for this view controller.
    // self.navigationItem.rightBarButtonItem = self.editButtonItem;
    
    
    // dont manually refresh the view
    self.refreshControl = nil;
    
    // show search bar
    self.searchBar.userInteractionEnabled = YES;
    self.searchBar.hidden = NO;
				
    // [self.searchDisplayController setActive:YES animated:YES];
    
    // self.searchBar.placeholder = searchedString;
    self.searchBar.text = nil; // searchedString;
    [self.searchBar setSelectedScopeButtonIndex:searchedScope];
    
    
    // previous / last search is shown on load
    if ( searchedString )
        self.title = [NSString stringWithFormat:@"%@:'%@'", NSLocalizedString(@"Search", nil), searchedString ];
    else
        self.title = NSLocalizedString(@"Search", nil);
    
    if ( [searchedString length] > 2 )
    {
        self->searchedItems = [[OPMLOutlineXMLElement alloc] initWithName:@"searchBody"];
        
        [[SubscriptionsController sharedInstance] loadSearchedItems:(OPMLOutlineXMLElement*)[SubscriptionsController sharedInstance].userOutlineDocument.bodyNode :self->searchedItems];
        
        [self.tableView reloadData];
    }
    
    
    // show keyboard
    [self.searchBar becomeFirstResponder];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

// ===================================================================
#pragma mark - UISearchBar

//-(void)searchBarTextDidEndEditing:(UISearchBar *)searchBar
//{
//    NSLog(@"%@ %@ in %@", @"searchBarTextDidEndEditing", searchBar.text, [searchBar selectedScopeButtonIndex] == 0 ? @"Headlines" : @"Fulltext" );
//}

-(void)searchBar:(UISearchBar *)searchBar selectedScopeButtonIndexDidChange:(NSInteger)selectedScope
{
    searchedScope = [searchBar selectedScopeButtonIndex];
    
    // show keyboard to allow easy tapping Search
    // [self.searchBar becomeFirstResponder];
    
    [self searchAndReload];
    
    // save params
    [((AppDelegate*)[[UIApplication sharedApplication] delegate]) saveSettings];
}

-(void)searchBarSearchButtonClicked:(UISearchBar *)searchBar
{
    if ( [searchBar.text length] < 3 )
        return;
    
    // NSLog(@"%@ %@ in %@", @"searchBarSearchButtonClicked", searchBar.text, [searchBar selectedScopeButtonIndex] == 0 ? @"Headlines" : @"Fulltext" );
    
    searchedString = searchBar.text;
    
    [self searchAndReload];
    
    // save params
    [((AppDelegate*)[[UIApplication sharedApplication] delegate]) saveSettings];
}

-(void)searchAndReload
{
    if ( [searchedString length] < 3 )
        return;
    
    OPMLOutlineXMLElement *body = (OPMLOutlineXMLElement*)[[SubscriptionsController sharedInstance] userOutlineDocument].bodyNode;
    
    NSUInteger searchAllCount = [[[body attributeForName:@"allItemsCount"] stringValue] integerValue];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        
        // clear previous search results
        [[SubscriptionsController sharedInstance] clearSearch];
        
        [[SubscriptionsController sharedInstance] refreshCounts:body progress:^(NSUInteger _progress) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [SVProgressHUD showProgress:(float)_progress / searchAllCount status:NSLocalizedString(@"Searching", nil)];
            });
        }];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            
            // self.searchBar.placeholder = searchedString;
            // [self.searchDisplayController setActive:NO animated:YES];
            
            self.title = [NSString stringWithFormat:@"%@:'%@'", NSLocalizedString(@"Search", nil), searchedString ];
            
            self->searchedItems = [[OPMLOutlineXMLElement alloc] initWithName:@"searchBody"];
            
            [[SubscriptionsController sharedInstance] loadSearchedItems:(OPMLOutlineXMLElement*)[SubscriptionsController sharedInstance].userOutlineDocument.bodyNode :self->searchedItems];
            
            [self.tableView reloadData];
            
            // hide keyboard
            [self.searchBar resignFirstResponder];
            
            [SVProgressHUD dismiss];
        });
    });
}

// ===================================================================
#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return self->searchedItems.childCount;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    TDBadgedCell *cell = [self.tableView dequeueReusableCellWithIdentifier:@"Cell" forIndexPath:indexPath];
    
    OPMLOutlineXMLElement *feedItem = (OPMLOutlineXMLElement*)[self->searchedItems childAtIndex:indexPath.row];
    
    if ( [[feedItem name] isEqualToString:@"item"] )
    {
        cell.textLabel.text = [[feedItem attributeForName:@"title"] stringValue];
        cell.detailTextLabel.text = [[feedItem attributeForName:@"date"] stringValue];
        
        NSString *urlString = [[feedItem attributeForName:@"htmlUrl"] stringValue];
        if (!urlString )
            urlString = [[feedItem attributeForName:@"parentHtmlUrl"] stringValue];
        
        NSURL *url = [NSURL URLWithString:urlString];
        
        if ( url )
        {
            CGSize size = CGSizeMake(32, 32);
            
            cell.imageView.image = [[DSFavIconManager sharedInstance] iconForURL:url
                                                                 downloadHandler:^(UINSImage *icon)
                                    {
                                        cell.imageView.image = [UIImage imageScaledToSize:icon size:size];
                                        [cell.imageView setNeedsDisplay];
                                    }];
            
            cell.imageView.image = [UIImage imageScaledToSize:cell.imageView.image size:size];
        }
        else
        {
            cell.imageView.image = nil;
        }
    }
    
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

// ===================================================================
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    NSIndexPath *indexPath = [self.tableView indexPathForSelectedRow];
    OPMLOutlineXMLElement *feedItem = (OPMLOutlineXMLElement*)[self->searchedItems childAtIndex:indexPath.row];
    
    PageViewController *pageViewController = nil;
    
    // iPad / `new` iOS
    if ( [[segue destinationViewController] isKindOfClass:[UINavigationController class]] )
    {
        pageViewController = (PageViewController *)[[segue destinationViewController] topViewController];
    }
    // iPhone / `old` iOS
    else if ( [[segue destinationViewController] isKindOfClass:[PageViewController class]] )
    {
        pageViewController = (PageViewController *)[segue destinationViewController];
    }
    else
    {
        // GFY
        NSLog(@"What is this ? Where are we ? What is this madness ? SplitViewController on some future unknown device ?");
    }
    
    // the UISplitViewController's primary view will be hidden -> UIPageViewController needs backbutton:
    pageViewController.navigationItem.leftBarButtonItem = self.splitViewController.displayModeButtonItem;
    pageViewController.navigationItem.leftItemsSupplementBackButton = YES;
    
    // slide the master
    // TODO: note this will slide correctly in portrait and not slide in landscape, but only on iPad. On iPhone 6+ it will slide in landscape ... :-(
    UIBarButtonItem *barButtonItem = self.splitViewController.displayModeButtonItem;
    [[UIApplication sharedApplication] sendAction:barButtonItem.action to:barButtonItem.target from:nil forEvent:nil];
    
    // UISplitViewControllerDisplayModePrimaryHidden will make master always be hidden in every orientation
    // self.splitViewController.preferredDisplayMode = UISplitViewControllerDisplayModePrimaryHidden;
    
    
    
    // set up PageViewController and jump to specific item / page
    [[PageViewModelController sharedInstance] setOutline:self->searchedItems];
    
    [PageViewModelController sharedInstance].pageViewControllerDelegate = pageViewController;
    
    [pageViewController setDataSource:[PageViewModelController sharedInstance] type:DisplayedDataType_SearchResults];
    
    
    DetailViewController *detailVC = [[PageViewModelController sharedInstance] viewControllerAtIndex:indexPath.row storyboard:self.storyboard];
    
    NSArray *controllers = @[detailVC];
    
    [pageViewController setViewControllers:controllers direction:UIPageViewControllerNavigationDirectionForward animated:NO completion:nil];
    
    pageViewController.currentlyDisplayedDetailViewController = detailVC;
    
    // if ( self.displayedDataType != DisplayedDataType_SubscriptionChooser )
    [[SubscriptionsController sharedInstance] markItemAsRead:feedItem];
}

@end
