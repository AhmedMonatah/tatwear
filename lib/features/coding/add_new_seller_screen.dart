import 'package:flutter/material.dart';
import '../../../utils/app_colors.dart';
import '../../../utils/app_styles.dart';
import '../../utils/snackbars.dart';
import '../../widgets/shared/responsive_container.dart';
import '../../widgets/shared/responsive_button.dart';
import '../../../widgets/shared/custom_app_bar.dart';
import '../../../widgets/shared/custom_text_field.dart';
import '../../../widgets/shared/loading_overlay.dart';
import '../../services/sync_service.dart';

class AddNewSellerScreen extends StatefulWidget {
  const AddNewSellerScreen({super.key});

  @override
  State<AddNewSellerScreen> createState() => _AddNewSellerScreenState();
}

class _AddNewSellerScreenState extends State<AddNewSellerScreen> {
  final SyncService _sync = SyncService.instance;

  bool _isSaving = false;

  final TextEditingController _sellerIdController = TextEditingController();
  final TextEditingController _sellerController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _startController = TextEditingController();

  @override
  void dispose() {
    _sellerIdController.dispose();
    _sellerController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _startController.dispose();
    super.dispose();
  }

  Future<void> _saveSeller() async {
    if (_sellerController.text.isEmpty ||
        _addressController.text.isEmpty ||
        _phoneController.text.isEmpty ||
        _startController.text.isEmpty) {
      showErrorSnackBar(context, 'يرجى ملء جميع الحقول المطلوبة');
      return;
    }

    final double? start = double.tryParse(_startController.text);
    if (start == null) {
      showErrorSnackBar(context, 'قيمة حساب أول المدة غير صالحة');
      return;
    }

    int? sellerId;
    if (_sellerIdController.text.isNotEmpty) {
      sellerId = int.tryParse(_sellerIdController.text);
      if (sellerId == null) {
        showErrorSnackBar(context, 'كود المورد غير صالح');
        return;
      }
    }

    setState(() => _isSaving = true);

    try {
      await _sync.addNewSeller(
        sellerId: sellerId,
        seller: _sellerController.text,
        address: _addressController.text,
        phone: _phoneController.text,
        start: start,
      );
      showSuccessSnackBar(context, 'تم إضافة المورد بنجاح');
      Navigator.pop(context, true);
    } catch (e) {
      showErrorSnackBar(context, 'حدث خطأ أثناء إضافة المورد');
    } finally {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(title: 'إضافة مورد جديد'),
      body: Stack(
        children: [
          ResponsiveContainer(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // SellerId Field (optional)
                  CustomTextField(
                    controller: _sellerIdController,
                    label: 'كود المورد (اختياري)',
                    prefixIcon: Icons.code,
                    keyboardType: TextInputType.number,
                  ),
                  SizedBox(height: AppStyles.verticalSpacing(context)),

                  // Seller Name Field
                  CustomTextField(
                    controller: _sellerController,
                    label: 'اسم المورد',
                    prefixIcon: Icons.person,
                  ),
                  SizedBox(height: AppStyles.verticalSpacing(context)),

                  // Address Field
                  CustomTextField(
                    controller: _addressController,
                    label: 'العنوان',
                    prefixIcon: Icons.location_on,
                  ),
                  SizedBox(height: AppStyles.verticalSpacing(context)),

                  // Phone Field
                  CustomTextField(
                    controller: _phoneController,
                    label: 'التليفون',
                    prefixIcon: Icons.phone,
                    keyboardType: TextInputType.phone,
                  ),
                  SizedBox(height: AppStyles.verticalSpacing(context)),

                  // Start Balance Field
                  CustomTextField(
                    controller: _startController,
                    label: 'حساب أول المدة',
                    prefixIcon: Icons.account_balance_wallet,
                    keyboardType: TextInputType.number,
                  ),
                  SizedBox(height: AppStyles.verticalSpacing(context) * 2),

                  // Save Button
                  ResponsiveButton(
                    text: 'حفظ المورد',
                    icon: Icons.save,
                    onPressed: _saveSeller,
                    backgroundColor: AppColors.success,
                  ),

                  SizedBox(height: MediaQuery.of(context).size.height * 0.02),
                ],
              ),
            ),
          ),
          LoadingOverlay(
            isLoading: _isSaving,
            message: 'جاري إضافة المورد...',
          ),
        ],
      ),
    );
  }
}
