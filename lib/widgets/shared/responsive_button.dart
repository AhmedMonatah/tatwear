import 'package:flutter/material.dart';
import '../../utils/app_colors.dart';
import '../../utils/app_styles.dart';

class ResponsiveButton extends StatelessWidget {
  final String text;
  final IconData icon;
  final VoidCallback onPressed;
  final bool isLoading;
  final Color backgroundColor;

  const ResponsiveButton({
    super.key,
    required this.text,
    required this.icon,
    required this.onPressed,
    this.isLoading = false,
    this.backgroundColor = AppColors.primary,
  });

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return ElevatedButton.icon(
      onPressed: isLoading ? null : onPressed,
      icon: isLoading
          ? SizedBox(
              width: screenHeight * 0.02,
              height: screenHeight * 0.02,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.onPrimary,
              ),
            )
          : Icon(icon, size: AppStyles.iconSize(context)),
      label: Text(
        text,
        style: AppStyles.bodyMedium(
          context,
        ).copyWith(fontWeight: FontWeight.bold, color: AppColors.onPrimary),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: backgroundColor,
        foregroundColor: AppColors.onPrimary,
        minimumSize: Size(double.infinity, screenHeight * 0.06),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
