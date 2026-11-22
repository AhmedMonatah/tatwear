import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../services/pdf_service.dart';
import '../../../services/printing/printer_selector_dialog.dart';
import '../../../utils/app_colors.dart';
import '../../../utils/app_styles.dart';
import '../../../utils/helpers.dart';
import '../../utils/snackbars.dart';
import '../../widgets/shared/responsive_button.dart';
import '../../../widgets/shared/loading_overlay.dart';
import '../../../widgets/shared/custom_app_bar.dart';
import '../../services/local_db_service.dart';
import '../../services/sync_service.dart';
import '../../../widgets/collection/collection_header.dart';

enum ExportAction { print, share }

class CollectionDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> collection;
  final bool internetAvailable;

  const CollectionDetailsScreen({
    super.key,
    required this.collection,
    required this.internetAvailable,
  });

  @override
  State<CollectionDetailsScreen> createState() =>
      _CollectionDetailsScreenState();
}

class _CollectionDetailsScreenState extends State<CollectionDetailsScreen> {
  final LocalDbService _localDbService = LocalDbService.instance;
  final SyncService _syncService = SyncService.instance;
  final PdfService _pdfService = PdfService();

  bool _loading = true;
  bool _isBusy = false;
  String _busyMessage = '';
  bool _hasChanges = false;
  String _error = '';
  bool _isLocked = false;

  // Editable fields
  double _amount = 0.0;
  String _notes = '';
  String _regionName = 'جاري التحميل...';

  // Track current collection data
  Map<String, dynamic> _currentCollection = {};

  // Text editing controllers
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  // Scroll controller for responsive scrolling

