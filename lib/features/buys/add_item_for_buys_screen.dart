import 'package:flutter/material.dart';
import '../../../utils/app_colors.dart';
import '../../../utils/app_styles.dart';
import '../../utils/snackbars.dart';
import '../../widgets/shared/responsive_container.dart';
import '../../widgets/shared/responsive_button.dart';
import '../../../widgets/shared/autocomplete_field.dart';
import '../../services/local_db_service.dart';

class AddItemForBuysScreen extends StatefulWidget {
  final int? billId;
  final List<Map<String, dynamic>>? initialPendingBuys;
  const AddItemForBuysScreen({super.key, this.billId, this.initialPendingBuys});

  @override
  State<AddItemForBuysScreen> createState() => _AddItemForBuysScreenState();
}

class _AddItemForBuysScreenState extends State<AddItemForBuysScreen> {
  final LocalDbService _local = LocalDbService.instance;

  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _allItems = [];
  List<Map<String, dynamic>> _filteredItems = [];
  Map<String, dynamic>? _selectedCategory;
  Map<String, dynamic>? _selectedItem;
  int _qty = 1;
  String _selectedUnit = 'صغرى';
  String _selectedType = 'شراء';
  double _price = 0.0;
  double _total = 0.0;
  bool _loading = true;
  List<Map<String, dynamic>> _pendingBuys = [];

  UniqueKey _itemAutocompleteKey = UniqueKey();

