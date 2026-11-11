import 'package:flutter/material.dart';
import 'package:paperless_mobile/api/paperless_api.dart';
import 'package:paperless_mobile/generated/l10n/app_localizations.dart';
import 'package:paperless_mobile/helpers/custom_field_icon_mappings.dart';
import 'package:paperless_mobile/helpers/format_helpers.dart';

class CustomFieldListItem extends StatelessWidget {
  final CustomField field;
  final VoidCallback? onEdit;

  const CustomFieldListItem({super.key, required this.field, this.onEdit});

  @override
  Widget build(BuildContext context) {
    final defaultSubtitle = _dataTypeDisplayName(context, field.dataType);
    final subtitle = switch (field.dataType) {
      DataTypeEnum.monetary =>
        field.extraData is Map
            ? (field.extraData as Map)['default_currency'] != null
                  ? '$defaultSubtitle (${(field.extraData as Map)['default_currency']})'
                  : defaultSubtitle
            : defaultSubtitle,
      _ => defaultSubtitle,
    };
    return ListTile(
      title: Text(field.name),
      subtitle: Text(subtitle),
      leading: CircleAvatar(child: Icon(getCustomFieldIcon(field.dataType))),
      trailing: Text(
        formatMaxCount(field.documentCount),
        style: Theme.of(context).textTheme.bodySmall,
      ),
      onTap: onEdit,
    );
  }

  static String _dataTypeDisplayName(
    BuildContext context,
    DataTypeEnum dataType,
  ) {
    return switch (dataType) {
      DataTypeEnum.string => S.of(context)!.customFieldTypeText,
      DataTypeEnum.url => S.of(context)!.customFieldTypeUrl,
      DataTypeEnum.date => S.of(context)!.customFieldTypeDate,
      DataTypeEnum.boolean => S.of(context)!.customFieldTypeBoolean,
      DataTypeEnum.integer => S.of(context)!.customFieldTypeInteger,
      DataTypeEnum.float => S.of(context)!.customFieldTypeFloat,
      DataTypeEnum.monetary => S.of(context)!.customFieldTypeMonetary,
      DataTypeEnum.documentlink => S.of(context)!.customFieldTypeDocumentLink,
      DataTypeEnum.select => S.of(context)!.customFieldTypeSelect,
      DataTypeEnum.longtext => 'Long Text',
    };
  }
}
