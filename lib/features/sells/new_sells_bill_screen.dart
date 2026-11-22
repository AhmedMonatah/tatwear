import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../utils/app_colors.dart';
import '../../../utils/app_styles.dart';
import '../../utils/snackbars.dart';
import '../../widgets/shared/responsive_container.dart';
import '../../widgets/shared/responsive_button.dart';
import '../../../widgets/shared/autocomplete_field.dart';
import '../../../widgets/shared/custom_app_bar.dart';
import '../../../widgets/shared/custom_text_field.dart';
import '../../../widgets/shared/loading_overlay.dart';
import 'add_item_for_sells_screen.dart';
import '../../services/local_db_service.dart';
import '../../services/sync_service.dart';

class NewSellsBillScreen extends StatefulWidget {
  const NewSellsBillScreen({super.key});

  @override
  State<NewSellsBillScreen> createState() => _NewSellsBillScreenState();
}

class _NewSellsBillScreenState extends State<NewSellsBillScreen> {
  final LocalDbService _local = LocalDbService.instance;
  final SyncService _sync = SyncService.instance;

  List<Map<String, dynamic>> _clients = [];
  List<Map<String, dynamic>> _filteredClients = [];
  List<Map<String, dynamic>> _regions = [];
  Map<String, dynamic>? _selectedClient;
  int? _selectedRegionId;
  bool _loading = true;
  bool _isSaving = false;

  int? _billId;
  double _itemsTotal = 0.0;
  List<Map<String, dynamic>> _pendingSells = [];

  double _pastAccount = 0.0;
  double _discount = 0.0;
  double _paied = 0.0;
  bool _balanceLoading = false;
  bool _balanceFetchFailed = false;

  final TextEditingController _paiedController = TextEditingController();
  final TextEditingController _discountController = TextEditingController();

  UniqueKey _clientAutocompleteKey = UniqueKey();

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  @override
  void dispose() {
    _paiedController.dispose();
    _discountController.dispose();
    super.dispose();
  }

  //  Calculate all required values
  double get _netTotal {
    return _itemsTotal - _discount;
  }

  // Calculate GrandTotal = NetTotal + PastAccount
  double get _grandTotal {
    return _netTotal + _pastAccount;
  }

  double get _rest {
    return _grandTotal - _paied;
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

  //  Function to fetch client balance (الحساب السابق)
  Future<void> _fetchClientBalance(int clientId) async {
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
      final balance = await _sync.getClientBalance(clientId);
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
      final clients = await _local.getClients();
      final regions = await _local.readTable('Region');
      setState(() {
        _clients = clients;
        _filteredClients = clients;
        _regions = regions;
        _loading = false;
      });
    } catch (e) {
      showErrorSnackBar(context, 'خطأ في تحميل البيانات');
      setState(() => _loading = false);
    }
  }

  void _filterClients() {
    if (_selectedRegionId == null) {
      setState(() {
        _filteredClients = _clients;
        _clientAutocompleteKey = UniqueKey();
      });
    } else {
      setState(() {
        _filteredClients = _clients.where((client) {
          return client['RegionId']?.toString() == _selectedRegionId.toString();
        }).toList();
        _clientAutocompleteKey = UniqueKey();
      });
    }
  }

  Future<void> _createLocalBillIfNeeded() async {
    if (_billId != null) return;

    if (_selectedClient == null) {
      showErrorSnackBar(context, 'يرجى اختيار عميل');
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

    //  Pass all new fields to createLocalBill including GrandTotal
    final created = await _local.createLocalBill(
      theDate: theDate,
      clientId: (_selectedClient!['Id'] as int),
      branchId: branchId!,
      userId: userId!,
      total: _itemsTotal, // Bill total before discount
      paied: _paied,
      pastAccount: _pastAccount,
      netTotal: _netTotal, // Items total - discount
      discount: _discount,
      rest: _rest, // Final total (grand total - paid)
      grandTotal: _grandTotal, // NetTotal + PastAccount
    );

    setState(() => _billId = created['Id'] as int?);

    final localUuid = created['LocalUuid'] as String?;
    await _local.batchInsertSells(
      _pendingSells,
      _billId!,
      localUuid: localUuid,
    );
  }

  Future<void> _openAddItems() async {
    if (_selectedClient == null) {
      showErrorSnackBar(context, 'يرجى اختيار عميل أولاً');
      return;
    }

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddItemForSellsScreen(initialPendingSells: _pendingSells),
      ),
    );

