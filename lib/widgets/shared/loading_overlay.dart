import 'package:flutter/material.dart';
import '../../utils/app_styles.dart';

/// A reusable loading overlay widget
class LoadingOverlay extends StatelessWidget {
  final String message;
  final bool isLoading;

  const LoadingOverlay({
    super.key,
    required this.message,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    if (!isLoading) return const SizedBox.shrink();

    return Container(
      color: Colors.black54,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Colors.white),
            SizedBox(height: AppStyles.verticalSpacing(context)),
            Text(
              message,
              style: TextStyle(
                color: Colors.white,
                fontSize: AppStyles.bodyLarge(context).fontSize,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

