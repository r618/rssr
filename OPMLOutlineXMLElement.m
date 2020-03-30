//
//  OPMLXMLElement.m
//  OPML
//
//  Created by Ivan Vučica on 16.01.2012..
//  Copyright (c) 2012 Ivan Vučica. All rights reserved.
//

#import "OPMLOutlineXMLElement.h"

@implementation OPMLOutlineXMLElement

- (OPMLOutline*)childOutline
{
    return _childOutline;
}
- (void)setChildOutline:(OPMLOutline *)childOutline
{
    _childOutline = childOutline;
}
-(void)setElementType:(OPMLOutlineXMLElementType)type
{
    OPMLOutlineXMLElement * element = self;
    
    DDXMLNode * elementTypeAttribute = [element attributeForName:@"type"];
    
    
    if(elementTypeAttribute && type == OPMLOutlineXMLElementTypeDefault)
    {
        // 0 == "default" doesn't need a "type" attribute
        [element removeAttributeForName:@"type"];
        elementTypeAttribute = nil;
    }
    
    
    if(!elementTypeAttribute && type != OPMLOutlineXMLElementTypeDefault) 
    {
        // everything except for 0 == "default" needs to have a "type" attribute
        // so if it doesn't exist, create it
        [element addAttribute:[DDXMLNode attributeWithName:@"type" stringValue:@""]];
        elementTypeAttribute = [element attributeForName:@"type"];
        
    }
    
    switch(type)
    {
        case OPMLOutlineXMLElementTypeDefault:
            // already deleted type element
            break;
        case OPMLOutlineXMLElementTypeInclusion:
            [elementTypeAttribute setStringValue:@"include"];
            if(![element attributeForName:@"url"])
            {
                [element addAttribute:[DDXMLNode attributeWithName:@"url" stringValue:@"about:blank"]];
            }
            break;
        case OPMLOutlineXMLElementTypeLink:
            [elementTypeAttribute setStringValue:@"link"];
            if(![element attributeForName:@"url"])
            {
                [element addAttribute:[DDXMLNode attributeWithName:@"url" stringValue:@"about:blank"]];
            }
            break;
        case OPMLOutlineXMLElementTypeRSS:
            [elementTypeAttribute setStringValue:@"rss"];
            if(![element attributeForName:@"xmlUrl"])
            {
                [element addAttribute:[DDXMLNode attributeWithName:@"xmlUrl" stringValue:@"http://example.com/rss.xml"]];
            }
            
            break;
    }
    
}

- (void)removeFromSupernode
{
    [((OPMLOutlineXMLElement*)[self parent]) removeChildAtIndex:[[[self parent] children] indexOfObject:self]]; 
}


@end
