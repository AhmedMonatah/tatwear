import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tatweer/widgets/bill/bill_header.dart';
import 'package:tatweer/widgets/bill/items_table.dart';
import '../../../services/pdf_service.dart';
import '../../../services/printing/printer_selector_dialog.dart';
import '../../../utils/app_colors.dart';
import '../../../utils/app_styles.dart';
import '../../../utils/helpers.dart';
import '../../utils/snackbars.dart';
import '../../widgets/shared/responsive_container.dart';
import '../../widgets/shared/responsive_button.dart';
import '../../../widgets/shared/loading_overlay.dart';
import '../../../widgets/shared/custom_app_bar.dart';
import '../../services/local_db_service.dart';
import '../../services/sync_service.dart';
import 'add_item_for_sells_screen.dart';

enum ExportAction { print, share }

class SellsBillDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> bill;
  final bool internetAvailable;
  const SellsBillDetailsScreen({
    super.key,
    required this.bill,
    required this.internetAvailable,
  });

  @override
  State<SellsBillDetailsScreen> createState() => _SellsBillDetailsScreenState();
}

class _SellsBillDetailsScreenState extends State<SellsBillDetailsScreen> {
  final LocalDbService _localDbService = LocalDbService.instance;
  final SyncService _syncService = SyncService.instance;
  final PdfService _pdfService = PdfService();

  List<Map<String, dynamic>> _sellItems = [];
  List<Map<String, dynamic>> _updatedSellItems = [];
  String _regionName = 'جاري التحميل...';
  bool _loading = true;
  bool _isBusy = false;
  String _busyMessage = '';
  bool _hasChanges = false;
  String _error = '';
  bool _isLocked = false;

  double _paiedAmount = 0.0;
  double _discount = 0.0;
  double _pastAccountFromServer = 0.0;
  bool _balanceLoading = false;
  bool _balanceFetchFailed = false;

  double _initialPaiedAmount = 0.0;
  double _initialDiscount = 0.0;
  double _initialItemsTotal = 0.0;
  double _initialBillRest = 0.0;

