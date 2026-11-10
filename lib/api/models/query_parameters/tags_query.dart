import 'package:freezed_annotation/freezed_annotation.dart';

part 'tags_query.freezed.dart';
part 'tags_query.g.dart';

@freezed
sealed class TagsQuery with _$TagsQuery {
  const factory TagsQuery.notAssigned() = NotAssignedTagsQuery;
  const factory TagsQuery.anyAssigned({@Default(<int>[]) List<int> tagIds}) =
      AnyAssignedTagsQuery;
  const factory TagsQuery.ids({
    @Default(<int>[]) List<int> include,
    @Default(<int>[]) List<int> exclude,
  }) = IdsTagsQuery;

  factory TagsQuery.fromJson(Map<String, dynamic> json) =>
      _$TagsQueryFromJson(json);
}

extension TagsQueryMethods on TagsQuery {
  Map<String, String> toQueryParameter() {
    return when(
      notAssigned: () => {'is_tagged': '0'},
      anyAssigned: (tagIds) => tagIds.isEmpty
          ? {'is_tagged': '1'}
          : {'tags__id__in': tagIds.join(',')},
      ids: (include, exclude) {
        final params = <String, String>{};
        if (include.isNotEmpty) {
          params['tags__id__all'] = include.join(',');
        }
        if (exclude.isNotEmpty) {
          params['tags__id__none'] = exclude.join(',');
        }
        return params;
      },
    );
  }

  bool matches(Iterable<int> ids) {
    return when(
      notAssigned: () => ids.isEmpty,
      anyAssigned: (tagIds) =>
          tagIds.isEmpty ? ids.isNotEmpty : tagIds.any((t) => ids.contains(t)),
      ids: (include, exclude) =>
          include.toSet().difference(ids.toSet()).isEmpty &&
          exclude.toSet().intersection(ids.toSet()).isEmpty,
    );
  }

  TagsQuery toggleInclude(int id) {
    return when(
      notAssigned: () => TagsQuery.ids(include: [id]),
      anyAssigned: (tagIds) {
        if (tagIds.isEmpty) {
          return TagsQuery.anyAssigned(tagIds: [id]);
        }
        final newIds = List<int>.from(tagIds);
        if (newIds.contains(id)) {
          newIds.remove(id);
        } else {
          newIds.add(id);
        }
        return newIds.isEmpty
            ? const TagsQuery.anyAssigned()
            : TagsQuery.anyAssigned(tagIds: newIds);
      },
      ids: (include, exclude) {
        final newInclude = List<int>.from(include);
        if (newInclude.contains(id)) {
          newInclude.remove(id);
        } else {
          newInclude.add(id);
        }
        if (newInclude.isEmpty && exclude.isEmpty) {
          return const TagsQuery.ids();
        }
        return TagsQuery.ids(include: newInclude, exclude: exclude);
      },
    );
  }

  TagsQuery toggleExclude(int id) {
    return when(
      notAssigned: () => TagsQuery.ids(exclude: [id]),
      anyAssigned: (tagIds) {
        List<int> newInclude = List<int>.from(tagIds);
        if (newInclude.contains(id)) {
          newInclude.remove(id);
        }
        return TagsQuery.ids(exclude: [id], include: newInclude);
      },
      ids: (include, exclude) {
        final newExclude = List<int>.from(exclude);
        final newInclude = List<int>.from(include);
        if (newExclude.contains(id)) {
          newExclude.remove(id);
        } else {
          newExclude.add(id);
        }

        if (newInclude.contains(id)) {
          newInclude.remove(id);
        }

        if (include.isEmpty && newExclude.isEmpty) {
          return const TagsQuery.ids();
        }
        return TagsQuery.ids(include: newInclude, exclude: newExclude);
      },
    );
  }
}
