#import "HoneywellPrinterBridge.h"

#import <ExternalAccessory/ExternalAccessory.h>
#import <PDFKit/PDFKit.h>
#import <printersdk/ITCExtraSettings.h>
#import <printersdk/ITCLinePrinter.h>
#import <printersdk/ITCLinePrinterException.h>

static NSString *const HoneywellPrinterErrorDomain = @"com.tatweer.honeywellPrinter";

@implementation HoneywellPrinterBridge

+ (NSArray<NSDictionary<NSString *,NSString *> *> *)availablePrinters {
  NSMutableArray<NSDictionary<NSString *, NSString *> *> *printers = [NSMutableArray array];
  for (EAAccessory *accessory in EAAccessoryManager.sharedAccessoryManager.connectedAccessories) {
    NSString *name = accessory.name.length > 0 ? accessory.name : accessory.modelNumber;
    [printers addObject:@{
      @"name" : name ?: @"Honeywell printer",
      @"address" : [NSString stringWithFormat:@"%ld", (long)accessory.connectionID],
      @"printerId" : [self profileForName:accessory.modelNumber ?: name],
    }];
  }
  return printers;
}

+ (NSDictionary<NSString *, NSNumber *> *)printPdf:(NSData *)pdfData
                                            address:(NSString *)address
                                          printerId:(NSString *)printerId
                                           testOnly:(BOOL)testOnly
                                              error:(NSError **)error {
  ITCLinePrinter *printer = nil;
  @try {
    EAAccessory *accessory = [self accessoryWithConnectionId:address];
    if (accessory == nil) {
      if (error != NULL) {
        *error = [NSError errorWithDomain:HoneywellPrinterErrorDomain
                                      code:1
                                  userInfo:@{NSLocalizedDescriptionKey : @"لم يتم العثور على طابعة Honeywell متصلة."}];
      }
      return nil;
    }

    NSString *profilePath = [NSBundle.mainBundle pathForResource:@"printer_profiles" ofType:@"JSON"];
    if (profilePath == nil) {
      if (error != NULL) {
        *error = [NSError errorWithDomain:HoneywellPrinterErrorDomain
                                      code:2
                                  userInfo:@{NSLocalizedDescriptionKey : @"ملف إعدادات طابعة Honeywell غير موجود."}];
      }
      return nil;
    }

    ITCExtraSettings *settings = [ITCExtraSettings retrieveExtraSettings];
    settings.accessory = accessory;
    settings.protocolString = @"com.honeywell.print";
    printer = [[ITCLinePrinter alloc] init:profilePath printerID:printerId extraSettings:settings];
    [printer connect];

    if (testOnly) {
      [printer setBold:YES];
      [printer writeLine:@"Tatweer App - Honeywell SDK OK"];
      [printer setBold:NO];
      [printer writeLine:[NSString stringWithFormat:@"Printer profile: %@", printerId]];
      [printer newLine:3];
    } else {
      PDFDocument *document = [[PDFDocument alloc] initWithData:pdfData];
      if (document == nil || document.pageCount == 0) {
        if (error != NULL) {
          *error = [NSError errorWithDomain:HoneywellPrinterErrorDomain
                                        code:3
                                    userInfo:@{NSLocalizedDescriptionKey : @"تعذّر تجهيز ملف الفاتورة للطباعة."}];
        }
        [printer disconnect];
        [printer close];
        return nil;
      }
      NSInteger width = [self printHeadWidthForProfile:printerId];
      for (NSInteger index = 0; index < document.pageCount; index++) {
        PDFPage *page = [document pageAtIndex:index];
        NSData *png = [self pngForPage:page targetWidth:width];
        [printer writeGraphicBase64:[png base64EncodedStringWithOptions:0]
                           rotation:DEGREE_0
                            xOffset:0
                              width:width
                             height:0];
        [printer newLine:1];
      }
    }

    [printer formFeed];
    NSInteger bytesWritten = [printer getBytesWritten];
    [printer disconnect];
    [printer close];
    return @{ @"bytesWritten" : @(bytesWritten) };
  }
  @catch (ITCLinePrinterException *exception) {
    if (error != NULL) {
      *error = [NSError errorWithDomain:HoneywellPrinterErrorDomain
                                    code:[exception getErrorCode]
                                userInfo:@{NSLocalizedDescriptionKey : exception.reason ?: @"فشل Honeywell SDK في الطباعة."}];
    }
  }
  @catch (NSException *exception) {
    if (error != NULL) {
      *error = [NSError errorWithDomain:HoneywellPrinterErrorDomain
                                    code:99
                                userInfo:@{NSLocalizedDescriptionKey : exception.reason ?: @"حدث خطأ غير متوقع في Honeywell SDK."}];
    }
  }
  @finally {
    @try {
      [printer disconnect];
      [printer close];
    } @catch (NSException *ignored) {
    }
  }
  return nil;
}

+ (EAAccessory *)accessoryWithConnectionId:(NSString *)connectionId {
  for (EAAccessory *accessory in EAAccessoryManager.sharedAccessoryManager.connectedAccessories) {
    if ([[NSString stringWithFormat:@"%ld", (long)accessory.connectionID] isEqualToString:connectionId]) {
      return accessory;
    }
  }
  return nil;
}

+ (NSData *)pngForPage:(PDFPage *)page targetWidth:(NSInteger)targetWidth {
  CGRect box = [page boundsForBox:kPDFDisplayBoxMediaBox];
  CGFloat scale = targetWidth / CGRectGetWidth(box);
  CGSize size = CGSizeMake(targetWidth, MAX(1, round(CGRectGetHeight(box) * scale)));
  UIGraphicsBeginImageContextWithOptions(size, YES, 1.0);
  CGContextRef context = UIGraphicsGetCurrentContext();
  CGContextSetRGBFillColor(context, 1, 1, 1, 1);
  CGContextFillRect(context, (CGRect){.origin = CGPointZero, .size = size});
  CGContextSaveGState(context);
  CGContextTranslateCTM(context, 0, size.height);
  CGContextScaleCTM(context, scale, -scale);
  [page drawWithBox:kPDFDisplayBoxMediaBox toContext:context];
  CGContextRestoreGState(context);
  UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
  UIGraphicsEndImageContext();
  return UIImagePNGRepresentation(image);
}

+ (NSString *)profileForName:(NSString *)name {
  NSString *value = name.uppercaseString;
  if ([value containsString:@"PB51"]) return @"PB51";
  if ([value containsString:@"PB42"]) return @"PB42";
  if ([value containsString:@"PB31"]) return @"PB31";
  if ([value containsString:@"PB21"]) return @"PB21";
  if ([value containsString:@"PR3"]) return @"PR3";
  return @"PR2";
}

+ (NSInteger)printHeadWidthForProfile:(NSString *)printerId {
  if ([printerId isEqualToString:@"PR3"] || [printerId isEqualToString:@"PB31"]) return 576;
  if ([printerId isEqualToString:@"PB42"] || [printerId isEqualToString:@"PB51"]) return 832;
  return 384;
}

@end
