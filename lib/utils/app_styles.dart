import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppStyles {
  // Responsive text styles
  static TextStyle heading1(BuildContext context) {
    final height = MediaQuery.of(context).size.height;
    return TextStyle(
      fontSize: height > 800 ? 24 : 20,
      fontWeight: FontWeight.bold,
      color: AppColors.onSurface,
    );
  }

  static TextStyle heading2(BuildContext context) {
    final height = MediaQuery.of(context).size.height;
    return TextStyle(
      fontSize: height > 800 ? 20 : 18,
      fontWeight: FontWeight.w600,
      color: AppColors.onSurface,
    );
  }

  static TextStyle bodyLarge(BuildContext context) {
    final height = MediaQuery.of(context).size.height;
    return TextStyle(
      fontSize: height > 800 ? 16 : 14,
      color: AppColors.onSurface,
    );
  }

  static TextStyle bodyMedium(BuildContext context) {
    final height = MediaQuery.of(context).size.height;
    return TextStyle(
      fontSize: height > 800 ? 14 : 13,
      color: AppColors.onSurface,
    );
  }

  static TextStyle bodySmall(BuildContext context) {
    final height = MediaQuery.of(context).size.height;
    return TextStyle(
      fontSize: height > 800 ? 12 : 11,
      color: AppColors.secondary,
    );
  }

  // Responsive button styles
  static ButtonStyle primaryButton(BuildContext context) {
    final height = MediaQuery.of(context).size.height;
    return ElevatedButton.styleFrom(
      backgroundColor: AppColors.primary,
      foregroundColor: AppColors.onPrimary,
      minimumSize: Size(double.infinity, height > 800 ? 50 : 45),
      textStyle: bodyLarge(context).copyWith(fontWeight: FontWeight.bold),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  static ButtonStyle secondaryButton(BuildContext context) {
    final height = MediaQuery.of(context).size.height;
    return ElevatedButton.styleFrom(
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.primary,
      minimumSize: Size(double.infinity, height > 800 ? 50 : 45),
      textStyle: bodyLarge(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.primary),
      ),
    );
  }

  // Card style
  static BoxDecoration cardDecoration = BoxDecoration(
    color: AppColors.surface,
    borderRadius: BorderRadius.circular(12),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withOpacity(0.1),
        blurRadius: 8,
        offset: const Offset(0, 2),
      ),
    ],
  );

  // Input decoration
  static InputDecoration textFieldDecoration(
    String label,
    BuildContext context,
  ) {
    final height = MediaQuery.of(context).size.height;
    return InputDecoration(
      labelText: label,
      labelStyle: bodyMedium(context),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.secondary),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary),
      ),
      contentPadding: EdgeInsets.symmetric(
        horizontal: 16,
        vertical: height > 800 ? 16 : 12,
      ),
    );
  }

  // Responsive padding
  static EdgeInsets screenPadding(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return EdgeInsets.all(width > 600 ? 24 : 16);
  }

  // Responsive spacing
  static double verticalSpacing(BuildContext context) {
    final height = MediaQuery.of(context).size.height;
    return height > 800 ? 16 : 12;
  }

  // Responsive icon size
  static double iconSize(BuildContext context) {
    final height = MediaQuery.of(context).size.height;
    return height > 800 ? 24 : 20;
  }
}
