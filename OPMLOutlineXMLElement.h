//
//  OPMLXMLElement.h
//  OPML
//
//  Created by Ivan Vučica on 16.01.2012..
//  Copyright (c) 2012 Ivan Vučica. All rights reserved.
//

#import "KissXML/DDXML.h"

enum OPMLOutlineXMLElementType
{
    OPMLOutlineXMLElementTypeDefault = 0,
    OPMLOutlineXMLElementTypeInclusion = 1,
    OPMLOutlineXMLElementTypeLink = 2,
    OPMLOutlineXMLElementTypeRSS = 3
};
typedef enum OPMLOutlineXMLElementType OPMLOutlineXMLElementType;

@class OPMLOutline;
@interface OPMLOutlineXMLElement : DDXMLElement
{
    OPMLOutline * _childOutline;
}

//@property (retain) OPMLOutline * childOutline;
-(OPMLOutline*)childOutline;
-(void)setChildOutline:(OPMLOutline*)childOutline;

-(void)setElementType:(OPMLOutlineXMLElementType)type;

// methods
-(void)removeFromSupernode;
@end
