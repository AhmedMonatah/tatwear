import 'package:flutter/material.dart';
import '../../utils/app_styles.dart';

/// A reusable info row widget for displaying label-value pairs
class InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final bool isBold;

  const InfoRow({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
    this.isBold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
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
            child: Text(
              value,
              style: AppStyles.bodyMedium(context).copyWith(
                color: valueColor,
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

