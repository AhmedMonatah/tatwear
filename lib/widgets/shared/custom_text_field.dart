import 'package:flutter/material.dart';
import '../../utils/app_styles.dart';

class CustomTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData prefixIcon;
  final TextInputType keyboardType;
  final bool readOnly;
  final String? initialValue;
  final ValueChanged<String>? onChanged;
  final FormFieldValidator<String>? validator;

  const CustomTextField({
    super.key,
    required this.controller,
    required this.label,
    required this.prefixIcon,
    this.keyboardType = TextInputType.text,
    this.readOnly = false,
    this.initialValue,
    this.onChanged,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      readOnly: readOnly,
      initialValue: initialValue,
      onChanged: onChanged,
      validator: validator,
      decoration: AppStyles.textFieldDecoration(
        label,
        context,
      ).copyWith(
        prefixIcon: Icon(
          prefixIcon,
          size: AppStyles.iconSize(context),
        ),
      ),
    );
  }
}