  Map<String, dynamic> _currentBill = {};
  final TextEditingController _discountController = TextEditingController();
  final TextEditingController _paiedController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _currentBill = Map.from(widget.bill);
    _loadBillDetails();
  }

  double get _itemsTotal {
    return _calculateBillTotal(_hasChanges ? _updatedSellItems : _sellItems);
  }

  double get _netTotal {
    return _itemsTotal - _discount;
  }

  double get _billRest {
    return _netTotal - _paiedAmount;
  }

  double get _totalRest {
    if (_balanceLoading || _balanceFetchFailed) {
      return 0.0;
    }

    if (!_hasChanges &&
        _paiedAmount == _initialPaiedAmount &&
        _discount == _initialDiscount) {
      return _pastAccountFromServer;
    }

    return _pastAccountFromServer - _initialBillRest + _billRest;
  }

  double _calculateBillTotal(List<Map<String, dynamic>> items) {
    double total = 0.0;
    for (var item in items) {
      String type = item['Type'] ?? 'بيع';
      double itemTotal = (item['Total'] as double?) ?? 0.0;

      if (type == 'بيع') {
        total += itemTotal;
      } else if (type == 'ارتجاع') {
        total -= itemTotal;
      }
    }
    return total;
  }

  Future<void> _fetchClientBalance(int clientId) async {
    if (!widget.internetAvailable) {
      setState(() {
        _balanceFetchFailed = true;
        _balanceLoading = false;
      });
      return;
    }

    setState(() {
      _balanceLoading = true;
      _balanceFetchFailed = false;
    });

    try {
      final balance = await _syncService.getClientBalance(clientId);
      setState(() {
        _pastAccountFromServer = balance ?? 0.0;
        _balanceLoading = false;
        _balanceFetchFailed = false;
      });
    } catch (e) {
      setState(() {
        _balanceFetchFailed = true;
        _balanceLoading = false;
        _pastAccountFromServer = 0.0;
      });
    }
  }

  Future<void> _loadBillDetails() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      await Future.wait([_loadRegionName(), _loadSellItems()]);
      _checkLockStatus();

      _initialPaiedAmount = getSafeDouble(_currentBill['PaiedForien']);
      _initialDiscount = getSafeDouble(_currentBill['Discount']);
      _initialItemsTotal = _calculateBillTotal(_sellItems);
      _initialBillRest =
          _initialItemsTotal - _initialDiscount - _initialPaiedAmount;

      _paiedAmount = _initialPaiedAmount;
      _discount = _initialDiscount;

      _discountController.text = _discount > 0
          ? _discount.toStringAsFixed(2)
          : '';
      _paiedController.text = _paiedAmount > 0
          ? _paiedAmount.toStringAsFixed(2)
          : '';

      final clientId = _currentBill['ClientId'];
      if (clientId != null && widget.internetAvailable && !_isLocked) {
        _fetchClientBalance(clientId);
      } else {
        setState(() {
          _balanceFetchFailed = !widget.internetAvailable || _isLocked;
          _balanceLoading = false;
        });
      }
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

  Future<void> _loadRegionName() async {
    try {
      final clientId = _currentBill['ClientId'];
      if (clientId == null) {
        setState(() => _regionName = 'غير معروف');
        return;
      }

      final client = await _localDbService.getClientById(clientId);
      if (client == null || client['RegionId'] == null) {
        setState(() => _regionName = 'غير معروف');
        return;
      }

      final region = await _localDbService.getRegionById(client['RegionId']);
      setState(
        () => _regionName = region?['Region']?.toString() ?? 'غير معروف',
      );
    } catch (e) {
      setState(() => _regionName = 'غير معروف');
    }
  }

  Future<void> _loadSellItems() async {
    try {
      final billId = _currentBill['Id'];
      if (billId == null) {
        setState(() => _sellItems = []);
        return;
      }

      final items = await _localDbService.getSellItemsByBillId(billId);
      final enhancedItems = await _enhanceItemsWithNames(items);
      setState(() {
        _sellItems = enhancedItems;
        _updatedSellItems = List.from(enhancedItems);
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

  void _onDiscountChanged(String value) {
    final newDiscount = double.tryParse(value) ?? 0.0;
    setState(() {
      _discount = newDiscount;
    });
  }

  void _onPaiedChanged(String value) {
    final newPaied = double.tryParse(value) ?? 0.0;
    setState(() {
      _paiedAmount = newPaied;
    });
  }

  Future<void> _openAddItems() async {
    final initialItems = _updatedSellItems
        .map(
          (item) => {
            'ItemId': item['ItemId'],
            'Qty': item['Qty'],
            'Price': item['Price'],
            'Total': item['Total'],
            'QtyUnit': item['QtyUnit'] ?? 'صغرى',
            'Pricing': item['Pricing'] ?? 'تجزئة',
            'Type': item['Type'] ?? 'بيع',
            'FirstPrice': item['FirstPrice'] ?? item['Price'],
            'BuyPrice': item['BuyPrice'] ?? 0.0,
            'ItemBranchId': item['ItemBranchId'] ?? _currentBill['BranchId'],
            'ItemName': item['ItemName'],
          },
        )
        .toList();

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddItemForSellsScreen(
          billId: _currentBill['Id'] as int,
          initialPendingSells: initialItems,
        ),
      ),
    );

    if (result is List<Map<String, dynamic>> && result.isNotEmpty) {
      setState(() {
        _updatedSellItems = result;
        _hasChanges = true;
      });
      showSuccessSnackBar(context, 'تم تحديث قائمة المنتجات');
    }
  }

  Future<void> _saveBillUpdates() async {
    final bool hasPaiedChanged = _paiedAmount != _initialPaiedAmount;
    final bool hasDiscountChanged = _discount != _initialDiscount;
    final bool hasItemsChanged = _hasChanges;

    if (!hasPaiedChanged && !hasDiscountChanged && !hasItemsChanged) {
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
      final newNetTotal = _netTotal;
      final newBillRest = _billRest;
      final currentPastAccount = getSafeDouble(_currentBill['PastAccount']);
      final newGrandTotal = newNetTotal + currentPastAccount;

      await _localDbService.updateBillTotalPaiedAndLock(
        billId,
        newTotal,
        _paiedAmount,
        _currentBill['Lock']?.toString(),
        discount: _discount,
        pastAccount: currentPastAccount,
        netTotal: newNetTotal,
        grandTotal: newGrandTotal,
        rest: newBillRest,
      );

      if (hasItemsChanged) {
        await _localDbService.replaceSellsItems(billId, _updatedSellItems);
      }

      if (widget.internetAvailable) {
        try {
          await _syncService.updateBillOnServer(
            billId,
            newTotal,
            hasItemsChanged ? _updatedSellItems : _sellItems,
            paied: _paiedAmount,
            discount: _discount,
            pastAccount: currentPastAccount,
            netTotal: newNetTotal,
            grandTotal: newGrandTotal,
            rest: newBillRest,
            lock: _currentBill['Lock']?.toString(),
          );
          await _localDbService.markBillAsSynced(billId);
          showSuccessSnackBar(context, 'تم تحديث الفاتورة على الخادم بنجاح');

          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(
            'last_action',
            DateTime.now().toIso8601String(),
          );
          saveSuccessful = true;
        } catch (syncError) {
          await _localDbService.markBillAsPendingSync(billId);
          showEnhancedOfflineSnackBar(context);
          saveSuccessful = true;
        }
      } else {
        await _localDbService.markBillAsPendingSync(billId);
        showEnhancedOfflineSnackBar(context);
        saveSuccessful = true;
      }

      setState(() {
        _currentBill['Total'] = newTotal;
        _currentBill['PaiedForien'] = _paiedAmount;
        _currentBill['Discount'] = _discount;
        _currentBill['PastAccount'] = currentPastAccount;
        _currentBill['NetTotal'] = newNetTotal;
        _currentBill['GrandTotal'] = newGrandTotal;
        _currentBill['Rest'] = newBillRest;

        _initialPaiedAmount = _paiedAmount;
        _initialDiscount = _discount;
        _initialItemsTotal = newTotal;
        _initialBillRest = _billRest;

        if (hasItemsChanged) {
          _sellItems = List.from(_updatedSellItems);
        }
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
        final newNetTotal = _netTotal;
        final currentPastAccount = getSafeDouble(_currentBill['PastAccount']);
        final newBillRest = _billRest;
        final newGrandTotal = newNetTotal + currentPastAccount;

        await _localDbService.updateBillTotalPaiedAndLock(
          billId,
          newTotal,
          _paiedAmount,
          'Lock',
          discount: _discount,
          pastAccount: currentPastAccount,
          netTotal: newNetTotal,
          grandTotal: newGrandTotal,
          rest: newBillRest,
        );

        if (_hasChanges) {
          await _localDbService.replaceSellsItems(billId, _updatedSellItems);
        }

        if (widget.internetAvailable) {
          try {
            await _syncService.updateBillOnServer(
              billId,
              newTotal,
              _hasChanges ? _updatedSellItems : _sellItems,
              paied: _paiedAmount,
              discount: _discount,
              pastAccount: currentPastAccount,
              netTotal: newNetTotal,
              grandTotal: newGrandTotal,
              rest: newBillRest,
              lock: 'Lock',
            );
            await _localDbService.markBillAsSynced(billId);
            showSuccessSnackBar(context, 'تم حفظ الفاتورة على الخادم بنجاح');
            saveSuccessful = true;
          } catch (syncError) {
            await _localDbService.markBillAsPendingSync(billId);
            showEnhancedOfflineSnackBar(context);
            saveSuccessful = true;
          }
        } else {
          await _localDbService.markBillAsPendingSync(billId);
          showEnhancedOfflineSnackBar(context);
          saveSuccessful = true;
        }

        setState(() {
          _currentBill['Total'] = newTotal;
          _currentBill['PaiedForien'] = _paiedAmount;
          _currentBill['Discount'] = _discount;
          _currentBill['NetTotal'] = newNetTotal;
          _currentBill['GrandTotal'] = newGrandTotal;
          _currentBill['Rest'] = newBillRest;
          _currentBill['Lock'] = 'Lock';

          _initialPaiedAmount = _paiedAmount;
          _initialDiscount = _discount;
          _initialItemsTotal = newTotal;
          _initialBillRest = _billRest;

          if (_hasChanges) {
            _sellItems = List.from(_updatedSellItems);
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
      final itemsToExport = _hasChanges ? _updatedSellItems : _sellItems;
      getSafeDouble(_currentBill['PastAccount']);

      final Uint8List pdfData = await _pdfService.generateBillPdf(
        _currentBill,
        itemsToExport,
        _regionName,
        _itemsTotal,
        _paiedAmount,
        discount: _discount,
        netTotal: _netTotal,
        pastAccount: _pastAccountFromServer,
        billRest: _billRest,
        totalRest: _totalRest,
        hasInternet: widget.internetAvailable && !_balanceFetchFailed,
      );

      final pdfName = 'فاتورة_${_currentBill['Bill'] ?? 'محلية'}.pdf';

      if (action == ExportAction.print) {
        if (!mounted) return;
        setState(() {
          _isBusy = false;
          _busyMessage = '';
        });
        await showPrintOptions(context, pdfBytes: pdfData, pdfName: pdfName);
        return; // isBusy already cleared above
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
          BillHeaderWidget(
            bill: _currentBill,
            customerLabel: 'العميل',
            customerName: getSafeString(_currentBill['ClientName']),
            regionName: _regionName,
            hasChanges: _hasChanges,
            isLocked: _isLocked,
            itemsTotal: _itemsTotal,
            discount: _discount,
            discountController: _discountController,
            onDiscountChanged: _onDiscountChanged,
            balanceLoading: _balanceLoading,
            balanceFetchFailed: _balanceFetchFailed,
            internetAvailable: widget.internetAvailable,
            paiedAmount: _paiedAmount,
            paiedController: _paiedController,
            onPaiedChanged: _onPaiedChanged,
            netTotal: _netTotal,
            billRest: _billRest,
            totalRest: _totalRest,
          ),
          SizedBox(height: AppStyles.verticalSpacing(context)),

          ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: 200,
              maxHeight: MediaQuery.of(context).size.height * 0.5,
            ),
            child: ItemsTableWidget(
              items: _hasChanges ? _updatedSellItems : _sellItems,
              hasChanges: _hasChanges,
              isLocked: _isLocked,
            ),
          ),
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
        title: 'فاتورة #${getSafeString(_currentBill['Bill'])}',
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
          if ((_hasChanges ||
                  _paiedAmount != _initialPaiedAmount ||
                  _discount != _initialDiscount) &&
              !_isLocked &&
              !_isBusy)
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
      bottomNavigationBar:
          ((_hasChanges ||
                  _paiedAmount != _initialPaiedAmount ||
                  _discount != _initialDiscount) &&
              !_isLocked)
          ? _buildSaveButton()
          : null,
    );
  }
}
