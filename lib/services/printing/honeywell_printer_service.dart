import 'package:flutter/services.dart';

/// Printer discovery and printing for Honeywell/Intermec mobile printers.
///
/// Android renders the invoice locally and sends its raster pixels directly
/// over the printer's paired Bluetooth connection; no companion print-service
/// application is required.
class HoneywellPrinterService {
  HoneywellPrinterService._();

  static final HoneywellPrinterService instance = HoneywellPrinterService._();

  static const MethodChannel _channel = MethodChannel(
    'com.tatweer/honeywell_printer',
  );

  /// Requests Android's standard Bluetooth enable dialog when required.
  /// Android intentionally does not allow apps to enable Bluetooth silently.
  Future<void> prepareBluetooth() async {
    try {
      await _channel.invokeMethod<bool>('prepareBluetooth');
    } on PlatformException catch (error) {
      throw PrinterException.fromPlatformException(error);
    }
  }

  Future<List<HoneywellPrinterDevice>> getAvailablePrinters() async {
    return _getBondedDevices('listPrinters');
  }

  /// Used only when the printer's Bluetooth name was changed, so the user can
  /// identify the paired PR2/PR3 device and choose its correct profile.
  Future<List<HoneywellPrinterDevice>> getAllBondedDevices() async {
    return _getBondedDevices('listAllBondedDevices');
  }

  Future<List<HoneywellPrinterDevice>> _getBondedDevices(String method) async {
    try {
      final result = await _channel.invokeListMethod<dynamic>(method);
      return (result ?? const [])
          .whereType<Map>()
          .map(
            (item) => HoneywellPrinterDevice.fromMap(
              Map<Object?, Object?>.from(item),
            ),
          )
          .toList();
    } on PlatformException catch (error) {
      throw PrinterException.fromPlatformException(error);
    }
  }

  Future<PrintJobResult> printInvoice({
    required HoneywellPrinterDevice printer,
    required Uint8List pdfBytes,
  }) async {
    try {
      final result = await _channel
          .invokeMapMethod<String, dynamic>('printPdf', <String, dynamic>{
            'address': printer.address,
            'printerId': printer.printerId,
            'pdfBytes': pdfBytes,
          });
      return PrintJobResult(bytesWritten: result?['bytesWritten'] as int? ?? 0);
    } on PlatformException catch (error) {
      throw PrinterException.fromPlatformException(error);
    }
  }

  Future<PrintJobResult> printTest(HoneywellPrinterDevice printer) async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'printTest',
        <String, dynamic>{
          'address': printer.address,
          'printerId': printer.printerId,
        },
      );
      return PrintJobResult(bytesWritten: result?['bytesWritten'] as int? ?? 0);
    } on PlatformException catch (error) {
      throw PrinterException.fromPlatformException(error);
    }
  }
}

class HoneywellPrinterDevice {
  final String name;
  final String address;
  final String printerId;
  final bool isKnownHoneywell;

  const HoneywellPrinterDevice({
    required this.name,
    required this.address,
    required this.printerId,
    this.isKnownHoneywell = true,
  });

  factory HoneywellPrinterDevice.fromMap(Map<Object?, Object?> value) {
    final address = value['address']?.toString() ?? '';
    return HoneywellPrinterDevice(
      name: value['name']?.toString().trim().isNotEmpty == true
          ? value['name']!.toString()
          : address,
      address: address,
      printerId: value['printerId']?.toString().trim().isNotEmpty == true
          ? value['printerId']!.toString()
          : 'PR2',
      isKnownHoneywell:
          value['isKnownHoneywell']?.toString().toLowerCase() != 'false',
    );
  }

  HoneywellPrinterDevice withProfile(String profile) => HoneywellPrinterDevice(
    name: name,
    address: address,
    printerId: profile,
    isKnownHoneywell: isKnownHoneywell,
  );
}

class PrintJobResult {
  final int bytesWritten;

  const PrintJobResult({required this.bytesWritten});
}

class PrinterException implements Exception {
  final String code;
  final String message;
  final String hint;
  final String? rawError;

  const PrinterException({
    required this.code,
    required this.message,
    required this.hint,
    this.rawError,
  });

  factory PrinterException.fromPlatformException(PlatformException error) {
    final details = error.details?.toString();
    switch (error.code) {
      case 'BLUETOOTH_PERMISSION_DENIED':
        return PrinterException(
          code: error.code,
          message: 'التطبيق لا يملك صلاحية الاتصال بالبلوتوث.',
          hint:
              'اذهب إلى إعدادات التطبيق وفعّل صلاحية Bluetooth ثم حاول مرة أخرى.',
          rawError: details,
        );
      case 'BLUETOOTH_DISABLED':
        return PrinterException(
          code: error.code,
          message: 'يلزم تشغيل Bluetooth للبحث عن الطابعة.',
          hint: 'اضغط إعادة المحاولة ثم وافق على طلب تشغيل Bluetooth.',
          rawError: details,
        );
      case 'BLUETOOTH_UNAVAILABLE':
        return PrinterException(
          code: error.code,
          message: error.message ?? 'Bluetooth غير متاح على هذا الهاتف.',
          hint: 'استخدم هاتفًا يدعم Bluetooth ثم حاول مرة أخرى.',
          rawError: details,
        );
      case 'INVALID_ARGUMENT':
        return PrinterException(
          code: error.code,
          message: 'بيانات الطابعة أو الفاتورة غير مكتملة.',
          hint: 'اختر الطابعة مرة أخرى ثم أعد المحاولة.',
          rawError: details,
        );
      case 'DIRECT_PROFILE_UNSUPPORTED':
        return PrinterException(
          code: error.code,
          message: error.message ?? 'موديل الطابعة المختار غير مدعوم بعد.',
          hint: 'هذا المسار المباشر يدعم PR2 وPR3. اختر الموديل الصحيح.',
          rawError: details,
        );
      default:
        return PrinterException(
          code: error.code,
          message: error.message ?? 'تعذّرت الطباعة المباشرة عبر Bluetooth.',
          hint:
              'تأكد من تشغيل الطابعة واقترانها بالهاتف وقربها منه. يجب ضبط لغة طابعة PR3 على CSim/CPCL قبل الطباعة المباشرة.',
          rawError: details,
        );
    }
  }

  @override
  String toString() => '[$code] $message';
}
