import 'package:cached_query_flutter/cached_query_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:go_router/go_router.dart';
import 'package:paperless_mobile/api/paperless_api.dart';
import 'package:paperless_mobile/core/extensions/context_extensions.dart';
import 'package:paperless_mobile/core/extensions/flutter_extensions.dart';
import 'package:paperless_mobile/core/translation/matching_algorithm_localization_mapper.dart';
import 'package:paperless_mobile/core/widgets/icon_loading_widget.dart';
import 'package:paperless_mobile/generated/l10n/app_localizations.dart';
import 'package:paperless_mobile/features/edit_label/view/label_form_values.dart';
import 'package:paperless_mobile/helpers/message_helpers.dart';

class SubmitButtonConfig<T extends Label, TRequest extends LabelRequest> {
  final Widget icon;
  final Widget label;
  final Mutation<T, TRequest> mutation;

  SubmitButtonConfig({
    required this.icon,
    required this.label,
    required this.mutation,
  });
}

class LabelForm<T extends Label, TRequest extends LabelRequest>
    extends StatefulWidget {
  final TRequest? initialValue;

  final SubmitButtonConfig<T, TRequest> submitButtonConfig;

  /// Type-safe builder that constructs a [TRequest] from the common
  /// [LabelFormValues] and optional additional field values read from
  /// [FormBuilderState].
  final TRequest Function(
    LabelFormValues commonValues,
    FormBuilderState formState,
  )
  buildRequest;

  /// List of additionally rendered form fields.
  final List<Widget> additionalFields;

  final bool autofocusNameField;
  final GlobalKey<FormBuilderState>? formKey;

  const LabelForm({
    super.key,
    required this.initialValue,
    required this.buildRequest,
    this.additionalFields = const [],
    required this.submitButtonConfig,
    required this.autofocusNameField,
    this.formKey,
  });

  @override
  State<LabelForm<T, TRequest>> createState() => _LabelFormState<T, TRequest>();
}

class _LabelFormState<T extends Label, TRequest extends LabelRequest>
    extends State<LabelForm<T, TRequest>> {
  late final GlobalKey<FormBuilderState> _formKey;

  late bool _enableMatchFormField;

  Map<String, String> _errors = {};

  @override
  void initState() {
    super.initState();
    _formKey = widget.formKey ?? GlobalKey<FormBuilderState>();
    var matchingAlgorithm =
        (widget.initialValue?.matchingAlgorithm ??
        MatchingAlgorithm.defaultValue);
    _enableMatchFormField =
        matchingAlgorithm != MatchingAlgorithm.auto &&
        matchingAlgorithm != MatchingAlgorithm.none;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      floatingActionButton: MutationBuilder(
        mutation: widget.submitButtonConfig.mutation,
        builder: (context, state, _) {
          return FloatingActionButton.extended(
            heroTag: "fab_label_form",
            icon: state.isLoading
                ? IconLoadingWidget()
                : widget.submitButtonConfig.icon,
            label: widget.submitButtonConfig.label,
            onPressed: state.isLoading ? null : () => _onSubmit(),
          );
        },
      ),
      body: FormBuilder(
        key: _formKey,
        child: ListView(
          children: [
            FormBuilderTextField(
              autofocus: widget.autofocusNameField,
              name: Label.nameKey,
              keyboardType: TextInputType.text,
              autocorrect: true,
              enableSuggestions: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: S.of(context)!.name,
                errorText: _errors[Label.nameKey],
              ),
              validator: (value) {
                if (value?.trim().isEmpty ?? true) {
                  return S.of(context)!.thisFieldIsRequired;
                }
                return null;
              },
              initialValue: widget.initialValue?.name,
              onChanged: (val) => setState(() => _errors = {}),
            ),
            FormBuilderDropdown<int?>(
              name: Label.matchingAlgorithmKey,
              initialValue:
                  (widget.initialValue?.matchingAlgorithm ??
                          MatchingAlgorithm.defaultValue)
                      .value,
              decoration: InputDecoration(
                labelText: S.of(context)!.matchingAlgorithm,
                errorText: _errors[Label.matchingAlgorithmKey],
              ),
              onChanged: (val) {
                setState(() {
                  _errors = {};
                  _enableMatchFormField =
                      val != MatchingAlgorithm.auto.value &&
                      val != MatchingAlgorithm.none.value;
                });
              },
              items: MatchingAlgorithm.values
                  .map(
                    (algo) => DropdownMenuItem<int?>(
                      value: algo.value,
                      child: Text(
                        translateMatchingAlgorithmDescription(context, algo),
                      ),
                    ),
                  )
                  .toList(),
            ),
            if (_enableMatchFormField)
              FormBuilderTextField(
                name: Label.matchKey,
                decoration: InputDecoration(
                  labelText: S.of(context)!.match,
                  errorText: _errors[Label.matchKey],
                ),
                initialValue: widget.initialValue?.match,
                onChanged: (val) => setState(() => _errors = {}),
              ),
            FormBuilderField<bool>(
              name: Label.isInsensitiveKey,
              initialValue: widget.initialValue?.isInsensitive ?? true,
              builder: (field) {
                return CheckboxListTile(
                  value: field.value,
                  title: Text(S.of(context)!.caseIrrelevant),
                  onChanged: (value) => field.didChange(value),
                );
              },
            ),
            ...widget.additionalFields,
          ].padded(),
        ),
      ),
    );
  }

  void _onSubmit() async {
    final owner = context.uiSettings.user.id;

    if (_formKey.currentState?.saveAndValidate() ?? false) {
      try {
        final formState = _formKey.currentState!;
        final commonValues = LabelFormValues(
          name: formState.value[Label.nameKey] as String,
          match: formState.value[Label.matchKey] as String?,
          matchingAlgorithm: formState.value[Label.matchingAlgorithmKey] != null
              ? MatchingAlgorithm.values.firstWhere(
                  (e) => e.value == formState.value[Label.matchingAlgorithmKey],
                )
              : null,
          isInsensitive: formState.value[Label.isInsensitiveKey] as bool?,
          owner: widget.initialValue != null
              ? widget.initialValue?.owner
              : owner,
        );
        final parsed = widget.buildRequest(commonValues, formState);
        final mutationResult = await widget.submitButtonConfig.mutation.mutate(
          parsed,
        );
        if (mutationResult is MutationError) {
          throw (mutationResult as MutationError).error;
        }
        if (mounted) context.pop(mutationResult.data);
      } on PaperlessApiException catch (error, stackTrace) {
        if (mounted) showErrorMessage(context, error, stackTrace);
      } on PaperlessFormValidationException catch (exception) {
        setState(() => _errors = exception.validationMessages);
      } catch (error, stackTrace) {
        if (mounted) {
          showGenericError(context, error, stackTrace);
        }
      }
    }
  }
}
