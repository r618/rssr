//
//  PageViewController.m
//  rssr
//
//  Created by Rupert Pole on 07/12/15.
//
//

#import "PageViewController.h"
#import "CJAMacros.h"
#import "TUSafariActivity.h"
#import "DetailViewController.h"
#import "SubscriptionsController.h"
#import "SVProgressHUD.h"
#import "DSFavIconManager.h"
#import "UIImage+Utils.h"

double fontSizePercentage = 100;
BOOL toolBarsHidden = NO;

@interface PageViewController ()
{
    DetailViewController *pendingDetailViewController;
}
@end

@implementation PageViewController

#pragma mark - UIViewController

-(void)setDataSource:(PageViewModelController*)ds type:(DisplayedDataType)type
{
	self.dataSource = ds;
	self->_displayedDataType = type;
}

-(void)setCurrentlyDisplayedDetailViewController:(DetailViewController *)currentlyDisplayedDetailViewController
{
    _currentlyDisplayedDetailViewController = currentlyDisplayedDetailViewController;
    
    self.title = [[_currentlyDisplayedDetailViewController.detailItem attributeForName:@"parentTitle"] stringValue];
    
    self.currentLink = [[_currentlyDisplayedDetailViewController.detailItem attributeForName:@"link"] stringValue];
    
    NSURL *parentUrl = [NSURL URLWithString:[[_currentlyDisplayedDetailViewController.detailItem attributeForName:@"parentHtmlUrl"] stringValue]];
    
    if ( parentUrl )
    {
        UIImageView *imageView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 28.0f, 28.0f)];
        CGSize size = CGSizeMake(32, 32);
        
        imageView.image = [[DSFavIconManager sharedInstance] iconForURL:parentUrl
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
    
    // match last state user toggled
    // ( although animated:NO is enough even in viewDidLoad )
    [_currentlyDisplayedDetailViewController.navigationController setToolbarHidden:toolBarsHidden animated:NO];
    [_currentlyDisplayedDetailViewController.navigationController setNavigationBarHidden:toolBarsHidden animated:NO];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [DSFavIconManager sharedInstance].useAppleTouchIconForHighResolutionDisplays = YES;
    
    // stepper configuration, appearance and starting value
    
    self.stepperBarButton.minimumValue = 55;
    
    if ( SYSTEM_VERSION_LESS_THAN(_iOS_7_0))
    {
        self.stepperBarButton.maximumValue = 280;
    }
    else
    {
        if ( DEVICE_IS_IPHONE )
            self.stepperBarButton.maximumValue = 255;
        else
            self.stepperBarButton.maximumValue = 500;
    }
    
    self.stepperBarButton.value = fontSizePercentage;
    
    [self.stepperBarButton setDecrementImage:[UIImage imageNamed:@"fontsize-16-000000b.png"] forState:UIControlStateNormal];
    [self.stepperBarButton setIncrementImage:[UIImage imageNamed:@"fontsize-24-000000b.png"] forState:UIControlStateNormal];
    [self.stepperBarButton setDecrementImage:[UIImage imageNamed:@"fontsize-16-000000b_highlighted.png"] forState:UIControlStateHighlighted];
    [self.stepperBarButton setIncrementImage:[UIImage imageNamed:@"fontsize-24-000000b_highlighted.png"] forState:UIControlStateHighlighted];
    
    [self.stepperBarButton setBackgroundImage:[UIImage new] forState:UIControlStateDisabled];
    [self.stepperBarButton setBackgroundImage:[UIImage new] forState:UIControlStateFocused];
    [self.stepperBarButton setBackgroundImage:[UIImage new] forState:UIControlStateHighlighted];
    [self.stepperBarButton setBackgroundImage:[UIImage new] forState:UIControlStateNormal];
    
    // divider - the vertical line
    //    [self.stepper setDividerImage:[UIImage new] forLeftSegmentState:UIControlStateDisabled rightSegmentState:UIControlStateDisabled];
    //    [self.stepper setDividerImage:[UIImage new] forLeftSegmentState:UIControlStateFocused rightSegmentState:UIControlStateFocused];
    //    [self.stepper setDividerImage:[UIImage new] forLeftSegmentState:UIControlStateHighlighted rightSegmentState:UIControlStateHighlighted];
    //    [self.stepper setDividerImage:[UIImage new] forLeftSegmentState:UIControlStateNormal rightSegmentState:UIControlStateNormal];
    
    // self.navigationController.toolbar.tintColor = [UIColor darkGrayColor];
    
    self.delegate = self;
    
    // match local item toolbar even when webView migh be still loading externals
    [self updateToolBarItems];
}

