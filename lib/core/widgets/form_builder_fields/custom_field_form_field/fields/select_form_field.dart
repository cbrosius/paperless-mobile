import 'package:flutter/material.dart';

/// A form field for editing a select custom field value.
///
/// Options are extracted from `extraData`, which has the structure:
/// ```json
/// {
///   "select_options": [
///     { "value": <dynamic>, "label": "<string>" }
///   ]
/// }
/// ```
class SelectFormField extends StatelessWidget {
  final String labelText;
  final Object? value;
  final Object? extraData;
  final bool enabled;
  final ValueChanged<Object?> onChanged;
  final String? errorText;

  const SelectFormField({
    super.key,
    required this.labelText,
    required this.value,
    required this.extraData,
    required this.enabled,
    required this.onChanged,
    this.errorText,
  });

  List<Map<String, dynamic>> _parseOptions() {
    if (extraData is Map) {
      final options = (extraData as Map)['select_options'];
      if (options is List) {
        return options
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    }
    return [];
  }

  @override
  Widget build(BuildContext context) {
    final options = _parseOptions();

    return DropdownButtonFormField<Object?>(
      initialValue: _findMatchingValue(options),
      onChanged: enabled ? onChanged : null,
      decoration: InputDecoration(
        labelText: labelText,
        errorText: errorText,
        isDense: true,
      ),
      items: [
        // Allow clearing the selection.
        const DropdownMenuItem<Object?>(value: null, child: Text('-')),
        ...options.map(
          (option) {
            final optId = option['id'] ?? option['value'];
            return DropdownMenuItem<Object?>(
              value: optId,
              child: Text('${option['label'] ?? optId}'),
            );
          },
        ),
      ],
    );
  }

  /// Finds the matching option value, accounting for type differences
  /// (e.g. the value may be stored as an int or string).
  Object? _findMatchingValue(List<Map<String, dynamic>> options) {
    if (value == null) return null;
    for (final option in options) {
      final optId = option['id'] ?? option['value'];
      if (optId == value || '$optId' == '$value') {
        return optId;
      }
    }
    return null;
  }
}
