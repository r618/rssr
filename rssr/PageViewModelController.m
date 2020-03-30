//
//  PageViewModelController.m
//  rssr
//
//  Created by Rupert Pole on 03/12/15.
//
//

#import "PageViewModelController.h"
#import "DetailViewController.h"
#import "PageViewController.h"

extern NSString *searchedString;
extern NSUInteger searchedScope;
extern BOOL firstLaunch;

@implementation PageViewModelController
{
	// items for DetailViewControllers
	OPMLOutlineXMLElement* outline;

	NSMutableArray *viewControllers;
}

+ (PageViewModelController*)sharedInstance
{
    static dispatch_once_t once;
    static id sharedInstance;
    
    dispatch_once(&once, ^{
        
        sharedInstance = [[self alloc] init];
    });
    
    return sharedInstance;
}

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        // Create [empty] initial data model.
		OPMLOutlineXMLElement *emptyOutline = [[OPMLOutlineXMLElement alloc] initWithName:@"outline"];
        OPMLOutlineXMLElement *item = [[OPMLOutlineXMLElement alloc] initWithName:@"item"];
        
        NSString *welcomeText = nil;
        if ( firstLaunch )
            welcomeText = @"Start here by adding subscriptions\n\n   Note: existing subscriptions can be imported via iTunes File Sharing ( go to: Settings -> Import ),\nor by opening OPML/XML file containing outlines/subscriptions from external application, such as Mail.";
        else
            welcomeText = @"Welcome";
        
        NSArray * attributes = @[
                                 [DDXMLNode attributeWithName:@"title" stringValue:@""]
                                 , [DDXMLNode attributeWithName:@"identifier" stringValue:@""]
                                 , [DDXMLNode attributeWithName:@"link" stringValue:@"about:blank"]
                                 , [DDXMLNode attributeWithName:@"date" stringValue:@""]
                                 , [DDXMLNode attributeWithName:@"summary" stringValue:@""]
                                 , [DDXMLNode attributeWithName:@"content" stringValue:[NSString stringWithFormat:@"\n\n< %@", welcomeText]]
                                 , [DDXMLNode attributeWithName:@"IsText" stringValue:@"YES"]
                                 , [DDXMLNode attributeWithName:@"IsHelpItem" stringValue:@"YES"]
                                 ];
        [item setAttributes:attributes];
		
        [emptyOutline addChild:item];
		
		[self setOutline:emptyOutline];
    }
    return self;
}

-(void)setOutline:(OPMLOutlineXMLElement *)outlineWithItems
{
    [self clearOutline];
    
    // clear the bitch it can be updated independently from master and here the state is lost
	self->outline = [outlineWithItems copy];
	
	self->viewControllers = [[NSMutableArray alloc] initWithCapacity:self->outline.childCount];
	for (int i = 0; i < [self->outline childCount]; ++i)
	{
		[self->viewControllers addObject:[NSNumber numberWithInt:i]];
	}
}

-(void)clearOutline
{
    self->outline = nil;
    
    for (__strong DetailViewController *vc in self->viewControllers)
    {
        vc = nil;
    }
    
    self->viewControllers = nil;
}

- (DetailViewController *)viewControllerAtIndex:(NSUInteger)index storyboard:(UIStoryboard *)storyboard
{
    // Return the data view controller for the given index.
    if ((self->outline.childCount == 0) || (index >= self->outline.childCount ))
    {
        return nil;
    }
	
	if ( ![[self->viewControllers objectAtIndex:index] isKindOfClass:[UIViewController class] ] )
	{
		// Create a new view controller and pass suitable data.
		DetailViewController *dataViewController = [storyboard instantiateViewControllerWithIdentifier:@"DetailViewController"];
		
		dataViewController.delegate = self.pageViewControllerDelegate;
        
        OPMLOutlineXMLElement *item = (OPMLOutlineXMLElement*)[self->outline.children objectAtIndex:index];
        
        // add section name attribute in detail
        NSString *hLabel = @"";
        
        if ( self.pageViewControllerDelegate.displayedDataType == DisplayedDataType_Today )
            hLabel = @"Today";
        else if ( self.pageViewControllerDelegate.displayedDataType == DisplayedDataType_Unread )
            hLabel = @"Unread";
        else if ( self.pageViewControllerDelegate.displayedDataType == DisplayedDataType_SearchResults )
            hLabel = [NSString stringWithFormat:@"%@ search for '%@'", (searchedScope == 0 ? @"Headlines" : @"Fulltext"), searchedString];
                      
        [item addAttribute:[DDXMLNode attributeWithName:@"hLabel" stringValue:hLabel]];
        
        // add page, page count attributes for N / M "footer" in detail.
        [item addAttribute:[DDXMLNode attributeWithName:@"pageNo" stringValue:[NSString stringWithFormat:@"%lu", (unsigned long)index + 1]]];
        [item addAttribute:[DDXMLNode attributeWithName:@"pagesNo" stringValue:[NSString stringWithFormat:@"%lu", (unsigned long)self->outline.childCount]]];

        [dataViewController setDetailItem:item];
		
		[self->viewControllers replaceObjectAtIndex:index withObject:dataViewController];
	}
	
	return [self->viewControllers objectAtIndex:index];
}

- (NSUInteger)indexOfViewController:(DetailViewController *)viewController
{
    // Return the index of the given data view controller.
    // For simplicity, this implementation uses a static array of model objects and the view controller stores the model object; you can therefore use the model object to identify the index.
    return [self->outline.children indexOfObject:viewController.detailItem];
}

#pragma mark - Page View Controller Data Source

- (UIViewController *)pageViewController:(UIPageViewController *)pageViewController viewControllerBeforeViewController:(UIViewController *)viewController
{
    NSUInteger index = [self indexOfViewController:(DetailViewController *)viewController];
    if ((index == 0) || (index == NSNotFound)) {
        return nil;
    }
    
    index--;
    
    return [self viewControllerAtIndex:index storyboard:viewController.storyboard];
}

- (UIViewController *)pageViewController:(UIPageViewController *)pageViewController viewControllerAfterViewController:(UIViewController *)viewController
{
    NSUInteger index = [self indexOfViewController:(DetailViewController *)viewController];
    if (index == NSNotFound) {
        return nil;
    }
    
    index++;
    if (index == self->outline.childCount) {
        return nil;
    }
    
    return [self viewControllerAtIndex:index storyboard:viewController.storyboard];
}

@end
