import 'package:flutter/material.dart';
import 'package:tatweer/utils/app_colors.dart';
import 'package:tatweer/utils/app_styles.dart';
import 'package:tatweer/utils/helpers.dart';
import 'package:tatweer/widgets/shared/info_row.dart';

class BillHeaderWidget extends StatelessWidget {
  final Map<String, dynamic> bill;
  final String customerLabel;
  final String customerName;
  final String? regionName;
  final bool hasChanges;
  final bool isLocked;

  final double itemsTotal;
  final double discount;
  final TextEditingController discountController;
  final Function(String) onDiscountChanged;
  final bool balanceLoading;
  final bool balanceFetchFailed;
  final bool internetAvailable;
  final double paiedAmount;
  final TextEditingController paiedController;
  final Function(String) onPaiedChanged;
  final double netTotal;
  final double billRest;
  final double totalRest;

  const BillHeaderWidget({
    super.key,
    required this.bill,
    required this.customerLabel,
    required this.customerName,
    this.regionName,
    required this.hasChanges,
    required this.isLocked,
    required this.itemsTotal,
    required this.discount,
    required this.discountController,
    required this.onDiscountChanged,
    required this.balanceLoading,
    required this.balanceFetchFailed,
    required this.internetAvailable,
    required this.paiedAmount,
    required this.paiedController,
    required this.onPaiedChanged,
    required this.netTotal,
    required this.billRest,
    required this.totalRest,
  });

  Widget _buildEditableField({
    required BuildContext context,
    required String label,
    required TextEditingController controller,
    required Function(String) onChanged,
    required bool enabled,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: AppStyles.bodyMedium(context).fontSize,
            ),
          ),
          Expanded(
            child: TextFormField(
              controller: controller,
              keyboardType: TextInputType.number,
              enabled: enabled,
              textAlign: TextAlign.left,
              decoration: InputDecoration(
                hintText: '0.00',
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                isDense: true,
              ),
              onChanged: onChanged,
            ),
          ),
          SizedBox(width: 8),
          Text('ج.م'),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      margin: EdgeInsets.all(MediaQuery.of(context).size.width * 0.03),
      child: Padding(
        padding: EdgeInsets.all(MediaQuery.of(context).size.width * 0.04),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InfoRow(label: 'رقم الفاتورة', value: getSafeString(bill['Bill'])),
            InfoRow(label: 'التاريخ', value: getSafeString(bill['TheDate'])),
            InfoRow(label: customerLabel, value: customerName),
            if (regionName != null)
              InfoRow(label: 'المنطقة', value: regionName!),

            // 💡 UPDATED: Items Total (before discount)
            InfoRow(
              label: 'إجمالي المنتجات',
              value:
                  '${itemsTotal.toStringAsFixed(2)} ج.م${hasChanges ? ' *' : ''}',
              isBold: true,
            ),

            // 💡 UPDATED: Editable Discount field - only show if not locked OR value is not zero
            if (!isLocked || (isLocked && discount > 0))
              !isLocked
                  ? _buildEditableField(
                      context: context,
                      label: 'الخصم',
                      controller: discountController,
                      onChanged: onDiscountChanged,
                      enabled: !isLocked,
                    )
                  : InfoRow(
                      label: 'الخصم',
                      value: '${discount.toStringAsFixed(2)} ج.م',
                      valueColor: AppColors.success,
                    ),

            // 💡 UPDATED: Net Total (Total - Discount)
            InfoRow(
              label: 'الصافي بعد الخصم',
              value: '${netTotal.toStringAsFixed(2)} ج.م',
              isBold: true,
            ),

            // 💡 UPDATED: Editable Paied field - only show if not locked OR value is not zero
            if (!isLocked || (isLocked && paiedAmount > 0))
              !isLocked
                  ? _buildEditableField(
                      context: context,
                      label: 'المدفوع',
                      controller: paiedController,
                      onChanged: onPaiedChanged,
                      enabled: !isLocked,
                    )
                  : InfoRow(
                      label: 'المدفوع',
                      value: '${paiedAmount.toStringAsFixed(2)} ج.م',
                    ),

            // 💡 NEW: Bill Rest (باقي الفاتورة)
            InfoRow(
              label: 'باقي الفاتورة',
              value: '${billRest.toStringAsFixed(2)} ج.م',
              valueColor: billRest > 0 ? AppColors.error : AppColors.success,
              isBold: true,
            ),

            // 💡 NEW: Total Rest (الباقي الكلي) - only show if we have internet connection, bill is not locked, and balance loading is complete
            if (internetAvailable &&
                !balanceFetchFailed &&
                !isLocked &&
                !balanceLoading)
              InfoRow(
                label: 'الباقي الكلي',
                value: '${totalRest.toStringAsFixed(2)} ج.م',
                valueColor: totalRest > 0 ? AppColors.error : AppColors.success,
                isBold: true,
              ),

            // 💡 NEW: Show loading message for total rest while balance is loading
            if (internetAvailable &&
                !balanceFetchFailed &&
                !isLocked &&
                balanceLoading)
              InfoRow(
                label: 'الباقي الكلي',
                value: 'جاري التحميل...',
                valueColor: AppColors.warning,
              ),

            if (isLocked)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Row(
                  children: [
                    Icon(Icons.lock, color: AppColors.error, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      'الفاتورة مغلقة - لا يمكن التعديل',
                      style: TextStyle(
                        color: AppColors.error,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            if (hasChanges && !isLocked)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  '* يوجد تغييرات غير محفوظة',
                  style: TextStyle(
                    color: AppColors.warning,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
