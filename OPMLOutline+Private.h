//
//  OPMLOutline+Private.h
//  OPML
//
//  Created by Ivan Vučica on 05.01.2012..
//  Copyright (c) 2012 Ivan Vučica. All rights reserved.
//

@interface OPMLOutline ()

////////////////
// Class methods
////////////////
+(void)addDocumentAttributeGetter:(SEL)getterSelector setter:(SEL)setterSelector;

//////////
// Methods
//////////

-(BOOL)isXMLValidOPMLWithError:(NSError**)error;

/////////////
// Properties
/////////////

//@property (retain) NSXMLNode *opmlRoot;
-(DDXMLNode*)opmlRoot;
-(void)setOpmlRoot:(DDXMLNode*)opmlRoot;
//@property (retain) NSMutableDictionary *includedOutlines;
-(NSMutableDictionary*)includedOutlines;
-(void)setIncludedOutlines:(NSMutableDictionary*)includedDocuments;

/////////////////////
// Dynamic properties
/////////////////////

@end

#define OPMLOUTLINE_DOCUMENT_ATTRIBUTE_STUB(getterName, setterName) -(NSString*)getterName { return nil; } -(void)setterName:(NSString*)aString { }
