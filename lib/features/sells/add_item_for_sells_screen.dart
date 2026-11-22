import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

class AddItemForSellsScreen extends StatefulWidget {
  final int? billId;
  final List<Map<String, dynamic>>? initialPendingSells;
  const AddItemForSellsScreen({
    super.key,
    this.billId,
    this.initialPendingSells,
  });

  @override
  State<AddItemForSellsScreen> createState() => _AddItemForSellsScreenState();
}

class _AddItemForSellsScreenState extends State<AddItemForSellsScreen> {
  final LocalDbService _local = LocalDbService.instance;

  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _allItems = [];
  List<Map<String, dynamic>> _filteredItems = [];
  Map<String, dynamic>? _selectedCategory;
  Map<String, dynamic>? _selectedItem;
  double _qty = 1;
  String _selectedUnit = 'صغرى';
  String _selectedPricing = 'تجزئة';
  String _selectedType = 'بيع'; // 💡 NEW: Default type is 'بيع'
  double _price = 0.0;
  double _total = 0.0;
  double _buyPrice = 0.0;
  bool _loading = true;
  List<Map<String, dynamic>> _pendingSells = [];

  UniqueKey _itemAutocompleteKey = UniqueKey();

  final TextEditingController _priceCtrl = TextEditingController();
  final TextEditingController _totalCtrl = TextEditingController();
  final TextEditingController _qtyCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _pendingSells = List.from(widget.initialPendingSells ?? []);
    _loadInitialData();
    _priceCtrl.text = _price.toStringAsFixed(2);
    _totalCtrl.text = _total.toStringAsFixed(2);
    _qtyCtrl.text = _qty.toString();
  }

  Future<void> _loadInitialData() async {
    try {
      final cats = await _local.getCategories();
      final allItems = await _local.getInventoryItemsByCategory(
        null,
      ); // 💡 Load all items
      setState(() {
        _categories = cats;
        _allItems = allItems;
        _filteredItems = allItems; // 💡 Initially show all items
        _loading = false;
      });
    } catch (e) {
      showErrorSnackBar(context, 'خطأ في تحميل البيانات');
      setState(() => _loading = false);
    }
  }

  // 💡 NEW: Filter items based on selected category
  void _filterItems() {
    if (_selectedCategory == null) {
      // If no category is selected, show all items
      setState(() {
        _filteredItems = _allItems;
        _itemAutocompleteKey = UniqueKey();
      });
    } else {
      // If a category is selected, filter the items
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
      _buyPrice = (item['BuyPrice'] as num?)?.toDouble() ?? 0.0;
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

    _local
        .getInventoryItemPrice(
          isSelling: true,
          itemId,
          _selectedPricing,
          _selectedUnit,
        )
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

  void _onPricingChanged(String? v) {
    setState(() => _selectedPricing = v ?? 'تجزئة');
    _calculatePrice();
  }

  // 💡 NEW: Handle type change
  void _onTypeChanged(String? v) {
    setState(() => _selectedType = v ?? 'بيع');
  }

  Future<void> _addToPending() async {
    // 💡 REMOVED: Category validation - only require item selection
    if (_selectedItem == null) {
      showErrorSnackBar(context, 'يرجى اختيار منتج');
      return;
    }

    if (_qty <= 0) {
      showErrorSnackBar(context, 'يرجى إدخال كمية أكبر من صفر');
      return;
    }

    // ItemBranchId belongs to the logged-in user's branch, rather than the
    // branch printed on an inventory row. This keeps sales and returns tied
    // to the branch that actually created the transaction.
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final itemBranchId = prefs.getInt('branch_id');
    if (itemBranchId == null) {
      showErrorSnackBar(context, 'تعذّر تحديد فرع المستخدم الحالي');
      return;
    }

    // 💡 NEW: Calculate UnitQty logic
    double unitQty;
    if (_selectedUnit == 'صغرى') {
      unitQty = 1.0;
    } else {
      // Get UnitQty from StrItems, default to 1 if not available
      unitQty = (_selectedItem!['UnitQty'] as num?)?.toDouble() ?? 1.0;
    }

    // 💡 NEW: Calculate TotalQty
    double totalQty = unitQty * _qty;

    // 💡 NEW: Check available quantity
    final availableQty = (_selectedItem!['Qty'] as num?)?.toDouble() ?? 0.0;
    if (totalQty > availableQty) {
      showErrorSnackBar(context, 'الكمية المتاحة غير كافية');
      return;
    }

    final pendingItem = {
      'ItemId': _selectedItem!['Id'],
      'Qty': _qty,
      'Price': _price,
      'Total': _total,
      'QtyUnit': _selectedUnit,
      'Pricing': _selectedPricing,
      'Type': _selectedType, // 💡 NEW: Add type field
      'FirstPrice': _price,
      'BuyPrice': _buyPrice,
      'ItemName': (_selectedItem!['Name'] ?? '').toString(),
      'UnitQty': unitQty, // 💡 NEW: Add UnitQty
      'TotalQty': totalQty, // 💡 NEW: Add TotalQty
      'ItemBranchId': itemBranchId,
    };

    setState(() {
      _pendingSells.add(pendingItem);
      _selectedItem = null;
      _qty = 1;
      _price = 0.0;
      _total = 0.0;
      _buyPrice = 0.0;
      _selectedType = 'بيع';
      _priceCtrl.text = '0.00';
      _totalCtrl.text = '0.00';
      _qtyCtrl.text = '1';
    });

    showSuccessSnackBar(
      context,
      'تم إضافة المنتج إلى السلة (${_pendingSells.length})',
    );
  }

  void _returnToBill() {
    if (_pendingSells.isEmpty) {
      showErrorSnackBar(context, 'يرجى إضافة منتجات إلى السلة أولاً');
      return;
    }
    Navigator.pop(context, _pendingSells);
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      appBar: CustomAppBar(
        title: widget.billId != null ? 'إضافة إلى فاتورة' : 'إضافة منتجات',
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
                        _filterItems(); // 💡 Filter items when category changes
                      },
                      selectedValue: _selectedCategory,
                      onClear: () {
                        setState(() {
                          _selectedCategory = null;
                          _selectedItem = null;
                        });
                        _filterItems(); // 💡 Reset to all items when category is cleared
                      },
                      icon: Icons.category,
                    ),
                    SizedBox(height: AppStyles.verticalSpacing(context)),

                    // Item Field
                    AutocompleteField(
                      fieldKey:
                          _itemAutocompleteKey, // 💡 Force rebuild when items change
                      label: 'المنتج',
                      options: _filteredItems, // 💡 Use filtered items
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

                    //  Quantity and Price in same row
                    Row(
                      children: [
                        Expanded(
                          child: CustomTextField(
                            controller: _qtyCtrl,
                            label: 'الكمية',
                            prefixIcon: Icons.numbers,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            onChanged: (v) {
                              // Accept both common decimal separators. Empty
                              // or invalid input stays invalid rather than
                              // silently changing the quantity back to 1.
                              _qty =
                                  double.tryParse(
                                    v
                                        .trim()
                                        .replaceAll(',', '.')
                                        .replaceAll('٫', '.'),
                                  ) ??
                                  0;
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

                    //  Unit and Pricing in same row
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
                          child: DropdownButtonFormField<String>(
                            value: _selectedPricing,
                            decoration:
                                AppStyles.textFieldDecoration(
                                  'التسعير',
                                  context,
                                ).copyWith(
                                  prefixIcon: Icon(
                                    Icons.price_change,
                                    size: AppStyles.iconSize(context),
                                  ),
                                ),
                            items: const [
                              DropdownMenuItem(
                                value: 'تجزئة',
                                child: Text('تجزئة'),
                              ),
                              DropdownMenuItem(
                                value: 'جملة',
                                child: Text('جملة'),
                              ),
                            ],
                            onChanged: _onPricingChanged,
                          ),
                        ),
                      ],
                    ),

                    SizedBox(height: AppStyles.verticalSpacing(context)),

                    // 💡 NEW: Type Field (dropdown)
                    DropdownButtonFormField<String>(
                      value: _selectedType,
                      decoration:
                          AppStyles.textFieldDecoration(
                            'النوع',
                            context,
                          ).copyWith(
                            prefixIcon: Icon(
                              Icons.category,
                              size: AppStyles.iconSize(context),
                            ),
                          ),
                      items: const [
                        DropdownMenuItem(value: 'بيع', child: Text('بيع')),
                        DropdownMenuItem(
                          value: 'ارتجاع',
                          child: Text('ارتجاع'),
                        ),
                        DropdownMenuItem(
                          value: 'استبدال',
                          child: Text('استبدال'),
                        ),
                      ],
                      onChanged: _onTypeChanged,
                    ),

                    SizedBox(height: AppStyles.verticalSpacing(context)),

                    // Total Field
                    CustomTextField(
                      controller: _totalCtrl,
                      label: 'الإجمالي',
                      prefixIcon: Icons.calculate,
                      readOnly: true,
                    ),

                    SizedBox(height: AppStyles.verticalSpacing(context) * 2),

                    // Add to Cart Button
                    ResponsiveButton(
                      text: 'إضافة إلى السلة',
                      icon: Icons.add_shopping_cart,
                      onPressed: _addToPending,
                    ),

                    SizedBox(height: AppStyles.verticalSpacing(context) * 2),

                    // Cart Items
                    Text(
                      'المنتجات في السلة:',
                      style: AppStyles.heading2(context),
                    ),
                    SizedBox(height: AppStyles.verticalSpacing(context)),

                    Container(
                      height: screenHeight * 0.25,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: AppColors.secondary.withOpacity(0.3),
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: _pendingSells.isEmpty
                          ? Center(
                              child: Text(
                                'لا توجد منتجات',
                                style: AppStyles.bodyMedium(
                                  context,
                                ).copyWith(color: AppColors.secondary),
                              ),
                            )
                          : ListView.builder(
                              itemCount: _pendingSells.length,
                              itemBuilder: (context, index) {
                                final item = _pendingSells[index];
                                // 💡 NEW: Color coding based on type
                                Color? itemColor;
                                if (item['Type'] == 'ارتجاع') {
                                  itemColor = Colors.red.shade100;
                                } else if (item['Type'] == 'استبدال') {
                                  itemColor = Colors.blue.shade100;
                                }

                                return Card(
                                  margin: const EdgeInsets.symmetric(
                                    vertical: 4,
                                    horizontal: 8,
                                  ),
                                  color: itemColor,
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 4,
                                    ),
                                    leading: Icon(
                                      Icons.shopping_cart,
                                      color: AppColors.primary,
                                    ),
                                    title: Text(
                                      item['ItemName'].toString(),
                                      style: AppStyles.bodyMedium(
                                        context,
                                      ).copyWith(fontWeight: FontWeight.bold),
                                    ),
                                    subtitle: Text(
                                      'كمية: ${item['Qty']} ${item['QtyUnit']} | سعر: ${item['Price']} | إجمالي: ${item['Total']}\n'
                                      'التسعير: ${item['Pricing']} | النوع: ${item['Type']}',
                                      style: AppStyles.bodySmall(context),
                                    ),
                                    trailing: IconButton(
                                      icon: Icon(
                                        Icons.delete,
                                        color: AppColors.error,
                                      ),
                                      onPressed: () {
                                        setState(
                                          () => _pendingSells.removeAt(index),
                                        );
                                        showSuccessSnackBar(
                                          context,
                                          'تم حذف المنتج من السلة',
                                        );
                                      },
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),

                    SizedBox(height: AppStyles.verticalSpacing(context) * 2),

                    // Return to Bill Button
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
