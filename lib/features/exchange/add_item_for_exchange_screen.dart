import 'package:flutter/material.dart';
import 'package:tatweer/features/sells/inventory_screen.dart';
import '../../../utils/app_colors.dart';
import '../../../utils/app_styles.dart';
import '../../utils/snackbars.dart';
import '../../widgets/shared/responsive_container.dart';
import '../../widgets/shared/responsive_button.dart';
import '../../../widgets/shared/autocomplete_field.dart';
import '../../../widgets/shared/custom_app_bar.dart';
import '../../../widgets/shared/custom_text_field.dart';
import '../../services/local_db_service.dart';

class AddItemForExchangeScreen extends StatefulWidget {
  final List<Map<String, dynamic>> initialPendingItems;
  final int sourceBranchId;
  final int destBranchId;

  const AddItemForExchangeScreen({
    super.key,
    required this.initialPendingItems,
    required this.sourceBranchId,
    required this.destBranchId,
  });

  @override
  State<AddItemForExchangeScreen> createState() =>
      _AddItemForExchangeScreenState();
}

class _AddItemForExchangeScreenState extends State<AddItemForExchangeScreen> {
  final LocalDbService _local = LocalDbService.instance;

  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _allItems = [];
  List<Map<String, dynamic>> _filteredItems = [];
  Map<String, dynamic>? _selectedCategory;
  Map<String, dynamic>? _selectedItem;
  int _qty = 1;
  String _selectedUnit = 'صغرى';
  double _price = 0.0;
  double _total = 0.0;
  bool _loading = true;
  List<Map<String, dynamic>> _pendingItems = [];

  UniqueKey _itemAutocompleteKey = UniqueKey();

