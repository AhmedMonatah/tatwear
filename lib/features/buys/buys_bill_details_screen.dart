import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tatweer/features/buys/add_item_for_buys_screen.dart';
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
import '../../services/local_db_service.dart';
import '../../services/sync_service.dart';

enum ExportAction { print, share }

class BuysBillDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> bill;
  final bool internetAvailable;
  const BuysBillDetailsScreen({
    super.key,
    required this.bill,
    required this.internetAvailable,
  });

  @override
  State<BuysBillDetailsScreen> createState() => _BuysBillDetailsScreenState();
}

class _BuysBillDetailsScreenState extends State<BuysBillDetailsScreen> {
  final LocalDbService _localDbService = LocalDbService.instance;
  final SyncService _syncService = SyncService.instance;
  final PdfService _pdfService = PdfService();

  List<Map<String, dynamic>> _buyItems = [];
  List<Map<String, dynamic>> _updatedBuyItems = [];
  String _sellerName = 'جاري التحميل...';
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
    return _calculateBillTotal(_hasChanges ? _updatedBuyItems : _buyItems);
  }

  double get _netTotal {
    return _itemsTotal - _discount;
  }

  double get _grandTotal {
    return _netTotal + _pastAccountFromServer;
  }

  double get _rest {
    return _grandTotal - _paiedAmount;
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
      String type = item['Type'] ?? 'شراء';
      double itemTotal = (item['Total'] as double?) ?? 0.0;

      if (type == 'شراء') {
        total += itemTotal;
      } else if (type == 'ارتجاع') {
        total -= itemTotal;
      }
    }
    return total;
  }

  Future<void> _fetchSellerBalance(int sellerId) async {
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
      final balance = await _syncService.getSellerBalance(sellerId);
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
      await Future.wait([_loadSellerName(), _loadBuyItems()]);
      _checkLockStatus();

      _initialPaiedAmount = getSafeDouble(_currentBill['Paied'] ?? 0.0);
      _initialDiscount = getSafeDouble(_currentBill['Discount']);
      _initialItemsTotal = _calculateBillTotal(_buyItems);
      _initialBillRest =
          (_initialItemsTotal - _initialDiscount) - _initialPaiedAmount;

      _paiedAmount = _initialPaiedAmount;
      _discount = _initialDiscount;

      _discountController.text = _discount > 0
          ? _discount.toStringAsFixed(2)
          : '';
      _paiedController.text = _paiedAmount > 0
          ? _paiedAmount.toStringAsFixed(2)
          : '';

      final sellerId = _currentBill['SellerId'];
      if (sellerId != null && widget.internetAvailable && !_isLocked) {
        _fetchSellerBalance(sellerId);
      } else {
        setState(() {
          _balanceFetchFailed = !widget.internetAvailable || _isLocked;
          _balanceLoading = false;
        });
      }
    } catch (e) {
      setState(() => _error = 'خطأ في تحميل تفاصيل فاتورة الشراء');
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

  Future<void> _loadSellerName() async {
    try {
      final sellerId = _currentBill['SellerId'];
      if (sellerId == null) {
        setState(() => _sellerName = 'غير معروف');
        return;
      }

      final seller = await _localDbService.getSellerById(sellerId);
      setState(
        () => _sellerName = seller?['Seller']?.toString() ?? 'غير معروف',
      );
    } catch (e) {
      setState(() => _sellerName = 'غير معروف');
    }
  }

  Future<void> _loadBuyItems() async {
    try {
      final billId = _currentBill['Id'];
      if (billId == null) {
        setState(() => _buyItems = []);
        return;
      }

      final items = await _localDbService.getBuysItemsByBillId(billId);
      final enhancedItems = await _enhanceItemsWithNames(items);
      setState(() {
        _buyItems = enhancedItems;
        _updatedBuyItems = List.from(enhancedItems);
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
    final initialItems = _updatedBuyItems
        .map(
          (item) => {
            'ItemId': item['ItemId'],
            'Qty': item['Qty'],
            'Price': item['Price'],
            'Total': item['Total'],
            'QtyUnit': item['QtyUnit'] ?? 'صغرى',
            'Type': item['Type'] ?? 'شراء',
            'FirstPrice': item['FirstPrice'] ?? item['Price'],
            'ItemName': item['ItemName'],
          },
        )
        .toList();

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddItemForBuysScreen(
          billId: _currentBill['Id'] as int,
          initialPendingBuys: initialItems,
        ),
      ),
    );

    if (result is List<Map<String, dynamic>> && result.isNotEmpty) {
      setState(() {
        _updatedBuyItems = result;
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
      print("Paaaaaaaaaaied is $_paiedAmount");
      await _localDbService.updateBuysBillTotalAndLock(
        billId,
        newTotal,
        lock: _currentBill['Lock']?.toString(),
        discount: _discount,
        pastAccount: currentPastAccount,
        netTotal: newNetTotal,
        grandTotal: newGrandTotal,
        paied: _paiedAmount,
        rest: newBillRest,
      );

      if (hasItemsChanged) {
        await _localDbService.replaceBuysItems(billId, _updatedBuyItems);
      }

      if (widget.internetAvailable) {
        try {
          await _syncService.updateBuysBillOnServer(
            billId,
            newTotal,
            hasItemsChanged ? _updatedBuyItems : _buyItems,
            lock: _currentBill['Lock']?.toString(),
            discount: _discount,
            pastAccount: currentPastAccount,
            netTotal: newNetTotal,
            grandTotal: newGrandTotal,
            paied: _paiedAmount,
            rest: newBillRest,
          );
          await _localDbService.markBuysBillAsSynced(billId);
          showSuccessSnackBar(
            context,
            'تم تحديث فاتورة الشراء على الخادم بنجاح',
          );

          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(
            'last_action',
            DateTime.now().toIso8601String(),
          );
          saveSuccessful = true;
        } catch (syncError) {
          await _localDbService.markBuysBillAsPendingSync(billId);
          showEnhancedOfflineSnackBar(context);
          saveSuccessful = true;
        }
      } else {
        await _localDbService.markBuysBillAsPendingSync(billId);
        showEnhancedOfflineSnackBar(context);
        saveSuccessful = true;
      }

      setState(() {
        _currentBill['Total'] = newTotal;
        _currentBill['Paied'] = _paiedAmount;
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
          _buyItems = List.from(_updatedBuyItems);
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
                  'طباعة فاتورة الشراء',
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
            'سيتم حفظ فاتورة الشراء وقفلها (لا يمكن تعديلها) قبل ${action == ExportAction.print ? 'الطباعة' : 'المشاركة'}. هل أنت متأكد؟',
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
        _busyMessage = 'جاري حفظ وقفل فاتورة الشراء...';
      });

      bool saveSuccessful = false;

      try {
        final billId = _currentBill['Id'] as int;
        final newTotal = _itemsTotal;
        final newNetTotal = _netTotal;
        final currentPastAccount = getSafeDouble(_currentBill['PastAccount']);
        final newBillRest = _billRest;
        final newGrandTotal = newNetTotal + currentPastAccount;

        await _localDbService.updateBuysBillTotalAndLock(
          billId,
          newTotal,
          lock: 'Lock',
          discount: _discount,
          pastAccount: currentPastAccount,
          netTotal: newNetTotal,
          grandTotal: newGrandTotal,
          paied: _paiedAmount,
          rest: newBillRest,
        );

        if (_hasChanges) {
          await _localDbService.replaceBuysItems(billId, _updatedBuyItems);
        }

        if (widget.internetAvailable) {
          try {
            await _syncService.updateBuysBillOnServer(
              billId,
              newTotal,
              _hasChanges ? _updatedBuyItems : _buyItems,
              lock: 'Lock',
              discount: _discount,
              pastAccount: currentPastAccount,
              netTotal: newNetTotal,
              grandTotal: newGrandTotal,
              paied: _paiedAmount,
              rest: newBillRest,
            );
            await _localDbService.markBuysBillAsSynced(billId);
            showSuccessSnackBar(
              context,
              'تم حفظ فاتورة الشراء على الخادم بنجاح',
            );
            saveSuccessful = true;
          } catch (syncError) {
            await _localDbService.markBuysBillAsPendingSync(billId);
            showEnhancedOfflineSnackBar(context);
            saveSuccessful = true;
          }
        } else {
          await _localDbService.markBuysBillAsPendingSync(billId);
          showEnhancedOfflineSnackBar(context);
          saveSuccessful = true;
        }

        setState(() {
          _currentBill['Total'] = newTotal;
          _currentBill['Paied'] = _paiedAmount;
          _currentBill['Discount'] = _discount;
          _currentBill['NetTotal'] = newNetTotal;
          _currentBill['GrandTotal'] = newGrandTotal;
          _currentBill['Rest'] = newBillRest;
          _currentBill['Lock'] = 'Lock';

          _initialPaiedAmount = _paiedAmount;
          _initialDiscount = _discount;
          _initialItemsTotal = newTotal;
          _initialBillRest = _rest;

          if (_hasChanges) {
            _buyItems = List.from(_updatedBuyItems);
          }
          _hasChanges = false;
          _isLocked = true;
        });

        await _generateAndProcessPdf(action);

        showSuccessSnackBar(
          context,
          'تم حفظ وقفل فاتورة الشراء و${action == ExportAction.print ? 'طباعتها' : 'مشاركتها'} بنجاح',
        );

        if (action != ExportAction.print && saveSuccessful && mounted) {
          await Future.delayed(const Duration(milliseconds: 1000));
          Navigator.pop(context, true);
        }
      } catch (e) {
        showErrorSnackBar(context, 'حدث خطأ أثناء حفظ وقفل فاتورة الشراء: $e');
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
          'تم ${action == ExportAction.print ? 'طباعة' : 'مشاركة'} فاتورة الشراء بنجاح',
        );

        if (action != ExportAction.print && mounted) {
          await Future.delayed(const Duration(milliseconds: 1000));
          Navigator.pop(context, true);
        }
      } catch (e) {
        showErrorSnackBar(
          context,
          'حدث خطأ أثناء ${action == ExportAction.print ? 'طباعة' : 'مشاركة'} فاتورة الشراء: $e',
        );
      }
    }
  }

  Future<void> _generateAndProcessPdf(ExportAction action) async {
    setState(() {
      _isBusy = true;
      _busyMessage =
          'جاري تجهيز فاتورة الشراء ${action == ExportAction.print ? 'للطباعة' : 'للمشاركة'}...';
    });

    try {
      final itemsToExport = _hasChanges ? _updatedBuyItems : _buyItems;

      final Uint8List pdfData = await _pdfService.generateBuysBillPdf(
        _currentBill,
        itemsToExport,
        _sellerName,
        _itemsTotal,
        _paiedAmount,
        discount: _discount,
        netTotal: _netTotal,
        pastAccount: _pastAccountFromServer,
        billRest: _billRest,
        totalRest: _totalRest,
        hasInternet: widget.internetAvailable && !_balanceFetchFailed,
      );

      final billNumber = _currentBill['Bill'] ?? 'محلية';
      final pdfName = 'فاتورة_شراء_$billNumber.pdf';

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
          'جاري تحميل تفاصيل فاتورة الشراء...',
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
            customerLabel: 'المورد',
            customerName: _sellerName,
            regionName: null,
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
              items: _hasChanges ? _updatedBuyItems : _buyItems,
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
            offset: const Offset(0, -2),
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
      appBar: AppBar(
        title: Text(
          'فاتورة #${getSafeString(_currentBill['Bill'])}',
          style: AppStyles.heading2(
            context,
          ).copyWith(color: AppColors.onPrimary),
        ),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
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
