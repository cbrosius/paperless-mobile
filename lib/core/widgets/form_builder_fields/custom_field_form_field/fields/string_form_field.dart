import 'package:flutter/material.dart';
import 'package:paperless_mobile/api/paperless_api.dart';
import 'package:paperless_mobile/helpers/custom_field_icon_mappings.dart';

/// A form field for editing a string custom field value.
class StringFormField extends StatefulWidget {
  final String labelText;
  final Object? value;
  final bool enabled;
  final ValueChanged<Object?> onChanged;
  final String? errorText;

  const StringFormField({
    super.key,
    required this.labelText,
    required this.value,
    required this.enabled,
    required this.onChanged,
    this.errorText,
  });

  @override
  State<StringFormField> createState() => _StringFormFieldState();
}

class _StringFormFieldState extends State<StringFormField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value?.toString() ?? '');
    _controller.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(covariant StringFormField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value?.toString() != oldWidget.value?.toString()) {
      _controller.removeListener(_onTextChanged);
      _controller.text = widget.value?.toString() ?? '';
      _controller.addListener(_onTextChanged);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final text = _controller.text;
    widget.onChanged(text.isEmpty ? null : text);
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      enabled: widget.enabled,
      keyboardType: TextInputType.text,
      autocorrect: true,
      enableSuggestions: true,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(
        prefixIcon: Icon(getCustomFieldIcon(DataTypeEnum.string)),
        labelText: widget.labelText,
        errorText: widget.errorText,
        isDense: true,
      ),
    );
  }
}
