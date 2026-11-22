import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tatweer/widgets/bill/items_table.dart';
import '../../../services/pdf_service.dart';
import '../../../services/printing/printer_selector_dialog.dart';
import '../../../utils/app_colors.dart';
import '../../../utils/app_styles.dart';
import '../../utils/snackbars.dart';
import '../../widgets/shared/responsive_container.dart';
import '../../widgets/shared/responsive_button.dart';
import '../../../widgets/shared/loading_overlay.dart';
import '../../../widgets/shared/custom_app_bar.dart';
import '../../services/local_db_service.dart';
import '../../services/sync_service.dart';
import 'add_item_for_exchange_screen.dart';

enum ExportAction { print, share }

class ExchangeBillDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> bill;
  final bool internetAvailable;
  const ExchangeBillDetailsScreen({
    super.key,
    required this.bill,
    required this.internetAvailable,
  });

  @override
  State<ExchangeBillDetailsScreen> createState() =>
      _ExchangeBillDetailsScreenState();
}

class _ExchangeBillDetailsScreenState extends State<ExchangeBillDetailsScreen> {
  final LocalDbService _localDbService = LocalDbService.instance;
  final SyncService _syncService = SyncService.instance;
  final PdfService _pdfService = PdfService();

  List<Map<String, dynamic>> _exchangeItems = [];
  List<Map<String, dynamic>> _updatedExchangeItems = [];
  String _fromBranchName = 'جاري التحميل...';
  String _toBranchName = 'جاري التحميل...';
  bool _loading = true;
  bool _isBusy = false;
  String _busyMessage = '';
  bool _hasChanges = false;
  String _error = '';
  bool _isLocked = false;

  Map<String, dynamic> _currentBill = {};

  @override
  void initState() {
    super.initState();
    _currentBill = Map.from(widget.bill);
    _loadBillDetails();
  }

  double get _itemsTotal {
    return _calculateItemsTotal(
      _hasChanges ? _updatedExchangeItems : _exchangeItems,
    );
  }

  double _calculateItemsTotal(List<Map<String, dynamic>> items) {
    double total = 0.0;
    for (var item in items) {
      total += (item['Total'] as double?) ?? 0.0;
    }
    return total;
  }

