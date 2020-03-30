//
//  OPMLOutline.m
//  OPML
//
//  Created by Ivan Vučica on 05.01.2012..
//  Copyright (c) 2012 Ivan Vučica. All rights reserved.
//

#import "OPMLOutline.h"
#import "OPMLOutline+Private.h"
#import "OPMLOutlineXMLElement.h"
#import <objc/objc.h>
#import <objc/runtime.h>

NSString * kOPMLOutlineErrorDomain =@"OPMLOutlineErrorDomain";

NSString * kOPMLOutlineInclusionLoadingBeganNotification =@"OPMLOutlineInclusionLoadingBeganNotification";
NSString * kOPMLOutlineInclusionLoadingEndedNotification =@"OPMLOutlineInclusionLoadingEndedNotification";

@implementation OPMLOutline

// MARK: -
// MARK: Class methods
+(Class)replacementClassForClass:(Class)cls
{
    if(cls == [DDXMLElement class])
    {
        return [OPMLOutlineXMLElement class];
    }
    if(cls == [DDXMLDocument class])
    {
        return [OPMLOutline class];
    }
    return cls;
}

+(void)initialize
{
    if(self == [OPMLOutline class])
    {
        [self addDocumentAttributeGetter:@selector(title) setter:@selector(setTitle:)];
        [self addDocumentAttributeGetter:@selector(ownerName) setter:@selector(setOwnerName:)];
        [self addDocumentAttributeGetter:@selector(ownerEmail) setter:@selector(setOwnerEmail:)];
        [self addDocumentAttributeGetter:@selector(ownerId) setter:@selector(setOwnerId:)];
        [self addDocumentAttributeGetter:@selector(dateCreated) setter:@selector(setDateCreated:)];
        [self addDocumentAttributeGetter:@selector(dateModified) setter:@selector(setDateModified:)];
    }
}

+(void)addDocumentAttributeGetter:(SEL)getterSelector setter:(SEL)setterSelector
{
    Method getterImpl = class_getInstanceMethod(self, @selector(_documentAttributeImpl));
    Method setterImpl = class_getInstanceMethod(self, @selector(_setDocumentAttributeImpl:));
    
    Method getterStub = class_getInstanceMethod(self, getterSelector);
    Method setterStub = class_getInstanceMethod(self, setterSelector);
    
    if(!getterStub)
        class_addMethod(self, getterSelector, method_getImplementation(getterImpl) , "@@:"); 
        // returns object, receives self, receives selector 
    else
        method_setImplementation(getterStub, method_getImplementation(getterImpl));
    
    if(!setterStub)
        class_addMethod(self, setterSelector, method_getImplementation(setterImpl) , "v@:@"); 
        // returns void, receives self, receives selector, receives string object
    else
        method_setImplementation(setterStub, method_getImplementation(setterImpl));
}

// MARK: -
// MARK: Initialization, deinitialization and saving

-(id)initWithBlankOutline
{

    NSLocale *enUS = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US"];
    NSDateFormatter * dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setLocale:enUS];
    [dateFormatter setDateFormat:@"EEE, dd MMM yyyy HH:mm:ss z"];
    [dateFormatter setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];

    NSDate * now = [NSDate date];
    NSString * defaultContent = [NSString stringWithFormat:
                                 @""
                                 "<?xml version=\"1.0\" encoding=\"utf-8\"?>"
                                 "<opml version=\"1.1\">"
                                 "  <head>"
                                 "    <title>rssr outline</title>"
                                 "    <dateCreated>%@</dateCreated>"
                                 "    <dateModified>%@</dateModified>"
                                 "  </head>"
                                 "  <body></body>"
                                 "</opml>"
                                 "",
                                 
                                 [dateFormatter stringFromDate:now],
                                 [dateFormatter stringFromDate:now],
                                 
                                 nil];
    
    self = [super initWithXMLString:defaultContent options:0 error:NULL];
    if(!self)
        return nil;

    NSArray *opmlNodes = [self nodesForXPath:@"./opml" error:NULL];

    _xmlDocument = self;
    [self setOpmlRoot:[opmlNodes objectAtIndex:0]];
    [self setIncludedOutlines:[NSMutableDictionary dictionary]];
    
    return self;
}

