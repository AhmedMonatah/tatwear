import 'package:flutter/material.dart';
import '../../utils/app_colors.dart';

class ConnectionStatus extends StatelessWidget {
  final bool internetAvailable;
  
  const ConnectionStatus({super.key, required this.internetAvailable});
  
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: internetAvailable 
            ? AppColors.success.withOpacity(0.1)
            : AppColors.error.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: internetAvailable ? AppColors.success : AppColors.error,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            internetAvailable ? Icons.wifi : Icons.wifi_off,
            color: internetAvailable ? AppColors.success : AppColors.error,
            size: 16,
          ),
          const SizedBox(width: 6),
          Text(
            internetAvailable ? 'متصل بالإنترنت' : 'غير متصل',
            style: TextStyle(
              color: internetAvailable ? AppColors.success : AppColors.error,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}