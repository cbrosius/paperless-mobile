import 'package:animations/animations.dart';
import 'package:cached_query_flutter/cached_query_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:paperless_mobile/api/paperless_api.dart';
import 'package:paperless_mobile/core/extensions/context_extensions.dart';
import 'package:paperless_mobile/core/extensions/flutter_extensions.dart';
import 'package:paperless_mobile/core/extensions/label_list_extension.dart';
import 'package:paperless_mobile/features/labels/tags/view/widgets/fullscreen_tags_form.dart';
import 'package:paperless_mobile/features/labels/view/widgets/query_label_option_chip.dart';
import 'package:paperless_mobile/generated/l10n/app_localizations.dart';

class TagsFormField extends StatelessWidget {
  final String name;
  final TagsQuery? initialValue;
  final bool allowCreation;
  final bool allowExclude;
  final Iterable<int> suggestions;

  const TagsFormField({
    super.key,
    this.initialValue,
    required this.name,
    required this.allowCreation,
    required this.allowExclude,
    this.suggestions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return QueryBuilder(
      query: context.tagRepository.getAllQuery(),
      builder: (context, state) {
        final options = state.data?.toIdMap() ?? {};
        final enabled = options.values.isNotEmpty || allowCreation;

        return FormBuilderField<TagsQuery?>(
          name: name,
          initialValue: initialValue,
          enabled: enabled,
          builder: (field) {
            final children = _generateOptions(
              context,
              field.value,
              field,
              options,
            );

            return Column(
              children: [
                OpenContainer<TagsQuery>(
                  middleColor: Theme.of(context).colorScheme.surface,
                  closedColor: Theme.of(context).colorScheme.surface,
                  openColor: Theme.of(context).colorScheme.surface,
                  closedShape: InputBorder.none,
                  openElevation: 0,
                  closedElevation: 0,
                  tappable: enabled,
                  closedBuilder: (context, openForm) {
                    if (field.value is NotAssignedTagsQuery ||
                        (field.value is AnyAssignedTagsQuery &&
                            (field.value as AnyAssignedTagsQuery)
                                .tagIds
                                .isEmpty)) {
                      return _buildAssignmentOptionInput(
                        context,
                        openForm,
                        enabled,
                        field,
                      );
                    }
                    return _buildMultiSelectionInput(
                      context,
                      enabled: enabled,
                      children: children.toList(),
                      openForm: openForm,
                      isAny: field.value is AnyAssignedTagsQuery,
                    );
                  },
                  openBuilder: (context, closeForm) => FullscreenTagsForm(
                    onSubmit: closeForm,
                    initialValue: field.value,
                    allowCreation:
                        allowCreation && context.uiSettings$.canCreateTags,
                    allowExclude: allowExclude,
                  ),
                  onClosed: (data) {
                    if (data != null) {
                      field.didChange(data);
                    }
                  },
                ),
                if (_getDisplayedSuggestions(field.value).isNotEmpty)
                  _buildSuggestions(context, field, options),
              ],
            );
          },
        );
      },
    );
  }

  List<int> _getDisplayedSuggestions(TagsQuery? value) {
    return switch (value) {
      IdsTagsQuery(include: var include) =>
        suggestions.toSet().difference(include.toSet()).toList(),
      AnyAssignedTagsQuery(tagIds: var tagIds) =>
        suggestions.toSet().difference(tagIds.toSet()).toList(),
      _ => <int>[],
    };
  }

  Iterable<Widget> _generateOptions(
    BuildContext context,
    TagsQuery? query,
    FormFieldState<TagsQuery?> field,
    Map<int, Tag> options,
  ) sync* {
    if (query == null) return;

    final widgets = switch (query) {
      IdsTagsQuery(include: final inc, exclude: final exc) => [
        for (var i in inc)
          _buildIncludedTagWidget(context, i, field, query, options),
        for (var e in exc)
          _buildExcludedTagWidget(context, e, field, query, options),
      ],
      AnyAssignedTagsQuery(tagIds: final ids) when ids.isNotEmpty => [
        for (var i in ids)
          _buildAnyAssignedTagWidget(context, i, field, query, options),
      ],
      _ => <Widget>[],
    };
    for (var child in widgets) {
      yield child;
    }
  }

  Widget _buildAnyAssignedTagWidget(
    BuildContext context,
    int id,
    FormFieldState<TagsQuery?> field,
    AnyAssignedTagsQuery query,
    Map<int, Tag> options,
  ) {
    final tag = options[id];

    return LabelQueryOptionChip(
      backgroundColor:
          tag?.color ?? Theme.of(context).colorScheme.secondaryContainer,
      foregroundColor:
          tag?.textColor ?? Theme.of(context).colorScheme.onSecondaryContainer,
      onDeleted: () {
        final newIds = query.tagIds.where((element) => element != id).toList();
        if (newIds.isEmpty) {
          field.didChange(null);
        } else {
          field.didChange(query.copyWith(tagIds: newIds));
        }
      },
      exclude: false,
      labelText: tag?.name ?? '?',
    );
  }

  Widget _buildIncludedTagWidget(
    BuildContext context,
    int id,
    FormFieldState<TagsQuery?> field,
    IdsTagsQuery query,
    Map<int, Tag> options,
  ) {
    final tag = options[id];

    return LabelQueryOptionChip(
      backgroundColor:
          tag?.color ?? Theme.of(context).colorScheme.secondaryContainer,
      foregroundColor:
          tag?.textColor ?? Theme.of(context).colorScheme.onSecondaryContainer,
      onDeleted: () {
        field.didChange(
          query.copyWith(
            include: query.include.where((element) => element != id).toList(),
          ),
        );
      },
      exclude: false,
      labelText: tag?.name ?? '?',
    );
  }

  Widget _buildExcludedTagWidget(
    BuildContext context,
    int id,
    FormFieldState<TagsQuery?> field,
    IdsTagsQuery query,
    Map<int, Tag> options,
  ) {
    final tag = options[id];

    return LabelQueryOptionChip(
      backgroundColor:
          tag?.color ?? Theme.of(context).colorScheme.secondaryContainer,
      foregroundColor:
          tag?.textColor ?? Theme.of(context).colorScheme.onSecondaryContainer,
      onDeleted: () {
        field.didChange(
          query.copyWith(
            exclude: query.exclude.where((element) => element != id).toList(),
          ),
        );
      },
      exclude: true,
      labelText: tag?.name ?? '?',
    );
  }

  Widget _buildAssignmentOptionInput(
    BuildContext context,
    VoidCallback openForm,
    bool enabled,
    FormFieldState<TagsQuery?> field,
  ) {
    final text = switch (field.value) {
      NotAssignedTagsQuery() => S.of(context)!.notAssigned,
      AnyAssignedTagsQuery() => S.of(context)!.anyAssigned,
      _ => '',
    };
    final controller = TextEditingController(text: text);

    return Container(
      margin: const EdgeInsets.only(top: 6),
      child: TextField(
        controller: controller,
        onTap: openForm,
        readOnly: true,
        enabled: enabled,
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.label_outline),
          labelText: S.of(context)!.tags,
          suffixIcon: controller.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () => field.didChange(null),
                )
              : null,
        ),
      ),
    );
  }

  Widget _buildMultiSelectionInput(
    BuildContext context, {
    required List<Widget> children,
    required bool enabled,
    required VoidCallback openForm,
    bool isAny = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      child: GestureDetector(
        onTap: openForm,
        child: InputDecorator(
          isEmpty: children.isEmpty,
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.all(12),
            prefixIcon: const Icon(Icons.label_outline),
            enabled: enabled,
            labelText: isAny
                ? '${S.of(context)!.tags} (${S.of(context)!.anyTag})'
                : S.of(context)!.tags,
          ),
          child: SizedBox(
            height: 32,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              separatorBuilder: (context, index) => const SizedBox(width: 4),
              itemBuilder: (context, index) => children[index],
              itemCount: children.length,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSuggestions(
    BuildContext context,
    FormFieldState<TagsQuery?> field,
    Map<int, Tag> options,
  ) {
    final displayedSuggestions = _getDisplayedSuggestions(field.value);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          S.of(context)!.suggestions,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        SizedBox(
          height: kMinInteractiveDimension,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: displayedSuggestions.length,
            itemBuilder: (context, index) {
              final suggestion = options[displayedSuggestions.elementAt(index)];
              if (suggestion == null) {
                return const SizedBox.shrink();
              }
              return ActionChip(
                label: Text(suggestion.name),
                onPressed: () {
                  field.didChange(switch (field.value) {
                    IdsTagsQuery(include: var include) => IdsTagsQuery(
                      include: [...include, suggestion.id],
                    ),
                    AnyAssignedTagsQuery(tagIds: var tagIds)
                        when tagIds.isNotEmpty =>
                      AnyAssignedTagsQuery(tagIds: [...tagIds, suggestion.id]),
                    _ => IdsTagsQuery(include: [suggestion.id]),
                  });
                },
              );
            },
            separatorBuilder: (BuildContext context, int index) =>
                const SizedBox(width: 4.0),
          ),
        ),
      ],
    ).padded();
  }
}