-(id)initWithOPMLData:(NSData*)data error:(NSError**)error
{
    OPMLOutline * doc;
    doc = [super initWithData:data options:0 error:error];
    self = doc;
    if(!self)
        return nil;
    
    NSArray *opmlNodes = [doc nodesForXPath:@"./opml" error:NULL];
    if([opmlNodes count] == 0)
    {
        NSDictionary * desc;
        desc = [NSDictionary dictionaryWithObjectsAndKeys:
                
                NSLocalizedString(@"XML root node 'opml' not found.", @"Text for error while loading an OPML file."), 
                NSLocalizedFailureReasonErrorKey,
                
                NSLocalizedString(@"Check that you are opening a valid OPML file.", @"Recovery suggestion for an error while loading an OPML file."),
                NSLocalizedRecoverySuggestionErrorKey,
                
                nil];
        *error = [NSError errorWithDomain:kOPMLOutlineErrorDomain 
                                     code:kOPMLOutlineErrorXMLRootNotFound 
                                 userInfo:desc];
        return nil;
    }
    
    // If there is more than one root <opml> node, too bad.
    // That's not valid XML nor OPML, but we'll ignore that and hope 
    // for the best.
    
    _xmlDocument = self;
    [self setOpmlRoot:[opmlNodes objectAtIndex:0]];
    [self setIncludedOutlines:[NSMutableDictionary dictionary]];

#if GNUSTEP
    [self _debug_printOutlineElementClasses];
#endif

    if(![self isXMLValidOPMLWithError:error])
    {
        return nil;
    }
    
    return self;
}

- (void)dealloc
{
    [self setIncludedOutlines:nil];
    [self setOpmlRoot:nil];
}

// MARK: -
// MARK: Methods

#if GNUSTEP
-(void)_debug_printOutlineElementClasses
{
    NSLog(@"debug");
    //for(NSXMLElement * element in [[self bodyNode] nodesForXPath:@"./outline" error:NULL])
    NSEnumerator *e = [[[self bodyNode] nodesForXPath:@"./outline" error:NULL] objectEnumerator];
    for(NSXMLElement * element = [e nextObject]; element; element = [e nextObject])
    {
        NSLog(@"element class: %@", [element class]);
    }
}
#endif

-(BOOL)isXMLValidOPMLWithError:(NSError**)error
{
    // Checks whether the XML structure is a valid OPML.
    // does not have to have head - YT exports its subs without it and we dont use it, so skip it
    
    // TODO:
    // - check that there is only one head node
    
    /*
    if(![self headNode])
    {
        NSDictionary * desc;
        desc = [NSDictionary dictionaryWithObjectsAndKeys:
                
                NSLocalizedString(@"'head' node not found.", @"Text for error while validating XML structure of an OPML document."), 
                NSLocalizedFailureReasonErrorKey,
                
                NSLocalizedString(@"Check that this is a valid OPML document.", @"Recovery suggestion for an error while validating XML structure of an OPML document."),
                NSLocalizedRecoverySuggestionErrorKey,
                
                nil];
        *error = [NSError errorWithDomain:kOPMLOutlineErrorDomain 
                                     code:kOPMLOutlineErrorRequiredXMLNotFound 
                                 userInfo:desc];
        return NO;
    }
    */
    
    /////////////////////
    
    if(![self bodyNode])
    {
        NSDictionary * desc;
        desc = [NSDictionary dictionaryWithObjectsAndKeys:
                
                NSLocalizedString(@"'body' node not found.", @"Text for error while validating XML structure of an OPML document."), 
                NSLocalizedFailureReasonErrorKey,
                
                NSLocalizedString(@"Check that this is a valid OPML document.", @"Recovery suggestion for an error while validating XML structure of an OPML document."),
                NSLocalizedRecoverySuggestionErrorKey,
                
                nil];
        *error = [NSError errorWithDomain:kOPMLOutlineErrorDomain 
                                     code:kOPMLOutlineErrorRequiredXMLNotFound 
                                 userInfo:desc];
        return NO;
    }
    
    NSArray *bodyNodes = [_opmlRoot nodesForXPath:@"./body" error:NULL];
    if([bodyNodes count] > 1)
    {
        NSDictionary * desc;
        desc = [NSDictionary dictionaryWithObjectsAndKeys:
                
                NSLocalizedString(@"The document contains more that 1 'body' node.", nil),
                NSLocalizedFailureReasonErrorKey,
                
                NSLocalizedString(@"Check that this is a valid OPML document.", nil),
                NSLocalizedRecoverySuggestionErrorKey,
                
                nil];
        *error = [NSError errorWithDomain:kOPMLOutlineErrorDomain
                                     code:kOPMLOutlineErrorRequiredXMLNotFound
                                 userInfo:desc];
        return NO;
    }

    ////////////////////
    
    // Reached the end? All ok.
    return YES;
}

