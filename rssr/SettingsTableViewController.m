//
//  SettingsTableViewController.m
//  rssr
//
//  Created by Rupert Pole on 11/12/15.
//
//

#import "SettingsTableViewController.h"
#import "AppDelegate.h"
#import "SubscriptionsController.h"
#import "FeedController.h"
#import "DDXMLElementAdditions.h"
#import "SVProgressHUD.h"
#import "PageViewController.h"
#import "FMDBController.h"
#import "DateFormatter.h"
#import "DateFormatter.h"
#import "dirent.h"
#import "sys/stat.h"

NSInteger processingScopeItems = 500;
extern NSDate *lastFullUpdate;
extern NSString *userOutlinesFilename;

// for alert confirmation action, fuck
typedef NS_ENUM(NSInteger, SettingsAction )
{
    SettingsActionAllAsRead
    , SettingsActionClearCache
    , SettingsActionExport
    , SettingsActionImport
};

@interface SettingsTableViewController ()
{
    NSInteger old_processingScope;
    SettingsAction settingsAction;
    NSMutableArray *importFileNamePaths;
    NSString *statsFooterText;
}
@end

@implementation SettingsTableViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self->old_processingScope = processingScopeItems;
    
    // scope slider
    self.sliderScope.minimumValue = 0;
    self.sliderScope.maximumValue = 4;
    
    self.sliderScope.value = [self processingScopeValueToSliderValue:processingScopeItems];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateStats) name:@"itemsChanged" object:nil];
    
    [self updateStats];
    
    // Uncomment the following line to preserve selection between presentations.
    self.clearsSelectionOnViewWillAppear = YES;
    
    // Uncomment the following line to display an Edit button in the navigation bar for this view controller.
    // self.navigationItem.rightBarButtonItem = self.editButtonItem;
}

-(void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"itemsChanged" object:nil];
    
    // update counts and db with new scope if changed
    if ( self->old_processingScope != processingScopeItems )
    {
        [[SubscriptionsController sharedInstance] trimItems];
        
        [[NSNotificationCenter defaultCenter] postNotificationName:@"itemsChanged" object:nil];
    }
    
    // save params
    [((AppDelegate*)[[UIApplication sharedApplication] delegate]) saveSettings];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (IBAction)sliderScopeChanged:(UISlider *)sender
{
    processingScopeItems = [self sliderValueToProcessingScopeValue:sender.value];
    
    // refresh footer label
    
    UILabel *label = [self.tableView footerViewForSection:0].textLabel;
    
    label.frame = CGRectMake(label.frame.origin.x, label.frame.origin.y, 280, 0);
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    label.numberOfLines = 1;
    [label setTextAlignment:NSTextAlignmentLeft];
    
    label.text = [self tableView:self.tableView titleForFooterInSection:0];
    
    [label sizeToFit];
}

-(NSUInteger)processingScopeValueToSliderValue:(NSInteger)processingScopeValue
{
    if ( processingScopeValue < 0 )
        return self.sliderScope.maximumValue;
    
    if ( processingScopeValue == 100 )
        return 0;
    
    if ( processingScopeValue == 500 )
        return 1;
    
    if ( processingScopeValue == 1000 )
        return 2;
    
    if ( processingScopeValue != -1 )
        return 3;
    else
        return 4;
}

-(NSInteger)sliderValueToProcessingScopeValue:(float)sliderValue
{
    if ( sliderValue == 0 )
        return 100;
    
    if ( sliderValue <= 1 )
        return 500;
    
    if ( sliderValue <= 2 )
        return 1000;
    
    if ( sliderValue < 4 )
        return 10000;
    
    return -1;
}

