import 'package:flutter/material.dart';
import '../../utils/app_colors.dart';
import '../../utils/app_styles.dart';

class CustomAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  final bool? centerTitle;
  final double? elevation;

  const CustomAppBar({
    super.key,
    required this.title,
    this.actions,
    this.centerTitle,
    this.elevation,
  });

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: Text(
        title,
        style: AppStyles.heading2(context).copyWith(
          color: AppColors.onPrimary,
          fontWeight: centerTitle == true ? FontWeight.bold : null,
        ),
      ),
      backgroundColor: AppColors.primary,
      foregroundColor: AppColors.onPrimary,
      actions: actions,
      centerTitle: centerTitle,
      elevation: elevation,
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