    if (result is List<Map<String, dynamic>>) {
      setState(() {
        _pendingSells = result;
        _itemsTotal = _calculateBillTotal(result);
      });
    }
  }

  Future<void> _saveBill() async {
    if (_selectedClient == null) {
      showErrorSnackBar(context, 'يرجى اختيار عميل');
      return;
    }

    if (_pendingSells.isEmpty) {
      showErrorSnackBar(context, 'يرجى إضافة منتجات إلى السلة');
      return;
    }

    setState(() => _isSaving = true);

    try {
      await _createLocalBillIfNeeded();

      try {
        await _sync.syncPendingToServer();
        if (mounted) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(
            'last_action',
            DateTime.now().toIso8601String(),
          );
          showSuccessSnackBar(context, 'تم حفظ الفاتورة بنجاح');
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



  // 💡 NEW: Build responsive row for Paid and Discount fields
  Widget _buildPaymentFieldsRow() {
    return Row(
      children: [
        // Paid Field
        Expanded(
          child: CustomTextField(
            controller: _paiedController,
            label: 'المبلغ المدفوع',
            prefixIcon: Icons.payments,
            keyboardType: TextInputType.number,
            onChanged: (value) {
              final parsed = double.tryParse(value) ?? 0.0;
              setState(() => _paied = parsed);
            },
          ),
        ),
        SizedBox(width: AppStyles.verticalSpacing(context)),
        // Discount Field
        Expanded(
          child: CustomTextField(
            controller: _discountController,
            label: 'الخصم بالجنيه',
            prefixIcon: Icons.discount,
            keyboardType: TextInputType.number,
            onChanged: (value) {
              final parsed = double.tryParse(value) ?? 0.0;
              setState(() => _discount = parsed);
            },
          ),
        ),
      ],
    );
  }

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

            //  Show detailed calculation breakdown
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

                  // Final Total (Rest)
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
                            'الإجمالي النهائي: ',
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

            //  Client balance loading and error states
            if (_balanceLoading)
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Row(
                  children: [
                    Icon(Icons.refresh, size: 14, color: AppColors.secondary),
                    SizedBox(width: 4),
                    Text(
                      'جاري تحميل الحساب السابق...',
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
                      'تعذر تحميل الحساب السابق - لا يوجد اتصال',
                      style: AppStyles.bodySmall(
                        context,
                      ).copyWith(color: AppColors.error),
                    ),
                  ],
                ),
              ),

            if (_pendingSells.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(
                  '${_pendingSells.length} منتج',
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
      appBar: const CustomAppBar(title: 'فاتورة جديدة'),
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

                        // Region Field
                        AutocompleteField(
                          label: 'المنطقة',
                          options: _regions,
                          displayKey: 'Region',
                          onSelected: (region) {
                            setState(() {
                              _selectedRegionId = region['RegionId'] as int?;
                              _selectedClient = null;
                              // 💡 Reset balance when region changes
                              _pastAccount = 0.0;
                              _balanceFetchFailed = false;
                            });
                            _filterClients();
                          },
                          selectedValue: _selectedRegionId != null
                              ? _regions.firstWhere(
                                  (r) => r['RegionId'] == _selectedRegionId,
                                  orElse: () => {},
                                )
                              : null,
                          onClear: () {
                            setState(() {
                              _selectedRegionId = null;
                              _selectedClient = null;
                              // 💡 Reset balance when region is cleared
                              _pastAccount = 0.0;
                              _balanceFetchFailed = false;
                            });
                            _filterClients();
                          },
                          icon: Icons.map,
                        ),
                        SizedBox(height: AppStyles.verticalSpacing(context)),

                        // Client Field
                        AutocompleteField(
                          fieldKey: _clientAutocompleteKey,
                          label: 'العميل',
                          options: _filteredClients,
                          displayKey: 'Client',
                          onSelected: (client) {
                            setState(() => _selectedClient = client);
                            // 💡 Fetch client balance when client is selected
                            final clientId = client['Id'] as int;
                            _fetchClientBalance(clientId);
                          },
                          selectedValue: _selectedClient,
                          onClear: () {
                            setState(() {
                              _selectedClient = null;
                              // 💡 Reset balance when client is cleared
                              _pastAccount = 0.0;
                              _balanceFetchFailed = false;
                            });
                          },
                          icon: Icons.person,
                          required: true,
                        ),

                        SizedBox(height: AppStyles.verticalSpacing(context)),

                        //  Payment Fields Row (Paid + Discount)
                        _buildPaymentFieldsRow(),

                        SizedBox(
                          height: AppStyles.verticalSpacing(context) * 2,
                        ),

                        // Total Card (now includes all calculations)
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
                        if (_pendingSells.isNotEmpty)
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
          LoadingOverlay(
            isLoading: _isSaving,
            message: 'جاري حفظ الفاتورة...',
          ),
        ],
      ),
    );
  }
}
