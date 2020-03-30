//
//  DetailViewController.h
//  rssr
//
//  Created by Rupert Pole on 24/10/15.
//
//

#import <UIKit/UIKit.h>
#import "OPMLOutlineXMLElement.h"
#import "JDFTooltips.h"

@interface DetailViewController : UIViewController<UIWebViewDelegate,UIGestureRecognizerDelegate>

@property (strong, nonatomic) IBOutlet UIWebView *webView;

@property (strong, nonatomic) OPMLOutlineXMLElement *detailItem;

-(void)updateFontSize;

@property(strong, nonatomic) id<UIWebViewDelegate> delegate;

// re/loads current item
- (void)loadItem;

@property (nonatomic, strong) JDFSequentialTooltipManager *tooltipManager;

@end

