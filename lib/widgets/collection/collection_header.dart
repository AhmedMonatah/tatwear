import 'package:flutter/material.dart';
import 'package:tatweer/utils/app_colors.dart';
import 'package:tatweer/utils/app_styles.dart';
import 'package:tatweer/utils/helpers.dart';
import 'package:tatweer/widgets/shared/info_row.dart';

class CollectionHeaderWidget extends StatelessWidget {
  final Map<String, dynamic> collection;
  final String regionName;
  final bool hasChanges;
  final bool isLocked;
  final double amount;
  final TextEditingController amountController;
  final Function(String) onAmountChanged;
  final String notes;
  final TextEditingController notesController;
  final Function(String) onNotesChanged;

  const CollectionHeaderWidget({
    super.key,
    required this.collection,
    required this.regionName,
    required this.hasChanges,
    required this.isLocked,
    required this.amount,
    required this.amountController,
    required this.onAmountChanged,
    required this.notes,
    required this.notesController,
    required this.onNotesChanged,
  });


  Widget _buildEditableAmountField({
    required BuildContext context,
    required TextEditingController controller,
    required Function(String) onChanged,
    required bool enabled,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Text(
            'المبلغ: ',
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
          const SizedBox(width: 8),
          const Text('ج.م'),
        ],
      ),
    );
  }

  Widget _buildEditableNotesField({
    required BuildContext context,
    required TextEditingController controller,
    required Function(String) onChanged,
    required bool enabled,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ملاحظات: ',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: AppStyles.bodyMedium(context).fontSize,
            ),
          ),
          const SizedBox(height: 4),
          TextFormField(
            controller: controller,
            maxLines: 3,
            enabled: enabled,
            textAlign: TextAlign.right,
            decoration: InputDecoration(
              hintText: 'أدخل ملاحظات هنا...',
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              alignLabelWithHint: true,
            ),
            onChanged: onChanged,
          ),
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
            InfoRow(
              label: 'رقم الفاتورة',
              value: getSafeString(collection['Bill']),
            ),
            InfoRow(label: 'التاريخ', value: getSafeString(collection['TheDate'])),
            InfoRow(
              label: 'العميل',
              value: getSafeString(collection['ClientName']),
            ),
            InfoRow(label: 'المنطقة', value: regionName),

            // Editable Amount field
            if (!isLocked)
              _buildEditableAmountField(
                context: context,
                controller: amountController,
                onChanged: onAmountChanged,
                enabled: !isLocked,
              )
            else
              InfoRow(
                label: 'المبلغ',
                value: '${amount.toStringAsFixed(2)} ج.م',
                valueColor: AppColors.primary,
                isBold: true,
              ),

            // Editable Notes field
            if (!isLocked)
              _buildEditableNotesField(
                context: context,
                controller: notesController,
                onChanged: onNotesChanged,
                enabled: !isLocked,
              )
            else if (getSafeString(collection['Notes'], '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ملاحظات: ',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: AppStyles.bodyMedium(context).fontSize,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      getSafeString(collection['Notes']),
                      style: AppStyles.bodyMedium(context),
                    ),
                  ],
                ),
              ),

            if (isLocked)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Row(
                  children: [
                    Icon(Icons.lock, color: AppColors.error, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      'فاتورة التحصيل مغلقة - لا يمكن التعديل',
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