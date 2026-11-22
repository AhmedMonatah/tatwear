import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_styles.dart';

/// Utility functions for showing snackbars across the app

void showErrorSnackBar(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        message,
        style: AppStyles.bodyMedium(
          context,
        ).copyWith(color: AppColors.background),
      ),
      backgroundColor: AppColors.error,
      duration: const Duration(seconds: 3),
    ),
  );
}

void showSuccessSnackBar(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        message,
        style: AppStyles.bodyMedium(
          context,
        ).copyWith(color: AppColors.background),
      ),
      backgroundColor: AppColors.success,

      duration: const Duration(seconds: 2),
    ),
  );
}

void showInfoSnackBar(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message, style: AppStyles.bodyMedium(context)),
      backgroundColor: Colors.blue,
      duration: const Duration(seconds: 1),
    ),
  );
}

void showEnhancedOfflineSnackBar(BuildContext context) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.cloud_off,
                color: Colors.orange.shade100,
                size: AppStyles.iconSize(context),
              ),
              SizedBox(width: AppStyles.verticalSpacing(context)),
              Text(
                'تم الحفظ محلياً',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  fontSize: AppStyles.bodyMedium(context).fontSize,
                ),
              ),
            ],
          ),
          SizedBox(height: AppStyles.verticalSpacing(context) / 2),
          Text(
            'سيتم المزامنة تلقائياً عند اتصال الإنترنت',
            style: TextStyle(
              color: Colors.orange.shade100,
              fontSize: AppStyles.bodySmall(context).fontSize,
            ),
          ),
        ],
      ),
      backgroundColor: AppColors.warning,
      duration: const Duration(seconds: 4),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}

void showSnackBar(
  BuildContext context,
  String message, {
  bool isError = false,
}) {
  if (!context.mounted) return;

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.check_circle_outline,
            color: AppColors.onPrimary,
            size: AppStyles.iconSize(context),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: AppStyles.bodyMedium(
                context,
              ).copyWith(color: AppColors.onPrimary),
            ),
          ),
        ],
      ),
      backgroundColor: isError ? AppColors.error : AppColors.success,
      duration: Duration(seconds: isError ? 3 : 2),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}