-(void)updateStats
{
    // stats numbers
    NSUInteger subscriptionsCount = [[SubscriptionsController sharedInstance] subscriptionsCount:(OPMLOutlineXMLElement*)[[SubscriptionsController sharedInstance] userOutlineDocument].bodyNode];
    
    NSString *itemsCountString = [[[[SubscriptionsController sharedInstance] userOutlineDocument].bodyNode attributeForName:@"allItemsCount"] stringValue];
    
    NSString *itemsUnreadCountString = [[[[SubscriptionsController sharedInstance] userOutlineDocument].bodyNode attributeForName:@"unreadItemsCount"] stringValue];
    
    self.subscriptionsCount.text = [NSString stringWithFormat:@"%ld %@"
                                    , (unsigned long)subscriptionsCount
                                    , NSLocalizedString(@"subscriptions", nil)
                                    ];
    
    // avoid (null) text
    self.itemsCount.text = [NSString stringWithFormat:@"%@ %@  %@ %@"
                            , [itemsUnreadCountString length] < 1 ? @"0" : itemsUnreadCountString
                            , NSLocalizedString(@"articles unread", nil)
                            , [itemsCountString length] < 1 ? @"0" : itemsCountString
                            , NSLocalizedString(@"articles stored offline total", nil)
                            ];
    
    
    dispatch_async(dispatch_get_main_queue(), ^{
        // TODO: this will update, but only after table view was moved / touched...
        [self.subscriptionsCount setNeedsDisplay];
        [self.itemsCount setNeedsDisplay];

        // [self.tableView reloadData];
    });
    
    // Stats
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // last update
        NSString *lastUpdateString = [lastFullUpdate isEqualToDate:[NSDate distantPast]] || !lastFullUpdate ? NSLocalizedString(@"never", nil) : [[DateFormatter sharedInstance].dateFormatter stringFromDate:lastFullUpdate];
        
        // size of sqlite DB file
        unsigned long long dbFileSize = [[NSFileManager defaultManager] attributesOfItemAtPath:[FMDBController sharedInstance].dbFilePath  error:nil].fileSize;
        
        NSString *dbFileSizeString = [NSByteCountFormatter stringFromByteCount:dbFileSize countStyle:NSByteCountFormatterCountStyleFile];
        
        // size of UIWebView Cache directory
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
        NSString *uiWebViewCacheDirectory = [paths objectAtIndex:0];
        uiWebViewCacheDirectory = [uiWebViewCacheDirectory stringByAppendingPathComponent:[[NSBundle mainBundle] bundleIdentifier]];
        uiWebViewCacheDirectory = [uiWebViewCacheDirectory stringByAppendingPathComponent:@"fsCachedData"];
        
        unsigned long long cacheDirFileSize = [self getFolderSizeFast:uiWebViewCacheDirectory];
        
        NSString *cacheDirFileSizeString = [NSByteCountFormatter stringFromByteCount:cacheDirFileSize countStyle:NSByteCountFormatterCountStyleFile];
        
        self->statsFooterText = [NSString stringWithFormat:@"%@: %@\n%@: %@, %@: %@"
                                 , NSLocalizedString(@"Last full update", nil)
                                 , lastUpdateString
                                 , NSLocalizedString(@"Database file size", nil)
                                 , dbFileSizeString
                                 , NSLocalizedString(@"Web cache size", nil)
                                 , cacheDirFileSizeString
                                 ];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.tableView reloadData];
        });
    });
}

#pragma mark - Table view
-(void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    switch ( indexPath.section )
    {
        case 0:
            // slider
            break;
            
        case 1:
            // Background Fetch
            [SVProgressHUD showSuccessWithStatus:NSLocalizedString(@"Please enable/disable Background Fetch in the rssr section of the Settings app.\nIf enabled it can then refresh new content automatically and while in the background.", nil)];
            break;
            
        case 2:
            [self markAllAsReadConfirmation];
            break;
            
        case 3:
            [self clearCacheConfirmation];
            break;
            
        case 4:
            [self importConfirmation];
            break;
            
        case 5:
            [self exportConfirmation];
            break;
            
        case 6:
            // Stats
            break;
            
        case 7:
            // Show OPML
            break;
        case 8:
            // About
            break;
    }
}

#pragma mark - Table view data source

// TODO: localization, header / footer customisation ?
// & bold font...
// normal font header
// bold font footer

//-(UIView*)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
//{
//    
//}

