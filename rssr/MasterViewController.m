//
//  MasterViewController.m
//  rssr
//
//  Created by Rupert Pole on 24/10/15.
//
//

#import "MasterViewController.h"
#import "DetailViewController.h"
#import "SubscriptionsController.h"
#import "TDBadgedCell.h"
#import "PageViewModelController.h"
#import "PageViewController.h"
#import "DSFavIconManager.h"
#import "SVProgressHUD.h"
#import "UIImage+Utils.h"
#import "FeedController.h"

extern  NSString *statusText;
extern BOOL firstLaunch;
extern BOOL tooltipsMasterCompleted;

static PageViewController *pageViewController; // currently shown static cause why not

typedef enum { TableView_Inserting, TableView_Deleting} TableView_Operation;

@interface MasterViewController ()
{
    OPMLOutlineXMLElement *viewOutlineWithItems; // only loaded and used when viewing single feed
    NSMutableArray *viewOutlineChildIndices;
    
    UILabel *statusLabel;
    BOOL isFeed;
    
    TableView_Operation tableView_Operation;
    NSIndexPath *indexPathOfTheRowToBeDeleted;
}

@property (nonatomic, strong) UIBarButtonItem *addButton;
@property (nonatomic, strong) UITapGestureRecognizer *singleTapButtonRecognizer;
@property (nonatomic, strong) UITapGestureRecognizer *doubleTapButtonRecognizer;
// @property (nonatomic, strong) UILongPressGestureRecognizer *longTapButtonRecognizer;
// @property (nonatomic, strong) UILongPressGestureRecognizer *longTapTableViewRecognizer;

@property (nonatomic) BOOL enteringNewFolder;

@end

@implementation MasterViewController

// http://stackoverflow.com/questions/19784454/when-should-i-use-synthesize-explicitly

#pragma mark - view controller

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

    
    
    
    self->isFeed = [[self.viewOutline attributeForName:@"xmlUrl"] stringValue].length > 0;
    
    self.clearsSelectionOnViewWillAppear = NO;
	
    if ( [[self.navigationController viewControllers] count] == 2  )
    {
        switch (self.displayedDataType )
        {
            case DisplayedDataType_Subscriptions:
                self.title = NSLocalizedString(@"Subscriptions", nil);
                break;
                
            case DisplayedDataType_Today:
                self.title = NSLocalizedString(@"Today", nil);
                break;
                
            case DisplayedDataType_Unread:
                self.title = NSLocalizedString(@"Unread", nil);
                break;
                
            case DisplayedDataType_Bookmarks:
                self.title = NSLocalizedString(@"Bookmarked", nil);
                break;
				
            default:
                break;
        }
    }
//    else if ( self.displayedDataType == DisplayedDataType_SubscriptionChooser )
//    {
//        self.title = NSLocalizedString(@"Choose from feeds", nil);
//        
//        if ( self->isFeed )
//            self.title = [[self.viewOutline attributeForName:@"text"] stringValue];
//    }
    else
    {
        self.title = [[self.viewOutline attributeForName:@"text"] stringValue];
        
        // if there's no title try other options for iOS 6 (otherwise the back button won't show up )
        if ([self.title length] < 1)
        {
            self.title = [[self.viewOutline attributeForName:@"title"] stringValue];
            
            if ([self.title length] < 1)
            {
                NSURL *url = [NSURL URLWithString:[[self.viewOutline attributeForName:@"htmlUrl"] stringValue]];
                self.title = url.resourceSpecifier;
            }
        }
    }
    
    // viewDidLoad is called for every new instance of view controller
    
    if ( self->isFeed )
    {
        // load items into separate outline to not poison main document
        self->viewOutlineWithItems = [[OPMLOutlineXMLElement alloc] initWithXMLString:[self.viewOutline XMLString] error:nil];
        
        [self loadItems];
        
        // load and display site icon
        NSURL *url = [NSURL URLWithString:[[self.viewOutline attributeForName:@"htmlUrl"] stringValue]];
        
        if ( url )
        {
            UIImageView *imageView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 28.0f, 28.0f)];
            CGSize size = CGSizeMake(28, 28);
            
            imageView.image = [[DSFavIconManager sharedInstance] iconForURL:url
                                                            downloadHandler:^(UINSImage *icon)
                               {
                                   imageView.image = [UIImage imageScaledToSize:icon size:size];
                                   
                                   // new UIBarButtonItem works. setting customView to IBOutlet UIBarButton ... does not.
                                   self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:imageView];
                               }];
            
            imageView.image = [UIImage imageScaledToSize:imageView.image size:size];
            
            // new UIBarButtonItem works. setting customView to IBOutlet UIBarButton ... does not.
            self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:imageView];
        }
    }
    else
    {
        self->viewOutlineWithItems = nil;
        
        // display editing controls if not viewing single rss subscription and viewing all subscriptions
        
        if (self.displayedDataType == DisplayedDataType_Subscriptions)
        {
            // too cluttered with edit button next to the back button ...
            // self.navigationItem.leftBarButtonItem = self.editButtonItem;
            
            self.addButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:nil]; // @selector(insertNewFeedWithInput:)];
            self.navigationItem.rightBarButtonItems = @[self.addButton];
            

            self.singleTapButtonRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(insertNewFeedWithInput:)];
            self.singleTapButtonRecognizer.numberOfTapsRequired = 1;
            
            
            self.doubleTapButtonRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(insertNewFolderWithInput:)];
            self.doubleTapButtonRecognizer.numberOfTapsRequired = 2;
            
            // self.longTapButtonRecognizer = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(browseDefaultOutline:)];
            // self.longTapButtonRecognizer.minimumPressDuration = 1.2;
            
            [self.singleTapButtonRecognizer requireGestureRecognizerToFail:self.doubleTapButtonRecognizer];
            // [self.singleTapButtonRecognizer requireGestureRecognizerToFail:self.longTapButtonRecognizer];
            // [self.doubleTapButtonRecognizer requireGestureRecognizerToFail:self.longTapButtonRecognizer];
        }
