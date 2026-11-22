import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tatweer/features/buys/add_item_for_buys_screen.dart';
import '../../../utils/app_colors.dart';
import '../../../utils/app_styles.dart';
import '../../utils/snackbars.dart';
import '../../widgets/shared/responsive_container.dart';
import '../../widgets/shared/responsive_button.dart';
import '../../../widgets/shared/autocomplete_field.dart';
import '../../services/local_db_service.dart';
import '../../services/sync_service.dart';

class NewBuysBillScreen extends StatefulWidget {
  const NewBuysBillScreen({super.key});

  @override
  State<NewBuysBillScreen> createState() => _NewBuysBillScreenState();
}

class _NewBuysBillScreenState extends State<NewBuysBillScreen> {
  final LocalDbService _local = LocalDbService.instance;
  final SyncService _sync = SyncService.instance;

  List<Map<String, dynamic>> _sellers = [];
  Map<String, dynamic>? _selectedSeller;
  bool _loading = true;
  bool _isSaving = false;

  int? _billId;
  double _itemsTotal = 0.0;
  List<Map<String, dynamic>> _pendingBuys = [];

  // ADDED: Paied field to match NewSellsBillScreen
  double _pastAccount = 0.0;
  double _discount = 0.0;
  double _paied = 0.0; // ADDED: Paied field
  bool _balanceLoading = false;
  bool _balanceFetchFailed = false;

  // ADDED: Controller for Paied field
  final TextEditingController _paiedController = TextEditingController();
  final TextEditingController _discountController = TextEditingController();
  final UniqueKey _sellerAutocompleteKey = UniqueKey();

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  @override
  void dispose() {
    // ADDED: Dispose paied controller
    _paiedController.dispose();
    _discountController.dispose();
    super.dispose();
  }

  // UPDATED: Added _paied to calculations
  double get _netTotal {
    return _itemsTotal - _discount;
  }

  double get _grandTotal {
    return _netTotal + _pastAccount;
  }

  // UPDATED: Now includes _paied like in sells screen
  double get _rest {
    return _grandTotal - _paied;
  }

  double _calculateBillTotal(List<Map<String, dynamic>> items) {
    double total = 0.0;
    for (var item in items) {
      double itemTotal = (item['Total'] as double?) ?? 0.0;
      total += itemTotal;
    }
    return total;
  }

  // Fetch seller balance
  Future<void> _fetchSellerBalance(int sellerId) async {
    if (!_sync.isConnected) {
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
      final balance = await _sync.getSellerBalance(sellerId);
      setState(() {
        _pastAccount = balance ?? 0.0;
        _balanceLoading = false;
        _balanceFetchFailed = false;
      });
    } catch (e) {
      setState(() {
        _balanceFetchFailed = true;
        _balanceLoading = false;
        _pastAccount = 0.0;
      });
    }
  }

  Future<void> _loadInitial() async {
    try {
      final sellers = await _local.getSellers();
      setState(() {
        _sellers = sellers;
        _loading = false;
      });
    } catch (e) {
      showErrorSnackBar(context, 'خطأ في تحميل بيانات الموردين');
      setState(() => _loading = false);
    }
  }

  Future<void> _createLocalBuysBillIfNeeded() async {
    if (_billId != null) return;

    if (_selectedSeller == null) {
      showErrorSnackBar(context, 'يرجى اختيار مورد');
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('user_id');
    final branchId = prefs.getInt('branch_id');

    final now = DateTime.now();
    final theDate = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute,
      now.second,
    );


    final created = await _local.createLocalBuysBill(
      theDate: theDate,
      sellerId: (_selectedSeller!['Id'] as int),
      branchId: branchId!,
      userId: userId!,
      total: _itemsTotal,
      paied: _paied, // ADDED: Pass paied field
      pastAccount: _pastAccount,
      netTotal: _netTotal,
      discount: _discount,
      rest: _rest, 
      grandTotal: _grandTotal,
    );

    setState(() => _billId = created['Id'] as int?);

    final localUuid = created['LocalUuid'] as String?;
    await _local.batchInsertBuys(_pendingBuys, _billId!, localUuid: localUuid);
  }

