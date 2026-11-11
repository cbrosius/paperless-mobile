import 'dart:developer';

import 'package:cached_query_flutter/cached_query_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:go_router/go_router.dart';
import 'package:paperless_mobile/api/paperless_api.dart';
import 'package:paperless_mobile/core/extensions/flutter_extensions.dart';
import 'package:paperless_mobile/core/widgets/dialog_utils/dialog_cancel_button.dart';
import 'package:paperless_mobile/core/widgets/dialog_utils/dialog_confirm_button.dart';
import 'package:paperless_mobile/core/widgets/dialog_utils/pop_with_unsaved_changes.dart';
import 'package:paperless_mobile/core/widgets/icon_loading_widget.dart';
import 'package:paperless_mobile/features/labels/custom_fields/view/custom_field_conditional_form_fields.dart';
import 'package:paperless_mobile/generated/l10n/app_localizations.dart';
import 'package:paperless_mobile/helpers/custom_field_icon_mappings.dart';
import 'package:paperless_mobile/helpers/message_helpers.dart';

class EditCustomFieldPage extends StatelessWidget {
  final CustomField customField;
  final Mutation<CustomField, CustomFieldRequest> editMutation;
  final Mutation<int, void> deleteMutation;
  final bool canDelete;

  const EditCustomFieldPage({
    super.key,
    required this.customField,
    required this.editMutation,
    required this.deleteMutation,
    required this.canDelete,
  });

  @override
  Widget build(BuildContext context) {
    return _EditCustomFieldForm(
      customField: customField,
      editMutation: editMutation,
      deleteMutation: deleteMutation,
      canDelete: canDelete,
    );
  }
}

class _EditCustomFieldForm extends StatelessWidget {
  final CustomField customField;
  final Mutation<CustomField, CustomFieldRequest> editMutation;
  final Mutation<int, void> deleteMutation;
  final bool canDelete;
  final _formKey = GlobalKey<FormBuilderState>();

  _EditCustomFieldForm({
    required this.customField,
    required this.editMutation,
    required this.deleteMutation,
    required this.canDelete,
  });

  @override
  Widget build(BuildContext context) {
    return PopWithUnsavedChanges(
      hasChangesPredicate: () {
        return _formKey.currentState?.isDirty ?? false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(S.of(context)!.editCustomField),
          actions: [
            MutationBuilder(
              mutation: deleteMutation,
              builder: (context, state, _) {
                return IconButton(
                  onPressed: canDelete && !state.isLoading
                      ? () => _onDelete(context)
                      : null,
                  icon: state.isLoading
                      ? const IconLoadingWidget()
                      : Icon(Icons.delete),
                ).paddedOnly(right: 8);
              },
            ),
          ],
        ),
        body: _CustomFieldEditForm(
          formKey: _formKey,
          customField: customField,
          editMutation: editMutation,
        ),
      ),
    );
  }

  void _onDelete(BuildContext context) async {
    if (customField.documentCount > 0) {
      final shouldDelete =
          await showDialog<bool>(
            useRootNavigator: false,
            context: context,
            builder: (context) => AlertDialog(
              title: Text(S.of(context)!.confirmDeletion),
              content: Text(S.of(context)!.deleteCustomFieldWarningText),
              actions: [
                const DialogCancelButton(),
                DialogConfirmButton(
                  label: S.of(context)!.delete,
                  style: DialogConfirmButtonStyle.danger,
                ),
              ],
            ),
          ) ??
          false;
      if (shouldDelete) {
        try {
          final mutationResult = await deleteMutation.mutate();
          if (mutationResult is MutationError) {
            throw (mutationResult as MutationError).error;
          }
          if (context.mounted) {
            context.pop();
          }
        } on PaperlessApiException catch (error) {
          if (context.mounted) {
            showErrorMessage(context, error);
          }
        } catch (error, stackTrace) {
          log("An error occurred!", error: error, stackTrace: stackTrace);
        }
      }
    } else {
      deleteMutation.mutate();
      context.pop();
    }
  }
}

class _CustomFieldEditForm extends StatefulWidget {
  final GlobalKey<FormBuilderState> formKey;
  final CustomField customField;
  final Mutation<CustomField, CustomFieldRequest> editMutation;

