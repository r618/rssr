//
//  OPMLOutline.h
//  OPML
//
//  Created by Ivan Vučica on 05.01.2012..
//  Copyright (c) 2012 Ivan Vučica. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "KissXML/DDXML.h"

extern NSString * kOPMLOutlineErrorDomain;
#define kOPMLOutlineErrorXMLRootNotFound 1
#define kOPMLOutlineErrorRequiredXMLNotFound 2

extern NSString * kOPMLOutlineInclusionLoadingBeganNotification;
extern NSString * kOPMLOutlineInclusionLoadingEndedNotification;

@class OPMLOutlineXMLElement;

@interface OPMLOutline : DDXMLDocument
{
    DDXMLDocument * _xmlDocument;
    DDXMLNode * _opmlRoot;
    
    NSMutableDictionary * _includedOutlines;
    NSUndoManager *_undoManager;
}

-(id)initWithBlankOutline;
-(id)initWithOPMLData:(NSData*)data error:(NSError**)error;

//////////
// Methods
//////////
-(OPMLOutline*)includedOutlineForURL:(NSURL*)url;
- (void)applyCurrentDateOfModification;

- (NSString*)documentAttributeValueForKey:(NSString*)nodeName;
- (void)setDocumentAttributeValue:(NSString*)aString forKey:(NSString*)nodeName;

- (OPMLOutlineXMLElement*)insertNewChildNodeOf:(OPMLOutlineXMLElement*)parent withText:(NSString*)text;
- (OPMLOutlineXMLElement*)insertNewSiblingNodeOf:(OPMLOutlineXMLElement*)sibling withText:(NSString*)text inFront:(BOOL)atFront;

/////////////
// Properties
/////////////

/////////////////////
// Dynamic properties
/////////////////////

//@property (retain) NSString * title;
//@dynamic instead of @synthesize
-(NSString*)title;
-(void)setTitle:(NSString*)aString;

//@property (retain) NSString * ownerName;
//@dynamic instead of @synthesize
-(NSString*)ownerName;
-(void)setOwnerName:(NSString*)aString;

//@property (retain) NSString * ownerEmail;
//@dynamic instead of @synthesize
-(NSString*)ownerEmail;
-(void)setOwnerEmail:(NSString*)aString;

//@property (retain) NSString * ownerId;
//@dynamic instead of @synthesize
-(NSString*)ownerId;
-(void)setOwnerId:(NSString*)aString;

//@property (retain) NSString * dateCreated;
//@dynamic instead of @synthesize
-(NSString*)dateCreated;
-(void)setDateCreated:(NSString*)aString;

//@property (retain) NSString * dateModified;
//@dynamic instead of @synthesize
-(NSString*)dateModified;
-(void)setDateModified:(NSString*)aString;

//@property (retain, readonly) NSXMLNode *headNode;
//@dynamic instead of @synthesize
-(DDXMLElement*)headNode;
//@property (retain, readonly) NSXMLNode *bodyNode;
//@dynamic instead of @synthesize
-(DDXMLElement*)bodyNode;

@end
