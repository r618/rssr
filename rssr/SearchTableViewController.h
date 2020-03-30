//
//  SearchTableViewController.h
//  rssr
//
//  Created by Martin Cvengroš on 25/12/2016.
//
//

#import <UIKit/UIKit.h>

@interface SearchTableViewController : UITableViewController <UISearchBarDelegate>
@property (strong, nonatomic) IBOutlet UISearchBar *searchBar;

@end