-(void)viewDidAppear:(BOOL)animated
{
    // update font size for the first one without page transition
    [_currentlyDisplayedDetailViewController updateFontSize];
}

-(void)viewWillDisappear:(BOOL)animated
{
	[super viewWillDisappear:animated];
	
	// hide the toolbar always
	[self.navigationController setToolbarHidden:YES animated:YES];
    
    // show the navigation bar always
    [self.navigationController setNavigationBarHidden:NO animated:YES];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    
    // clear datasource and recreate pages again
    [[PageViewModelController sharedInstance] setOutline:(OPMLOutlineXMLElement*)[self.currentlyDisplayedDetailViewController.detailItem parent]];
    
    [PageViewModelController sharedInstance].pageViewControllerDelegate = self;
    
    [self setDataSource:[PageViewModelController sharedInstance]];
    
    [self setViewControllers:@[self.currentlyDisplayedDetailViewController] direction:UIPageViewControllerNavigationDirectionForward animated:NO completion:nil];
    
    // restore current item -
    dispatch_async(dispatch_get_main_queue(), ^{
        
        [self restoreItem:nil];
        
        [self updateToolBarItems];
    });
}

#pragma mark - UIPageViewControllerDelegate

-(void)pageViewController:(UIPageViewController *)pageViewController willTransitionToViewControllers:(NSArray<UIViewController *> *)pendingViewControllers
{
    self->pendingDetailViewController = (DetailViewController*)[pendingViewControllers firstObject];
}

-(void)pageViewController:(UIPageViewController *)pageViewController didFinishAnimating:(BOOL)finished previousViewControllers:(NSArray<UIViewController *> *)previousViewControllers transitionCompleted:(BOOL)completed
{
    if ( completed )
    {
        self.currentlyDisplayedDetailViewController = self->pendingDetailViewController;
        
        [self.currentlyDisplayedDetailViewController updateFontSize];
		
		// if ( self.displayedDataType != DisplayedDataType_SubscriptionChooser )
		{
			// mark as read in the tree
			[[SubscriptionsController sharedInstance] markItemAsRead:self.currentlyDisplayedDetailViewController.detailItem];
		}
		
        [self updateToolBarItems];
        
        // notify view controllers
        [[NSNotificationCenter defaultCenter] postNotificationName:@"selectedItemChanged" object:nil];
    }
}

#pragma mark - UIWebViewDelegate
-(void)webViewDidStartLoad:(UIWebView *)webView
{
    [self updateToolBarItems];
}

-(void)webViewDidFinishLoad:(UIWebView *)webView
{
    [self updateToolBarItems];
}

#pragma mark - navigation bar

