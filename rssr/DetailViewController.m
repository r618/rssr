//
//  DetailViewController.m
//  rssr
//
//  Created by Rupert Pole on 24/10/15.
//
//

#import "DetailViewController.h"
#import "SubscriptionsController.h"
#import <objc/runtime.h>
#import "FeedController.h"
#import "PageViewController.h"

extern double fontSizePercentage;
extern BOOL toolBarsHidden;

BOOL linkClicked = NO;

extern BOOL firstLaunch;
extern BOOL tooltipsDetail_1_Completed;
extern BOOL tooltipsDetail_2_Completed;
extern BOOL tooltipsDetail_3_Completed;
extern BOOL tooltipsDetail_4_Completed;

@interface DetailViewController ()
{
    BOOL _webViewTapRecognized;
    Class cUITextTapRecognizer;
    
    UITapGestureRecognizer *tapGestureRecognizer;
    
    BOOL isHelpItem;
}

@end

@implementation DetailViewController

#pragma mark - Managing the detail item
-(void)setDetailItem:(OPMLOutlineXMLElement *)newDetailItem
{
    if (_detailItem != newDetailItem)
    {
        _detailItem = newDetailItem;
    }
}

// if summary is "" - might be only image - e.g.:
//
//<item title="France has a powerful and controversial new surveillance law" identifier="http://recode.net/2015/11/14/france-has-a-powerful-and-controversial-new-surveillance-law/" link="http://recode.net/2015/11/14/france-has-a-powerful-and-controversial-new-surveillance-law/" date="Nov 15, 2015, 12:15:02 AM" updated="Nov 15, 2015, 12:15:02 AM" summary="&lt;img alt=&quot;&quot; src=&quot;https://cdn2.vox-cdn.com/thumbor/Ckwzb-uEDrZsEnEX3RMmEKgtcPo=/0x17:1000x684/800x536/cdn0.vox-cdn.com/uploads/chorus_image/image/47663133/france_flag.0.0.jpg&quot; /&gt;" content="" author="Recode Staff">
//
// is it worth to pursue content from link ?


#pragma mark - UIView

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [self loadItem];
    
    // swipe gestures
    // http://stackoverflow.com/a/18834365/2875238
    //UISwipeGestureRecognizer *leftSwipeGesture = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(leftSwipeGesture:)];
    //UISwipeGestureRecognizer *rightSwipeGesture = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(rightSwipeGesture:)];
    //leftSwipeGesture.direction = UISwipeGestureRecognizerDirectionLeft;
    //rightSwipeGesture.direction = UISwipeGestureRecognizerDirectionRight;
    //[self.view addGestureRecognizer:leftSwipeGesture];
    //[self.view addGestureRecognizer:rightSwipeGesture];
    
    //[_webView.scrollView.panGestureRecognizer requireGestureRecognizerToFail:leftSwipeGesture];
    //[_webView.scrollView.panGestureRecognizer requireGestureRecognizerToFail:rightSwipeGesture];
    
    
    cUITextTapRecognizer = NSClassFromString(@"UITextTapRecognizer");
    
    self->tapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(webViewTap:)];
    self->tapGestureRecognizer.numberOfTapsRequired = 1;
    self->tapGestureRecognizer.numberOfTouchesRequired = 1;
    
    self->tapGestureRecognizer.delegate = self;
    
    // <UITapGestureRecognizer: 0x7b0ae650; state = Possible; view = <UIWebView 0x7a62d7e0>; target= <(action=webViewTapped:, target=<DetailViewController 0x7a6ed9f0>)>>
    
    [self.webView addGestureRecognizer:self->tapGestureRecognizer];
}

-(void)viewDidAppear:(BOOL)animated
{
    // help on iOS 6 after toolbar being dismissed from process items....
    if (!toolBarsHidden)
        [self.navigationController setToolbarHidden:NO animated:NO];
}

-(void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    
    [self.webView stopLoading];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
    });
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

-(void)dealloc
{
    [self.webView stopLoading];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
    });
}

-(void)webViewTap:(id)sender
{
    if ( _webViewTapRecognized )
    {
        [self performSelector:@selector(toggleToolBars:) withObject:nil afterDelay:0.4];
    }
}

