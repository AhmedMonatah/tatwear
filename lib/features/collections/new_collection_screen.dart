import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

class NewCollectionScreen extends StatefulWidget {
  const NewCollectionScreen({super.key});

  @override
  State<NewCollectionScreen> createState() => _NewCollectionScreenState();
}

class _NewCollectionScreenState extends State<NewCollectionScreen> {
  final LocalDbService _local = LocalDbService.instance;
  final SyncService _sync = SyncService.instance;

  List<Map<String, dynamic>> _clients = [];
  List<Map<String, dynamic>> _filteredClients = [];
  List<Map<String, dynamic>> _regions = [];
  Map<String, dynamic>? _selectedClient;
  int? _selectedRegionId;
  bool _loading = true;
  bool _isSaving = false;

  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  double _amount = 0.0;
  String _notes = '';

  UniqueKey _clientAutocompleteKey = UniqueKey();

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
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

  Future<void> _saveCollection() async {
    if (_selectedClient == null) {
      showErrorSnackBar(context, 'يرجى اختيار عميل');
      return;
    }

    if (_amount <= 0) {
      showErrorSnackBar(context, 'يرجى إدخال مبلغ صحيح');
      return;
    }

    setState(() => _isSaving = true);

    try {
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

      // Create local collection
      await _local.createLocalCollection(
        theDate: theDate,
        clientId: (_selectedClient!['Id'] as int),
        bill: '', // Will be set by server
        amount: _amount,
        branchId: branchId!,
        userId: userId!,
        notes: _notes.isNotEmpty ? _notes : null,
      );

      try {
        // Try to sync to server
        await _sync.syncPendingCollectionsToServer();
        if (mounted) {
          await prefs.setString(
            'last_action',
            DateTime.now().toIso8601String(),
          );
          showSuccessSnackBar(context, 'تم حفظ فاتورة التحصيل بنجاح');
          Navigator.pop(context, true);
        }
      } catch (syncError) {
        // Save locally and show offline message
        if (mounted) {
          showEnhancedOfflineSnackBar(context);
          await Future.delayed(const Duration(seconds: 3));
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
      showErrorSnackBar(context, 'حدث خطأ أثناء حفظ فاتورة التحصيل');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }



  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final dateFormat =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';

    return Scaffold(
      appBar: const CustomAppBar(title: 'فاتورة تحصيل جديد'),
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
                          controller: TextEditingController(text: dateFormat), // Initial value equivalent
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
                          },
                          selectedValue: _selectedClient,
                          onClear: () {
                            setState(() => _selectedClient = null);
                          },
                          icon: Icons.person,
                          required: true,
                        ),

                        SizedBox(height: AppStyles.verticalSpacing(context)),

                        // Amount Field
                        CustomTextField(
                          controller: _amountController,
                          label: 'المبلغ',
                          prefixIcon: Icons.attach_money,
                          keyboardType: TextInputType.number,
                          onChanged: (value) {
                            final parsed = double.tryParse(value) ?? 0.0;
                            setState(() => _amount = parsed);
                          },
                        ),

                        SizedBox(height: AppStyles.verticalSpacing(context)),

                        // Notes Field
                        // CustomTextField doesn't explicitly support maxLines. We'll leave this as TextFormField for now since it needs maxLines=3, or we could update CustomTextField. Let's update CustomTextField later if needed, but for now we'll just format it properly to keep maxLines.
                        TextFormField(
                          controller: _notesController,
                          maxLines: 3,
                          decoration: AppStyles.textFieldDecoration('ملاحظات', context).copyWith(
                            prefixIcon: Icon(Icons.note, size: AppStyles.iconSize(context)),
                          ),
                          onChanged: (value) => setState(() => _notes = value),
                        ),

                        SizedBox(
                          height: AppStyles.verticalSpacing(context) * 2,
                        ),

                        // Save Collection Button
                        if (_selectedClient != null && _amount > 0)
                          ResponsiveButton(
                            text: 'حفظ فاتورة التحصيل',
                            icon: Icons.save,
                            onPressed: _saveCollection,
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
            message: 'جاري حفظ فاتورة التحصيل...',
          ),
        ],
      ),
    );
  }
}
