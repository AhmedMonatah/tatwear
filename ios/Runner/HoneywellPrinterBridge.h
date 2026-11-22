#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Objective-C wrapper for the Honeywell iOS SDK.  The vendor API reports
/// errors as NSException, which cannot safely cross into Swift/Flutter.
@interface HoneywellPrinterBridge : NSObject

+ (NSArray<NSDictionary<NSString *, NSString *> *> *)availablePrinters;

+ (nullable NSDictionary<NSString *, NSNumber *> *)printPdf:(NSData *)pdfData
                                                     address:(NSString *)address
                                                   printerId:(NSString *)printerId
                                                    testOnly:(BOOL)testOnly
                                                       error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
