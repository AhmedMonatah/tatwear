import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../utils/app_colors.dart';
import '../../../utils/app_styles.dart';
import '../../widgets/shared/responsive_container.dart';
import '../../services/local_db_service.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final LocalDbService _local = LocalDbService.instance;

  List<Map<String, dynamic>> _allItems = [];
  List<Map<String, dynamic>> _filteredItems = [];
  String _searchTerm = '';
  String _branchName = '';
  bool _loading = true;

  int? _roleId; // Stores role_id from SharedPreferences

  bool get isAdmin => _roleId == 1; // True only if role_id == 1

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await _loadRole();
    await _loadInventory();
  }

  Future<void> _loadRole() async {
    final prefs = await SharedPreferences.getInstance();
    _roleId = prefs.getInt('role_id');
  }

  Future<void> _loadInventory() async {
    setState(() => _loading = true);
    try {
      final items = await _local.getInventoryItemsByCategory(null);

      String branchName = '';
      if (items.isNotEmpty) {
        branchName = items.first['BranchName']?.toString() ?? 'غير معروف';
      }

      setState(() {
        _allItems = items;
        _filteredItems = List.from(items);
        _branchName = branchName;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  void _filterItems() {
    List<Map<String, dynamic>> filtered = List.from(_allItems);

    if (_searchTerm.isNotEmpty) {
      filtered = filtered.where((item) {
        final name = item['Name']?.toString().toLowerCase() ?? '';
        return name.contains(_searchTerm.toLowerCase());
      }).toList();
    }

    setState(() {
      _filteredItems = filtered;
    });
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final screenWidth = media.size.width;
    final screenHeight = media.size.height;

    final horizontalPadding = screenWidth * 0.015;
    final verticalSpacing = screenHeight * 0.02;

    final isDesktop = screenWidth >= 1000;
    final isTablet = screenWidth >= 600 && screenWidth < 1000;

    final nameWidth = isDesktop
        ? 320.0
        : isTablet
        ? 240.0
        : 200.0;

    final smallColWidth = isDesktop
        ? 140.0
        : isTablet
        ? 120.0
        : 110.0;

    final qtyWidth = isDesktop
        ? 130.0
        : isTablet
        ? 110.0
        : 100.0;

    final columnsCount = isAdmin ? 7 : 5;
    final totalTableWidth =
        16 + nameWidth + qtyWidth + (smallColWidth * columnsCount);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        elevation: 0,
        title: Text(
          'المخزون',
          style: AppStyles.heading2(
            context,
          ).copyWith(color: AppColors.onPrimary),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : RefreshIndicator(
              onRefresh: _loadInventory,
              color: AppColors.primary,
              child: ResponsiveContainer(
                child: Column(
                  children: [
                    SizedBox(height: verticalSpacing),
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: horizontalPadding,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.store,
                            color: AppColors.primary,
                            size: screenWidth * 0.06,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'فرع: $_branchName',
                              style: AppStyles.bodyLarge(
                                context,
                              ).copyWith(fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: verticalSpacing),
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: horizontalPadding,
                      ),
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: 'البحث عن منتج...',
                          prefixIcon: const Icon(Icons.search),
                          filled: true,
                          fillColor: AppColors.surface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onChanged: (value) {
                          _searchTerm = value;
                          _filterItems();
                        },
                      ),
                    ),
                    SizedBox(height: verticalSpacing),
                    Expanded(
                      child: _filteredItems.isEmpty
                          ? const Center(child: Text('لا توجد منتجات'))
                          : Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: horizontalPadding,
                              ),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: AppColors.surface,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: SizedBox(
                                    width: totalTableWidth,
                                    child: Column(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 12,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppColors.primary
                                                .withOpacity(0.08),
                                            borderRadius:
                                                const BorderRadius.vertical(
                                                  top: Radius.circular(12),
                                                ),
                                          ),
                                          child: Row(
                                            children: [
                                              const SizedBox(width: 16),
                                              _HeaderCell('المنتج', nameWidth),
                                              _HeaderCell('الكمية', qtyWidth),
                                              _HeaderCell(
                                                'بيع صغرى',
                                                smallColWidth,
                                              ),
                                              _HeaderCell(
                                                'بيع كبرى',
                                                smallColWidth,
                                              ),
                                              _HeaderCell(
                                                'جملة صغرى',
                                                smallColWidth,
                                              ),
                                              _HeaderCell(
                                                'جملة كبرى',
                                                smallColWidth,
                                              ),
                                              if (isAdmin)
                                                _HeaderCell(
                                                  'شراء صغرى',
                                                  smallColWidth,
                                                ),
                                              if (isAdmin)
                                                _HeaderCell(
                                                  'شراء كبرى',
                                                  smallColWidth,
                                                ),
                                            ],
                                          ),
                                        ),
                                        Expanded(
                                          child: ListView.builder(
                                            itemCount: _filteredItems.length,
                                            itemBuilder: (context, index) {
                                              final item =
                                                  _filteredItems[index];

                                              final qty = (item['Qty'] ?? 0)
                                                  .toDouble();

                                              final qtyColor = qty > 0
                                                  ? AppColors.success
                                                  : AppColors.error;

                                              return Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      vertical: 10,
                                                    ),
                                                decoration: BoxDecoration(
                                                  border: Border(
                                                    bottom: BorderSide(
                                                      color: Colors.grey
                                                          .withOpacity(0.1),
                                                    ),
                                                  ),
                                                ),
                                                child: Row(
                                                  children: [
                                                    const SizedBox(width: 16),
                                                    _DataCell(
                                                      item['Name']
                                                              ?.toString() ??
                                                          '',
                                                      nameWidth,
                                                      bold: true,
                                                    ),
                                                    _DataCell(
                                                      qty.toStringAsFixed(2),
                                                      qtyWidth,
                                                      color: qtyColor,
                                                    ),
                                                    _DataCell(
                                                      _price(
                                                        item['SellingPrice'],
                                                      ),
                                                      smallColWidth,
                                                    ),
                                                    _DataCell(
                                                      _price(
                                                        item['SellingPriceBig'],
                                                      ),
                                                      smallColWidth,
                                                    ),
                                                    _DataCell(
                                                      _price(
                                                        item['WholesalePrice'],
                                                      ),
                                                      smallColWidth,
                                                    ),
                                                    _DataCell(
                                                      _price(
                                                        item['WholesalePriceBig'],
                                                      ),
                                                      smallColWidth,
                                                    ),
                                                    if (isAdmin)
                                                      _DataCell(
                                                        _price(
                                                          item['BuyPrice'],
                                                        ),
                                                        smallColWidth,
                                                      ),
                                                    if (isAdmin)
                                                      _DataCell(
                                                        _price(
                                                          item['BuyPriceBig'],
                                                        ),
                                                        smallColWidth,
                                                      ),
                                                  ],
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  String _price(dynamic value) {
    return (value ?? 0).toDouble().toStringAsFixed(2);
  }
}

class _HeaderCell extends StatelessWidget {
  final String title;
  final double width;

  const _HeaderCell(this.title, this.width);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Text(
        title,
        overflow: TextOverflow.ellipsis,
        style: AppStyles.bodyMedium(
          context,
        ).copyWith(fontWeight: FontWeight.bold, color: AppColors.primary),
      ),
    );
  }
}

class _DataCell extends StatelessWidget {
  final String text;
  final double width;
  final bool bold;
  final Color? color;

  const _DataCell(this.text, this.width, {this.bold = false, this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Text(
        text,
        overflow: TextOverflow.ellipsis,
        style: AppStyles.bodySmall(context).copyWith(
          fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
          color: color ?? AppColors.onSurface,
        ),
      ),
    );
  }
}