//        else if ( self.displayedDataType == DisplayedDataType_SubscriptionChooser )
//        {
//            self.longTapTableViewRecognizer = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(selectedDefaultOutline:)];
//            [self.tableView addGestureRecognizer:self.longTapTableViewRecognizer];
//        }
        else if ( self.displayedDataType == DisplayedDataType_Today )
        {
            self->viewOutlineWithItems = [[OPMLOutlineXMLElement alloc] initWithXMLString:[self.viewOutline XMLString] error:nil];
            
            [self loadItems];
        }
    }
    
    // if ( self.displayedDataType == DisplayedDataType_Subscriptions || self.displayedDataType == DisplayedDataType_Today )
    {
        self.refreshControl = [[UIRefreshControl alloc] init];
        
        [self.refreshControl addTarget:self action:@selector(refresh:) forControlEvents:UIControlEventValueChanged];
    }
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    // ?
//    if ( self.navigationController.viewControllers.count > 2 )
//    {
//        // set text on back button on detail vc
//        // since "The title of the display mode button is set from the title of the master view controller." // https://forums.developer.apple.com/thread/7578
//        // set self.title on first MasterViewController, since it is apparently set from the first one only
//        [[self.navigationController viewControllers] firstObject].title = self.title;
//    }
//    else
//    {
//        [[self.navigationController viewControllers] firstObject].title = nil;
//    }
//    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadTablePreservingSelection) name:@"itemsChanged" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(scrollToDetailSelection) name:@"selectedItemChanged" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(statusChanged:) name:@"statusChanged" object:nil];
}


-(void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    [self reloadTablePreservingSelection];
    
    [self scrollToDetailSelection];

    if ( statusText )
        [self statusChanged:[NSNotification notificationWithName:@"viewShownNotif" object:nil userInfo:@{@"status" : statusText}]];
    
    if ( self.displayedDataType == DisplayedDataType_Subscriptions )
    {
        [[self.addButton valueForKey:@"view" ] addGestureRecognizer:self.singleTapButtonRecognizer];
        [[self.addButton valueForKey:@"view" ] addGestureRecognizer:self.doubleTapButtonRecognizer];
        // [[self.addButton valueForKey:@"view"] addGestureRecognizer:self.longTapButtonRecognizer];
    }
    
    // tooltips
    if (!self->isFeed && self.displayedDataType == DisplayedDataType_Subscriptions) // only where + button is
    {
        if ( firstLaunch )
        {
            if (!tooltipsMasterCompleted)
            {
                if (!self.tooltipManager)
                {
                    // targetView: addButton view
                    // hostView:superview       - display OK,   touch NOK
                    // hostView:self.tableView  - display NOK,  touch OK
                    // the reason is that the view/tooltip is outside the bounds of its parent view
                    // https://developer.apple.com/library/content/qa/qa2013/qa1812.html
                    // so to have the arrow and have touches we would have to SUBCLASS UINAvigationBar and implement -(UIView *)hitTest:withEvent:
                    // so.. no.
                    // go with hidden arrow now which is ugly as fuck, but at least works
                    // ( the other options would be to display the tooltip at point, but we would have to handle rotations in that cae, so screw that, too )
                    
                    self.tooltipManager = [[JDFSequentialTooltipManager alloc] initWithHostView:self.view];
                
                    UIView *targetView = [self.addButton valueForKey:@"view"];
                    // UIView *targetSuperview = [targetView superview];
                    
                    [self.tooltipManager addTooltipWithTargetView:targetView
                                                         hostView:self.view
                                                      tooltipText:@"Tap to add RSS/Atom feed/link to current folder.\nDouble tap to add a new folder\n\n(tap to dismiss this help text)"
                                                   arrowDirection:JDFTooltipViewArrowDirectionUp
                                                            width:200.0f
                                              showCompletionBlock:^{
                                                  ;
                                              }
                                              hideCompletionBlock:^{
                                                  tooltipsMasterCompleted = YES;
                                              }
                     ];
                    
                    [self.tooltipManager showNextTooltip];
                }
            }
        }
    }
}

