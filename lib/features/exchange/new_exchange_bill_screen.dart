import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tatweer/features/exchange/add_item_for_exchange_screen.dart';
import '../../../utils/app_colors.dart';
import '../../../utils/app_styles.dart';
import '../../utils/snackbars.dart';
import '../../widgets/shared/responsive_container.dart';
import '../../widgets/shared/responsive_button.dart';
import '../../../widgets/shared/autocomplete_field.dart';
import '../../../widgets/shared/custom_app_bar.dart';
import '../../../widgets/shared/custom_text_field.dart';
import '../../../widgets/shared/loading_overlay.dart';
import '../../services/local_db_service.dart';
import '../../services/sync_service.dart';

class NewExchangeBillScreen extends StatefulWidget {
  const NewExchangeBillScreen({super.key});

  @override
  State<NewExchangeBillScreen> createState() => _NewExchangeBillScreenState();
}

class _NewExchangeBillScreenState extends State<NewExchangeBillScreen> {
  final LocalDbService _local = LocalDbService.instance;
  final SyncService _sync = SyncService.instance;

  List<Map<String, dynamic>> _branches = [];
  Map<String, dynamic>? _selectedToBranch;
  Map<String, dynamic>? _currentBranch;
  bool _loading = true;
  bool _isSaving = false;

  int? _billId;
  double _itemsTotal = 0.0;
  List<Map<String, dynamic>> _pendingExchangeItems = [];

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  @override
  void dispose() {
    super.dispose();
  }

  double _calculateItemsTotal(List<Map<String, dynamic>> items) {
    double total = 0.0;
    for (var item in items) {
      total += (item['Total'] as double?) ?? 0.0;
    }
    return total;
  }

  Future<void> _loadInitial() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentBranchId = prefs.getInt('branch_id');

      // Get all branches from local DB
      final allBranches = await _local.getBranches();

      // Find current branch (using getBranchById if needed)
      _currentBranch = await _local.getBranchById(currentBranchId);