  Future<void> _loadBillDetails() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      await Future.wait([_loadBranchNames(), _loadExchangeItems()]);
      _checkLockStatus();
    } catch (e) {
      setState(() => _error = 'خطأ في تحميل تفاصيل الفاتورة');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _checkLockStatus() {
    final lockValue = _currentBill['Lock']?.toString();
    setState(() {
      _isLocked = lockValue == 'Lock';
    });
  }

  Future<void> _loadBranchNames() async {
    try {
      final fromBranchId = _currentBill['BranchId'];
      final toBranchId = _currentBill['DestBranchId'];

      if (fromBranchId != null) {
        final branch = await _localDbService.getBranchById(fromBranchId);
        _fromBranchName = branch?['Name']?.toString() ?? 'غير معروف';
      }
      if (toBranchId != null) {
        final branch = await _localDbService.getBranchById(toBranchId);
        _toBranchName = branch?['Name']?.toString() ?? 'غير معروف';
      }
    } catch (e) {
      setState(() {
        _fromBranchName = 'غير معروف';
        _toBranchName = 'غير معروف';
      });
    }
  }

  Future<void> _loadExchangeItems() async {
    try {
      final billId = _currentBill['Id'];
      if (billId == null) {
        setState(() => _exchangeItems = []);
        return;
      }

      final items = await _localDbService.getExchangeItemsByBillId(billId);
      final enhancedItems = await _enhanceItemsWithNames(items);
      setState(() {
        _exchangeItems = enhancedItems;
        _updatedExchangeItems = List.from(enhancedItems);
      });
    } catch (e) {
      setState(() => _error = 'خطأ في تحميل منتجات الفاتورة');
    }
  }

  Future<List<Map<String, dynamic>>> _enhanceItemsWithNames(
    List<Map<String, dynamic>> items,
  ) async {
    final enhancedItems = <Map<String, dynamic>>[];
    for (final item in items) {
      try {
        final itemId = item['ItemId'];
        String itemName = 'غير معروف';
        if (itemId != null) {
          final strItem = await _localDbService.getSTRItemById(itemId);
          itemName = strItem?['Name']?.toString() ?? 'غير معروف';
        }
        enhancedItems.add({...item, 'ItemName': itemName});
      } catch (e) {
        enhancedItems.add({...item, 'ItemName': 'غير معروف'});
      }
    }
    return enhancedItems;
  }

  Future<void> _openAddItems() async {
    final initialItems = _updatedExchangeItems
        .map(
          (item) => {
            'ItemId': item['ItemId'],
            'Qty': item['Qty'],
            'QtyUnit': item['QtyUnit'] ?? 'صغرى',
            'Price': item['Price'],
            'Total': item['Total'],
            'ItemName': item['ItemName'],
            'UnitQty': item['UnitQty'],
            'TotalQty': item['TotalQty'],
            'BranchId': item['BranchId'],
            'DestBranchId': item['DestBranchId'],
          },
        )
        .toList();

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddItemForExchangeScreen(
          initialPendingItems: initialItems,
          sourceBranchId: _currentBill['BranchId'] as int,
          destBranchId: _currentBill['DestBranchId'] as int,
        ),
      ),
    );

    if (result is List<Map<String, dynamic>> && result.isNotEmpty) {
      setState(() {
        _updatedExchangeItems = result;
        _hasChanges = true;
      });
      showSuccessSnackBar(context, 'تم تحديث قائمة المنتجات');
    }
  }

  Future<void> _saveBillUpdates() async {
    if (!_hasChanges) {
      showInfoSnackBar(context, 'لا توجد تغييرات لحفظها');
      return;
    }

    setState(() {
      _isBusy = true;
      _busyMessage = 'جاري حفظ التغييرات...';
    });

    bool saveSuccessful = false;

    try {
      final billId = _currentBill['Id'] as int;
      final newTotal = _itemsTotal;

      await _localDbService.updateExchangeBillDetails(billId, newTotal);

      if (_hasChanges) {
        await _localDbService.replaceExchangeItems(
          billId,
          _updatedExchangeItems,
        );
      }

      if (widget.internetAvailable) {
        try {
          await _syncService.updateExchangeBillOnServer(
            billId,
            newTotal,
            _updatedExchangeItems,
            _currentBill['Lock']?.toString(),
          );
          await _localDbService.markExchangeBillAsSynced(billId);
          showSuccessSnackBar(context, 'تم تحديث الفاتورة على الخادم بنجاح');

          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(
            'last_action',
            DateTime.now().toIso8601String(),
          );
          saveSuccessful = true;
        } catch (syncError) {
          await _localDbService.markExchangeBillAsPendingSync(billId);
          showEnhancedOfflineSnackBar(context);
          saveSuccessful = true;
        }
      } else {
        await _localDbService.markExchangeBillAsPendingSync(billId);
        showEnhancedOfflineSnackBar(context);
        saveSuccessful = true;
      }

      setState(() {
        _currentBill['Total'] = newTotal;
        _exchangeItems = List.from(_updatedExchangeItems);
        _hasChanges = false;
      });

      if (saveSuccessful && mounted) {
        await Future.delayed(const Duration(milliseconds: 1000));
        Navigator.pop(context, true);
      }
    } catch (e) {
      showErrorSnackBar(context, 'حدث خطأ أثناء حفظ التحديثات: $e');
    } finally {
      if (mounted && !saveSuccessful) {
        setState(() {
          _isBusy = false;
          _busyMessage = '';
        });
      }
    }
  }

  void _showExportOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: <Widget>[
              ListTile(
                leading: Icon(Icons.print, color: AppColors.primary),
                title: Text(
                  'طباعة الفاتورة',
                  style: AppStyles.bodyLarge(context),
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  _handleExport(ExportAction.print);
                },
              ),
              ListTile(
                leading: Icon(Icons.share, color: AppColors.success),
                title: Text(
                  'مشاركة كـ PDF',
                  style: AppStyles.bodyLarge(context),
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  _handleExport(ExportAction.share);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _handleExport(ExportAction action) async {
    if (!_isLocked) {
      final shouldSaveAndLock = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          title: const Text(
            'تأكيد الإجراء',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
          ),
          content: Text(
            'سيتم حفظ الفاتورة وقفلها (لا يمكن تعديلها) قبل ${action == ExportAction.print ? 'الطباعة' : 'المشاركة'}. هل أنت متأكد؟',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, height: 1.5),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              style: TextButton.styleFrom(
                foregroundColor: Colors.grey[700],
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
              ),
              child: const Text('إلغاء', style: TextStyle(fontSize: 14)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'نعم',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      );

      if (shouldSaveAndLock != true) return;

      setState(() {
        _isBusy = true;
        _busyMessage = 'جاري حفظ وقفل الفاتورة...';
      });

      bool saveSuccessful = false;

      try {
        final billId = _currentBill['Id'] as int;
        final newTotal = _itemsTotal;

        await _localDbService.updateExchangeBillDetails(billId, newTotal);
        await _localDbService.updateExchangeBillLockStatus(billId, 'Lock');

        if (_hasChanges) {
          await _localDbService.replaceExchangeItems(
            billId,
            _updatedExchangeItems,
          );
        }

        if (widget.internetAvailable) {
          try {
            await _syncService.updateExchangeBillOnServer(
              billId,
              newTotal,
              _hasChanges ? _updatedExchangeItems : _exchangeItems,
              'Lock',
            );
            await _localDbService.markExchangeBillAsSynced(billId);
            showSuccessSnackBar(context, 'تم حفظ الفاتورة على الخادم بنجاح');
            saveSuccessful = true;
          } catch (syncError) {
            await _localDbService.markExchangeBillAsPendingSync(billId);
            showEnhancedOfflineSnackBar(context);
            saveSuccessful = true;
          }
        } else {
          await _localDbService.markExchangeBillAsPendingSync(billId);
          showEnhancedOfflineSnackBar(context);
          saveSuccessful = true;
        }

        setState(() {
          _currentBill['Total'] = newTotal;
          _currentBill['Lock'] = 'Lock';
          if (_hasChanges) {
            _exchangeItems = List.from(_updatedExchangeItems);
          }
          _hasChanges = false;
          _isLocked = true;
        });

        await _generateAndProcessPdf(action);

        showSuccessSnackBar(
          context,
          'تم حفظ وقفل الفاتورة و${action == ExportAction.print ? 'طباعتها' : 'مشاركتها'} بنجاح',
        );

        if (action != ExportAction.print && saveSuccessful && mounted) {
          await Future.delayed(const Duration(milliseconds: 1000));
          Navigator.pop(context, true);
        }
      } catch (e) {
        showErrorSnackBar(context, 'حدث خطأ أثناء حفظ وقفل الفاتورة: $e');
        if (mounted) {
          setState(() {
            _isBusy = false;
            _busyMessage = '';
          });
        }
      }
    } else {
      try {
        await _generateAndProcessPdf(action);

        showSuccessSnackBar(
          context,
          'تم ${action == ExportAction.print ? 'طباعة' : 'مشاركة'} الفاتورة بنجاح',
        );

        if (action != ExportAction.print && mounted) {
          await Future.delayed(const Duration(milliseconds: 1000));
          Navigator.pop(context, true);
        }
      } catch (e) {
        showErrorSnackBar(
          context,
          'حدث خطأ أثناء ${action == ExportAction.print ? 'طباعة' : 'مشاركة'} الفاتورة: $e',
        );
      }
    }
  }

  Future<void> _generateAndProcessPdf(ExportAction action) async {
    setState(() {
      _isBusy = true;
      _busyMessage =
          'جاري تجهيز الفاتورة ${action == ExportAction.print ? 'للطباعة' : 'للمشاركة'}...';
    });

    try {
      final itemsToExport = _hasChanges
          ? _updatedExchangeItems
          : _exchangeItems;
      final Uint8List pdfData = await _pdfService.generateExchangeBillPdf(
        _currentBill,
        itemsToExport,
        _fromBranchName,
        _toBranchName,
        _itemsTotal,
      );

      final pdfName = 'فاتورة_تحويل_${_currentBill['Bill'] ?? 'محلية'}.pdf';

      if (action == ExportAction.print) {
        if (!mounted) return;
        setState(() { _isBusy = false; _busyMessage = ''; });
        await showPrintOptions(
          context,
          pdfBytes: pdfData,
          pdfName: pdfName,
        );
        return;
      } else {
        await Printing.sharePdf(bytes: pdfData, filename: pdfName);
      }
    } catch (e) {
      showErrorSnackBar(
        context,
        'حدث خطأ أثناء تجهيز الفاتورة: ${e.toString()}',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
          _busyMessage = '';
        });
      }
    }
  }

  Widget _buildLoading() => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        CircularProgressIndicator(color: AppColors.primary),
        SizedBox(height: AppStyles.verticalSpacing(context)),
        Text(
          'جاري تحميل تفاصيل الفاتورة...',
          style: AppStyles.bodyLarge(context),
        ),
      ],
    ),
  );

  Widget _buildError() => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.error_outline_rounded, color: AppColors.error, size: 80),
        SizedBox(height: AppStyles.verticalSpacing(context)),
        Text(
          _error,
          style: AppStyles.heading2(context).copyWith(color: AppColors.error),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: AppStyles.verticalSpacing(context)),
        ResponsiveButton(
          text: 'إعادة المحاولة',
          icon: Icons.refresh,
          onPressed: _loadBillDetails,
        ),
      ],
    ),
  );

  Widget _buildContent() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Custom header for exchange bill (without editable fields)
          _buildExchangeHeader(),
          SizedBox(height: AppStyles.verticalSpacing(context)),
          ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: 200,
              maxHeight: MediaQuery.of(context).size.height * 0.5,
            ),
            child: ItemsTableWidget(
              items: _hasChanges ? _updatedExchangeItems : _exchangeItems,
              hasChanges: _hasChanges,
              isLocked: _isLocked,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExchangeHeader() {
    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'فاتورة تحويل #${_currentBill['Bill'] ?? 'محلية'}',
                  style: AppStyles.heading2(context),
                ),
                if (_isLocked)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.error.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'مغلقة',
                      style: AppStyles.bodySmall(context).copyWith(
                        color: AppColors.error,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _buildInfoRow('التاريخ:', _currentBill['TheDate']),
            _buildInfoRow('من فرع:', _fromBranchName),
            _buildInfoRow('إلى فرع:', _toBranchName),
            const Divider(height: 20),
            _buildInfoRow(
              'إجمالي المنتجات:',
              '${_itemsTotal.toStringAsFixed(2)} ج.م',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            label,
            style: AppStyles.bodyMedium(
              context,
            ).copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 8),
          Text(value, style: AppStyles.bodyMedium(context)),
        ],
      ),
    );
  }

  Widget _buildSaveButton() {
    return Container(
      padding: AppStyles.screenPadding(context),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 4,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: ResponsiveButton(
        text: 'حفظ التغييرات',
        icon: Icons.save,
        onPressed: _isBusy ? () {} : _saveBillUpdates,
        isLoading: _isBusy,
        backgroundColor: AppColors.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(
        title: 'فاتورة #${_currentBill['Bill'] ?? ''}',
        actions: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextButton.icon(
              icon: Icon(
                Icons.picture_as_pdf,
                color: AppColors.onPrimary,
                size: AppStyles.iconSize(context),
              ),
              label: Text(
                'طباعة الفاتورة',
                style: AppStyles.bodyMedium(
                  context,
                ).copyWith(color: AppColors.onPrimary),
              ),
              onPressed: _isBusy ? null : _showExportOptions,
              style: TextButton.styleFrom(backgroundColor: AppColors.error),
            ),
          ),
          if (_hasChanges && !_isLocked && !_isBusy)
            IconButton(
              icon: Icon(Icons.save, size: AppStyles.iconSize(context)),
              onPressed: _saveBillUpdates,
              tooltip: 'حفظ التغييرات',
            ),
        ],
      ),
      body: Stack(
        children: [
          _loading
              ? _buildLoading()
              : _error.isNotEmpty
              ? _buildError()
              : ResponsiveContainer(child: _buildContent()),
          LoadingOverlay(message: _busyMessage, isLoading: _isBusy),
        ],
      ),
      floatingActionButton: (_currentBill['Id'] != null && !_isLocked)
          ? FloatingActionButton.extended(
              onPressed: _isBusy ? null : _openAddItems,
              icon: Icon(
                Icons.edit,
                size: AppStyles.iconSize(context),
                color: AppColors.onPrimary,
              ),
              label: Text(
                _hasChanges ? 'تعديل المنتجات' : 'إضافة/تعديل منتجات',
                style: AppStyles.bodyMedium(
                  context,
                ).copyWith(color: AppColors.onPrimary),
              ),
              backgroundColor: _isBusy ? Colors.grey : AppColors.primary,
            )
          : null,
      bottomNavigationBar: (_hasChanges && !_isLocked)
          ? _buildSaveButton()
          : null,
    );
  }
}