-(void)viewDidDisappear:(BOOL)animated
{
    [super viewDidDisappear:animated];
    
    if ( self.displayedDataType == DisplayedDataType_Subscriptions )
    {
        [[self.addButton valueForKey:@"view" ] removeGestureRecognizer:self.singleTapButtonRecognizer];
        [[self.addButton valueForKey:@"view" ] removeGestureRecognizer:self.doubleTapButtonRecognizer];
        // [[self.addButton valueForKey:@"view"] removeGestureRecognizer:self.longTapButtonRecognizer];
    }
    
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"itemsChanged" object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"selectedItemChanged" object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"statusChanged" object:nil];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    
    // clear data source
    [[PageViewModelController sharedInstance] clearOutline];
    
    // pvc should clear itself
}

-(void)reloadTablePreservingSelection
{
    // preserve the selection
    
    OPMLOutlineXMLElement *currentlySelectedObject = nil;
    
    if ( [self.tableView indexPathForSelectedRow] ) // ?
    {
        if ( self->isFeed || self.displayedDataType == DisplayedDataType_Today)
        {
            if ( [self->viewOutlineWithItems.children count] > 0 ) // ??
                currentlySelectedObject = (OPMLOutlineXMLElement*)[self->viewOutlineWithItems.children objectAtIndex:[self.tableView indexPathForSelectedRow].row];
        }
        else {
            if ( [self.viewOutline.children count] > 0 )
                currentlySelectedObject = (OPMLOutlineXMLElement*)[self.viewOutline.children objectAtIndex:[[self->viewOutlineChildIndices objectAtIndex:[self.tableView indexPathForSelectedRow].row] integerValue]];
        }
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        
        [self.tableView reloadData];
    
        if ( currentlySelectedObject )
        {
            NSIndexPath *newIP;
            
            if ( self->isFeed || self.displayedDataType == DisplayedDataType_Today )
            {
                NSUInteger count = [self->viewOutlineWithItems childCount];
                for (int i = 0; i < count; ++i)
                {
                    OPMLOutlineXMLElement *object = (OPMLOutlineXMLElement*)[self->viewOutlineWithItems childAtIndex:i];
                    
                    if ( [object isEqual:currentlySelectedObject] )
                    {
                        newIP = [NSIndexPath indexPathForRow:i inSection:0];
                        break;
                    }
                }
            }
            else
            {
                NSUInteger count = [self->viewOutlineChildIndices count];
                for (int i = 0; i < count; ++i)
                {
                    OPMLOutlineXMLElement *object = (OPMLOutlineXMLElement*)[self.viewOutline.children objectAtIndex:[[self->viewOutlineChildIndices objectAtIndex:i] integerValue]];
                    
                    if ( [object isEqual:currentlySelectedObject] )
                    {
                        newIP = [NSIndexPath indexPathForRow:i inSection:0];
                        break;
                    }
                }
            }
            
            if ( newIP )
            {
                [self.tableView selectRowAtIndexPath:newIP animated:NO scrollPosition:UITableViewScrollPositionNone];
            }
        }
    });
}

-(void)scrollToDetailSelection
{
    NSIndexPath *result = nil;
    NSString *toSelectxmlUrl = pageViewController.currentLink;
    
    if ( toSelectxmlUrl )
    {
        if ( self->isFeed || self.displayedDataType == DisplayedDataType_Today )
        {
            NSUInteger count = [self->viewOutlineWithItems childCount];
            for (int i = 0; i < count; ++i)
            {
                OPMLOutlineXMLElement *object = (OPMLOutlineXMLElement*)[self->viewOutlineWithItems childAtIndex:i];
                if ( [[[object attributeForName:@"link"] stringValue] isEqualToString:toSelectxmlUrl] )
                {
                    result = [NSIndexPath indexPathForRow:i inSection:0];
                    break;
                }
            }
        }
        else
        {
            NSUInteger count = [self->viewOutlineChildIndices count];
            for (int i = 0; i < count; ++i)
            {
                OPMLOutlineXMLElement *object = (OPMLOutlineXMLElement*)[self.viewOutline.children objectAtIndex:[[self->viewOutlineChildIndices objectAtIndex:i] integerValue]];
                if ( [[[object attributeForName:@"link"] stringValue] isEqualToString:toSelectxmlUrl] )
                {
                    result = [NSIndexPath indexPathForRow:i inSection:0];
                    break;
                }
            }
        }
    }
    
    if ( result )
    {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.tableView selectRowAtIndexPath:result animated:YES scrollPosition:UITableViewScrollPositionNone];
            [self.tableView scrollToRowAtIndexPath:result atScrollPosition:UITableViewScrollPositionNone animated:YES];
        });
    }
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