-(void)toggleToolBars:(id)sender
{
    if ( self->_webViewTapRecognized )
    {
        BOOL show = self.navigationController.toolbarHidden;
        
        [self.navigationController setToolbarHidden:!show animated:YES];
        [self.navigationController setNavigationBarHidden:!show animated:YES];
        
		toolBarsHidden = self.navigationController.toolbarHidden;
    }
}

#pragma mark - UIGestureRecognizerDelegate

-(BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer
{
    RSLog(@"%@", otherGestureRecognizer );
    
    // UITapGestureRecognizer Ended ( but there is Failed with numberOfTapsRequired = 2; numberOfTouchesRequired = 2 )
    // UITextTapRecognizer Ended on menu dismiss
    
    if ( [otherGestureRecognizer isMemberOfClass:[UITapGestureRecognizer class]]
        && ( ((UITapGestureRecognizer*)otherGestureRecognizer).numberOfTapsRequired == 1 )
        && ( ((UITapGestureRecognizer*)otherGestureRecognizer).numberOfTouchesRequired == 1 )
        )
        _webViewTapRecognized &= YES;
    else if ( [otherGestureRecognizer isMemberOfClass:[UITapGestureRecognizer class]]
             && ( ((UITapGestureRecognizer*)otherGestureRecognizer).numberOfTapsRequired > 1 )
             && ( ((UITapGestureRecognizer*)otherGestureRecognizer).numberOfTouchesRequired > 1 )
             && otherGestureRecognizer.state != UIGestureRecognizerStateFailed
             )
        _webViewTapRecognized &= YES;
    else if ( [otherGestureRecognizer isMemberOfClass:cUITextTapRecognizer] && otherGestureRecognizer.state == UIGestureRecognizerStateFailed )
        _webViewTapRecognized &= YES;
    else if ( otherGestureRecognizer.state == UIGestureRecognizerStateFailed )
        _webViewTapRecognized &= YES;
    else
        _webViewTapRecognized &= NO;
    
    return _webViewTapRecognized;
}

-(BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer
{
    // reset chain on beginning
    _webViewTapRecognized = YES;
    
    return YES;
}

//#pragma mark - swipe gestures
//
//-(void)leftSwipeGesture:(UISwipeGestureRecognizer*)sender
//{
//    if ( sender.state == UIGestureRecognizerStateEnded)
//    {
//        OPMLOutlineXMLElement *newDetailItem = (OPMLOutlineXMLElement*)[self.detailItem nextSibling];
//        if ( newDetailItem )
//            self.detailItem = newDetailItem;
//    }
//}
//
//-(void)rightSwipeGesture:(UISwipeGestureRecognizer*)sender
//{
//    if ( sender.state == UIGestureRecognizerStateEnded)
//    {
//        OPMLOutlineXMLElement *newDetailItem = (OPMLOutlineXMLElement*)[self.detailItem previousSibling];
//        if ( newDetailItem )
//            self.detailItem = newDetailItem;
//    }
//}

#pragma mark - UIWebView

- (void)loadItem
{
    [self.webView stopLoading];
    
    // string / object empty : http://stackoverflow.com/questions/899209/how-do-i-test-if-a-string-is-empty-in-objective-c
    NSString *title = [[self.detailItem attributeForName:@"title"] stringValue];
    
    NSString *date = [[self.detailItem attributeForName:@"date"] stringValue];
    date = [date length] ? date : @"";
    
    NSString *link = [[self.detailItem attributeForName:@"link"] stringValue];
    link = [link length] ? link : @"";
    link = ![link isEqualToString:@"about:blank"] ? link : @"";
    
    NSString *author = [[self.detailItem attributeForName:@"author"] stringValue];
    author = [author length] ? author : @"";
    
    NSString *itemContent = [[self.detailItem attributeForName:@"content"] stringValue];
    itemContent = [itemContent length] ? itemContent : @"";
    
    NSString *itemSummary = [[self.detailItem attributeForName:@"summary"] stringValue];
    itemSummary = [itemSummary length] ? itemSummary : @"";
    
    // website name
    NSString *website = [[NSURL URLWithString:link] host];
    website = [website length] ? website : @"";
    
    // hLabel
    NSString *hLabel = [[self.detailItem attributeForName:@"hLabel"] stringValue];
    // page No
    NSString *pageNo = [[self.detailItem attributeForName:@"pageNo"] stringValue];
    NSString *pagesNo = [[self.detailItem attributeForName:@"pagesNo"] stringValue];
    
    
    
    linkClicked = NO;
    
    BOOL isText = [[[self.detailItem attributeForName:@"IsText"] stringValue] isEqualToString:@"YES"];
    isHelpItem = [[[self.detailItem attributeForName:@"IsHelpItem"] stringValue] isEqualToString:@"YES"];
    
    if ( isText || isHelpItem )
    {
        // load text data
        
        NSData *htmlData = [itemContent dataUsingEncoding:NSUTF8StringEncoding];
        
        [self.webView loadData:htmlData MIMEType:@"text/text" textEncodingName:@"UTF-8" baseURL:[NSURL URLWithString:@""]];
    }
    else
    {
        // load html page
        
        NSString *webViewContent = [NSString stringWithFormat:
                                    @"<!DOCTYPE HTML PUBLIC \"-//W3C//DTD HTML 4.01//EN\" \"http://www.w3.org/TR/html4/strict.dtd\">\
                                    <html>\
                                    <head>\
                                    <meta http-equiv='Content-Type' content='text/html;charset=utf-8'>\
                                    <style type=""text/css"">\
                                    img{ margin: auto; max-width: 100%%; max-height: 100%%; }\
                                    </style>\
                                    <title>%@</title>\
                                    </head>\
                                        <body>\
                                            <div style='width: 100%%; text-align: center; font-size: %@pt; color: red;font-family:Helvetica;' id=\"errorDIV\"></div>\
                                            <div style='width: 100%%; height: 100%%; font-family:%@;'>\
                                                <br/>\
                                                <table width=\"100%%\" height=\"100%%\">\
                                                    <tr>\
                                                        <td align=\"left\" valign=\"top\">\
                                                            %@ %@ / %@\
                                                        </td>\
                                                        <td align=\"right\" valign=\"top\">\
                                                            %@\
                                                        </td>\
                                                    </tr>\
                                                    <tr>\
                                                        <td align=\"center\" valign=\"top\" colspan=\"2\">\
                                                            <h2>%@</h2>\
                                                        </td>\
                                                    </tr>\
                                                    <tr>\
                                                        <td align=\"right\" valign=\"top\" colspan=\"2\">\
                                                            %@\
                                                        </td>\
                                                    </tr>\
                                                    <tr>\
                                                        <td align=\"right\" valign=\"top\" colspan=\"2\">\
                                                            %@\
                                                        </td>\
                                                    </tr>\
                                                    <tr>\
                                                        <td align=\"right\" valign=\"top\" colspan=\"2\">\
                                                            🔗<a href=\"%@\"> %@</a>\
                                                        </td>\
                                                    </tr>\
                                                    <tr>\
                                                        <td colspan=\"2\">\
                                                            <p>%@</p>\
                                                        </td>\
                                                    </tr>\
                                                </table>\
                                            </div>\
                                        </body>\
                                    </html>"
                                    , title
                                    , [[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad ? @"15" : @"30"  // error message font size
                                    // , @"Optima-Regular" - black on white
                                    , @"Verdana" // white on black
                                    // @"TrebuchetMS" // @"OriyaSangamMN" // @"Thonburi" // @"Kailasa" // @"Helvetica" // http://iosfonts.com
                                    , hLabel
                                    , pageNo
                                    , pagesNo
                                    , website
                                    , title
                                    , author
                                    , date
                                    , link
                                    , title
                                    , [itemContent length] ? itemContent : itemSummary
                                    ]
        ;
        
        {
            // note: @"rssr-app-request" specific request doesn't seem to be neccessary for loadHTMLString to work with custom NSURLProtocol
            // (in case it is needed it is neccessary to setValue forHTTPHeaderFiled for all requests to be recognized in NSURLProtocol)
            // loadHTMLString is more friendly since for NSURLRequest we need at least a file which has to be created
            // loadHTMLString does call canInitWithRequest, but doesn't call startLoading on NSURLProtocol
            
            // cache
            NSString *cachePath = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) lastObject];
            NSString *appID = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleIdentifier"];
            cachePath = [cachePath stringByAppendingPathComponent:appID];
            NSURL *baseUrl = [NSURL fileURLWithPath:cachePath];
            
            [self.webView loadHTMLString:webViewContent baseURL:baseUrl];
        }
    }
}

#pragma mark - UIWebView delegate

-(BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType
{
    if ( navigationType == UIWebViewNavigationTypeLinkClicked )
        linkClicked = YES;
    
    return YES;
}

-(void)webViewDidStartLoad:(UIWebView *)webView
{
    self->_webViewTapRecognized = NO;

    dispatch_async(dispatch_get_main_queue(), ^{
        [UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
    });

    if ( self.delegate )
        [self.delegate webViewDidStartLoad:webView];
    
}

-(void)webViewDidFinishLoad:(UIWebView *)webView
{
    RSLog(@"%@", [webView stringByEvaluatingJavaScriptFromString:@"document.title"]);
    
    // update font size continuously
    [self updateFontSize];
    
	if ( self.delegate )
		[self.delegate webViewDidFinishLoad:webView];

    // last request
	if ( !webView.isLoading )
    {
        linkClicked = NO;
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
        });

        // tooltips
        BOOL isText = [[[self.detailItem attributeForName:@"IsText"] stringValue] isEqualToString:@"YES"];
        
        if (!isText && !isHelpItem && !self.navigationController.toolbarHidden)
        {
            if (firstLaunch)
            {
                if (!tooltipsDetail_1_Completed
                    || !tooltipsDetail_2_Completed
                    || !tooltipsDetail_3_Completed
                    || !tooltipsDetail_4_Completed
                    )
                {
                    // UIView *targetView = [self.actionButton valueForKey:@"view"];
                    UIView *targetSuperview = [self.webView superview];
                    
                    // if (!self.tooltipManager)
                    {
                        self.tooltipManager = [[JDFSequentialTooltipManager alloc] initWithHostView:targetSuperview];
                        
                        if ( !tooltipsDetail_1_Completed )
                            [self.tooltipManager addTooltipWithTargetBarButtonItem:((PageViewController*)(self.parentViewController)).actionButton
                                                                          hostView:targetSuperview
                                                                       tooltipText:@"Share link to currently displayed article.\n\n(tap to dismiss this help text)"
                                                                    arrowDirection:JDFTooltipViewArrowDirectionDown
                                                                             width:200.0f
                                                               showCompletionBlock:^{
                                                                   ;
                                                               }
                                                               hideCompletionBlock:^{
                                                                   tooltipsDetail_1_Completed = YES;
                                                               }
                             ];
                        
                        if ( !tooltipsDetail_2_Completed )
                            [self.tooltipManager addTooltipWithTargetBarButtonItem:((PageViewController*)(self.parentViewController)).organizeBarButtonItem
                                                                          hostView:targetSuperview
                                                                       tooltipText:@"Bookmark currently displayed article.\n\n(tap to dismiss this help text)"
                                                                    arrowDirection:JDFTooltipViewArrowDirectionDown
                                                                             width:200.0f
                                                               showCompletionBlock:^{
                                                                   ;
                                                               }
                                                               hideCompletionBlock:^{
                                                                   tooltipsDetail_2_Completed = YES;
                                                               }
                             ];
                        
                        if ( !tooltipsDetail_3_Completed )
                            [self.tooltipManager addTooltipWithTargetBarButtonItem:((PageViewController*)(self.parentViewController)).stepperBarButtonItem
                                                                          hostView:targetSuperview
                                                                       tooltipText:@"Adjust font size.\n\n(tap to dismiss this help text)"
                                                                    arrowDirection:JDFTooltipViewArrowDirectionDown
                                                                             width:200.0f
                                                               showCompletionBlock:^{
                                                                   ;
                                                               }
                                                               hideCompletionBlock:^{
                                                                   tooltipsDetail_3_Completed = YES;
                                                               }
                             ];
                        
                        if ( !tooltipsDetail_4_Completed && ![((PageViewController*)(self.parentViewController)) isLocalContent])
                            [self.tooltipManager addTooltipWithTargetBarButtonItem:((PageViewController*)(self.parentViewController)).restoreItemBarButtonItem
                                                                          hostView:targetSuperview
                                                                       tooltipText:@"If you click a link in a article you can return back to original by tapping here.\n\n(tap to dismiss this help text)"
                                                                    arrowDirection:JDFTooltipViewArrowDirectionDown
                                                                             width:200.0f
                                                               showCompletionBlock:^{
                                                                   ;
                                                               }
                                                               hideCompletionBlock:^{
                                                                   tooltipsDetail_4_Completed = YES;
                                                               }
                             ];
                        
                        [self.tooltipManager showNextTooltip];
                    }
                }
            }
        }
    }
}

- (void)webView:(UIWebView *)webView didFailLoadWithError:(NSError *)error
{
    // if user for whatever reason cancelled navigation, do nothing;
    // https://developer.apple.com/library/mac/documentation/Cocoa/Reference/Foundation/Miscellaneous/Foundation_Constants/Reference/reference.html
    // ( here, pressing previous / next in rapid succession causes NSURLErrorCancelled to be emitted.. )
    
    if ([error.domain isEqualToString:NSURLErrorDomain] && error.code == NSURLErrorCancelled )
        return;
	
	if ([error.domain isEqualToString:NSURLErrorDomain] && error.code == NSURLErrorUnsupportedURL )
		return;
    
    RSLog(@"failed to load %@: %@, %@, %@, %@ for %@", [webView.request.URL absoluteString], error.localizedDescription, error.localizedFailureReason, error.localizedRecoveryOptions, error.localizedRecoverySuggestion, [[self.detailItem attributeForName:@"link"] stringValue] );
	
//	error.userInfo
//	{
//		NSErrorFailingURLKey = "applewebdata://bbnaut.ibillboard.com/g/ca2";
//		NSErrorFailingURLStringKey = "applewebdata://bbnaut.ibillboard.com/g/ca2";
//		NSLocalizedDescription = "unsupported URL";
//		NSUnderlyingError = "Error Domain=kCFErrorDomainCFNetwork Code=-1002 \"unsupported URL\" UserInfo=0x1e073880 {NSErrorFailingURLKey=applewebdata://bbnaut.ibillboard.com/g/ca2, NSErrorFailingURLStringKey=applewebdata://bbnaut.ibillboard.com/g/ca2, NSLocalizedDescription=unsupported URL}";
//	}

	
	// report the error inside the webview
    
    NSString* js = [NSString stringWithFormat:@"document.getElementById('errorDIV').innerHTML = '%@'"
                    , [error.localizedDescription length] > 0 ? error.localizedDescription : NSLocalizedString(@"An error occured, the page might not have been loaded completely.", nil)
                    ];
    
	
	[webView stringByEvaluatingJavaScriptFromString:js];
    
    if ( !webView.isLoading )
    {
        linkClicked = NO;
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
        });
    }
}

