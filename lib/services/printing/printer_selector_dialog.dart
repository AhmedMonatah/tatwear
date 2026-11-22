import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:printing/printing.dart';

import '../../utils/app_colors.dart';
import '../../utils/app_styles.dart';
import 'honeywell_printer_service.dart';
import 'printer_manager.dart';

/// Shows the invoice actions. Hardware printing is always sent through the
/// direct Bluetooth raster printing; PDF sharing remains available separately.
Future<void> showPrintOptions(
  BuildContext context, {
  required Uint8List pdfBytes,
  required String pdfName,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _PrintOptionsSheet(
      parentContext: context,
      pdfBytes: pdfBytes,
      pdfName: pdfName,
    ),
  );
}

class _PrintOptionsSheet extends StatefulWidget {
  final BuildContext parentContext;
  final Uint8List pdfBytes;
  final String pdfName;

  const _PrintOptionsSheet({
    required this.parentContext,
    required this.pdfBytes,
    required this.pdfName,
  });

  @override
  State<_PrintOptionsSheet> createState() => _PrintOptionsSheetState();
}

class _PrintOptionsSheetState extends State<_PrintOptionsSheet> {
  SavedPrinterInfo? _savedPrinter;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSavedPrinter();
  }

  Future<void> _loadSavedPrinter() async {
    final printer = await PrinterManager.instance.loadSavedPrinter();
    if (mounted) {
      setState(() {
        _savedPrinter = printer;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'خيارات الفاتورة والطباعة',
              style: AppStyles.heading2(context),
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(18),
                child: CircularProgressIndicator(),
              )
            else ...[
              if (_savedPrinter != null)
                ListTile(
                  leading: _tileIcon(Icons.print, AppColors.primary),
                  title: const Text(
                    'طباعة الفاتورة',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    '${_savedPrinter!.name} — ${_savedPrinter!.printerId}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _startPrinting(
                      widget.parentContext,
                      HoneywellPrinterDevice(
                        name: _savedPrinter!.name,
                        address: _savedPrinter!.address,
                        printerId: _savedPrinter!.printerId,
                      ),
                    );
                  },
                ),
              ListTile(
                leading: _tileIcon(Icons.settings_bluetooth, Colors.blue),
                title: Text(
                  _savedPrinter == null
                      ? 'اختيار طابعة Honeywell'
                      : 'تغيير الطابعة',
                ),
                subtitle: const Text(
                  'يعرض الطابعات المقترنة ويطبع مباشرة عبر Bluetooth',
                  style: TextStyle(fontSize: 12),
                ),
                onTap: _openPrinterSelector,
              ),
              if (_savedPrinter != null)
                ListTile(
                  leading: _tileIcon(Icons.bolt, Colors.orange),
                  title: const Text('طباعة اختبارية'),
                  subtitle: const Text(
                    'يتحقق من الاتصال والطباعة المباشرة',
                    style: TextStyle(fontSize: 12),
                  ),
                  onTap: () async {
                    final printer = HoneywellPrinterDevice(
                      name: _savedPrinter!.name,
                      address: _savedPrinter!.address,
                      printerId: _savedPrinter!.printerId,
                    );
                    Navigator.pop(context);
                    if (widget.parentContext.mounted) {
                      await Navigator.push<void>(
                        widget.parentContext,
                        MaterialPageRoute(
                          builder: (_) => PrintingProgressScreen(
                            printer: printer,
                            testOnly: true,
                          ),
                        ),
                      );
                    }
                  },
                ),
              ListTile(
                leading: _tileIcon(Icons.share, AppColors.success),
                title: const Text('مشاركة كـ PDF'),
                subtitle: const Text(
                  'إرسال الفاتورة عبر واتساب أو البريد',
                  style: TextStyle(fontSize: 12),
                ),
                onTap: () {
                  Navigator.pop(context);
                  Printing.sharePdf(
                    bytes: widget.pdfBytes,
                    filename: widget.pdfName,
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _tileIcon(IconData icon, Color color) => Container(
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: color.withAlpha(28),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Icon(icon, color: color),
  );

  Future<void> _openPrinterSelector() async {
    Navigator.pop(context);
    final targetContext = widget.parentContext;
    if (!targetContext.mounted) return;
    final selected = await Navigator.push<HoneywellPrinterDevice>(
      targetContext,
      MaterialPageRoute(builder: (_) => const PrinterSelectorScreen()),
    );
    if (selected == null || !targetContext.mounted) return;

    await PrinterManager.instance.savePrinter(
      address: selected.address,
      name: selected.name,
      printerId: selected.printerId,
    );
    if (targetContext.mounted) _startPrinting(targetContext, selected);
  }

  void _startPrinting(BuildContext context, HoneywellPrinterDevice printer) {
    if (!context.mounted) return;
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            PrintingProgressScreen(printer: printer, pdfBytes: widget.pdfBytes),
      ),
    );
  }
}

class PrinterSelectorScreen extends StatefulWidget {
  const PrinterSelectorScreen({super.key});

  @override
  State<PrinterSelectorScreen> createState() => _PrinterSelectorScreenState();
}

class _PrinterSelectorScreenState extends State<PrinterSelectorScreen> {
  List<HoneywellPrinterDevice> _printers = const [];
  String? _error;
  bool _loading = true;
  bool _showingAllDevices = false;

  @override
  void initState() {
    super.initState();
    _loadPrinters();
  }

  Future<void> _loadPrinters({bool includeAllDevices = false}) async {
    setState(() {
      _loading = true;
      _error = null;
      _showingAllDevices = includeAllDevices;
    });
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        final statuses = await [
          Permission.bluetoothConnect,
          Permission.bluetoothScan,
        ].request();
        if (statuses.values.any((status) => !status.isGranted)) {
          throw const PrinterException(
            code: 'BLUETOOTH_PERMISSION_DENIED',
            message: 'يلزم منح صلاحية Bluetooth لعرض الطابعات المقترنة.',
            hint: 'امنح الصلاحية من إعدادات التطبيق ثم حدّث القائمة.',
          );
        }
        // Shows Android's standard enable dialog instead of making the user
        // leave the app and switch Bluetooth on manually in Settings.
        await HoneywellPrinterService.instance.prepareBluetooth();
      }
      final printers = includeAllDevices
          ? await HoneywellPrinterService.instance.getAllBondedDevices()
          : await HoneywellPrinterService.instance.getAvailablePrinters();
      if (mounted) setState(() => _printers = printers);
    } on PrinterException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) setState(() => _error = 'تعذّر تحميل الطابعات: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('اختيار طابعة Honeywell'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'تحديث القائمة',
            onPressed: _loading
                ? null
                : () => _loadPrinters(includeAllDevices: _showingAllDevices),
          ),
          IconButton(
            icon: const Icon(Icons.bluetooth_searching),
            tooltip: 'عرض كل الأجهزة المقترنة',
            onPressed: _loading || _showingAllDevices
                ? null
                : () => _loadPrinters(includeAllDevices: true),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _MessageState(
              message: _error!,
              onRetry: () =>
                  _loadPrinters(includeAllDevices: _showingAllDevices),
            )
          : _printers.isEmpty
          ? _MessageState(
              message: _showingAllDevices
                  ? 'لا توجد أجهزة Bluetooth مقترنة بهذا الهاتف.'
                  : 'لم نجد طابعة Honeywell/Intermec مدعومة. تأكد أنها مقترنة وأن اسمها يحتوي على الموديل PR2 أو PR3.',
              onRetry: () =>
                  _loadPrinters(includeAllDevices: _showingAllDevices),
              onShowAllDevices: _showingAllDevices
                  ? null
                  : () => _loadPrinters(includeAllDevices: true),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _printers.length + 1,
              separatorBuilder: (_, index) => index == 0
                  ? const SizedBox(height: 14)
                  : const SizedBox(height: 10),
              itemBuilder: (_, index) {
                if (index == 0) {
                  return _showingAllDevices
                      ? const _AllDevicesHint()
                      : const _CompatiblePrintersHint();
                }
                final printer = _printers[index - 1];
                return Card(
                  elevation: 0,
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(color: Colors.grey.shade200),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 7,
                    ),
                    leading: Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withAlpha(22),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.print_outlined,
                        color: AppColors.primary,
                      ),
                    ),
                    title: Text(
                      printer.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      printer.isKnownHoneywell
                          ? 'موديل ${printer.printerId}  •  ${printer.address}'
                          : 'اسم مخصص أو جهاز غير معروف  •  ${printer.address}',
                    ),
                    trailing: CircleAvatar(
                      radius: 16,
                      backgroundColor: AppColors.primary,
                      child: const Icon(
                        Icons.arrow_back,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                    onTap: () => _selectPrinter(printer),
                  ),
                );
              },
            ),
    );
  }

  Future<void> _selectPrinter(HoneywellPrinterDevice printer) async {
    if (printer.isKnownHoneywell) {
      if (mounted) Navigator.pop(context, printer);
      return;
    }

    final profile = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('اختر موديل الطابعة'),
        content: const Text(
          'لأن اسم الجهاز تم تغييره، اختر موديل Honeywell/Intermec الحقيقي قبل الطباعة.',
        ),
        actions: [
          for (final profile in const ['PR2', 'PR3'])
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, profile),
              child: Text(profile),
            ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء'),
          ),
        ],
      ),
    );
    if (profile != null && mounted) {
      Navigator.pop(context, printer.withProfile(profile));
    }
  }
}

