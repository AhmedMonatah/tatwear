import 'package:shared_preferences/shared_preferences.dart';

/// يدير حفظ واسترجاع الطابعة المختارة لاستخدام Honeywell / Intermec SDK.
class PrinterManager {
  PrinterManager._();
  static final PrinterManager instance = PrinterManager._();

  static const _keyAddress = 'honeywell_printer_address';
  static const _keyName = 'honeywell_printer_name';
  static const _keyProfile = 'honeywell_printer_profile';

  /// حفظ بيانات الطابعة المحددة
  Future<void> savePrinter({
    required String address,
    required String name,
    required String printerId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAddress, address);
    await prefs.setString(_keyName, name);
    await prefs.setString(_keyProfile, printerId);
  }

  /// استرجاع بيانات الطابعة المحفوظة
  Future<SavedPrinterInfo?> loadSavedPrinter() async {
    final prefs = await SharedPreferences.getInstance();
    final address = prefs.getString(_keyAddress);
    final name = prefs.getString(_keyName);
    final printerId = prefs.getString(_keyProfile);

    if (address == null ||
        address.isEmpty ||
        printerId == null ||
        printerId.isEmpty) {
      return null;
    }
    return SavedPrinterInfo(
      address: address,
      name: (name != null && name.isNotEmpty) ? name : address,
      printerId: printerId,
    );
  }

  /// مسح الطابعة المحفوظة
  Future<void> clearSavedPrinter() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyAddress);
    await prefs.remove(_keyName);
    await prefs.remove(_keyProfile);
  }
}

class SavedPrinterInfo {
  final String address;
  final String name;
  final String printerId;

  const SavedPrinterInfo({
    required this.address,
    required this.name,
    required this.printerId,
  });
}