-(void)loadItems
{
    if ( self->isFeed )
    {
        // if refresh
        for (DDXMLElement *el in self->viewOutlineWithItems.children )
        {
            [el detach];
        }
        
        switch (self.displayedDataType)
        {
            case DisplayedDataType_Subscriptions:
                [[SubscriptionsController sharedInstance] loadAllItems:self->viewOutlineWithItems isTemporary:NO];
                break;
                
//            case DisplayedDataType_SubscriptionChooser:
//                [[SubscriptionsController sharedInstance] loadAllItems:self->viewOutlineWithItems isTemporary:YES];
//                break;
                
//            case DisplayedDataType_Today:
//                [[SubscriptionsController sharedInstance] loadTodayItems:self->viewOutlineWithItems];
//                break;
                
            case DisplayedDataType_Unread:
                [[SubscriptionsController sharedInstance] loadUnreadItems:self->viewOutlineWithItems];
                break;
                
            case DisplayedDataType_Bookmarks:
                [[SubscriptionsController sharedInstance] loadBookmarkedItems:self->viewOutlineWithItems];
                
				break;
				
            default:
                break;
        }
    }
    else if ( self.displayedDataType == DisplayedDataType_Today )
    {
        // if refresh
        for (DDXMLElement *el in self->viewOutlineWithItems.children )
        {
            [el detach];
        }
        
        [[SubscriptionsController sharedInstance] loadTodayItems:self.viewOutline :self->viewOutlineWithItems];
    }

    [self reloadTablePreservingSelection];
}

#pragma mark - Buttons event handlers

-(void)refresh:(id)sender
{
    if ( [SubscriptionsController sharedInstance].isRefreshing )
    {
        [self.refreshControl endRefreshing];
        return;
    }
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        
        NSLog(@"== :: == :: MasterVC refreshFeeds.");
        
        [[SubscriptionsController sharedInstance] refreshFeeds:self.viewOutline
         
                                          progressFeedCallbackPre:^(NSString *progressFeedName)
         {
             dispatch_async(dispatch_get_main_queue(), ^{
                 NSString *status = [NSString stringWithFormat:@"%@ %@", NSLocalizedString(@"Updating", nil), progressFeedName];
                 [[NSNotificationCenter defaultCenter] postNotificationName:@"statusChanged" object:nil userInfo:@{@"status":status}];
             });
         }
         
                                              progressFeedCallback:^(NSString *progressFeedName)
        {
            dispatch_async(dispatch_get_main_queue(), ^{
                NSString *status = [NSString stringWithFormat:@"%@ %@", NSLocalizedString(@"Updated", nil), progressFeedName];
                [[NSNotificationCenter defaultCenter] postNotificationName:@"statusChanged" object:nil userInfo:@{@"status":status}];
            });
        }];
        
        NSLog(@"== :: == :: MasterVC refreshFeeds ended.");
        
        NSUInteger allCount = [[[self.viewOutline attributeForName:@"allItemsCount"] stringValue] integerValue];
        
        [[SubscriptionsController sharedInstance] refreshCounts:self.viewOutline progress:^(NSUInteger _progress)
        {
            dispatch_async(dispatch_get_main_queue(), ^{
                NSString *status = [NSString stringWithFormat:@"%@ %ld / %ld", NSLocalizedString(@"Processing", nil), (unsigned long)_progress, (unsigned long)allCount];
                
                [[NSNotificationCenter defaultCenter] postNotificationName:@"statusChanged" object:nil userInfo:@{@"status":status}];
            });
        }];
        
        NSLog(@"== :: == :: MasterVC refreshCounts ended.");
    
        dispatch_async(dispatch_get_main_queue(), ^{
            
            [[NSNotificationCenter defaultCenter] postNotificationName:@"statusChanged" object:nil userInfo:nil];
            
            [self loadItems];
            
            [self scrollToDetailSelection];
            
            [self.refreshControl endRefreshing];
        });
    });
}

- (void)insertNewFeedWithInput:(id)sender
{
    // open an alert with two custom buttons
    self.enteringNewFolder = NO;
    
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Enter RSS/Atom link or website URL", nil)
                                                    message:NSLocalizedString(@"(rssr will try to find a feed on a website if no direct link to an RSS feed is entered)", nil)
                                                   delegate:self
                                          cancelButtonTitle:NSLocalizedString(@"Dismiss", nil)
                                          otherButtonTitles:NSLocalizedString(@"OK", nil), nil];
    alert.alertViewStyle = UIAlertViewStylePlainTextInput;
    alert.delegate = self;
    
    [[alert textFieldAtIndex:0] setClearButtonMode:UITextFieldViewModeWhileEditing];
    [[alert textFieldAtIndex:0] setKeyboardType:UIKeyboardTypeURL];
    
    // see if there's anything interesting in clipboard; if yes prefill textfield
    UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
    NSString *string = pasteboard.string;
    if (string)
    {
        string = [[string lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        
        NSURL *url = [NSURL URLWithString:string];
        
        if (string != nil && ([string hasPrefix:@"http://"] || [string hasPrefix:@"https://"] || [string hasPrefix:@"feed://"]))
        {
            [alert textFieldAtIndex:0].text = string;
        }
    }
    
    self->tableView_Operation = TableView_Inserting;
    
    [alert show];
}

- (void)insertNewFolderWithInput:(id)sender
{
    self.enteringNewFolder = YES;
    
    // present text input, if successfull, add subscription and save
    // open an alert with two custom buttons
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Enter name of the new folder", nil)
                                                    message:nil
                                                   delegate:self
                                          cancelButtonTitle:NSLocalizedString(@"Dismiss", nil)
                                          otherButtonTitles:NSLocalizedString(@"OK", nil), nil];
    alert.alertViewStyle = UIAlertViewStylePlainTextInput;
    alert.delegate = self;
    
    [[alert textFieldAtIndex:0] setClearButtonMode:UITextFieldViewModeWhileEditing];
    // [[alert textFieldAtIndex:0] setKeyboardType:UIKeyboardTypeURL];
    
    self->tableView_Operation = TableView_Inserting;
    
    [alert show];
}