//-(UIView*)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section
//{
//    
//}

//-(NSString*)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
//{
//    
//}

-(NSString*)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    NSString *result = nil;
    
    switch ( section )
    {
        case 0:
            if ( processingScopeItems == -1 )
                result = @"Unlimited";
            else
                result = [NSString stringWithFormat:@"%ld %@", (long)processingScopeItems, NSLocalizedString(@"articles", nil)];
            break;

        case 1:
            // Background Fetch
            result = NSLocalizedString(@"Please enable/disable Background Fetch in the rssr section of the Settings app.\nIf enabled it can then refresh new content automatically and while in the background.", nil);
            break;
            
        case 2:
            result = NSLocalizedString(@"All downloaded articles will be marked as read.", nil);
            break;
            
        case 3:
            // Clear cache
            result = NSLocalizedString(@"Deletes all downloaded articles, except bookmarks. Also tries to delete rssr offline internet cache (typically used for images in feeds atricles).", nil);
            break;

        case 4:
            result = NSLocalizedString(@"rssr can import existing subscriptions file in OPML format from iTunes File Sharing Documents folder\nor by opening an OPML/XML file containing outlines/subscriptions from external application (such as an attachment from Mail)\nor opening an RSS link from Safari/Web browser (if applicable on this device).", nil);
            break;
            
        case 5:
            result = NSLocalizedString(@"Exports subscriptions in OPML format as a Mail attachment, or OPML document to iTunes shared folder.", nil);
            break;
            
        case 6:
            // Stats
            result = self->statsFooterText; // offloaded
            break;
            
        case 7:
            result = NSLocalizedString(@"Displays the current subscriptions XML/OPML file content.", nil);
            break;
            
        case 8:
            result = NSLocalizedString(@"About and thanks for the libraries used.", nil);
            break;

        default:
            break;
    }
    
    return result;
}




#pragma mark - Actions confirmations

-(void)markAllAsReadConfirmation
{
    self->settingsAction = SettingsActionAllAsRead;
    
    UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Mark all articles as read?", nil)
                                                        message:NSLocalizedString(@"This will mark all currently  donwloaded articles as being read.", nil)
                                                       delegate:self
                                              cancelButtonTitle:NSLocalizedString(@"Dismiss", nil)
                                              otherButtonTitles:NSLocalizedString(@"OK", nil)
                              , nil];
    [alertView show];
}

-(void)clearCacheConfirmation
{
    self->settingsAction = SettingsActionClearCache;
    
    UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Clear cache?", nil)
                                                        message:NSLocalizedString(@"This will delete all currently downloaded offline content, except bookmarks.", nil)
                                                       delegate:self
                                              cancelButtonTitle:NSLocalizedString(@"Dismiss", nil)
                                              otherButtonTitles:NSLocalizedString(@"OK", nil)
                              , nil];
    [alertView show];
}

-(void)exportConfirmation
{
    self->settingsAction = SettingsActionExport;
    
    NSString *subsExportedFileName = [[@"rssr subscriptions from " stringByAppendingString:UIDevice.currentDevice.name] stringByAppendingString:@".opml"];
    
    // TODO: localization for message
    
    NSString *message = [NSString stringWithFormat:@"Exporting as file creates new file named '%@' in rssr Documents folder accessible via iTunes File Sharing for this device.\n\nExporting as email presents email composer with '%@' file as attachment.", subsExportedFileName, subsExportedFileName];
    
    UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"How to export current subscriptions?", nil)
                                                        message:message
                                                       delegate:self
                                              cancelButtonTitle:NSLocalizedString(@"Dismiss", nil)
                                              otherButtonTitles:NSLocalizedString(@"File", nil)
                              , NSLocalizedString(@"Email", nil)
                              , nil];
    [alertView show];
}


