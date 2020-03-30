//
//  AppDelegate.m
//  rssr
//
//  Created by Rupert Pole on 24/10/15.
//
//

// document type org.opml.opml acc. to http://inessential.com/2017/01/05/opml_file_type_on_macs

#import "AppDelegate.h"
#import "DetailViewController.h"
#import "MainViewController.h"
#import "SubscriptionsController.h"
#import "PageViewModelController.h"
#import "PageViewController.h"
#import "SVProgressHUD.h"
#import "RSSRURLProtocol.h"
#import "FeedController.h"

extern double fontSizePercentage;
extern BOOL toolBarsHidden;
extern NSString *searchedString;
extern NSUInteger searchedScope;
extern NSInteger processingScopeItems;
extern NSDate *lastFullUpdate;
BOOL firstLaunch = NO;

@interface AppDelegate () <UISplitViewControllerDelegate>

@end

@implementation AppDelegate


- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    // handle teh scheme
    if ( launchOptions )
    {
        //for (NSString *key in [launchOptions allKeys]) RSLog(@"%@ : %@", key, [launchOptions valueForKey:key] );
        
        //Nov 23 13:28:41 r6s-iPod rssr[2070] <Warning>: UIApplicationLaunchOptionsURLKey : feed://www.aktuality.sk/rss/
        //Nov 23 13:28:41 r6s-iPod rssr[2070] <Warning>: UIApplicationLaunchOptionsSourceApplicationKey : com.apple.mobilesafari
    }
    
    
    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"HasLaunchedOnce"])
    {
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"HasLaunchedOnce"];
        [[NSUserDefaults standardUserDefaults] synchronize];
        
        firstLaunch = YES;
    }
    else
    {
        firstLaunch = NO;
    }
    
    // setup UISplitViewController delegate and
    // show the backbutton on detail
    
    // iPad / `new` iOS
    if ( [self.window.rootViewController isKindOfClass:[UISplitViewController class]] )
    {
        UISplitViewController *splitViewController = (UISplitViewController *)self.window.rootViewController;
        splitViewController.delegate = self;
        
		// prevent the gesture for UIPageViewController
		// splitViewController.presentsWithGesture = NO;
		

		// set up [empty] data source for UIPageViewController to avoid crashing it
        
        UINavigationController *pageViewNavigationController = [splitViewController.viewControllers lastObject];
        PageViewController *pageViewController = (PageViewController*)[[pageViewNavigationController viewControllers] firstObject];
        
        [PageViewModelController sharedInstance].pageViewControllerDelegate = pageViewController;
		
		// dont even cache init empty .
        [pageViewController setDataSource:[PageViewModelController sharedInstance] type:DisplayedDataType_Bookmarks]; // to leave the bookmark button out
		
        DetailViewController *startingViewController = [[PageViewModelController sharedInstance] viewControllerAtIndex:0 storyboard:[UIStoryboard storyboardWithName:@"Main" bundle:nil]];

        NSArray *viewControllers = @[startingViewController];
        
        [pageViewController setViewControllers:viewControllers direction:UIPageViewControllerNavigationDirectionForward animated:NO completion:nil];
        pageViewController.currentlyDisplayedDetailViewController = startingViewController;
        
        
        pageViewController.navigationItem.leftBarButtonItem = splitViewController.displayModeButtonItem;
        pageViewController.navigationItem.leftItemsSupplementBackButton = YES;
    }
    // iPhone / `old` iOS
    else if( [self.window.rootViewController isKindOfClass:[UINavigationController class]] )
    {
        ;
    }
    else
    {
        [SVProgressHUD showErrorWithStatus:@"We really can't tell what rootViewController is. This is pretty unfortunate, as in really really bad unfortunate. Nothing and anything can and will happen."];
        
        return NO;
    }
  

    // rssr_settings
    
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *path = [[paths firstObject] stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.plist",@"rssr_settings"]];
    
    NSDictionary *dict = [[NSDictionary alloc] initWithContentsOfFile:path];
    
    // fallback to default in place init values
    if ( dict )
	{
        id object = [dict objectForKey:@"fontSizePercentage"];
        if (object)
            fontSizePercentage = [object doubleValue];
        
        object = [dict objectForKey:@"toolBarsHidden"];
        if (object)
            toolBarsHidden = [object boolValue];
        
		searchedString = [dict objectForKey:@"searchedString"];
        
        object = [dict objectForKey:@"searchedScope"];
        if (object)
            searchedScope = [object integerValue];
        
        object = [dict objectForKey:@"processingScopeItems"];
        if (object)
            processingScopeItems = [object integerValue];
        
        object = [dict objectForKey:@"lastFullUpdate"];
        if (!object)
            lastFullUpdate = [NSDate distantPast];
        else
            lastFullUpdate = (NSDate*)object;
	}
    
    // background fetch
    if ( [application respondsToSelector:@selector(setMinimumBackgroundFetchInterval:)] )
        [application setMinimumBackgroundFetchInterval:UIApplicationBackgroundFetchIntervalMinimum];
    
    // RSS content handler
    [NSURLProtocol registerClass:[RSSRURLProtocol class]];
    
    // Local notification
    // In iOS 8.0 and later, your application must register for user notifications using -[UIApplication registerUserNotificationSettings:] before being able to set the icon badge.
    if ( [application respondsToSelector:@selector(registerUserNotificationSettings:)] )
    {
        UIUserNotificationSettings *ns = [UIUserNotificationSettings settingsForTypes:UIUserNotificationTypeBadge categories:nil];
        [application registerUserNotificationSettings:ns];
    }
    
    if ( application.applicationState == UIApplicationStateBackground )
    {
    }
    
    return YES;
}

