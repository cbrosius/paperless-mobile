import 'package:cached_query_flutter/cached_query_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:paperless_mobile/api/paperless_api.dart';
import 'package:paperless_mobile/core/extensions/context_extensions.dart';
import 'package:paperless_mobile/core/extensions/flutter_extensions.dart';
import 'package:paperless_mobile/core/widgets/form_builder_fields/custom_field_form_field/form_builder_custom_field_instance.dart';

/// A single [FormBuilderField] that manages a [List<CustomFieldInstance>].
///
/// Instead of creating individual form fields per custom field instance
/// (and tracking additions/removals via widget state), this widget wraps the
/// entire list as one form value. Adding or removing a custom field simply
/// updates the list, and value changes within a field update the corresponding
/// entry in the list.
class FormBuilderCustomFieldsField extends StatelessWidget {
  final int parentDocumentId;
  final String name;
  final List<CustomFieldInstance> initialValue;

  const FormBuilderCustomFieldsField({
    super.key,
    required this.name,
    this.initialValue = const [],
    required this.parentDocumentId,
  });

  @override
  Widget build(BuildContext context) {
    return FormBuilderField<List<CustomFieldInstance>>(
      name: name,
      initialValue: initialValue,
      builder: (field) {
        return QueryBuilder(
          query: context.customFieldRepository.getAllQuery(),
          builder: (context, customFieldsState) {
            final allCustomFields = customFieldsState.data;
            if (allCustomFields == null) {
              return const SizedBox.shrink();
            }
            final customFieldMap = {for (final cf in allCustomFields) cf.id: cf};
            final instances = field.value ?? [];

            return Column(
              spacing: 12,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final instance in instances)
                  if (customFieldMap.containsKey(instance.field))
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: CustomFieldValueEditor(
                            parentDocumentId: parentDocumentId,
                            labelText: customFieldMap[instance.field]!.name,
                            dataType: customFieldMap[instance.field]!.dataType,
                            value: instance.value,
                            extraData:
                                customFieldMap[instance.field]!.extraData,
                            enabled: true,
                            onChanged: (newValue) {
                              final updated = instances.map((i) {
                                if (i.field == instance.field) {
                                  return CustomFieldInstance(
                                    field: i.field,
                                    value: newValue,
                                  );
                                }
                                return i;
                              }).toList();
                              field.didChange(updated);
                            },
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.delete_outline,
                            color: Theme.of(context).colorScheme.error,
                          ),
                          tooltip: MaterialLocalizations.of(
                            context,
                          ).deleteButtonTooltip,
                          onPressed: () {
                            final updated = instances
                                .where((i) => i.field != instance.field)
                                .toList();
                            field.didChange(updated);
                          },
                        ).paddedSymmetrically(horizontal: 4),
                      ],
                    ),
              ],
            );
          },
        );
      },
    );
  }
}
