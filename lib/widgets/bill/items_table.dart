import 'package:flutter/material.dart';
import 'package:tatweer/utils/app_colors.dart';
import 'package:tatweer/utils/app_styles.dart';
import 'package:tatweer/utils/helpers.dart';

class ItemsTableWidget extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  final bool hasChanges;
  final bool isLocked;

  const ItemsTableWidget({
    super.key,
    required this.items,
    required this.hasChanges,
    required this.isLocked,
  });

  // helper: hide "غير معروف"
  String _clean(String value) {
    return value == 'غير معروف' ? '' : value;
  }

  Widget _buildWideTable(
    List<Map<String, dynamic>> items,
    BuildContext context,
  ) {
    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: [
            DataColumn(
              label: Text('اسم الصنف', style: AppStyles.bodyMedium(context)),
            ),
            DataColumn(
              label: Text('الكمية', style: AppStyles.bodyMedium(context)),
            ),
            DataColumn(
              label: Text('الوحدة', style: AppStyles.bodyMedium(context)),
            ),
            DataColumn(
              label: Text('التسعير', style: AppStyles.bodyMedium(context)),
            ),
            DataColumn(
              label: Text('السعر', style: AppStyles.bodyMedium(context)),
            ),
            DataColumn(
              label: Text('النوع', style: AppStyles.bodyMedium(context)),
            ),
            DataColumn(
              label: Text('الإجمالي', style: AppStyles.bodyMedium(context)),
            ),
          ],
          rows: items.map((item) {
            return DataRow(
              cells: [
                DataCell(
                  Text(
                    _clean(getSafeString(item['ItemName'])),
                    style: AppStyles.bodyMedium(context),
                  ),
                ),
                DataCell(
                  Text(
                    getSafeDouble(item['Qty']).toStringAsFixed(2),
                    style: AppStyles.bodyMedium(context),
                  ),
                ),
                DataCell(
                  Text(
                    _clean(getSafeString(item['QtyUnit'])),
                    style: AppStyles.bodyMedium(context),
                  ),
                ),
                DataCell(
                  Text(
                    _clean(getSafeString(item['Pricing'])),
                    style: AppStyles.bodyMedium(context),
                  ),
                ),
                DataCell(
                  Text(
                    getSafeDouble(item['Price']).toStringAsFixed(2),
                    style: AppStyles.bodyMedium(context),
                  ),
                ),
                DataCell(
                  Text(
                    _clean(getSafeString(item['Type'])),
                    style: AppStyles.bodyMedium(context),
                  ),
                ),
                DataCell(
                  Text(
                    getSafeDouble(item['Total']).toStringAsFixed(2),
                    style: AppStyles.bodyMedium(context),
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildNarrowList(
    List<Map<String, dynamic>> items,
    BuildContext context,
  ) {
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];

        final qtyUnit = _clean(getSafeString(item['QtyUnit']));
        final pricing = _clean(getSafeString(item['Pricing']));
        final type = _clean(getSafeString(item['Type']));

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          child: ListTile(
            contentPadding: const EdgeInsets.all(12),
            leading: Icon(Icons.shopping_cart, color: AppColors.primary),
            title: Text(
              _clean(getSafeString(item['ItemName'])),
              style: AppStyles.bodyMedium(
                context,
              ).copyWith(fontWeight: FontWeight.bold),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (qtyUnit.isNotEmpty)
                  Text(
                    'الكمية: ${getSafeDouble(item['Qty']).toStringAsFixed(2)} $qtyUnit',
                    style: AppStyles.bodySmall(context),
                  ),
                Text(
                  'السعر: ${getSafeDouble(item['Price']).toStringAsFixed(2)} | الإجمالي: ${getSafeDouble(item['Total']).toStringAsFixed(2)}',
                  style: AppStyles.bodySmall(context),
                ),
                if (pricing.isNotEmpty || type.isNotEmpty)
                  Text(
                    '${pricing.isNotEmpty ? 'التسعير: $pricing' : ''}'
                    '${pricing.isNotEmpty && type.isNotEmpty ? ' | ' : ''}'
                    '${type.isNotEmpty ? 'النوع: $type' : ''}',
                    style: AppStyles.bodySmall(context),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.list,
              size: screenWidth * 0.15,
              color: AppColors.secondary,
            ),
            SizedBox(height: AppStyles.verticalSpacing(context)),
            Text(
              'لا توجد منتجات في هذه الفاتورة',
              style: AppStyles.bodyLarge(context),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              Text('المنتجات:', style: AppStyles.heading2(context)),
              if (hasChanges && !isLocked)
                Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: Text(
                    '(${items.length} منتج) *',
                    style: TextStyle(
                      color: AppColors.warning,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: screenWidth > 600
              ? _buildWideTable(items, context)
              : _buildNarrowList(items, context),
        ),
      ],
    );
  }
}