  const _CustomFieldEditForm({
    required this.formKey,
    required this.customField,
    required this.editMutation,
  });

  @override
  State<_CustomFieldEditForm> createState() => _CustomFieldEditFormState();
}

class _CustomFieldEditFormState extends State<_CustomFieldEditForm> {
  Map<String, String> _errors = {};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      floatingActionButton: MutationBuilder(
        mutation: widget.editMutation,
        builder: (context, state, mutate) {
          return FloatingActionButton.extended(
            heroTag: "fab_custom_field_edit_form",
            icon: state.isLoading
                ? const IconLoadingWidget()
                : const Icon(Icons.save),
            label: Text(S.of(context)!.saveChanges),
            onPressed: state.isLoading ? null : _onSubmit,
          );
        },
      ),
      body: FormBuilder(
        key: widget.formKey,
        child: ListView(
          children: [
            FormBuilderTextField(
              autofocus: false,
              name: 'name',
              decoration: InputDecoration(
                labelText: S.of(context)!.customFieldName,
                errorText: _errors['name'],
              ),
              validator: (value) {
                if (value?.trim().isEmpty ?? true) {
                  return S.of(context)!.thisFieldIsRequired;
                }
                return null;
              },
              initialValue: widget.customField.name,
              onChanged: (val) => setState(() => _errors = {}),
            ),
            FormBuilderDropdown<DataTypeEnum>(
              name: 'data_type',
              enabled: false, // Editing data type is not allowed.
              initialValue: widget.customField.dataType,
              decoration: InputDecoration(
                labelText: S.of(context)!.customFieldDataType,
                errorText: _errors['data_type'],
              ),
              items: DataTypeEnum.values
                  .map(
                    (type) => DropdownMenuItem<DataTypeEnum>(
                      value: type,

                      child: Row(
                        spacing: 4,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Icon(getCustomFieldIcon(type)),
                          Text(_dataTypeDisplayName(type)),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
            CustomFieldConditionalFormFields(
              dataType: widget.customField.dataType,
              extraData: widget.customField.extraData as Map<String, dynamic>?,
            ),
          ].padded(),
        ),
      ),
    );
  }

  void _onSubmit() async {
    if (widget.formKey.currentState?.saveAndValidate() ?? false) {
      try {
        final formState = widget.formKey.currentState!;
        final selectOptions =
            formState.value['select_options'] as List<Map<String, dynamic>>?;
        final defaultCurrency = formState.value['default_currency'] as String?;
        final extraData = <String, dynamic>{
          'select_options': selectOptions ?? [],
          'default_currency': defaultCurrency,
        };
        final request = CustomFieldRequest(
          name: formState.value['name'] as String,
          dataType: formState.value['data_type'] as DataTypeEnum,
          extraData: extraData,
        );
        final mutationResult = await widget.editMutation.mutate(request);
        if (mutationResult is MutationError) {
          throw (mutationResult as MutationError).error;
        }
        if (mounted) context.pop(mutationResult.data);
      } on PaperlessApiException catch (error, stackTrace) {
        if (mounted) showErrorMessage(context, error, stackTrace);
      } on PaperlessFormValidationException catch (exception) {
        if (exception.hasUnspecificErrorMessage()) {
          if (mounted) {
            showGenericError(context, exception.unspecificErrorMessage() ?? "");
          }
          return;
        }
        setState(() => _errors = exception.validationMessages);
      } catch (error, stackTrace) {
        if (mounted) {
          showGenericError(context, error, stackTrace);
        }
      }
    }
  }

  static String _dataTypeDisplayName(DataTypeEnum dataType) {
    return switch (dataType) {
      DataTypeEnum.string => 'Text',
      DataTypeEnum.url => 'URL',
      DataTypeEnum.date => 'Date',
      DataTypeEnum.boolean => 'Boolean',
      DataTypeEnum.integer => 'Integer',
      DataTypeEnum.float => 'Float',
      DataTypeEnum.monetary => 'Monetary',
      DataTypeEnum.documentlink => 'Document Link',
      DataTypeEnum.select => 'Select',
      DataTypeEnum.longtext => 'Long Text',
    };
  }
}
