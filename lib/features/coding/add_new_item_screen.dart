import 'package:flutter/material.dart';
import '../../../utils/app_colors.dart';
import '../../../utils/app_styles.dart';
import '../../utils/snackbars.dart';
import '../../widgets/shared/responsive_container.dart';
import '../../widgets/shared/responsive_button.dart';
import '../../../widgets/shared/custom_app_bar.dart';
import '../../../widgets/shared/custom_text_field.dart';
import '../../../widgets/shared/loading_overlay.dart';
import '../../../widgets/shared/autocomplete_field.dart';
import '../../services/local_db_service.dart';
import '../../services/sync_service.dart';

class AddNewItemScreen extends StatefulWidget {
  const AddNewItemScreen({super.key});

  @override
  State<AddNewItemScreen> createState() => _AddNewItemScreenState();
}

class _AddNewItemScreenState extends State<AddNewItemScreen> {
  final LocalDbService _local = LocalDbService.instance;
  final SyncService _sync = SyncService.instance;

  List<Map<String, dynamic>> _categories = [];
  int? _selectedCategoryId;
  bool _loading = true;
  bool _isSaving = false;

  final TextEditingController _itemIdController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _buyPriceController = TextEditingController();
  final TextEditingController _sellingPriceController = TextEditingController();
  final TextEditingController _unitQtyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  @override
  void dispose() {
    _itemIdController.dispose();
    _nameController.dispose();
    _buyPriceController.dispose();
    _sellingPriceController.dispose();
    _unitQtyController.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    try {
      final categories = await _local.readTable('STRCategory');
      setState(() {
        _categories = categories;
        _loading = false;
      });
    } catch (e) {
      showErrorSnackBar(context, 'خطأ في تحميل التصنيفات');
      setState(() => _loading = false);
    }
  }

  Future<void> _saveItem() async {
    if (_nameController.text.isEmpty ||
        _buyPriceController.text.isEmpty ||
        _sellingPriceController.text.isEmpty ||
        _unitQtyController.text.isEmpty ||
        _selectedCategoryId == null) {
      showErrorSnackBar(context, 'يرجى ملء جميع الحقول المطلوبة');
      return;
    }

    final double? buyPrice = double.tryParse(_buyPriceController.text);
    final double? sellingPrice = double.tryParse(_sellingPriceController.text);
    final double? unitQty = double.tryParse(_unitQtyController.text);

    if (buyPrice == null || sellingPrice == null || unitQty == null) {
      showErrorSnackBar(context, 'قيم الأسعار أو العدد غير صالحة');
      return;
    }

    int? itemId;
    if (_itemIdController.text.isNotEmpty) {
      itemId = int.tryParse(_itemIdController.text);
      if (itemId == null) {
        showErrorSnackBar(context, 'كود الصنف غير صالح');
        return;
      }
    }

    setState(() => _isSaving = true);

    try {
      await _sync.addNewItem(
        itemId: itemId,
        name: _nameController.text,
        categoryId: _selectedCategoryId!,
        buyPrice: buyPrice,
        sellingPrice: sellingPrice,
        unitQty: unitQty,
      );
      showSuccessSnackBar(context, 'تم إضافة الصنف بنجاح');
      Navigator.pop(context, true);
    } catch (e) {
      showErrorSnackBar(context, 'حدث خطأ أثناء إضافة الصنف');
    } finally {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        appBar: const CustomAppBar(title: 'إضافة صنف جديد'),
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
                          // ItemId Field (optional)
                          CustomTextField(
                            controller: _itemIdController,
                            label: 'كود الصنف (اختياري)',
                            prefixIcon: Icons.code,
                            keyboardType: TextInputType.number,
                          ),
                          SizedBox(height: AppStyles.verticalSpacing(context)),

                          // Name Field
                          CustomTextField(
                            controller: _nameController,
                            label: 'الإسم',
                            prefixIcon: Icons.label,
                          ),
                          SizedBox(height: AppStyles.verticalSpacing(context)),

                          // Category Field
                          AutocompleteField(
                            label: 'التصنيف',
                            options: _categories,
                            displayKey: 'Category',
                            onSelected: (category) {
                              setState(() {
                                _selectedCategoryId = category['Id'] as int?;
                              });
                            },
                            selectedValue: _selectedCategoryId != null
                                ? _categories.firstWhere(
                                    (c) => c['Id'] == _selectedCategoryId,
                                    orElse: () => {},
                                  )
                                : null,
                            onClear: () {
                              setState(() {
                                _selectedCategoryId = null;
                              });
                            },
                            icon: Icons.category,
                            required: true,
                          ),
                          SizedBox(height: AppStyles.verticalSpacing(context)),

                          // BuyPrice Field
                          CustomTextField(
                            controller: _buyPriceController,
                            label: 'سعر شراء',
                            prefixIcon: Icons.shopping_cart,
                            keyboardType: TextInputType.number,
                          ),
                          SizedBox(height: AppStyles.verticalSpacing(context)),

                          // SellingPrice Field
                          CustomTextField(
                            controller: _sellingPriceController,
                            label: 'سعر بيع',
                            prefixIcon: Icons.sell,
                            keyboardType: TextInputType.number,
                          ),
                          SizedBox(height: AppStyles.verticalSpacing(context)),

                          // UnitQty Field
                          CustomTextField(
                            controller: _unitQtyController,
                            label: 'العدد بالكبرى',
                            prefixIcon: Icons.numbers,
                            keyboardType: TextInputType.number,
                          ),
                          SizedBox(height: AppStyles.verticalSpacing(context) * 2),

                          // Save Button
                          ResponsiveButton(
                            text: 'حفظ الصنف',
                            icon: Icons.save,
                            onPressed: _saveItem,
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
              message: 'جاري إضافة الصنف...',
            ),
          ],
        ),
      ),
    );
  }
}