-(void)application:(UIApplication *)application performFetchWithCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler
{
    // if fetch is already runnig do nothing
    if ( [SubscriptionsController sharedInstance].isRefreshing )
    {
        completionHandler(UIBackgroundFetchResultNoData);
        return;
    }
    
    // limit refreshing to at least to 5 minutes between e.g. manual refresh and background fetch
    if ( lastFullUpdate )
    {
        NSTimeInterval refDiff = [[NSDate date] timeIntervalSinceDate:lastFullUpdate];
        
        if ( refDiff <= 300 )
        {
            completionHandler(UIBackgroundFetchResultNoData);
            return;
        }
    }
    
        
    OPMLOutlineXMLElement *body = (OPMLOutlineXMLElement*)[SubscriptionsController sharedInstance].userOutlineDocument.bodyNode;
    
    NSInteger allCountCurr = [[[body attributeForName:@"allItemsCount"] stringValue] integerValue];
    __block NSInteger allCountNew = allCountCurr;
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        
        NSLog(@"== :: == :: backgroundFetch refreshFeeds.");
    
        [[SubscriptionsController sharedInstance] refreshFeeds:body
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
        
        NSLog(@"== :: == :: backgroundFetch refreshFeeds ended.");
        
        allCountNew = [[[body attributeForName:@"allItemsCount"] stringValue] integerValue];
        
        [[SubscriptionsController sharedInstance] refreshCounts:body progress:^(NSUInteger _progress)
         {
             dispatch_async(dispatch_get_main_queue(), ^{
                 NSString *status = [NSString stringWithFormat:@"%@ %ld / %ld", NSLocalizedString(@"Processing", nil), (unsigned long)_progress, (unsigned long)allCountNew];
                 
                 [[NSNotificationCenter defaultCenter] postNotificationName:@"statusChanged" object:nil userInfo:@{@"status":status}];
             });
         }];
        
        NSLog(@"== :: == :: backgroundFetch refreshCounts ended.");
        
        dispatch_async(dispatch_get_main_queue(), ^{
            
            [[NSNotificationCenter defaultCenter] postNotificationName:@"statusChanged" object:nil userInfo:nil];
            
            if ( allCountNew > allCountCurr )
            {
                [[NSNotificationCenter defaultCenter] postNotificationName:@"itemsChanged" object:nil];
                completionHandler(UIBackgroundFetchResultNewData);
            }
            else
                completionHandler(UIBackgroundFetchResultNoData);
        });
    });
}

// called on iOS 6.1, deprecated iOS 9.0
-(BOOL)application:(UIApplication *)application openURL:(NSURL *)url sourceApplication:(NSString *)sourceApplication annotation:(id)annotation
{
    if ( [url isFileURL] )
    {
        // we are in Inbox of our Documents directory..
        
        // TODO: similar check is in OPMLOutline init
        NSData *oData = [NSData dataWithContentsOfURL:url];
        
        NSError *error;
        OPMLOutline *o = [[OPMLOutline alloc] initWithOPMLData:oData error:&error];
        
        if ( !o )
        {
            NSString *message = [NSString stringWithFormat:@"%@, %@, %@, %@", [error localizedDescription], [error localizedFailureReason], [error localizedRecoveryOptions], [error localizedRecoverySuggestion]];
            
            [SVProgressHUD showErrorWithStatus:message];
            
            return NO;
        }
        
        [[SubscriptionsController sharedInstance] mergeDocument:o];
        
        return YES;
    }
    else if ([[url scheme] isEqualToString:@"feed"])
    {
        RSLog(@"openURL : %@", url);
        RSLog(@"sourceApplication: %@", sourceApplication);
        RSLog(@"annotation: %@", annotation);
        
        //Nov 23 13:28:41 r6s-iPod rssr[2070] <Warning>: openURL : feed://www.aktuality.sk/rss/
        //Nov 23 13:28:41 r6s-iPod rssr[2070] <Warning>: sourceApplication: com.apple.mobilesafari
        //Nov 23 13:28:41 r6s-iPod rssr[2070] <Warning>: annotation: (null)
        
        // TODO: present chooser
        
        NSString *message;
        OPMLOutlineXMLElement *body = (OPMLOutlineXMLElement*)[[SubscriptionsController sharedInstance] userOutlineDocument].bodyNode;
        
        if ( ! [[SubscriptionsController sharedInstance] createOutlineFromURL:[url absoluteString] underParent:body message:&message] )
        {
            UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:@"Unable to add new subscription 😧"
                                                                message:message
                                                               delegate:nil
                                                      cancelButtonTitle:NSLocalizedString(@"Dismiss", nil)
                                                      otherButtonTitles:nil];
            
            [alertView show];
            
            return NO;
        }
        
        [SVProgressHUD showSuccessWithStatus:NSLocalizedString(@"Subscription added",nil)];
        
        [[NSNotificationCenter defaultCenter] postNotificationName:@"itemsChanged" object:nil];
        
        return YES;
    }
    
    return NO;
}

