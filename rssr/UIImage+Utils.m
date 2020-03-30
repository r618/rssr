//
//  UIImage+Utils.m
//  rssr
//
//  Created by Martin Cvengroš on 28/12/2016.
//
//

#import "UIImage+Utils.h"

@implementation UIImage (Utils)

+(UIImage*)imageScaledToSize:(UIImage*)aImage size:(CGSize)size;
{
    UIGraphicsBeginImageContext(size);
    [aImage drawInRect:CGRectMake(0, 0, size.width, size.height)];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

//- (UIImage*)tintAndScaleImage:(UIImage *)aImage color:(UIColor*)aColor size:(CGSize)size
//{
//    UIGraphicsBeginImageContext(size);
//
//    CGRect imageRect = CGRectMake(0, 0, size.width, size.height);
//
//    CGContextRef context = UIGraphicsGetCurrentContext();
//
//    // [UIColor colorWithRed:0.5 green:0.5 blue:0 alpha:1].CGColor
//    CGFloat r, g, b, a;
//    [aColor getRed:&r green:&g blue:&b alpha:&a];
//
//    UIColor *color = [UIColor colorWithRed:r green:g blue:b alpha:1.0];
//
//    CGContextSetFillColor(context, CGColorGetComponents(color.CGColor));
//
//    CGContextFillRect(context, imageRect); // draw base
//
//
//
//    [aImage drawInRect:imageRect blendMode:kCGBlendModeOverlay alpha:1.0]; // draw image
//
//    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
//
//    UIGraphicsEndImageContext();
//
//    return image;
//}

//- (UIImage *)convertImageToGrayScaleAndScale:(UIImage *)aImage size:(CGSize)size
//{
//    if (!aImage)
//        return nil;
//
//    // Create image rectangle with new image width/height
//    CGRect imageRect = CGRectMake(0, 0, size.width, size.height);
//
//    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceGray();
//
//    // Create bitmap content with current image size and grayscale colorspace
//    CGContextRef context = CGBitmapContextCreate(nil, size.width, size.height, 8, 0, colorSpace, kCGImageAlphaNone);
//
//    // Draw image into current context, with specified rectangle
//    // using previously defined context (with grayscale colorspace)
//    CGContextDrawImage(context, imageRect, [aImage CGImage]);
//
//    // Create bitmap image info from pixel data in current context
//    CGImageRef imageRef = CGBitmapContextCreateImage(context);
//
//    // Create a new UIImage object
//    UIImage *newImage = [UIImage imageWithCGImage:imageRef];
//
//    // Release colorspace, context and bitmap information
//    CGColorSpaceRelease(colorSpace);
//    CGContextRelease(context);
//    CFRelease(imageRef);
//
//    // Return the new grayscale image
//    return newImage;
//}

@end