/*
-(void)browseDefaultOutline:(id)sender
{
    if ( self.displayedDataType == DisplayedDataType_SubscriptionChooser )
        return;
    
    if ( self.longTapButtonRecognizer.state == UIGestureRecognizerStateEnded )
    {
        // present defaul outline in new self
        
        UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Main" bundle:nil];
        MasterViewController *controller = (MasterViewController *)[storyboard instantiateViewControllerWithIdentifier:@"MasterViewController"];
        controller.displayedDataType = DisplayedDataType_SubscriptionChooser;
        
        NSError *error;
        controller.viewOutline = (OPMLOutlineXMLElement*)[[SubscriptionsController sharedInstance] defaultOutlineDocument:error].bodyNode;
        controller.mainViewOutline = self.viewOutline;
        
        [self.navigationController pushViewController:controller animated:YES];
    }
}
*/

/*
-(void)selectedDefaultOutline:(id)sender
{
   UILongPressGestureRecognizer *r = (UILongPressGestureRecognizer*)sender;
    
   if ( r.state == UIGestureRecognizerStateEnded )
   {
       CGPoint p = [r locationInView:self.tableView];
       
       NSIndexPath *ip = [self.tableView indexPathForRowAtPoint:p];
       
       // TODO: for now allow adding only single feed ( i.e. no folder )
       
       if ( ip.row >= 0 )
       {
           OPMLOutlineXMLElement *toBAdded = [(OPMLOutlineXMLElement*)[self.viewOutline childAtIndex:[[self->viewOutlineChildIndices objectAtIndex:ip.row] integerValue]] copy];
           
           if ( [[toBAdded attributeForName:@"xmlUrl"] stringValue] )
           {
               // TODO: present selector as to where to save this
               
               // rss / atom feed
               // display progress
               NSString *status = [NSString stringWithFormat:@"%@ %@", NSLocalizedString(@"Adding", nil), [[toBAdded attributeForName:@"text"] stringValue]];
               
               [SVProgressHUD showWithStatus:status];
               
               dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
               
                   NSString *message;
                   
                   if ( ![[SubscriptionsController sharedInstance] createOutlineFromOutline:toBAdded underParent:self.mainViewOutline message:&message] )
                   {
                       dispatch_async(dispatch_get_main_queue(), ^{
                           
                           [SVProgressHUD dismiss];
                           
                           [self displayAlert:message withError:nil];
                       });
                   }
                   else
                   {
                       dispatch_async(dispatch_get_main_queue(), ^{

                           [self reloadTablePreservingSelection];
                           
                           [SVProgressHUD showSuccessWithStatus:[NSString stringWithFormat:@"%@ %@", [[toBAdded attributeForName:@"text"] stringValue], NSLocalizedString(@"added",nil)]];
                           
                       });
                   }
                   
               });
               
           }
       }
   }
}
 */

#pragma mark - Editing - UIAlertViewDelegate