// iOS 9.0
-(BOOL)application:(UIApplication *)app openURL:(NSURL *)url options:(NSDictionary<NSString *,id> *)options
{
    if ( [url isFileURL] )
    {
        // we are in Inbox of our Documents directory..
        
        // TODO: similar check is in OPMLOutline init
        NSData *oData = [NSData dataWithContentsOfURL:url];
        
        NSError *error;
        OPMLOutline *o = [[OPMLOutline alloc] initWithOPMLData:oData error:&error];
        
        if ( !o )
        {
            NSString *message = [NSString stringWithFormat:@"%@, %@, %@, %@", [error localizedDescription], [error localizedFailureReason], [error localizedRecoveryOptions], [error localizedRecoverySuggestion]];
            
            [SVProgressHUD showErrorWithStatus:message];
            
            return NO;
        }
        
        [[SubscriptionsController sharedInstance] mergeDocument:o];
        
        return YES;
    }
    else if ([[url scheme] isEqualToString:@"feed"])
    {
        //for (NSString *key in [options allKeys])
        //    RSLog(@"%@ : %@", key, [options valueForKey:key] );
        
        
        // TODO: present chooser
        
        NSString *message;
        OPMLOutlineXMLElement *body = (OPMLOutlineXMLElement*)[[SubscriptionsController sharedInstance] userOutlineDocument].bodyNode;
        
        if ( ! [[SubscriptionsController sharedInstance] createOutlineFromURL:[url absoluteString] underParent:body message:&message] )
        {
            UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:@"Unable to add new subscription 😧"
                                                                message:message
                                                               delegate:nil
                                                      cancelButtonTitle:NSLocalizedString(@"Dismiss", nil)
                                                      otherButtonTitles:nil];
            
            [alertView show];
            
            return NO;
        }
        
        [SVProgressHUD showSuccessWithStatus:NSLocalizedString(@"Subscription added",nil)];
        
        [[NSNotificationCenter defaultCenter] postNotificationName:@"itemsChanged" object:nil];
        
        return YES;
    }
    
    return NO;
}

- (void)applicationWillResignActive:(UIApplication *)application
{
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
    
    [self saveSettings];
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
}

-(void)applicationDidReceiveMemoryWarning:(UIApplication *)application
{
    [self saveSettings];
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
    // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    
    // reflect background fetch changes / today's count ... on main view
    
    [[NSNotificationCenter defaultCenter] postNotificationName:@"itemsChanged" object:nil];
}

- (void)applicationWillTerminate:(UIApplication *)application
{
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
}

#pragma mark -
-(void)saveSettings
{
    NSDictionary *dict = [NSDictionary dictionaryWithObjects:@[ [NSNumber numberWithDouble:fontSizePercentage]
                                                                , [NSNumber numberWithBool:toolBarsHidden]
                                                                , searchedString ? searchedString : @""
                                                                , [NSNumber numberWithUnsignedInteger:searchedScope]
                                                                , [NSNumber numberWithInteger:processingScopeItems]
                                                                , lastFullUpdate ? lastFullUpdate : [NSDate distantPast]
                                                                ]
                                                     forKeys:@[ @"fontSizePercentage"
                                                                , @"toolBarsHidden"
                                                                , @"searchedString"
                                                                , @"searchedScope"
                                                                , @"processingScopeItems"
                                                                , @"lastFullUpdate"
                                                                ]
                          ];
    
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *path = [[paths firstObject] stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.plist",@"rssr_settings"]];
    
    NSString *error;
    NSData *plistData = [NSPropertyListSerialization dataFromPropertyList:dict
                                                                   format:NSPropertyListXMLFormat_v1_0
                                                         errorDescription:&error];
    if (plistData)
    {
        [plistData writeToFile:path atomically:YES];
    }
    else
    {
        NSLog(@"unable to save settings: %@",error);
    }
}

#pragma mark - Split view

- (BOOL)splitViewController:(UISplitViewController *)splitViewController collapseSecondaryViewController:(UIViewController *)secondaryViewController ontoPrimaryViewController:(UIViewController *)primaryViewController
{
    if ([secondaryViewController isKindOfClass:[UINavigationController class]] && [[(UINavigationController *)secondaryViewController topViewController] isKindOfClass:[PageViewController class]]
        // && ([(DetailViewController *)[(UINavigationController *)secondaryViewController topViewController] detailItem] == nil)
        )
    {
        // Return YES to indicate that we have handled the collapse by doing nothing; the secondary controller will be discarded.
        return YES;
    } else {
        return NO;
    }
}

@end