  @override
  void initState() {
    super.initState();
    _currentCollection = Map.from(widget.collection);
    _loadCollectionDetails();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadCollectionDetails() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      await Future.wait([_loadRegionName(), _loadCollectionData()]);
      _checkLockStatus();

      // Initialize values from collection
      _amount = getSafeDouble(_currentCollection['Amount']);
      _notes = getSafeString(_currentCollection['Notes'], '');

      // Initialize text controllers
      _amountController.text = _amount.toStringAsFixed(2);
      _notesController.text = _notes;
    } catch (e) {
      setState(() => _error = 'خطأ في تحميل تفاصيل فاتورة التحصيل');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _checkLockStatus() {
    final lockValue = _currentCollection['Lock']?.toString();
    setState(() {
      _isLocked = lockValue == 'Lock';
    });
  }

  Future<void> _loadRegionName() async {
    try {
      final clientId = _currentCollection['ClientId'];
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

  Future<void> _loadCollectionData() async {
    try {
      final collectionId = _currentCollection['Id'];
      if (collectionId != null) {
        final collection = await _localDbService.getCollectionById(
          collectionId,
        );
        if (collection != null) {
          setState(() {
            _currentCollection = {..._currentCollection, ...collection};
          });
        }
      }
    } catch (e) {
      print('Error loading collection data: $e');
    }
  }

  // Handle amount changes
  void _onAmountChanged(String value) {
    final newAmount = double.tryParse(value) ?? 0.0;
    setState(() {
      _amount = newAmount;
      _hasChanges =
          _amount != getSafeDouble(_currentCollection['Amount']) ||
          _notes != getSafeString(_currentCollection['Notes'], '');
    });
  }

  // Handle notes changes
  void _onNotesChanged(String value) {
    setState(() {
      _notes = value;
      _hasChanges =
          _amount != getSafeDouble(_currentCollection['Amount']) ||
          _notes != getSafeString(_currentCollection['Notes'], '');
    });
  }

    // Validate amount before saving - UPDATED with better validation
    bool _validateAmount() {
      if (_amount == 0.0 || _amount <= 0) {
        showErrorSnackBar(context, 'يجب إدخال مبلغ أكبر من الصفر');
        return false;
      }
      return true;
    }

  Future<void> _saveCollectionUpdates() async {
    // ✅ ADDED: Validate amount before proceeding
    if (!_validateAmount()) {
      return;
    }

    // Check if any values have changed
    final bool hasAmountChanged =
        _amount != getSafeDouble(_currentCollection['Amount']);
    final bool hasNotesChanged =
        _notes != getSafeString(_currentCollection['Notes'], '');

    if (!hasAmountChanged && !hasNotesChanged) {
      showInfoSnackBar(context, 'لا توجد تغييرات لحفظها');
      return;
    }

    setState(() {
      _isBusy = true;
      _busyMessage = 'جاري حفظ التغييرات...';
    });

    bool saveSuccessful = false;

    try {
      final collectionId = _currentCollection['Id'] as int;

      // Local DB UPDATE
      await _localDbService.updateCollection(collectionId, _amount, _notes);

      // SERVER SYNC
      if (widget.internetAvailable) {
        try {
          await _syncService.updateCollectionOnServer(
            collectionId,
            _amount,
            _notes,
          );

          await _localDbService.markCollectionAsSynced(collectionId);
          showSuccessSnackBar(context, 'تم تحديث فاتورة التحصيل على الخادم بنجاح');
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(
            'last_action',
            DateTime.now().toIso8601String(),
          );
          saveSuccessful = true;
        } catch (syncError) {
          // Still successful locally
          await _localDbService.markCollectionAsPendingSync(collectionId);
          showEnhancedOfflineSnackBar(context);
          saveSuccessful = true;
        }
      } else {
        // Offline — save locally and mark pending sync
        await _localDbService.markCollectionAsPendingSync(collectionId);
        showEnhancedOfflineSnackBar(context);
        saveSuccessful = true;
      }

      // Update the local UI state immediately
      setState(() {
        _currentCollection['Amount'] = _amount;
        _currentCollection['Notes'] = _notes;

        _hasChanges = false;
      });

      // Navigate back if saving was successful
      if (saveSuccessful && mounted) {
        await Future.delayed(const Duration(milliseconds: 1000));
        Navigator.pop(context, true);
      }
    } catch (e) {
      showErrorSnackBar(context, 'حدث خطأ أثناء حفظ التحديثات: $e');
    } finally {
      // Do NOT stop busy if navigating away
      if (mounted && !saveSuccessful) {
        setState(() {
          _isBusy = false;
          _busyMessage = '';
        });
      }
    }
  }

  /// Export functionality
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
                  'طباعة فاتورة التحصيل',
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
    // ✅ ADDED: Validate amount before export
    if (!_validateAmount()) {
      return;
    }

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
            'سيتم حفظ فاتورة التحصيل وقفله (لا يمكن تعديله) قبل ${action == ExportAction.print ? 'الطباعة' : 'المشاركة'}. هل أنت متأكد؟',
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
        _busyMessage = 'جاري حفظ وقفل فاتورة التحصيل...';
      });

      try {
        final collectionId = _currentCollection['Id'] as int;

        // Update local DB with 'Lock'
        await _localDbService.updateCollectionAmountAndLock(
          collectionId,
          _amount,
          'Lock',
        );

        // Try to sync with server
        if (widget.internetAvailable) {
          try {
            await _syncService.updateCollectionOnServer(
              collectionId,
              _amount,
              _notes,
              lock: 'Lock',
            );
            await _localDbService.markCollectionAsSynced(collectionId);
            showSuccessSnackBar(context, 'تم حفظ فاتورة التحصيل على الخادم بنجاح');
          } catch (syncError) {
            await _localDbService.markCollectionAsPendingSync(collectionId);
            showEnhancedOfflineSnackBar(context);
          }
        } else {
          await _localDbService.markCollectionAsPendingSync(collectionId);
          showEnhancedOfflineSnackBar(context);
        }

        // Update local state immediately
        setState(() {
          _currentCollection['Amount'] = _amount;
          _currentCollection['Notes'] = _notes;
          _currentCollection['Lock'] = 'Lock';
          _hasChanges = false;
          _isLocked = true;
        });

        await _generateAndProcessPdf(action);

        // Show success message
        showSuccessSnackBar(context, 'تم حفظ وقفل فاتورة التحصيل بنجاح');

        // Navigate back to Collections screen only if NOT printing
        if (action != ExportAction.print && mounted) {
          await Future.delayed(const Duration(milliseconds: 1000));
          Navigator.pop(context, true); // Pass true to indicate update
        }
      } catch (e) {
        showErrorSnackBar(context, 'حدث خطأ أثناء حفظ وقفل فاتورة التحصيل: $e');
        if (mounted) {
          setState(() {
            _isBusy = false;
            _busyMessage = '';
          });
        }
      }
    } else {
      await _generateAndProcessPdf(action);
    }
  }

  Future<void> _generateAndProcessPdf(ExportAction action) async {
    setState(() {
      _isBusy = true;
      _busyMessage =
          'جاري تجهيز فاتورة التحصيل ${action == ExportAction.print ? 'للطباعة' : 'للمشاركة'}...';
    });

    try {
      final Uint8List pdfData = await _pdfService.generateCollectionPdf(
        _currentCollection,
        _regionName,
        _amount,
        _notes,
      );

      final pdfName =
          'فاتورة_تحصيل_${_currentCollection['Bill'] ?? 'محلية'}.pdf';

      if (action == ExportAction.print) {
        if (!mounted) return;
        setState(() { _isBusy = false; _busyMessage = ''; });
        await showPrintOptions(
          context,
          pdfBytes: pdfData,
          pdfName: pdfName,
        );
        showSuccessSnackBar(context, 'تم تجهيز فاتورة التحصيل بنجاح');
        return;
      } else {
        await Printing.sharePdf(bytes: pdfData, filename: pdfName);
      }

      showSuccessSnackBar(context, 'تم تجهيز فاتورة التحصيل بنجاح');
    } catch (e) {
      showErrorSnackBar(context, 'حدث خطأ أثناء تجهيز فاتورة التحصيل: ${e.toString()}');
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
          'جاري تحميل تفاصيل فاتورة التحصيل...',
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
          onPressed: _loadCollectionDetails,
        ),
      ],
    ),
  );

  Widget _buildContent() {
    return SingleChildScrollView(
      padding: AppStyles.screenPadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header section
          CollectionHeaderWidget(
            collection: _currentCollection,
            regionName: _regionName,
            hasChanges: _hasChanges,
            isLocked: _isLocked,
            amount: _amount,
            amountController: _amountController,
            onAmountChanged: _onAmountChanged,
            notes: _notes,
            notesController: _notesController,
            onNotesChanged: _onNotesChanged,
          ),

          // Add some bottom padding to ensure content is not hidden by the save button
          SizedBox(height: MediaQuery.of(context).padding.bottom + 80),
        ],
      ),
    );
  }

  Widget _buildSaveButton() {
    return Container(
      padding: EdgeInsets.only(
        left: AppStyles.screenPadding(context).left,
        right: AppStyles.screenPadding(context).right,
        bottom: MediaQuery.of(context).padding.bottom + 16,
        top: 16,
      ),
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
        onPressed: _isBusy || _isLocked ? () {} : _saveCollectionUpdates,
        isLoading: _isBusy,
        backgroundColor: AppColors.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(
        title: 'فاتورة تحصيل #${getSafeString(_currentCollection['Bill'])}',
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
                'طباعة التحصيل',
                style: AppStyles.bodyMedium(
                  context,
                ).copyWith(color: AppColors.onPrimary),
              ),
              onPressed: _isBusy ? null : () => _showExportOptions(),
              style: TextButton.styleFrom(backgroundColor: AppColors.error),
            ),
          ),
          if (_hasChanges && !_isLocked && !_isBusy)
            IconButton(
              icon: Icon(Icons.save, size: AppStyles.iconSize(context)),
              onPressed: () => _saveCollectionUpdates(),
              tooltip: 'حفظ التغييرات',
            ),
        ],
      ),
      body: Stack(
        children: [
          // Main content with scrollable behavior
          _loading
              ? _buildLoading()
              : _error.isNotEmpty
              ? _buildError()
              : _buildContent(),

          // Busy overlay
          LoadingOverlay(
            message: _busyMessage,
            isLoading: _isBusy,
          ),
        ],
      ),
      bottomNavigationBar: (_hasChanges && !_isLocked)
          ? _buildSaveButton()
          : null,
    );
  }
}
