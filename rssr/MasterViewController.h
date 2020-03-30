//
//  MasterViewController.h
//  rssr
//
//  Created by Rupert Pole on 24/10/15.
//
//

#import <UIKit/UIKit.h>
#import "OPMLOutline.h"
#import "OPMLOutlineXMLElement.h"
#import "JDFTooltips.h"

typedef enum {
    DisplayedDataType_Today
    , DisplayedDataType_Unread
    , DisplayedDataType_Bookmarks
    , DisplayedDataType_Subscriptions
    // , DisplayedDataType_SubscriptionChooser
	, DisplayedDataType_SearchResults
    , DisplayedDataType_Text
    
} DisplayedDataType;


@class DetailViewController;

@interface MasterViewController : UITableViewController<UIAlertViewDelegate>

/// read only view for subs selection from preselected set
@property (nonatomic) DisplayedDataType displayedDataType;

/// XML Node / Element which is the root for displaying its children in this view, is the node from main outline document
@property (strong, nonatomic) OPMLOutlineXMLElement *viewOutline;

/// for browsing default feeds for selection - this is the outline under which the selected feed will be added in the main document
// TODO: remove
@property (strong, nonatomic) OPMLOutlineXMLElement *mainViewOutline;

@property (weak, nonatomic) IBOutlet UIBarButtonItem *uiBarButtonItem;

@property (nonatomic, strong) JDFSequentialTooltipManager *tooltipManager;

@end