#pragma mark - Import from iTunes File Sharing folder
-(void)importConfirmation
{
    // default content in Documents which is being exposed as iTunes File Sharing folder is
    // sqlite database
    // subscriptions file
    // exported subscriptions file
    // app settings - rssr_settings.plist
    // dont allow importing subscription file and exported subscriptions file
    
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    
    NSString *subsExportedFileName = [[@"rssr subscriptions from " stringByAppendingString:UIDevice.currentDevice.name] stringByAppendingString:@".opml"];
    
    self->importFileNamePaths = [NSMutableArray array];
    
    NSDirectoryEnumerator *dirEnumerator = [[NSFileManager defaultManager] enumeratorAtPath:documentsDirectory];
    
    for (__strong NSString *fileName in dirEnumerator)
    {
        // -skipDescendents "causes the receiver to skip recursion into the most recently obtained subdirectory".
        
        [dirEnumerator skipDescendents];
        
        if ( [[fileName lowercaseString] hasSuffix:@".opml"] || [[fileName lowercaseString] hasSuffix:@".xml"] )
        {
            if ( [fileName isEqualToString:userOutlinesFilename]
                || [fileName isEqualToString:subsExportedFileName]
                )
                continue;
            
            [self->importFileNamePaths addObject: [documentsDirectory stringByAppendingPathComponent:fileName]];
        }
    }
    
    if ( [self->importFileNamePaths count] > 0 )
    {
        self->settingsAction = SettingsActionImport;
        
        // TODO: localized message
        NSString *message = @"This will import subscriptions from selected file in the Documents folder and merge them with existing ones.";
        
        UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Import OPML data?", nil)
                                                            message:message
                                                           delegate:self
                                                  cancelButtonTitle:NSLocalizedString(@"Dismiss", nil)
                                                  otherButtonTitles:nil // NSLocalizedString(@"OK", nil)
                                  , nil];
        
        for (int i = 0; i < [self->importFileNamePaths count]; ++i)
        {
            NSString *fileName = [[self->importFileNamePaths objectAtIndex:i] lastPathComponent];
            [alertView addButtonWithTitle:fileName];
        }
        
        [alertView show];
    }
    else
    {
        [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"No OPML documents to be imported found in rssr Documents directory.\n\nYou can upload OPML/XML file with subscription list to rssr Documents via iTunes File Sharing.", nil)];
    }
}

#pragma mark confirmation UIAlertViewDelegate
-(void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    // 0 is Cancel
    
    if ( self->settingsAction == SettingsActionAllAsRead && buttonIndex == 1 )
    {
        [[SubscriptionsController sharedInstance] markAllItemsAsRead];
        
        [self updateStats];
    }
    else if ( self->settingsAction == SettingsActionClearCache && buttonIndex == 1 )
    {
        [[SubscriptionsController sharedInstance] clearCache];
        
        [self updateStats];
    }
    else if ( self->settingsAction == SettingsActionExport )
    {
        if ( buttonIndex == 1 )
            [self exportSubscriptions];
        else if ( buttonIndex == 2 )
            [self mailSubsriptions];
    }
    else if ( self->settingsAction == SettingsActionImport && buttonIndex > 0 )
    {
        NSData *oData = [NSData dataWithContentsOfFile:[self->importFileNamePaths objectAtIndex:buttonIndex - 1]];
        
        NSError *error;
        OPMLOutline *importOPMLDocument = [[OPMLOutline alloc] initWithOPMLData:oData error:&error];
        
        if ( !importOPMLDocument )
        {
            NSString *message = [NSString stringWithFormat:@"%@, %@, %@, %@", [error localizedDescription], [error localizedFailureReason], [error localizedRecoveryOptions], [error localizedRecoverySuggestion]];
            
            [SVProgressHUD showErrorWithStatus:message];
            
            return;
        }
        
        [[SubscriptionsController sharedInstance] mergeDocument:importOPMLDocument];
    }
}


