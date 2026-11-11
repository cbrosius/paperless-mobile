import 'package:paperless_mobile/api/constants/api_date_format.dart';

/// A wrapper type that represents a value that can be:
/// 1. Not provided (field is `null` in Dart) - excluded from JSON
/// 2. Explicitly set to null (`PatchedValue(null)`) - included as `null` in JSON
/// 3. Set to a value (`PatchedValue(value)`) - included as `value` in JSON
///
/// This solves the common PATCH request problem where you need to differentiate
/// between "don't change this field" and "set this field to null".
class PatchedValue<T> {
  final T value;

  const PatchedValue(this.value);

  /// Returns the PatchedValue itself so that json_serializable can serialize it.
  /// The actual serialization is handled by [processPatchedValueJson].
  PatchedValue<T> toJson() => this;

  @override
  String toString() => 'PatchedValue($value)';
}

/// Processes a JSON map and handles PatchedValue and Option serialization properly.
///
/// For PatchedValue:
/// - Fields where the PatchedValue itself is null are excluded (not provided)
/// - Fields where PatchedValue wraps null are included as null (explicitly set to null)
/// - Fields where PatchedValue wraps a value are included with that value
///
/// For Option (fpdart):
/// - Fields where Option is null are excluded (not provided)
/// - Fields where Option is None() are included as null (explicitly set to null)
/// - Fields where Option is Some(value) are included with that value
Map<String, dynamic> processPatchedValueJson(Map<String, dynamic> json) {
  final result = <String, dynamic>{};

  for (final entry in json.entries) {
    final key = entry.key;
    final value = entry.value;

    if (value is PatchedValue) {
      // PatchedValue was explicitly set - include it (even if inner value is null)
      final innerValue = value.value;
      result[key] = _serializeValue(innerValue);
    } else {
      // Regular value - include as-is
      result[key] = value;
    }
  }

  return result;
}

/// Helper to serialize values with special handling for DateTime
dynamic _serializeValue(dynamic value) {
  if (value is DateTime) {
    if (value.hour == 0 &&
        value.minute == 0 &&
        value.second == 0 &&
        value.millisecond == 0) {
      return apiDateFormat.format(value);
    }
    return value.toIso8601String();
  }

  if (value is List) {
    return value.map(_serializeValue).toList();
  }

  try {
    return value.toJson();
  } on NoSuchMethodError {
    return value;
  }
}