class _MessageState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final VoidCallback? onShowAllDevices;

  const _MessageState({
    required this.message,
    required this.onRetry,
    this.onShowAllDevices,
  });

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.print_disabled_outlined,
            size: 48,
            color: Colors.grey,
          ),
          const SizedBox(height: 14),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('إعادة المحاولة'),
          ),
          if (onShowAllDevices != null) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: onShowAllDevices,
              icon: const Icon(Icons.bluetooth_searching),
              label: const Text('الطابعة غيّرت اسمها؟ عرض كل الأجهزة'),
            ),
          ],
        ],
      ),
    ),
  );
}

class _CompatiblePrintersHint extends StatelessWidget {
  const _CompatiblePrintersHint();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.primary.withAlpha(16),
      borderRadius: BorderRadius.circular(12),
    ),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.verified_outlined, color: AppColors.primary),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            'تظهر هنا طابعات Honeywell/Intermec المدعومة للطباعة المباشرة: PR2 وPR3 فقط.',
            style: TextStyle(height: 1.45),
          ),
        ),
      ],
    ),
  );
}

class _AllDevicesHint extends StatelessWidget {
  const _AllDevicesHint();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.orange.withAlpha(18),
      borderRadius: BorderRadius.circular(12),
    ),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline, color: Colors.orange),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            'هذه قائمة الأجهزة المقترنة لأن اسم الطابعة قد تغيّر. اختر جهاز Honeywell/Intermec فقط، ثم اختر موديل PR2 أو PR3 الصحيح.',
            style: TextStyle(height: 1.45),
          ),
        ),
      ],
    ),
  );
}