- (IBAction)action:(UIBarButtonItem *)sender
{
    NSString *isText = [[self.currentlyDisplayedDetailViewController.detailItem attributeForName:@"IsText"] stringValue];
    
    NSArray *activityItems = nil;
    
    if ( [isText isEqualToString:@"YES"] )
    {
        // if not rss content, share content, not url
        NSString *content = [[self.currentlyDisplayedDetailViewController.detailItem attributeForName:@"content"] stringValue];
        activityItems = @[content];
    }
    else
    {
        NSURL *url = nil;
        
        // URL seems to be empty on first ( the original offline article content ) request when it is not finished
        // in that case share original link
        // otherwise requests are pending ( link clicked ) so share that
        // except when it is hit from cache
        // in that case share original link cause WTF
        // TODO: how to get original URL from cached request
        
        if ( [self.currentlyDisplayedDetailViewController.webView.request.URL.absoluteString length] > 0 )
        {
            if ( [self.currentlyDisplayedDetailViewController.webView.request.URL.scheme isEqualToString:@"file"] )
                url = [NSURL URLWithString:[[self.currentlyDisplayedDetailViewController.detailItem attributeForName:@"link"] stringValue]];
            else
                url = self.currentlyDisplayedDetailViewController.webView.request.URL;
        }
        else
        {
            url = [NSURL URLWithString:[[self.currentlyDisplayedDetailViewController.detailItem attributeForName:@"link"] stringValue]];
        }
        
        if ( url )
            activityItems = @[url];
    }
    
    if ( activityItems )
    {
        UIActivityViewController *activityViewController = [[UIActivityViewController alloc] initWithActivityItems:activityItems applicationActivities:@[[[TUSafariActivity alloc] init]]];
        
        if ( SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(_iOS_7_0))
            activityViewController.popoverPresentationController.barButtonItem = sender;
        
        [self presentViewController:activityViewController animated:YES completion:nil];
        
        // TODO: toolbar hidden after dismissed email composer: WTF ?
    }
}

#pragma mark - toolbar

-(void)updateToolBarItems
{
    BOOL isLocalContent = [self isLocalContent];
    
    NSString *isText = [[self.currentlyDisplayedDetailViewController.detailItem attributeForName:@"IsText"] stringValue];
    
    // show / hide restore item button
    NSMutableArray *toolbarItems = [self.toolbarItems mutableCopy];

    if ( isLocalContent )
    {
        [toolbarItems removeObject:self.restoreItemBarButtonItem];
    }
    else
    {
        if (![toolbarItems containsObject:self.restoreItemBarButtonItem])
            [toolbarItems insertObject:self.restoreItemBarButtonItem atIndex:1];
    }
    
    // show / hide bookmark button
    if (
        // self.displayedDataType == DisplayedDataType_SubscriptionChooser||
        isText )
    {
        [toolbarItems removeObject:self.organizeBarButtonItem];
    }
    else
    {
        if (![toolbarItems containsObject:self.organizeBarButtonItem] )
            [toolbarItems insertObject:self.organizeBarButtonItem atIndex:toolbarItems.count - 2];
    }
        
    
    self.toolbarItems = toolbarItems; // setToolbarItems:toolbarItems animated:YES];
}

-(BOOL)isLocalContent
{
    return
    // empty request
    (
     !self.currentlyDisplayedDetailViewController.webView.request.URL
     || (
         self.currentlyDisplayedDetailViewController.webView.request.URL
         && [self.currentlyDisplayedDetailViewController.webView.request.URL.absoluteString length] < 1
         )
     )
    // cached / local request
    || [self.currentlyDisplayedDetailViewController.webView.request.URL.absoluteString isEqualToString:@"about:blank"]
    || [self.currentlyDisplayedDetailViewController.webView.request.URL.scheme isEqualToString:@"file"]
    ;
}


- (IBAction)stepperValueChanged:(UIStepper *)sender
{
    fontSizePercentage = sender.value;
    
    // update all views
    // also we have a bug :-( where currently displayed detail is not the right one
    for (DetailViewController *uivc in self.viewControllers )
        [uivc updateFontSize];
    
    // [self.currentlyDisplayedDetailViewController updateFontSize];
}

- (IBAction)organize:(UIBarButtonItem *)sender
{
    // if ( self.displayedDataType != DisplayedDataType_SubscriptionChooser )
    {
        // mark as bookmark in the tree
        if ( [[SubscriptionsController sharedInstance] markItemBookmarked:self.currentlyDisplayedDetailViewController.detailItem clear:NO] )
        {
            // notify view controllers
            [[NSNotificationCenter defaultCenter] postNotificationName:@"itemBookmarked" object:nil];
        }
        
        [SVProgressHUD showSuccessWithStatus:NSLocalizedString(@"Bookmarked", nil)];
    }
}

- (IBAction)restoreItem:(UIBarButtonItem *)sender
{
	[self.currentlyDisplayedDetailViewController loadItem];
}

@end