-(void)updateFontSize
{
    double sizeP = isHelpItem ? 200 : fontSizePercentage;
    
    // alt. style.webkitTextSizeAdjust
    NSString *jsString = [[NSString alloc] initWithFormat:@"document.getElementsByTagName('body')[0].style.fontSize= '%f%%'", sizeP];
    [self.webView stringByEvaluatingJavaScriptFromString:jsString];
	
	RSLog(@"%f", sizeP );
}

/// http://cybersam.com/ios-dev/proper-url-percent-encoding-in-ios
/// + http://stackoverflow.com/questions/3423545/objective-c-iphone-percent-encode-a-string

-(NSString*) encodeToPercentEscapeString:(NSString*)string
{
    return (NSString *)
    CFBridgingRelease(CFURLCreateStringByAddingPercentEscapes(NULL,
                                                              (CFStringRef) string,
                                                              NULL,
                                                              (CFStringRef) @":/?#[]@!$ &'()*+,;=\"<>%{}|\\^~`",
                                                              kCFStringEncodingUTF8));
}

// Decode a percent escape encoded string.
-(NSString*)decodeFromPercentEscapeString:(NSString*)string
{
    return (NSString *)
    CFBridgingRelease(CFURLCreateStringByReplacingPercentEscapesUsingEncoding(NULL,
                                                                              (CFStringRef) string,
                                                                              CFSTR(""),
                                                                              kCFStringEncodingUTF8));
}

@end