  Future<void> _openAddItems() async {
    if (_selectedSeller == null) {
      showErrorSnackBar(context, 'يرجى اختيار مورد أولاً');
      return;
    }

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddItemForBuysScreen(initialPendingBuys: _pendingBuys),
      ),
    );

    if (result is List<Map<String, dynamic>>) {
      setState(() {
        _pendingBuys = result;
        _itemsTotal = _calculateBillTotal(result);
      });
    }
  }

  Future<void> _saveBill() async {
    if (_selectedSeller == null) {
      showErrorSnackBar(context, 'يرجى اختيار مورد');
      return;
    }

    if (_pendingBuys.isEmpty) {
      showErrorSnackBar(context, 'يرجى إضافة منتجات إلى السلة');
      return;
    }

    setState(() => _isSaving = true);

    try {
      await _createLocalBuysBillIfNeeded();

      try {
        await _sync.syncPendingBuysToServer();
        if (mounted) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(
            'last_action',
            DateTime.now().toIso8601String(),
          );
          showSuccessSnackBar(context, 'تم حفظ فاتورة الشراء بنجاح');
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
      showErrorSnackBar(context, 'حدث خطأ أثناء حفظ فاتورة الشراء');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // UPDATED: Now includes Paied field exactly like in sells screen
  Widget _buildPaymentFieldsRow() {
    return Row(
      children: [
        // Paid Field - ADDED: Exactly like in sells screen
        Expanded(
          child: TextFormField(
            controller: _paiedController,
            keyboardType: TextInputType.number,
            decoration: AppStyles.textFieldDecoration('المبلغ المدفوع', context)
                .copyWith(
                  prefixIcon: Icon(
                    Icons.payments,
                    size: AppStyles.iconSize(context),
                  ),
                ),
            onChanged: (value) {
              final parsed = double.tryParse(value) ?? 0.0;
              setState(() => _paied = parsed);
            },
          ),
        ),
        SizedBox(width: AppStyles.verticalSpacing(context)),
        // Discount Field
        Expanded(
          child: TextFormField(
            controller: _discountController,
            keyboardType: TextInputType.number,
            decoration: AppStyles.textFieldDecoration('الخصم بالجنيه', context)
                .copyWith(
                  prefixIcon: Icon(
                    Icons.discount,
                    size: AppStyles.iconSize(context),
                  ),
                ),
            onChanged: (value) {
              final parsed = double.tryParse(value) ?? 0.0;
              setState(() => _discount = parsed);
            },
          ),
        ),
      ],
    );
  }

  // UPDATED: Total card exactly like in sells screen
  Widget _buildTotalCard() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: EdgeInsets.all(MediaQuery.of(context).size.width * 0.02),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('إجمالي الفاتورة', style: AppStyles.heading2(context)),
            SizedBox(height: AppStyles.verticalSpacing(context) / 2),
            Text(
              _itemsTotal.toStringAsFixed(2),
              style: AppStyles.heading1(
                context,
              ).copyWith(color: AppColors.primary),
            ),

            // UPDATED: Same breakdown as sells screen
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Bill total before discount
                  Row(
                    children: [
                      Text(
                        'إجمالي الفاتورة قبل الخصم: ',
                        style: AppStyles.bodySmall(context),
                      ),
                      Text(
                        _itemsTotal.toStringAsFixed(2),
                        style: AppStyles.bodySmall(context),
                      ),
                    ],
                  ),

                  // Discount
                  if (_discount > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Row(
                        children: [
                          Text('الخصم: ', style: AppStyles.bodySmall(context)),
                          Text(
                            _discount.toStringAsFixed(2) + " ج.م",
                            style: AppStyles.bodySmall(
                              context,
                            ).copyWith(color: AppColors.success),
                          ),
                        ],
                      ),
                    ),

                  // Net Total (after discount)
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Row(
                      children: [
                        Text(
                          "الفاتورة بعد الخصم: ",
                          style: AppStyles.bodySmall(
                            context,
                          ).copyWith(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          _netTotal.toStringAsFixed(2),
                          style: AppStyles.bodySmall(
                            context,
                          ).copyWith(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),

                  // Past Account
                  if (_pastAccount != 0.0)
                    Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Row(
                        children: [
                          Text(
                            'الحساب السابق: ',
                            style: AppStyles.bodySmall(context),
                          ),
                          Text(
                            _pastAccount.toStringAsFixed(2),
                            style: AppStyles.bodySmall(context),
                          ),
                        ],
                      ),
                    ),

                  // Final Total (Rest) - UPDATED: Exactly like sells screen
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Container(
                      padding: EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'الإجمالي النهائي: ', // SAME TEXT as sells screen
                            style: AppStyles.bodyMedium(context).copyWith(
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                          Text(
                            _rest.toStringAsFixed(2),
                            style: AppStyles.heading2(
                              context,
                            ).copyWith(color: AppColors.primary),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Seller balance loading and error states
            if (_balanceLoading)
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Row(
                  children: [
                    Icon(Icons.refresh, size: 14, color: AppColors.secondary),
                    SizedBox(width: 4),
                    Text(
                      'جاري تحميل الحساب السابق...', // SAME TEXT as sells screen
                      style: AppStyles.bodySmall(
                        context,
                      ).copyWith(color: AppColors.secondary),
                    ),
                  ],
                ),
              ),

            if (_balanceFetchFailed)
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Row(
                  children: [
                    Icon(Icons.wifi_off, size: 14, color: AppColors.error),
                    SizedBox(width: 4),
                    Text(
                      'تعذر تحميل الحساب السابق - لا يوجد اتصال', // SAME TEXT as sells screen
                      style: AppStyles.bodySmall(
                        context,
                      ).copyWith(color: AppColors.error),
                    ),
                  ],
                ),
              ),

            if (_pendingBuys.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(
                  '${_pendingBuys.length} منتج',
                  style: AppStyles.bodySmall(
                    context,
                  ).copyWith(color: AppColors.secondary),
                ),
              ),
          ],
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
      appBar: AppBar(
        title: Text(
          'فاتورة شراء جديدة',
          style: AppStyles.heading2(
            context,
          ).copyWith(color: AppColors.onPrimary),
        ),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
      ),
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
                        TextFormField(
                          initialValue: dateFormat,
                          readOnly: true,
                          decoration:
                              AppStyles.textFieldDecoration(
                                'التاريخ',
                                context,
                              ).copyWith(
                                prefixIcon: Icon(
                                  Icons.date_range,
                                  size: AppStyles.iconSize(context),
                                ),
                              ),
                        ),
                        SizedBox(height: AppStyles.verticalSpacing(context)),

                        // Seller Field
                        AutocompleteField(
                          fieldKey: _sellerAutocompleteKey,
                          label: 'المورد',
                          options: _sellers,
                          displayKey: 'Seller',
                          onSelected: (seller) {
                            setState(() => _selectedSeller = seller);
                            final sellerId = seller['Id'] as int;
                            _fetchSellerBalance(sellerId);
                          },
                          selectedValue: _selectedSeller,
                          onClear: () {
                            setState(() {
                              _selectedSeller = null;
                              _pastAccount = 0.0;
                              _balanceFetchFailed = false;
                            });
                          },
                          icon: Icons.person,
                          required: true,
                        ),

                        SizedBox(height: AppStyles.verticalSpacing(context)),

                        // UPDATED: Payment Fields Row (now includes Paied field)
                        _buildPaymentFieldsRow(),

                        SizedBox(
                          height: AppStyles.verticalSpacing(context) * 2,
                        ),

                        // Total Card (now exactly like sells screen)
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
                          height: AppStyles.verticalSpacing(context) * 2,
                        ),

                        // Save Bill Button
                        if (_pendingBuys.isNotEmpty)
                          ResponsiveButton(
                            text: 'حفظ فاتورة الشراء',
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
          if (_isSaving)
            Container(
              color: Colors.black54,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: AppColors.onPrimary),
                    SizedBox(height: AppStyles.verticalSpacing(context)),
                    Text(
                      'جاري حفظ فاتورة الشراء...',
                      style: TextStyle(
                        color: AppColors.onPrimary,
                        fontSize: AppStyles.bodyLarge(context).fontSize,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}