-(void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if ( self->tableView_Operation == TableView_Inserting )
    {
        // OK button
        if ( buttonIndex == 1 )
        {
            // process entered text
            NSString *l = [alertView textFieldAtIndex:0].text;
            
            if ( l != nil && l.length > 0 )
            {
                if (!self.enteringNewFolder)
                {
                    // rss / atom feed
                    // display progress
                    NSString *status = [NSString stringWithFormat:@"%@ %@", NSLocalizedString(@"Adding", nil), l];
                    
                    [SVProgressHUD showWithStatus:status];
                    
                    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                        
                        NSString *message;
                    
                        if (! [[SubscriptionsController sharedInstance] createOutlineFromURL:l underParent:self.viewOutline message:&message] )
                        {
                            dispatch_async(dispatch_get_main_queue(), ^{
                                
                                [SVProgressHUD dismiss];
                                
                                [self displayAlert:message withError:nil];
                            });
                        }
                        else
                        {
                            dispatch_async(dispatch_get_main_queue(), ^{

                                [self reloadTablePreservingSelection];
                                
                                [SVProgressHUD showSuccessWithStatus:[NSString stringWithFormat:@"%@ %@", l, NSLocalizedString(@"added",nil)]];
                                
                            });
                        }
                    });
                }
                else
                {
                    // folder
                    
                    NSString *message;

                    if (! [[SubscriptionsController sharedInstance] createOutlineWithText:l underParent:self.viewOutline message:&message] )
                    {
                        [SVProgressHUD dismiss];
                        
                        [self displayAlert:message withError:nil];
                        
                        return;
                    }

                    [self reloadTablePreservingSelection];
                    
                    [SVProgressHUD showSuccessWithStatus:[NSString stringWithFormat:@"%@ %@ %@", NSLocalizedString(@"Folder",nil), l, NSLocalizedString(@"created",nil)]];
                }
            }
        }
    }
    else if ( self->tableView_Operation == TableView_Deleting )
    {
        if ( buttonIndex == 1 )
        {
            // ok, proceed with the deletion
            if ( self.displayedDataType == DisplayedDataType_Subscriptions )
            {
                // delete outline
                
                // cache removal:
                OPMLOutlineXMLElement *outlineToBeRemoved = (OPMLOutlineXMLElement*)[self.viewOutline childAtIndex:[[self->viewOutlineChildIndices objectAtIndex:indexPathOfTheRowToBeDeleted.row] integerValue]];
                
                // delete the element
                [[SubscriptionsController sharedInstance] deleteOutline:outlineToBeRemoved];
                
                if ( [[outlineToBeRemoved attributeForName:@"xmlUrl"] stringValue] )
                    [SVProgressHUD showSuccessWithStatus:NSLocalizedString(@"Subscription removed",nil)];
                else
                    [SVProgressHUD showSuccessWithStatus:NSLocalizedString(@"Folder removed",nil)];
            }
            else if ( self.displayedDataType == DisplayedDataType_Bookmarks )
            {
                OPMLOutlineXMLElement *item = (OPMLOutlineXMLElement*)[self->viewOutlineWithItems childAtIndex:indexPathOfTheRowToBeDeleted.row];
                
                // remove bookmark
                [[SubscriptionsController sharedInstance] markItemBookmarked:item clear:YES];
                
                [self->viewOutlineWithItems removeChildAtIndex:indexPathOfTheRowToBeDeleted.row];
                
                [SVProgressHUD showSuccessWithStatus:NSLocalizedString(@"Bookmark removed",nil)];
            }
            
            // update tableview
            [self.tableView deleteRowsAtIndexPaths:@[indexPathOfTheRowToBeDeleted] withRowAnimation:UITableViewRowAnimationFade];
        }
        else
        {
            // cancel deletion
            [self.tableView setEditing:NO animated:YES];
        }
    }
}


#pragma mark - Segues

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    //storyboards should use segues and override prepareForSegue instead
    //but here we need custom logic to determine which segue to use
    
    OPMLOutlineXMLElement *object;
    if ( self->isFeed )
        object = (OPMLOutlineXMLElement*)self->viewOutlineWithItems.children[indexPath.row];
    else if ( self.displayedDataType == DisplayedDataType_Today)
        object = (OPMLOutlineXMLElement*)self->viewOutlineWithItems.children[indexPath.row];
    else
        object = (OPMLOutlineXMLElement*)[self.viewOutline.children objectAtIndex:[[self->viewOutlineChildIndices objectAtIndex:indexPath.row] integerValue]];
    
    if ( [[object name] isEqualToString:@"item"] )
    {
        [self performSegueWithIdentifier:@"showDetail" sender:self];
    }
    else if ( [[object name] isEqualToString:@"outline"] )
    {
        [self performSegueWithIdentifier:@"showMaster" sender:self];
    }
}

- (BOOL)shouldPerformSegueWithIdentifier:(NSString *)identifier sender:(id)sender
{
    //ignore segue from cell since we we are calling manually in didSelectRowAtIndexPath
    return (sender == self);
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    NSIndexPath *indexPath = [self.tableView indexPathForSelectedRow];
    
    OPMLOutlineXMLElement *object;
    if ( self->isFeed )
        object = (OPMLOutlineXMLElement*)[self->viewOutlineWithItems childAtIndex:indexPath.row];
    else if ( self.displayedDataType == DisplayedDataType_Today )
        object = (OPMLOutlineXMLElement*)[self->viewOutlineWithItems childAtIndex:indexPath.row];
    else
        object = (OPMLOutlineXMLElement*)[self.viewOutline.children objectAtIndex:[[self->viewOutlineChildIndices objectAtIndex:indexPath.row] integerValue]];

    if ([[segue identifier] isEqualToString:@"showDetail"])
    {
        pageViewController = nil;
        
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
            NSLog(@"What is this ? Where am I ? What is this madness ? SplitViewController on some future unknown device ?");
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
		[[PageViewModelController sharedInstance] setOutline:self->viewOutlineWithItems];
		
		[PageViewModelController sharedInstance].pageViewControllerDelegate = pageViewController;
		
		[pageViewController setDataSource:[PageViewModelController sharedInstance] type:self.displayedDataType];
        

		DetailViewController *detailVC = [[PageViewModelController sharedInstance] viewControllerAtIndex:indexPath.row storyboard:self.storyboard];
        
        NSArray *controllers = @[detailVC];
        
        [pageViewController setViewControllers:controllers direction:UIPageViewControllerNavigationDirectionForward animated:NO completion:nil];
        
        pageViewController.currentlyDisplayedDetailViewController = detailVC;
		
		// if ( self.displayedDataType != DisplayedDataType_SubscriptionChooser )
			[[SubscriptionsController sharedInstance] markItemAsRead:object];
        
    }
    else if ( [[segue identifier] isEqualToString:@"showMaster"] )
    {
        MasterViewController *controller = (MasterViewController *)[segue destinationViewController];
        controller.displayedDataType = self.displayedDataType;
        controller.viewOutline = object;
        controller.mainViewOutline = self.mainViewOutline;
    }
}

