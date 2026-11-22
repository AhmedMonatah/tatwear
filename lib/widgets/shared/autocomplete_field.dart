import 'package:flutter/material.dart';
import '../../utils/app_colors.dart';
import '../../utils/app_styles.dart';

class AutocompleteField extends StatefulWidget {
  final String label;
  final List<Map<String, dynamic>> options;
  final String displayKey;
  final Function(Map<String, dynamic>) onSelected;
  final Map<String, dynamic>? selectedValue;
  final Function() onClear;
  final IconData icon;
  final String? filterKey;
  final dynamic filterValue;
  final bool required;
  final Key? fieldKey;

  const AutocompleteField({
    super.key,
    required this.label,
    required this.options,
    required this.displayKey,
    required this.onSelected,
    required this.selectedValue,
    required this.onClear,
    required this.icon,
    this.filterKey,
    this.filterValue,
    this.required = false,
    this.fieldKey,
  });

  @override
  State<AutocompleteField> createState() => _AutocompleteFieldState();
}

class _AutocompleteFieldState extends State<AutocompleteField> {
  FocusNode? _focusNode;
  TextEditingController? _controller;
  Map<String, dynamic>? _lastSelectedValue;
  String? _validationError;

  @override
  void initState() {
    super.initState();
    _lastSelectedValue = widget.selectedValue;
  }

  @override
  void didUpdateWidget(covariant AutocompleteField oldWidget) {
    super.didUpdateWidget(oldWidget);

    // تحديث النص فقط إذا تغيرت القيمة المختارة من الخارج
    if (widget.selectedValue != _lastSelectedValue) {
      _lastSelectedValue = widget.selectedValue;
      final newText = widget.selectedValue != null
          ? (widget.selectedValue![widget.displayKey]?.toString() ?? '')
          : '';

      if (_controller != null && _controller!.text != newText) {
        _controller!.text = newText;
      }
      if (widget.selectedValue != null && _validationError != null) {
        setState(() => _validationError = null);
      }
    }
  }

  @override
  void dispose() {
    _focusNode?.removeListener(_onFocusChange);
    super.dispose();
  }

  void _onFocusChange() {
    if (_focusNode == null) return;

    // عندما يخرج المستخدم من الخانة (Focus Lost)
    if (!_focusNode!.hasFocus) {
      final text = _controller?.text.trim() ?? '';

      // إذا كانت الخانة فارغة
      if (text.isEmpty) {
        if (widget.selectedValue != null) {
          widget.onClear();
        }
        if (_validationError != null) {
          setState(() => _validationError = null);
        }
        return;
      }

      // إذا كان هناك اختيار مسبق والنص مطابق له
      if (widget.selectedValue != null) {
        final selectedText =
            (widget.selectedValue![widget.displayKey]?.toString() ?? '').trim();
        if (selectedText.toLowerCase() == text.toLowerCase()) {
          if (_validationError != null) {
            setState(() => _validationError = null);
          }
          return;
        }
      }

      // البحث الذكي: إذا كتب المستخدم اسماً ولم يضغط على القائمة المنسدلة
      final availableOptions = _getFilteredOptions();

      // 1. تطابق تام
      final exactMatches = availableOptions.where((item) {
        final val = (item[widget.displayKey]?.toString() ?? '').trim();
        return val.toLowerCase() == text.toLowerCase();
      }).toList();

      if (exactMatches.isNotEmpty) {
        final match = exactMatches.first;
        widget.onSelected(match);
        _lastSelectedValue = match;
        _controller?.text = (match[widget.displayKey]?.toString() ?? '').trim();
        if (_validationError != null) {
          setState(() => _validationError = null);
        }
        return;
      }

      // 2. تطابق جزئي وحيد
      final partialMatches = availableOptions.where((item) {
        final val = (item[widget.displayKey]?.toString() ?? '').trim();
        return val.toLowerCase().contains(text.toLowerCase());
      }).toList();

      if (partialMatches.length == 1) {
        final match = partialMatches.first;
        widget.onSelected(match);
        _lastSelectedValue = match;
        _controller?.text = (match[widget.displayKey]?.toString() ?? '').trim();
        if (_validationError != null) {
          setState(() => _validationError = null);
        }
        return;
      }

      // 3. النص المكتوب لا يطابق أي عنصر بالقائمة
      // لا نقوم بمسح النص، بل ننبه المستخدم
      if (mounted) {
        setState(() {
          _validationError =
              'يرجى اختيار ${_cleanLabel(widget.label)} من القائمة المنسدلة';
        });
      }
    }
  }