      // Filter out current branch for "to branch" list
      setState(() {
        _branches = allBranches
            .where((b) => b['Id'] != currentBranchId)
            .toList();
        _loading = false;
      });
    } catch (e) {
      showErrorSnackBar(context, 'خطأ في تحميل الفروع');
      setState(() => _loading = false);
    }
  }

  Future<void> _createLocalBillIfNeeded() async {
    if (_billId != null) return;

    if (_selectedToBranch == null) {
      showErrorSnackBar(context, 'يرجى اختيار الفرع المستلم');
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('user_id');
    final currentBranchId = prefs.getInt('branch_id');

    final now = DateTime.now();
    final theDate = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute,
      now.second,
    );

    // Create local exchange bill
    final created = await _local.createLocalExchangeBill(
      theDate: theDate,
      userId: userId!,
      branchId: currentBranchId!,
      destBranchId: _selectedToBranch!['Id'] as int,
      total: _itemsTotal,
    );

    setState(() => _billId = created['Id'] as int?);

    final localUuid = created['LocalUuid'] as String?;
    await _local.batchInsertExchange(
      _pendingExchangeItems,
      _billId!,
      localUuid: localUuid,
    );
  }

  Future<void> _openAddItems() async {
    if (_selectedToBranch == null) {
      showErrorSnackBar(context, 'يرجى اختيار الفرع المستلم أولاً');
      return;
    }

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddItemForExchangeScreen(
          initialPendingItems: _pendingExchangeItems,
          sourceBranchId: _currentBranch!['Id'] as int,
          destBranchId: _selectedToBranch!['Id'] as int,
        ),
      ),
    );

    if (result is List<Map<String, dynamic>>) {
      setState(() {
        _pendingExchangeItems = result;
        _itemsTotal = _calculateItemsTotal(result);
      });
    }
  }

  Future<void> _saveBill() async {
    if (_selectedToBranch == null) {
      showErrorSnackBar(context, 'يرجى اختيار الفرع المستلم');
      return;
    }

    if (_pendingExchangeItems.isEmpty) {
      showErrorSnackBar(context, 'يرجى إضافة منتجات إلى الفاتورة');
      return;
    }

    setState(() => _isSaving = true);

    try {
      await _createLocalBillIfNeeded();

      try {
        await _sync.syncPendingExchangeToServer();
        if (mounted) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(
            'last_action',
            DateTime.now().toIso8601String(),
          );
          showSuccessSnackBar(context, 'تم حفظ فاتورة التحويل بنجاح');
          Navigator.pop(context, true);
        }
      } catch (syncError) {
        if (mounted) {
          showEnhancedOfflineSnackBar(context);
          await Future.delayed(const Duration(seconds: 3));
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
      showErrorSnackBar(context, 'حدث خطأ أثناء حفظ الفاتورة');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _buildTotalCard() {
    return SizedBox(
      width: double.infinity,
      child: Card(
        elevation: 4,
        child: Padding(
          padding: EdgeInsets.all(MediaQuery.of(context).size.width * 0.02),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('إجمالي فاتورة التحويل', style: AppStyles.heading2(context)),
              SizedBox(height: AppStyles.verticalSpacing(context) / 2),
              Text(
                _itemsTotal.toStringAsFixed(2),
                style: AppStyles.heading1(
                  context,
                ).copyWith(color: AppColors.primary),
              ),

              if (_pendingExchangeItems.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: Text(
                    '${_pendingExchangeItems.length} منتج',
                    style: AppStyles.bodySmall(
                      context,
                    ).copyWith(color: AppColors.secondary),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final dateFormat =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';

    return Scaffold(
      appBar: const CustomAppBar(title: 'فاتورة تحويل جديدة'),
      body: Stack(
        children: [
          _loading
              ? const Center(child: CircularProgressIndicator())
              : ResponsiveContainer(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Date Field
                        CustomTextField(
                          controller: TextEditingController(text: dateFormat),
                          label: 'التاريخ',
                          prefixIcon: Icons.date_range,
                          readOnly: true,
                        ),
                        SizedBox(height: AppStyles.verticalSpacing(context)),

                        // From Branch (non-editable)
                        CustomTextField(
                          controller: TextEditingController(
                            text: _currentBranch != null
                                ? _currentBranch!['Name']?.toString() ?? ''
                                : '',
                          ),
                          label: 'من فرع',
                          prefixIcon: Icons.store,
                          readOnly: true,
                        ),
                        SizedBox(height: AppStyles.verticalSpacing(context)),

                        // To Branch (dropdown)
                        AutocompleteField(
                          label: 'إلى فرع',
                          options: _branches,
                          displayKey: 'Name',
                          onSelected: (branch) {
                            setState(() => _selectedToBranch = branch);
                          },
                          selectedValue: _selectedToBranch,
                          onClear: () {
                            setState(() => _selectedToBranch = null);
                          },
                          icon: Icons.store,
                          required: true,
                        ),

                        SizedBox(
                          height: AppStyles.verticalSpacing(context) * 1.5,
                        ),

                        // Total Card
                        _buildTotalCard(),

                        SizedBox(
                          height: AppStyles.verticalSpacing(context) * 2,
                        ),

                        // Add Products Button
                        ResponsiveButton(
                          text: 'إضافة منتجات',
                          icon: Icons.add,
                          onPressed: _openAddItems,
                          backgroundColor: AppColors.primary,
                        ),

                        SizedBox(
                          height: AppStyles.verticalSpacing(context) * 1.5,
                        ),

                        // Save Bill Button
                        if (_pendingExchangeItems.isNotEmpty)
                          ResponsiveButton(
                            text: 'حفظ الفاتورة',
                            icon: Icons.save,
                            onPressed: _saveBill,
                            backgroundColor: AppColors.success,
                          ),

                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.02,
                        ),
                      ],
                    ),
                  ),
                ),
          LoadingOverlay(isLoading: _isSaving, message: 'جاري حفظ الفاتورة...'),
        ],
      ),
    );
  }
}