#pragma mark - Table View

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if ( self->isFeed )
        return self->viewOutlineWithItems.childCount;
    else if (self.displayedDataType == DisplayedDataType_Today )
        return  self->viewOutlineWithItems.childCount;
    else
    {
        // display only outlines with nonzero child count
        self->viewOutlineChildIndices = [[NSMutableArray alloc] init];
        
        // suppose that DDXMLNode.children returns children always in the same order...
        NSArray *theChildren = self.viewOutline.children;
        NSUInteger count = 0;
        
        for ( NSUInteger i = 0; i < theChildren.count; ++i)
        {
            // is a folder ?
            NSString *childOutlineLink = [[((OPMLOutlineXMLElement*)[self.viewOutline childAtIndex:i]) attributeForName:@"xmlUrl"] stringValue];
            
            switch (self.displayedDataType)
            {
                case DisplayedDataType_Subscriptions:
                    
                    // display even with zero count if it is a folder
                    if ( ! childOutlineLink )
                        [self->viewOutlineChildIndices addObject:[NSNumber numberWithUnsignedInteger:i]];
                    else
                    {
                        // display all subscribed feeds, even with zero feed items
                        [self->viewOutlineChildIndices addObject:[NSNumber numberWithUnsignedInteger:i]];
                    }
                    
                    break;
                    
//                case DisplayedDataType_SubscriptionChooser:
//                    // dont display already subscribed
//                    if (! childOutlineLink )
//                        [self->viewOutlineChildIndices addObject:[NSNumber numberWithUnsignedInteger:i]];
//                    else
//                    {
//                        if ( ![[SubscriptionsController sharedInstance] outlineFromLink:childOutlineLink ] )
//                            [self->viewOutlineChildIndices addObject:[NSNumber numberWithUnsignedInteger:i]];
//                    }
//                    break;
                    
                case DisplayedDataType_Today:
                    count = [[[[theChildren objectAtIndex:i] attributeForName:@"todayItemsCount"] stringValue] integerValue];
                    
                    if (  count )
                        [self->viewOutlineChildIndices addObject:[NSNumber numberWithUnsignedInteger:i]];

                    break;
                    
                case DisplayedDataType_Unread:
                    count = [[[[theChildren objectAtIndex:i] attributeForName:@"unreadItemsCount"] stringValue] integerValue];
                    
                    if (  count )
                        [self->viewOutlineChildIndices addObject:[NSNumber numberWithUnsignedInteger:i]];
                    
                    break;
                    
                case DisplayedDataType_Bookmarks:
                    count = [[[[theChildren objectAtIndex:i] attributeForName:@"bookmarkedItemsCount"] stringValue] integerValue];
                    
                    if (  count )
                        [self->viewOutlineChildIndices addObject:[NSNumber numberWithUnsignedInteger:i]];
                    
                    break;
                    
                default:
                    [self->viewOutlineChildIndices addObject:[NSNumber numberWithUnsignedInteger:i]];
                    
                    break;
            }
        }
        
        return self->viewOutlineChildIndices.count;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    TDBadgedCell *cell = [self.tableView dequeueReusableCellWithIdentifier:@"Cell" forIndexPath:indexPath];

    OPMLOutlineXMLElement *object;
    if ( self->isFeed )
        object = (OPMLOutlineXMLElement*)[self->viewOutlineWithItems.children objectAtIndex:indexPath.row];
    else if ( self.displayedDataType == DisplayedDataType_Today)
        object = (OPMLOutlineXMLElement*)[self->viewOutlineWithItems.children objectAtIndex:indexPath.row];
    else
        object = (OPMLOutlineXMLElement*)[self.viewOutline.children objectAtIndex:[[self->viewOutlineChildIndices objectAtIndex:indexPath.row] integerValue]];
    
    // element might be of various types such as comment
    
    // TODO: strip on loading, not here
    
    if ( [[object name] isEqualToString:@"outline"] )
    {
        /// outline
        cell.textLabel.text = [[object attributeForName:@"text"] stringValue];
        cell.detailTextLabel.text = [[object attributeForName:@"description"] stringValue];

        NSUInteger cnt = 0;
    
        switch (self.displayedDataType)
        {
            case DisplayedDataType_Subscriptions:
                cnt = [[[object attributeForName:@"allItemsCount"] stringValue] integerValue];
                break;

            case DisplayedDataType_Today:
                cnt = [[[object attributeForName:@"todayItemsCount"] stringValue] integerValue];
                break;
            
            case DisplayedDataType_Unread:
                cnt = [[[object attributeForName:@"unreadItemsCount"] stringValue] integerValue];
                break;
                
            case DisplayedDataType_Bookmarks:
                cnt = [[[object attributeForName:@"bookmarkedItemsCount"] stringValue] integerValue];
                break;
                
            default:
                break;
        }
        
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
    }
    else if ( [[object name] isEqualToString:@"item"] )
    {
        /// item
        cell.textLabel.text = [[object attributeForName:@"title"] stringValue];
        cell.detailTextLabel.text = [[object attributeForName:@"date"] stringValue];
        
        cell.badgeString = nil;
    }
    else
    {
        cell.textLabel.text = nil;
        cell.detailTextLabel.text = nil;
        
        cell.badgeString = nil;
    }
    
//    if ( self.readonly )
//    {
//        UILongPressGestureRecognizer *lpr = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(selectedDefaultOutline:)];
//        [cell addGestureRecognizer:lpr];
//    }
    
    NSString *urlString = [[object attributeForName:@"htmlUrl"] stringValue];
    if (!urlString )
        urlString = [[object attributeForName:@"parentHtmlUrl"] stringValue];
    
    NSURL *url = [NSURL URLWithString:urlString];
    
    if ( url && !self->isFeed )
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
    
    return cell;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    // Return NO if you do not want the specified item to be editable.
    return
    ( self.displayedDataType == DisplayedDataType_Subscriptions && !self->isFeed )
    ||
    ( self.displayedDataType == DisplayedDataType_Bookmarks && self->isFeed )
    ;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (editingStyle == UITableViewCellEditingStyleDelete)
    {
        indexPathOfTheRowToBeDeleted = indexPath;
        
        [self deleteConfirmation];
    }
    else if (editingStyle == UITableViewCellEditingStyleInsert)
    {
        // Create a new instance of the appropriate class, insert it into the array, and add a new row to the table view.
    }
}

