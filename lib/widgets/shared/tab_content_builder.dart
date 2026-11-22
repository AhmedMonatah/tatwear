import 'package:flutter/material.dart';
import '../../utils/app_colors.dart';
import '../../utils/app_styles.dart';

/// A reusable tab content builder widget
class TabContentBuilder extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  final String status;
  final bool isSynced;
  final IconData emptyIcon;
  final String emptyMessage;
  final String statusMessage;
  final Widget Function(BuildContext, Map<String, dynamic>, bool) itemBuilder;

  const TabContentBuilder({
    super.key,
    required this.items,
    required this.status,
    required this.isSynced,
    required this.emptyIcon,
    required this.emptyMessage,
    required this.statusMessage,
    required this.itemBuilder,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                emptyIcon,
                size: 80,
                color: AppColors.secondary.withOpacity(0.5),
              ),
              const SizedBox(height: 16),
              Text(
                emptyMessage,
                style: AppStyles.heading2(context)
                    .copyWith(color: AppColors.secondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                status,
                style: AppStyles.bodyMedium(context)
                    .copyWith(color: AppColors.secondary),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        // Status Header
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isSynced
                ? AppColors.success.withOpacity(0.1)
                : AppColors.warning.withOpacity(0.1),
            border: Border(
              bottom: BorderSide(
                color: isSynced
                    ? AppColors.success.withOpacity(0.3)
                    : AppColors.warning.withOpacity(0.3),
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(
                isSynced
                    ? Icons.info_outline_rounded
                    : Icons.warning_amber_rounded,
                color: isSynced ? AppColors.success : AppColors.warning,
                size: AppStyles.iconSize(context),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  statusMessage,
                  style: AppStyles.bodyMedium(context).copyWith(
                    color: isSynced ? AppColors.success : AppColors.warning,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: items.length,
            itemBuilder: (context, index) =>
                itemBuilder(context, items[index], isSynced),
          ),
        ),
      ],
    );
  }
}