  String _cleanLabel(String label) {
    return label.replaceAll('*', '').trim();
  }

  Iterable<Map<String, dynamic>> _getFilteredOptions() {
    Iterable<Map<String, dynamic>> filtered = widget.options;
    if (widget.filterKey != null && widget.filterValue != null) {
      filtered = widget.options.where(
        (item) =>
            item[widget.filterKey]?.toString() == widget.filterValue.toString(),
      );
    }
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final filteredOptions = _getFilteredOptions();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Autocomplete<Map<String, dynamic>>(
          key: widget.fieldKey,
          optionsBuilder: (TextEditingValue textEditingValue) {
            if (textEditingValue.text.isEmpty) {
              return filteredOptions;
            }

            return filteredOptions.where(
              (item) => (item[widget.displayKey]?.toString() ?? '')
                  .toLowerCase()
                  .contains(textEditingValue.text.toLowerCase()),
            );
          },
          displayStringForOption: (opt) =>
              (opt[widget.displayKey]?.toString() ?? 'غير محدد'),
          onSelected: (value) {
            _lastSelectedValue = value;
            widget.onSelected(value);
            if (_validationError != null) {
              setState(() => _validationError = null);
            }
            _focusNode?.unfocus();
          },
          fieldViewBuilder:
              (context, textEditingController, focusNode, onFieldSubmitted) {
            if (_focusNode != focusNode) {
              _focusNode?.removeListener(_onFocusChange);
              _focusNode = focusNode;
              _focusNode!.addListener(_onFocusChange);
            }

            _controller = textEditingController;

            // ضبط القيمة الأولية إذا لم تكن مضبوطة
            if (widget.selectedValue != null &&
                textEditingController.text.isEmpty) {
              final initialText =
                  (widget.selectedValue![widget.displayKey] ?? '').toString();
              if (initialText.isNotEmpty) {
                textEditingController.text = initialText;
              }
            }

            return TextFormField(
              controller: textEditingController,
              focusNode: focusNode,
              autofocus: false,
              onTap: () {
                if (_validationError != null) {
                  setState(() => _validationError = null);
                }
              },
              onChanged: (value) {
                if (_validationError != null) {
                  setState(() => _validationError = null);
                }
                if (widget.selectedValue != null && value.isEmpty) {
                  _lastSelectedValue = null;
                  widget.onClear();
                }
              },
              decoration: AppStyles.textFieldDecoration(
                '${widget.label}${widget.required ? ' *' : ''}',
                context,
              ).copyWith(
                prefixIcon: Icon(
                  widget.icon,
                  size: AppStyles.iconSize(context),
                  color: _validationError != null
                      ? AppColors.error
                      : (widget.selectedValue != null
                          ? AppColors.primary
                          : null),
                ),
                suffixIcon: (widget.selectedValue != null ||
                        textEditingController.text.isNotEmpty)
                    ? IconButton(
                        icon: Icon(
                          Icons.clear,
                          size: AppStyles.iconSize(context),
                        ),
                        onPressed: () {
                          _lastSelectedValue = null;
                          widget.onClear();
                          textEditingController.clear();
                          if (_validationError != null) {
                            setState(() => _validationError = null);
                          }
                          focusNode.requestFocus();
                        },
                      )
                    : null,
              ),
            );
          },
          optionsViewBuilder: (context, onSelected, options) {
            return Align(
              alignment: Alignment.topRight,
              child: Material(
                elevation: 6.0,
                borderRadius: BorderRadius.circular(10),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.35,
                    maxWidth: MediaQuery.of(context).size.width - 32,
                  ),
                  child: options.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Text(
                            'لا توجد نتائج مطابقة',
                            style: AppStyles.bodyMedium(context),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          shrinkWrap: true,
                          itemCount: options.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1, indent: 16, endIndent: 16),
                          itemBuilder: (context, index) {
                            final option = options.elementAt(index);
                            final title =
                                (option[widget.displayKey] ?? '').toString();

                            return ListTile(
                              dense: true,
                              title: Text(
                                title,
                                style: AppStyles.bodyMedium(context).copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              onTap: () {
                                onSelected(option);
                              },
                            );
                          },
                        ),
                ),
              ),
            );
          },
        ),
        if (_validationError != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, right: 12),
            child: Text(
              _validationError!,
              style: TextStyle(
                color: AppColors.error,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }
}