#pragma mark - delete confirmation
-(void)deleteConfirmation
{
    OPMLOutlineXMLElement *outlineToBeRemoved = nil;
    NSString *deletedObjectDescription;
    NSString *message;
    
    if ( self->isFeed ) // removing a concrete article -> bookmark
    {
        outlineToBeRemoved = (OPMLOutlineXMLElement*)[self->viewOutlineWithItems.children objectAtIndex:indexPathOfTheRowToBeDeleted.row];
        deletedObjectDescription = NSLocalizedString(@"bookmark", nil);
        message = NSLocalizedString(@"", nil);
    }
    else
    {
        outlineToBeRemoved = (OPMLOutlineXMLElement*)[self.viewOutline childAtIndex:[[self->viewOutlineChildIndices objectAtIndex:indexPathOfTheRowToBeDeleted.row] integerValue]];
        deletedObjectDescription = [[outlineToBeRemoved attributeForName:@"xmlUrl"] stringValue] ? NSLocalizedString(@"subscription", nil) : NSLocalizedString(@"folder", nil);
        message = NSLocalizedString(@"This will remove subscription and all its downloaded articles so far (including any bookmarks) and in case of folder it will remove all subscriptions and folders it may contain.", nil);
    }
    
    UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:[NSString stringWithFormat:@"%@ %@?", NSLocalizedString(@"Delete", nil), deletedObjectDescription]
                                                        message:message
                                                       delegate:self
                                              cancelButtonTitle:NSLocalizedString(@"Dismiss", nil)
                                              otherButtonTitles:NSLocalizedString(@"OK", nil)
                              , nil];
    
    self->tableView_Operation = TableView_Deleting;
    
    [alertView show];
}

#pragma mark - Display utility

-(void)displayAlert:(NSString*)withTitle withError:(NSError*)error
{
    NSString *messageString = [error localizedDescription] ? [error localizedDescription] : @"";
    NSString *moreString = [error localizedFailureReason] ? [error localizedFailureReason] : @"";
    NSString *moreString2 = [error localizedRecoverySuggestion] ? [error localizedRecoverySuggestion] : @"";
    messageString = [NSString stringWithFormat:@"%@. %@. %@.", messageString, moreString, moreString2];
    
    RSLog(@"%@", messageString );
    
    if ([UIAlertController class] == nil) // pre iOS 8.0
    {
        UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:withTitle
                                                            message:messageString
                                                           delegate:nil
                                                  cancelButtonTitle:NSLocalizedString(@"Dismiss", nil)
                                                  otherButtonTitles:nil];
        
        

        [alertView show];
    }
    else
    {
        UIAlertController *alertController = [UIAlertController alertControllerWithTitle:withTitle
                                                                                 message:messageString
                                                                          preferredStyle:UIAlertControllerStyleAlert];
        
        //We add buttons to the alert controller by creating UIAlertActions:
        UIAlertAction *actionOk = [UIAlertAction actionWithTitle:NSLocalizedString(@"OK", nil)
                                                           style:UIAlertActionStyleDefault
                                                         handler:nil]; //You can use a block here to handle a press on this button
        [alertController addAction:actionOk];
        [self presentViewController:alertController animated:YES completion:nil];
    }
}
@end