- (OPMLOutline*)includedOutlineForURL:(NSURL *)url
{
    if(![_includedOutlines valueForKey:[url absoluteString]])
    {
        [[NSNotificationCenter defaultCenter] postNotificationName:kOPMLOutlineInclusionLoadingBeganNotification object:self userInfo:nil];
        NSData * data = [NSData dataWithContentsOfURL:url];
        [[NSNotificationCenter defaultCenter] postNotificationName:kOPMLOutlineInclusionLoadingEndedNotification object:self userInfo:nil];
        
        OPMLOutline * o = [[OPMLOutline alloc] initWithOPMLData:data error:NULL];
        if(o)
        {
            [_includedOutlines setValue:o forKey:[url absoluteString]];
        }
    }
    return [_includedOutlines valueForKey:[url absoluteString]];
        
}

- (void)applyCurrentDateOfModification
{
    NSLocale *enUS = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US"];
    NSDateFormatter * dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setLocale:enUS];
    [dateFormatter setDateFormat:@"EEE, dd MMM yyyy HH:mm:ss z"];
    [dateFormatter setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
    
    NSDate * now = [NSDate date];

    [self setDateModified:[dateFormatter stringFromDate:now]];
}

- (OPMLOutlineXMLElement *)insertNewChildNodeOf:(OPMLOutlineXMLElement *)parent withText:(NSString*)text
{
    // title and text are the same from observation of export from other apps ?
    
    NSArray * attributes = [NSArray arrayWithObjects:
                            [DDXMLNode attributeWithName:@"text" stringValue:text]
                            , [DDXMLNode attributeWithName:@"title" stringValue:text]
                            , nil
                            ];
    
    OPMLOutlineXMLElement * newNode = [[OPMLOutlineXMLElement alloc] initWithName:@"outline"];
    [newNode setAttributes:attributes];
    
    if(parent)
        [parent addChild:newNode];
    else
        [[self bodyNode] addChild:newNode];
    return newNode;
}
- (OPMLOutlineXMLElement *)insertNewSiblingNodeOf:(OPMLOutlineXMLElement *)sibling withText:(NSString*)text inFront:(BOOL)atFront
{
    // title and text are the same from observation of export from other apps ?
    
    NSArray * attributes = [NSArray arrayWithObjects:
                            [DDXMLNode attributeWithName:@"text" stringValue:text]
                            , [DDXMLNode attributeWithName:@"title" stringValue:text]
                            , nil
                            ];
    
    OPMLOutlineXMLElement * newNode = [[OPMLOutlineXMLElement alloc] initWithName:@"outline"];
    [newNode setAttributes:attributes];
    
    OPMLOutlineXMLElement * parent = (OPMLOutlineXMLElement*)[sibling parent];
    NSInteger index = [[parent children] indexOfObject:sibling];
    
    if ( atFront )
        [parent insertChild:newNode atIndex:index];
    else
        [parent insertChild:newNode atIndex:index+1];
    return newNode;
}