  final TextEditingController _priceCtrl = TextEditingController();
  final TextEditingController _totalCtrl = TextEditingController();
  final TextEditingController _qtyCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _pendingItems = List.from(widget.initialPendingItems);
    _loadInitialData();
    _priceCtrl.text = _price.toStringAsFixed(2);
    _totalCtrl.text = _total.toStringAsFixed(2);
    _qtyCtrl.text = _qty.toString();
  }

  Future<void> _loadInitialData() async {
    try {
      final cats = await _local.getCategories();
      final allItems = await _local.getInventoryItemsByCategory(null);
      setState(() {
        _categories = cats;
        _allItems = allItems;
        _filteredItems = allItems;
        _loading = false;
      });
    } catch (e) {
      showErrorSnackBar(context, 'خطأ في تحميل البيانات');
      setState(() => _loading = false);
    }
  }

  void _filterItems() {
    if (_selectedCategory == null) {
      setState(() {
        _filteredItems = _allItems;
        _itemAutocompleteKey = UniqueKey();
      });
    } else {
      final categoryId = _selectedCategory!['Id'] as int?;
      if (categoryId != null) {
        setState(() {
          _filteredItems = _allItems.where((item) {
            return item['CategoryId']?.toString() == categoryId.toString();
          }).toList();
          _itemAutocompleteKey = UniqueKey();
        });
      }
    }
  }

  void _onItemSelected(Map<String, dynamic> item) {
    setState(() {
      _selectedItem = item;
    });
    _calculatePrice();
  }

  void _calculatePrice() {
    if (_selectedItem == null) {
      setState(() {
        _price = 0.0;
        _priceCtrl.text = _price.toStringAsFixed(2);
      });
      return;
    }

    final itemId = _selectedItem!['Id'] as int?;
    if (itemId == null) return;

    // Use selling price (تجزئة) – we don't have pricing toggle, so just use selling price based on unit
    // We'll mimic the original getInventoryItemPrice but force retail pricing
    _local
        .getInventoryItemPrice(itemId, 'تجزئة', _selectedUnit, isSelling: false)
        .then((price) {
          if (!mounted) return;
          setState(() {
            _price = price ?? 0.0;
            _priceCtrl.text = _price.toStringAsFixed(2);
          });
          _calculateTotal();
        });
  }

  void _calculateTotal() {
    setState(() {
      _total = _price * _qty;
      _totalCtrl.text = _total.toStringAsFixed(2);
    });
  }

  void _onUnitChanged(String? v) {
    setState(() => _selectedUnit = v ?? 'صغرى');
    _calculatePrice();
  }

  void _addToPending() {
    if (_selectedItem == null) {
      showErrorSnackBar(context, 'يرجى اختيار منتج');
      return;
    }

    if (_qty <= 0) {
      showErrorSnackBar(context, 'يرجى إدخال كمية صحيحة');
      return;
    }

    // Calculate UnitQty
    double unitQty;
    if (_selectedUnit == 'صغرى') {
      unitQty = 1.0;
    } else {
      unitQty = (_selectedItem!['UnitQty'] as num?)?.toDouble() ?? 1.0;
    }

    // TotalQty = UnitQty * Qty
    double totalQty = unitQty * _qty;

    // Check available quantity (from inventory view)
    final availableQty = (_selectedItem!['Qty'] as num?)?.toDouble() ?? 0.0;
    if (totalQty > availableQty) {
      showErrorSnackBar(context, 'الكمية المتاحة غير كافية');
      return;
    }

    final pendingItem = {
      'ItemId': _selectedItem!['Id'],
      'Qty': _qty.toDouble(),
      'QtyUnit': _selectedUnit,
      'Price': _price,
      'Total': _total,
      'UnitQty': unitQty,
      'TotalQty': totalQty,
      'BranchId': widget.sourceBranchId,
      'DestBranchId': widget.destBranchId,
      'ItemName': (_selectedItem!['Name'] ?? '').toString(),
    };

    setState(() {
      _pendingItems.add(pendingItem);
      _selectedItem = null;
      _qty = 1;
      _price = 0.0;
      _total = 0.0;
      _priceCtrl.text = '0.00';
      _totalCtrl.text = '0.00';
      _qtyCtrl.text = '1';
    });

    showSuccessSnackBar(
      context,
      'تم إضافة المنتج إلى قائمة التحويل (${_pendingItems.length})',
    );
  }

  void _returnToBill() {
    if (_pendingItems.isEmpty) {
      showErrorSnackBar(context, 'يرجى إضافة منتجات أولاً');
      return;
    }
    Navigator.pop(context, _pendingItems);
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      appBar: CustomAppBar(
        title: 'إضافة منتجات',
        actions: [
          Padding(
            padding: EdgeInsets.only(right: screenWidth * 0.03),
            child: TextButton.icon(
              style: TextButton.styleFrom(
                backgroundColor: AppColors.error,
                padding: EdgeInsets.symmetric(
                  horizontal: screenWidth * 0.03,
                  vertical: screenHeight * 0.008,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const InventoryScreen(),
                  ),
                );
              },
              icon: Icon(
                Icons.inventory_2_outlined,
                size: screenWidth * 0.045,
                color: AppColors.onPrimary,
              ),
              label: Text(
                "عرض المخزون",
                style: TextStyle(
                  fontSize: screenWidth * 0.035,
                  fontWeight: FontWeight.w600,
                  color: AppColors.onPrimary,
                ),
              ),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ResponsiveContainer(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Category Field
                    AutocompleteField(
                      label: 'الفئة',
                      options: _categories,
                      displayKey: 'Category',
                      onSelected: (category) {
                        setState(() {
                          _selectedCategory = category;
                          _selectedItem = null;
                          _price = 0.0;
                          _total = 0.0;
                          _priceCtrl.text = '0.00';
                          _totalCtrl.text = '0.00';
                        });
                        _filterItems();
                      },
                      selectedValue: _selectedCategory,
                      onClear: () {
                        setState(() {
                          _selectedCategory = null;
                          _selectedItem = null;
                        });
                        _filterItems();
                      },
                      icon: Icons.category,
                    ),
                    SizedBox(height: AppStyles.verticalSpacing(context)),

                    // Item Field
                    AutocompleteField(
                      fieldKey: _itemAutocompleteKey,
                      label: 'المنتج',
                      options: _filteredItems,
                      displayKey: 'Name',
                      onSelected: _onItemSelected,
                      selectedValue: _selectedItem,
                      onClear: () {
                        setState(() {
                          _selectedItem = null;
                          _price = 0.0;
                          _total = 0.0;
                          _priceCtrl.text = '0.00';
                          _totalCtrl.text = '0.00';
                        });
                      },
                      icon: Icons.search,
                    ),
                    SizedBox(height: AppStyles.verticalSpacing(context)),

                    // Row: Quantity and Price
                    Row(
                      children: [
                        Expanded(
                          child: CustomTextField(
                            controller: _qtyCtrl,
                            label: 'الكمية',
                            prefixIcon: Icons.numbers,
                            keyboardType: TextInputType.number,
                            onChanged: (v) {
                              _qty = int.tryParse(v) ?? 1;
                              _calculateTotal();
                            },
                          ),
                        ),
                        SizedBox(width: AppStyles.verticalSpacing(context)),
                        Expanded(
                          child: CustomTextField(
                            controller: _priceCtrl,
                            label: 'السعر',
                            prefixIcon: Icons.attach_money,
                            readOnly: true,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: AppStyles.verticalSpacing(context)),

                    // Row: Unit and Total
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _selectedUnit,
                            decoration:
                                AppStyles.textFieldDecoration(
                                  'الوحدة',
                                  context,
                                ).copyWith(
                                  prefixIcon: Icon(
                                    Icons.scale,
                                    size: AppStyles.iconSize(context),
                                  ),
                                ),
                            items: const [
                              DropdownMenuItem(
                                value: 'صغرى',
                                child: Text('صغرى'),
                              ),
                              DropdownMenuItem(
                                value: 'كبرى',
                                child: Text('كبرى'),
                              ),
                            ],
                            onChanged: _onUnitChanged,
                          ),
                        ),
                        SizedBox(width: AppStyles.verticalSpacing(context)),
                        Expanded(
                          child: CustomTextField(
                            controller: _totalCtrl,
                            label: 'الإجمالي',
                            prefixIcon: Icons.calculate,
                            readOnly: true,
                          ),
                        ),
                      ],
                    ),

                    SizedBox(height: AppStyles.verticalSpacing(context) * 1.5),

                    // Add to List Button
                    ResponsiveButton(
                      text: 'إضافة إلى قائمة التحويل',
                      icon: Icons.add_shopping_cart,
                      onPressed: _addToPending,
                    ),

                    SizedBox(height: AppStyles.verticalSpacing(context)),

                    // Items List
                    Text('منتجات التحويل:', style: AppStyles.heading2(context)),
                    SizedBox(height: AppStyles.verticalSpacing(context)),

                    Container(
                      height: screenHeight * 0.25,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: AppColors.secondary.withOpacity(0.3),
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: _pendingItems.isEmpty
                          ? Center(
                              child: Text(
                                'لا توجد منتجات',
                                style: AppStyles.bodyMedium(
                                  context,
                                ).copyWith(color: AppColors.secondary),
                              ),
                            )
                          : ListView.builder(
                              itemCount: _pendingItems.length,
                              itemBuilder: (context, index) {
                                final item = _pendingItems[index];
                                return Card(
                                  margin: const EdgeInsets.symmetric(
                                    vertical: 4,
                                    horizontal: 8,
                                  ),
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 4,
                                    ),
                                    leading: Icon(
                                      Icons.inventory,
                                      color: AppColors.primary,
                                    ),
                                    title: Text(
                                      item['ItemName'].toString(),
                                      style: AppStyles.bodyMedium(
                                        context,
                                      ).copyWith(fontWeight: FontWeight.bold),
                                    ),
                                    subtitle: Text(
                                      'كمية: ${item['Qty']} ${item['QtyUnit']} | سعر: ${item['Price']} | إجمالي: ${item['Total']}',
                                      style: AppStyles.bodySmall(context),
                                    ),
                                    trailing: IconButton(
                                      icon: Icon(
                                        Icons.delete,
                                        color: AppColors.error,
                                      ),
                                      onPressed: () {
                                        setState(
                                          () => _pendingItems.removeAt(index),
                                        );
                                        showSuccessSnackBar(
                                          context,
                                          'تم حذف المنتج من القائمة',
                                        );
                                      },
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),

                    SizedBox(height: AppStyles.verticalSpacing(context) * 1.5),

                    // Return Button
                    ResponsiveButton(
                      text: 'حفظ التعديلات',
                      icon: Icons.check,
                      onPressed: _returnToBill,
                      backgroundColor: AppColors.success,
                    ),

                    SizedBox(height: screenHeight * 0.02),
                  ],
                ),
              ),
            ),
    );
  }

  @override
  void dispose() {
    _priceCtrl.dispose();
    _totalCtrl.dispose();
    _qtyCtrl.dispose();
    super.dispose();
  }
}
