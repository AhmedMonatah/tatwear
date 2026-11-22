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

class AddNewClientScreen extends StatefulWidget {
  const AddNewClientScreen({super.key});

  @override
  State<AddNewClientScreen> createState() => _AddNewClientScreenState();
}

class _AddNewClientScreenState extends State<AddNewClientScreen> {
  final LocalDbService _local = LocalDbService.instance;
  final SyncService _sync = SyncService.instance;

  List<Map<String, dynamic>> _regions = [];
  int? _selectedRegionId;
  bool _loading = true;
  bool _isSaving = false;

  final TextEditingController _clientIdController = TextEditingController();
  final TextEditingController _clientController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _startController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadRegions();
  }

  @override
  void dispose() {
    _clientIdController.dispose();
    _clientController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _startController.dispose();
    super.dispose();
  }

  Future<void> _loadRegions() async {
    try {
      final regions = await _local.readTable('Region');
      setState(() {
        _regions = regions;
        _loading = false;
      });
    } catch (e) {
      showErrorSnackBar(context, 'خطأ في تحميل المناطق');
      setState(() => _loading = false);
    }
  }

  Future<void> _saveClient() async {
    if (_clientController.text.isEmpty ||
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

    int? clientId;
    if (_clientIdController.text.isNotEmpty) {
      clientId = int.tryParse(_clientIdController.text);
      if (clientId == null) {
        showErrorSnackBar(context, 'كود العميل غير صالح');
        return;
      }
    }

    setState(() => _isSaving = true);

    try {
      await _sync.addNewClient(
        clientId: clientId,
        client: _clientController.text,
        address: _addressController.text,
        phone: _phoneController.text,
        start: start,
        regionId: _selectedRegionId,
      );
      showSuccessSnackBar(context, 'تم إضافة العميل بنجاح');
      Navigator.pop(context, true);
    } catch (e) {
      showErrorSnackBar(context, 'حدث خطأ أثناء إضافة العميل');
    } finally {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        appBar: const CustomAppBar(title: 'إضافة عميل جديد'),
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
                          // ClientId Field (optional)
                          CustomTextField(
                            controller: _clientIdController,
                            label: 'كود العميل (اختياري)',
                            prefixIcon: Icons.code,
                            keyboardType: TextInputType.number,
                          ),
                          SizedBox(height: AppStyles.verticalSpacing(context)),

                          // Client Name Field
                          CustomTextField(
                            controller: _clientController,
                            label: 'اسم العميل',
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

                          // Region Field
                          AutocompleteField(
                            label: 'المنطقة (اختياري)',
                            options: _regions,
                            displayKey: 'Region',
                            onSelected: (region) {
                              setState(() {
                                _selectedRegionId = region['RegionId'] as int?;
                              });
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
                              });
                            },
                            icon: Icons.map,
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
                         
                          SizedBox(
                            height: AppStyles.verticalSpacing(context) * 2,
                          ),

                          // Save Button
                          ResponsiveButton(
                            text: 'حفظ العميل',
                            icon: Icons.save,
                            onPressed: _saveClient,
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
              message: 'جاري إضافة العميل...',
            ),
          ],
        ),
      ),
    );
  }
}