// MARK: -
// MARK: Properties

- (DDXMLNode*)opmlRoot
{
    return _opmlRoot;
}
- (void)setOpmlRoot:(DDXMLNode *)opmlRoot
{
    _opmlRoot = opmlRoot;
}
- (NSMutableDictionary*)includedOutlines
{
    return _includedOutlines;
}
- (void)setIncludedOutlines:(NSMutableDictionary *)includedOutlines
{
    _includedOutlines = includedOutlines;
}

// MARK: -
// MARK: Dynamic properties

- (DDXMLElement*)headNode
{
    NSArray * headNodes;
    
    headNodes = [_opmlRoot nodesForXPath:@"./head" error:NULL];
    if([headNodes count] == 0)
    {
        return nil;
    }
    if(![[headNodes objectAtIndex:0] isKindOfClass:[DDXMLElement class]])
    {
        return nil;
    }
    return [headNodes objectAtIndex:0];
}
- (DDXMLElement*)bodyNode
{
    NSArray * bodyNodes;
    
    bodyNodes = [_opmlRoot nodesForXPath:@"./body" error:NULL];
    if([bodyNodes count] == 0)
    {
        return nil;
    }
    if(![[bodyNodes objectAtIndex:0] isKindOfClass:[DDXMLElement class]])
    {
        return nil;
    }
    return [bodyNodes objectAtIndex:0];
}

- (NSString*) documentAttributeValueForKey:(NSString*)nodeName
{
    NSArray * attributeNodes = [[self headNode] nodesForXPath:[NSString stringWithFormat:@"./%@", nodeName] error:NULL];
    NSString * attribute = [attributeNodes count] ? [[attributeNodes objectAtIndex:0] stringValue] : @"";
    return attribute ? attribute : @"";
}
- (void) setDocumentAttributeValue:(NSString*)aString forKey:(NSString*)nodeName
{
    NSArray * attributeNodes = [[self headNode] nodesForXPath:[NSString stringWithFormat:@"./%@", nodeName] error:NULL];
    if([attributeNodes count] == 0)
    {
        [[self headNode] addChild:[DDXMLElement elementWithName:nodeName stringValue:aString]];
    }
    else
    {
        [[attributeNodes objectAtIndex:0] setStringValue:aString];
    }
}


- (NSString*)_documentAttributeImpl
{
    NSString * attributeName = NSStringFromSelector(_cmd);
    return [self documentAttributeValueForKey:attributeName];
}
- (void)_setDocumentAttributeImpl:(NSString*)aString
{
    NSString * attributeName = NSStringFromSelector(_cmd);
    attributeName = [attributeName substringToIndex:[attributeName length]-1]; // strip ":"
    attributeName = [attributeName substringFromIndex:3]; // strip "set"
    attributeName = [NSString stringWithFormat:@"%c%@", tolower([attributeName characterAtIndex:0]), [attributeName substringFromIndex:1]]; // make first character lowercase
        
    [self setDocumentAttributeValue:aString forKey:attributeName];
}

// stub implementations 
OPMLOUTLINE_DOCUMENT_ATTRIBUTE_STUB(title, setTitle);
OPMLOUTLINE_DOCUMENT_ATTRIBUTE_STUB(ownerName, setOwnerName);
OPMLOUTLINE_DOCUMENT_ATTRIBUTE_STUB(ownerEmail, setOwnerEmail);
OPMLOUTLINE_DOCUMENT_ATTRIBUTE_STUB(ownerId, setOwnerId);
OPMLOUTLINE_DOCUMENT_ATTRIBUTE_STUB(dateCreated, setDateCreated);
OPMLOUTLINE_DOCUMENT_ATTRIBUTE_STUB(dateModified, setDateModified);

@end