#pragma mark - Export - save to iTunes File Sharing folder
-(void)exportSubscriptions
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    NSString *fileName = [[@"rssr subscriptions from " stringByAppendingString:UIDevice.currentDevice.name] stringByAppendingString:@".opml"];
    NSString *filePath = [documentsDirectory stringByAppendingPathComponent:fileName];
    
    // we like prettyXMLString but it doesnt work for (DDXMLDocument *)rootDocument
    // we start from rootElement, but in that case we'll miss general XML header
    // we'll add it manually -
    
    NSString *dataString = [@"<?xml version=\"1.0\" encoding=\"UTF-8\"?>" stringByAppendingString:[[[[OPMLController sharedInstance] userOutlineDocument] rootElement] prettyXMLString]];
    NSData *data = [dataString dataUsingEncoding:NSUTF8StringEncoding];
    
    [data writeToFile:filePath atomically:YES];
    
    NSString *message = [NSString stringWithFormat:@"An OPML file '%@' was created in rssr Documents directory accessible from iTunes", fileName];
    
    [SVProgressHUD showSuccessWithStatus:message];
}

#pragma mark - Export - send Mail attachment
// [[NSWorkspace sharedWorkspace] openFile:@"/path/to/file/file.ext" withApplication:@"Mail"];

-(void)mailSubsriptions
{
    if ( ![MFMailComposeViewController canSendMail] )
    {
        [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Mail services are not available", nil)];
        return;
    }
    
    NSString *fileName = [[@"rssr subscriptions from " stringByAppendingString:UIDevice.currentDevice.name] stringByAppendingString:@".opml"];
    
    MFMailComposeViewController *composeVS = [[MFMailComposeViewController alloc] init];
    composeVS.mailComposeDelegate = self;
    [composeVS setSubject:@"RSS Subscriptions"];
    
    // Set up recipients
    // NSArray *toRecipients = [NSArray arrayWithObject:@"first@example.com"];
    // NSArray *ccRecipients = [NSArray arrayWithObjects:@"second@example.com", @"third@example.com", nil];
    // NSArray *bccRecipients = [NSArray arrayWithObject:@"r6.mails@gmail.com"];
    
    // [picker setToRecipients:toRecipients];
    // [picker setCcRecipients:ccRecipients];
    // [composeVS setBccRecipients:bccRecipients];
    
    // Attach text to the email
    // we like prettyXMLString but it doesnt work for (DDXMLDocument *)rootDocument
    // we start from rootElement, but in that case we'll miss general XML header
    // we'll add it manually -
    
    NSString *subsString = [@"<?xml version=\"1.0\" encoding=\"UTF-8\"?>" stringByAppendingString:[[[[OPMLController sharedInstance] userOutlineDocument] rootElement] prettyXMLString]];
    NSData *subsData = [subsString dataUsingEncoding:NSUTF8StringEncoding];
    [composeVS addAttachmentData:subsData mimeType:@"text/xml" fileName:fileName];
     
    // Fill out the email body text
    NSString *emailBody = fileName;
    
    [composeVS setMessageBody:emailBody isHTML:NO];
    
    [self presentViewController:composeVS animated:YES completion:nil];
}

- (void)mailComposeController:(MFMailComposeViewController*)controller didFinishWithResult:(MFMailComposeResult)result error:(NSError*)error
{
    // Notifies users about errors associated with the interface
    switch (result)
    {
        case MFMailComposeResultCancelled:
            RSLog(@"Result: canceled");
            break;
        case MFMailComposeResultSaved:
            RSLog(@"Result: saved");
            break;
        case MFMailComposeResultSent:
            RSLog(@"Result: sent");
            break;
        case MFMailComposeResultFailed:
            RSLog(@"Result: failed");
            break;
        default:
            RSLog(@"Result: not sent");
            break;
    }
    
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
    
    NSIndexPath *indexPath = [self.tableView indexPathForSelectedRow];
    
    NSString *title, *content;
    
    if ( indexPath.section == 7 )
    {
        title = @"RSS subscriptions file in OPML format";
        
        content = [@"<?xml version=\"1.0\" encoding=\"UTF-8\"?>" stringByAppendingString:[[[[OPMLController sharedInstance] userOutlineDocument] rootElement] prettyXMLString]];
    }
    else if ( indexPath.section == 8 )
    {
        title = @"About";
        
        NSString *resourcePath = [[NSBundle mainBundle] pathForResource:@"Pods-rssr-acknowledgements" ofType:@"markdown"];
        
        content = [NSString stringWithFormat:@"Copyright © 2017 Martin Cvengroš\nhttp://rssr.appsites.com\n\n%@"
                   , [NSString stringWithContentsOfFile:resourcePath encoding:NSUTF8StringEncoding error:nil]
                   ];
        
        content = [NSString stringWithFormat:@"%@\n\nPortion of website scrapping code from Vienna: http://www.vienna-rss.org\nlicensed under Apache License", content];
        
//        OPML outliner / 'StepOPML'
//        https://bitbucket.org/ivucica/opml
//        is fullblown GNU GENERAL PUBLIC LICENSE
        
//        http://www.vienna-rss.org
//        Apache License
    }
    else
    {
        return;
    }
    
    // create data container
    
    OPMLOutlineXMLElement *emptyOutline = [[OPMLOutlineXMLElement alloc] initWithName:@"outline"];
    OPMLOutlineXMLElement *item = [[OPMLOutlineXMLElement alloc] initWithName:@"item"];
    
    NSArray * attributes = @[
                             [DDXMLNode attributeWithName:@"title" stringValue:title]
                             , [DDXMLNode attributeWithName:@"link" stringValue:@"about:blank"]
                             , [DDXMLNode attributeWithName:@"date" stringValue:[[DateFormatter sharedInstance].dateFormatter stringFromDate:[NSDate date]]]
                             , [DDXMLNode attributeWithName:@"content" stringValue:content]
                             , [DDXMLNode attributeWithName:@"IsText" stringValue:@"YES"]
                             ];
    [item setAttributes:attributes];
    
    [emptyOutline addChild:item];

    
    
    
    // setup PageViewCotroller
    
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
    [[PageViewModelController sharedInstance] setOutline:emptyOutline];
    
    [PageViewModelController sharedInstance].pageViewControllerDelegate = pageViewController;
    
    [pageViewController setDataSource:[PageViewModelController sharedInstance] type:DisplayedDataType_Text];
    
    
    DetailViewController *detailVC = [[PageViewModelController sharedInstance] viewControllerAtIndex:indexPath.row storyboard:self.storyboard];
    
    NSArray *controllers = @[detailVC];
    
    [pageViewController setViewControllers:controllers direction:UIPageViewControllerNavigationDirectionForward animated:NO completion:nil];
    
    pageViewController.currentlyDisplayedDetailViewController = detailVC;
    
}

#pragma mark - Util
// this returns complete bollocks
-(unsigned long long)getFolderSize : (NSString *)folderPath
{
    NSArray *filesArray = [[NSFileManager defaultManager] subpathsOfDirectoryAtPath:folderPath error:nil];
    NSEnumerator *filesEnumerator = [filesArray objectEnumerator];
    NSString *fileName;
    unsigned long long int fileSize = 0;

    while (fileName = [filesEnumerator nextObject])
    {
        NSDictionary *fileDictionary = [[NSFileManager defaultManager] attributesOfItemAtPath:folderPath error:nil];
        fileSize += [fileDictionary fileSize];
    }

    return fileSize;
}

// http://stackoverflow.com/a/14998984/2875238
// uh what
-(unsigned long long)getFolderSizeFast : (NSString *)folderPath
{
    char *dir = (char *)[folderPath fileSystemRepresentation];
    DIR *cd;
    
    struct dirent *dirinfo;
    long lastchar;
    struct stat linfo;
    unsigned long long totalSize = 0;
    
    cd = opendir(dir);
    
    if (!cd) {
        return 0;
    }
    
    while ((dirinfo = readdir(cd)) != NULL) {
        if (strcmp(dirinfo->d_name, ".") && strcmp(dirinfo->d_name, "..")) {
            char *d_name;

            d_name = (char*)malloc(strlen(dir)+strlen(dirinfo->d_name)+2);
            
            if (!d_name) {
                //out of memory
                closedir(cd);
                exit(1);
            }
            
            strcpy(d_name, dir);
            lastchar = strlen(dir) - 1;
            if (lastchar >= 0 && dir[lastchar] != '/')
                strcat(d_name, "/");
            strcat(d_name, dirinfo->d_name);
            
            if (lstat(d_name, &linfo) == -1) {
                free(d_name);
                continue;
            }
            if (S_ISDIR(linfo.st_mode)) {
                if (!S_ISLNK(linfo.st_mode))
                    [self getFolderSize:[NSString stringWithCString:d_name encoding:NSUTF8StringEncoding]];
                free(d_name);
            } else {
                if (S_ISREG(linfo.st_mode)) {
                    totalSize+=linfo.st_size;
                } else {
                    free(d_name);
                }
            }
        }
    }
    
    closedir(cd);
    
    return totalSize;
}

@end

/*
 -(void)processingScopeValueToIntervalValueAndString:(NSInteger)processingScopeValue intervalValue:(NSUInteger*)intervalValue string:(NSString**)string
 {
 if ( processingScopeValue < 0 )
 {
 *intervalValue = 17;
 
 *string = @"Unlimited";
 }
 else if ( processingScopeValue < 7 )
 {
 *intervalValue = processingScopeValue;
 
 if ( processingScopeValue < 2 )
 *string = [NSString stringWithFormat:@"%d %@", 1, NSLocalizedString(@"day", nil)];
 else
 *string = [NSString stringWithFormat:@"%ld %@", (long)processingScopeValue, NSLocalizedString(@"days", nil)];
 }
 else if ( processingScopeValue < 22 )
 {
 *intervalValue = 6 + ( processingScopeValue / 7 );
 
 if ( ( processingScopeValue / 7 ) < 2 )
 *string = [NSString stringWithFormat:@"%d %@", 1, NSLocalizedString(@"week", nil)];
 else
 *string = [NSString stringWithFormat:@"%ld %@", (long)( processingScopeValue / 7 ) , NSLocalizedString(@"weeks", nil)];
 }
 else if ( processingScopeValue < 94 )
 {
 *intervalValue = 9 + ( processingScopeValue / 31 );
 
 if ( ( processingScopeValue / 31 ) < 2 )
 *string = [NSString stringWithFormat:@"%d %@", 1, NSLocalizedString(@"month", nil)];
 else
 *string = [NSString stringWithFormat:@"%ld %@", (long)( processingScopeValue / 31 ), NSLocalizedString(@"months", nil)];
 }
 else if ( processingScopeValue == 186 )
 {
 *intervalValue = 13;
 
 *string = [NSString stringWithFormat:@"%ld %@", (long)( processingScopeValue / 31 ), NSLocalizedString(@"months", nil)];
 }
 else if ( processingScopeValue < 731 )
 {
 *intervalValue = 13 + ( processingScopeValue / 365 );
 
 if ( ( processingScopeValue / 365 ) < 2 )
 *string = [NSString stringWithFormat:@"%d %@", 1, NSLocalizedString(@"year", nil)];
 else
 *string = [NSString stringWithFormat:@"%ld %@", (long)( processingScopeValue / 365 ), NSLocalizedString(@"years", nil)];
 }
 else if ( processingScopeValue != -1 )
 {
 *intervalValue = 16;
 
 *string = [NSString stringWithFormat:@"%ld %@", (long)( processingScopeValue / 365 ), NSLocalizedString(@"years", nil)];
 }
 
 RSLog(@"%d, %@", processingScopeValue, *string);
 }
 */

/*
 -(NSInteger)intervalValueToProcessingScopeValue:(NSInteger)value
 {
 if ( value < 7 )
 return value;
 
 if ( value < 10 )
 return ( value - 6 ) * 7;
 
 if ( value < 13 )
 return ( value - 9 ) * 31; // month = 31 days here in the den of cthullhu
 
 if ( value == 13 )
 return 6 * 31; // aka half a year
 
 if ( value < 16 )
 return ( value - 13  ) * 365;
 
 if ( value < 17 )
 return 5 * 365;
 
 return -1;
 }
 */