  final TextEditingController _priceCtrl = TextEditingController();
  final TextEditingController _totalCtrl = TextEditingController();
  final TextEditingController _qtyCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _pendingBuys = List.from(widget.initialPendingBuys ?? []);
    _loadInitialData();
    _priceCtrl.text = _price.toStringAsFixed(2);
    _totalCtrl.text = _total.toStringAsFixed(2);
    _qtyCtrl.text = _qty.toString();
  }

  Future<void> _loadInitialData() async {
    try {
      final cats = await _local.getCategories();
      final allItems = await _local.getItemsByCategory(null);
      setState(() {
        _categories = cats;
        _allItems = allItems;
        _filteredItems = allItems; // Initially show all items
        _loading = false;
      });
    } catch (e) {
      showErrorSnackBar(context, 'خطأ في تحميل البيانات');
      setState(() => _loading = false);
    }
  }

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
      _calculatePrice(); // Calculate price based on unit
    });
  }

  void _calculatePrice() {
    if (_selectedItem == null) {
      setState(() {
        _price = 0.0;
        _priceCtrl.text = _price.toStringAsFixed(2);
      });
      return;
    }

    // UPDATED: Use BuyPrice for صغرى and BuyPriceBig for كبرى
    double buyPrice;
    if (_selectedUnit == 'صغرى') {
      buyPrice = (_selectedItem!['BuyPrice'] as num?)?.toDouble() ?? 0.0;
    } else {
      buyPrice = (_selectedItem!['BuyPriceBig'] as num?)?.toDouble() ?? 0.0;
    }

    setState(() {
      _price = buyPrice;
      _priceCtrl.text = _price.toStringAsFixed(2);
    });
    _calculateTotal();
  }

  void _calculateTotal() {
    setState(() {
      _total = _price * _qty;
      _totalCtrl.text = _total.toStringAsFixed(2);
    });
  }

  void _onUnitChanged(String? v) {
    setState(() => _selectedUnit = v ?? 'صغرى');
    _calculatePrice(); // Recalculate price when unit changes
  }

  void _onTypeChanged(String? v) {
    setState(() => _selectedType = v ?? 'شراء');
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

    // Calculate UnitQty logic
    double unitQty;
    if (_selectedUnit == 'صغرى') {
      unitQty = 1.0;
    } else {
      unitQty = (_selectedItem!['UnitQty'] as num?)?.toDouble() ?? 1.0;
    }

    // Calculate TotalQty
    double totalQty = unitQty * _qty;

    final pendingItem = {
      'ItemId': _selectedItem!['Id'],
      'Qty': _qty.toDouble(),
      'Price': _price,
      'Total': _total,
      'QtyUnit': _selectedUnit,
      'Type': _selectedType,
      'FirstPrice': _price,
      'ItemName': (_selectedItem!['Name'] ?? '').toString(),
      'UnitQty': unitQty,
      'TotalQty': totalQty,
    };

    setState(() {
      _pendingBuys.add(pendingItem);

      // DO NOT clear the category - keep it selected
      _selectedItem = null;
      _qty = 1;
      _price = 0.0;
      _total = 0.0;
      _selectedType = 'شراء';
      _priceCtrl.text = '0.00';
      _totalCtrl.text = '0.00';
      _qtyCtrl.text = '1';

      // Re-filter items based on current category (if any)
      if (_selectedCategory != null) {
        _filterItems();
      }
    });

    showSuccessSnackBar(
      context,
      'تم إضافة المنتج إلى السلة (${_pendingBuys.length})',
    );
  }

  void _returnToBill() {
    if (_pendingBuys.isEmpty) {
      showErrorSnackBar(context, 'يرجى إضافة منتجات إلى السلة أولاً');
      return;
    }
    Navigator.pop(context, _pendingBuys);
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.billId != null
              ? 'إضافة إلى فاتورة الشراء'
              : 'إضافة منتجات للشراء',
          style: AppStyles.heading2(
            context,
          ).copyWith(color: AppColors.onPrimary),
        ),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ResponsiveContainer(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Category Field - SAME AS SELLS SCREEN
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
                        _filterItems(); // Filter items when category changes
                      },
                      selectedValue: _selectedCategory,
                      onClear: () {
                        setState(() {
                          _selectedCategory = null;
                          _selectedItem = null;
                        });
                        _filterItems(); // Reset to all items when category is cleared
                      },
                      icon: Icons.category,
                    ),
                    SizedBox(height: AppStyles.verticalSpacing(context)),

                    // Item Field - SAME AS SELLS SCREEN
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

                    // UPDATED: Quantity and Price in same row - SAME AS SELLS SCREEN
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _qtyCtrl,
                            keyboardType: TextInputType.number,
                            onChanged: (v) {
                              _qty = int.tryParse(v) ?? 1;
                              _calculateTotal();
                            },
                            decoration:
                                AppStyles.textFieldDecoration(
                                  'الكمية',
                                  context,
                                ).copyWith(
                                  prefixIcon: Icon(
                                    Icons.numbers,
                                    size: AppStyles.iconSize(context),
                                  ),
                                ),
                          ),
                        ),
                        SizedBox(width: AppStyles.verticalSpacing(context)),
                        // UPDATED: Price field is now read-only for buys
                        Expanded(
                          child: TextFormField(
                            controller: _priceCtrl,
                            readOnly: true,
                            decoration:
                                AppStyles.textFieldDecoration(
                                  'سعر الشراء',
                                  context,
                                ).copyWith(
                                  prefixIcon: Icon(
                                    Icons.attach_money,
                                    size: AppStyles.iconSize(context),
                                  ),
                                ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: AppStyles.verticalSpacing(context)),

                    // UPDATED: Unit and Type in same row - SAME AS SELLS SCREEN
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
                            value: _selectedType,
                            decoration:
                                AppStyles.textFieldDecoration(
                                  'النوع',
                                  context,
                                ).copyWith(
                                  prefixIcon: Icon(
                                    _selectedType == 'شراء'
                                        ? Icons.shopping_cart
                                        : Icons.assignment_return,
                                    size: AppStyles.iconSize(context),
                                  ),
                                ),
                            items: const [
                              DropdownMenuItem(
                                value: 'شراء',
                                child: Text('شراء'),
                              ),
                              DropdownMenuItem(
                                value: 'ارتجاع',
                                child: Text('ارتجاع'),
                              ),
                            ],
                            onChanged: _onTypeChanged,
                          ),
                        ),
                      ],
                    ),

                    SizedBox(height: AppStyles.verticalSpacing(context)),

                    // Total Field - SAME AS SELLS SCREEN
                    TextFormField(
                      controller: _totalCtrl,
                      readOnly: true,
                      decoration:
                          AppStyles.textFieldDecoration(
                            'الإجمالي',
                            context,
                          ).copyWith(
                            prefixIcon: Icon(
                              Icons.calculate,
                              size: AppStyles.iconSize(context),
                            ),
                          ),
                    ),

                    SizedBox(height: AppStyles.verticalSpacing(context) * 2),

                    // Add to Cart Button - SAME AS SELLS SCREEN
                    ResponsiveButton(
                      text: 'إضافة إلى السلة',
                      icon: Icons.add_shopping_cart,
                      onPressed: _addToPending,
                    ),

                    SizedBox(height: AppStyles.verticalSpacing(context) * 2),

                    // Cart Items - SAME AS SELLS SCREEN
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
                      child: _pendingBuys.isEmpty
                          ? Center(
                              child: Text(
                                'لا توجد منتجات',
                                style: AppStyles.bodyMedium(
                                  context,
                                ).copyWith(color: AppColors.secondary),
                              ),
                            )
                          : ListView.builder(
                              itemCount: _pendingBuys.length,
                              itemBuilder: (context, index) {
                                final item = _pendingBuys[index];
                                // Color coding based on type - SAME AS SELLS SCREEN
                                Color? itemColor;
                                if (item['Type'] == 'ارتجاع') {
                                  itemColor = Colors.red.shade100;
                                } else if (item['Type'] == 'شراء') {
                                  itemColor = Colors.green.shade100;
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
                                      item['Type'] == 'شراء'
                                          ? Icons.shopping_cart
                                          : Icons.assignment_return,
                                      color: item['Type'] == 'شراء'
                                          ? AppColors.primary
                                          : AppColors.error,
                                    ),
                                    title: Text(
                                      item['ItemName'].toString(),
                                      style: AppStyles.bodyMedium(
                                        context,
                                      ).copyWith(fontWeight: FontWeight.bold),
                                    ),
                                    subtitle: Text(
                                      'كمية: ${item['Qty']} ${item['QtyUnit']} | سعر: ${item['Price']} | إجمالي: ${item['Total']}\n'
                                      'النوع: ${item['Type']}',
                                      style: AppStyles.bodySmall(context),
                                    ),
                                    trailing: IconButton(
                                      icon: Icon(
                                        Icons.delete,
                                        color: AppColors.error,
                                      ),
                                      onPressed: () {
                                        setState(
                                          () => _pendingBuys.removeAt(index),
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

                    // Return to Bill Button - SAME AS SELLS SCREEN
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
