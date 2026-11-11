import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class MonetaryFieldValue extends StatelessWidget {
  final Object? value;
  final Object? extraData;
  final TextStyle? style;
  final Widget placeholder;

  const MonetaryFieldValue({
    super.key,
    required this.value,
    this.extraData,
    this.style,
    required this.placeholder,
  });

  String? _getDefaultCurrency() {
    if (extraData is Map) {
      final currency = (extraData as Map)['default_currency'];
      if (currency is String && currency.trim().isNotEmpty) {
        return currency.trim();
      }
    }
    return null;
  }

  (String?, double?) _parseValue() {
    if (value == null) return (null, null);
    if (value is num) return (null, (value as num).toDouble());
    final raw = '$value'.trim();
    if (raw.isEmpty) return (null, null);

    // E.g. "EUR12.50" or "EUR 12.50"
    final prefixMatch = RegExp(r'^([A-Za-z]{3})\s*(-?\d+(?:[.,]\d+)?)$').firstMatch(raw);
    if (prefixMatch != null) {
      final code = prefixMatch.group(1);
      final amount = double.tryParse(prefixMatch.group(2)!.replaceAll(',', '.'));
      return (code, amount);
    }

    // E.g. "12.50 EUR" or "12.50EUR"
    final suffixMatch = RegExp(r'^(-?\d+(?:[.,]\d+)?)\s*([A-Za-z]{3})$').firstMatch(raw);
    if (suffixMatch != null) {
      final amount = double.tryParse(suffixMatch.group(1)!.replaceAll(',', '.'));
      final code = suffixMatch.group(2);
      return (code, amount);
    }

    // Pure number
    final amount = double.tryParse(raw.replaceAll(',', '.'));
    return (null, amount);
  }

  @override
  Widget build(BuildContext context) {
    if (value == null) return placeholder;

    final (parsedCode, amount) = _parseValue();
    if (amount == null) {
      return Text('$value', style: style);
    }

    final currencyCode = parsedCode ?? _getDefaultCurrency();
    String? localeName;
    try {
      localeName = Localizations.localeOf(context).toString();
    } catch (_) {}

    try {
      final formatter = NumberFormat.simpleCurrency(
        locale: localeName,
        name: currencyCode,
      );
      return Text(formatter.format(amount), style: style);
    } catch (_) {
      if (currencyCode != null) {
        return Text('$amount $currencyCode', style: style);
      }
      return Text('$amount', style: style);
    }
  }
}