class PrintingProgressScreen extends StatefulWidget {
  final HoneywellPrinterDevice printer;
  final Uint8List? pdfBytes;
  final bool testOnly;

  const PrintingProgressScreen({
    super.key,
    required this.printer,
    this.pdfBytes,
    this.testOnly = false,
  });

  @override
  State<PrintingProgressScreen> createState() => _PrintingProgressScreenState();
}

class _PrintingProgressScreenState extends State<PrintingProgressScreen> {
  String _status = 'جارٍ الاتصال بالطابعة عبر Bluetooth...';
  PrinterException? _error;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _print();
  }

  Future<void> _print() async {
    setState(() {
      _error = null;
      _done = false;
      _status = widget.testOnly
          ? 'جارٍ إرسال صفحة الاختبار...'
          : 'جارٍ تحويل الفاتورة لصورة وإرسالها مباشرة عبر Bluetooth...';
    });
    try {
      final result = widget.testOnly
          ? await HoneywellPrinterService.instance.printTest(widget.printer)
          : await HoneywellPrinterService.instance.printInvoice(
              printer: widget.printer,
              pdfBytes: widget.pdfBytes!,
            );
      if (!mounted) return;
      setState(() {
        _done = true;
        _status =
            'تم إرسال ${widget.testOnly ? 'صفحة الاختبار' : 'الفاتورة'} للطابعة بنجاح ✓\n${result.bytesWritten} بايت';
      });
    } on PrinterException catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _status = error.message;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = PrinterException(
            code: 'UNEXPECTED_ERROR',
            message: 'حدث خطأ غير متوقع أثناء الطباعة.',
            hint: 'أعد تشغيل الطابعة وحاول مرة أخرى.',
            rawError: error.toString(),
          );
          _status = _error!.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final failed = _error != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.testOnly ? 'اختبار الطابعة' : 'طباعة الفاتورة'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: failed || _done,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!failed && !_done)
                const CircularProgressIndicator()
              else
                Icon(
                  _done ? Icons.check_circle : Icons.error_outline,
                  size: 64,
                  color: _done ? AppColors.success : AppColors.error,
                ),
              const SizedBox(height: 20),
              Text(
                _status,
                textAlign: TextAlign.center,
                style: AppStyles.bodyLarge(context),
              ),
              if (failed) ...[
                const SizedBox(height: 12),
                Text(
                  'كود الخطأ: ${_error!.code}',
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
                const SizedBox(height: 12),
                Text(
                  _error!.hint,
                  textAlign: TextAlign.center,
                  style: const TextStyle(height: 1.5),
                ),
                if (_error!.rawError != null) ...[
                  const SizedBox(height: 10),
                  TextButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(
                          text:
                              '${_error!.code}\n${_error!.message}\n${_error!.rawError}',
                        ),
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('تم نسخ تفاصيل الخطأ')),
                        );
                      }
                    },
                    icon: const Icon(Icons.copy),
                    label: const Text('نسخ التفاصيل التقنية'),
                  ),
                ],
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _print,
                  icon: const Icon(Icons.refresh),
                  label: const Text('إعادة المحاولة'),
                ),
              ],
              if (_done) ...[
                const SizedBox(height: 18),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('تم'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
