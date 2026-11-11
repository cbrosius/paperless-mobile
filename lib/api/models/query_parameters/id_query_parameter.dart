import 'package:freezed_annotation/freezed_annotation.dart';

part 'id_query_parameter.freezed.dart';
part 'id_query_parameter.g.dart';

@freezed
sealed class IdQueryParameter with _$IdQueryParameter {
  const factory IdQueryParameter.unset() = UnsetIdQueryParameter;
  const factory IdQueryParameter.notAssigned() = NotAssignedIdQueryParameter;
  const factory IdQueryParameter.anyAssigned() = AnyAssignedIdQueryParameter;
  const factory IdQueryParameter.include({required List<int> ids}) =
      IncludeIdsQueryParameter;
  const factory IdQueryParameter.exclude({required List<int> ids}) =
      ExcludeIdsQueryParameter;
  factory IdQueryParameter.single({required int id}) = SingleIdQueryParameter;
  factory IdQueryParameter.fromJson(Map<String, dynamic> json) =>
      _$IdQueryParameterFromJson(json);
}

extension IdQueryParameterMethods on IdQueryParameter {
  bool matches(int? id) {
    return when(
      unset: () => true,
      notAssigned: () => id == null,
      anyAssigned: () => id != null,
      include: (ids) => ids.contains(id),
      exclude: (ids) => !ids.contains(id),
      single: (idValue) => id == idValue,
    );
  }

  Map<String, String> toQueryParameter(String field) {
    final notAssignedValue = field == 'owner' ? 'true' : '1';
    final anyAssignedValue = field == 'owner' ? 'false' : '0';
    return when(
      unset: () => {},
      notAssigned: () => {'${field}__isnull': notAssignedValue},
      anyAssigned: () => {'${field}__isnull': anyAssignedValue},
      include: (ids) => {'${field}__id__in': ids.join(',')},
      exclude: (ids) => {'${field}__id__none': ids.join(',')},
      single: (id) => {'${field}__id': id.toString()},
    );
  }

  IdQueryParameter toggleInclude(int id) {
    return when(
      unset: () => IdQueryParameter.include(ids: [id]),
      notAssigned: () => IdQueryParameter.include(ids: [id]),
      anyAssigned: () => IdQueryParameter.include(ids: [id]),
      single: (idValue) {
        if (id == idValue) {
          return const IdQueryParameter.unset();
        } else {
          return IdQueryParameter.include(ids: [id, idValue]);
        }
      },
      include: (ids) {
        final newIds = List<int>.from(ids);
        if (newIds.contains(id)) {
          newIds.remove(id);
        } else {
          newIds.add(id);
        }
        if (newIds.isEmpty) {
          return const IdQueryParameter.unset();
        }
        return IdQueryParameter.include(ids: newIds);
      },
      exclude: (ids) {
        return IdQueryParameter.include(ids: [id]);
      },
    );
  }

  IdQueryParameter merge(IdQueryParameter other) {
    return when(
      unset: () => other,
      notAssigned: () => other,
      anyAssigned: () => other,
      single: (_) => other,
      include: (ids) => IncludeIdsQueryParameter(
        ids: [
          ...ids,
          ...other.when(
            unset: () => [],
            notAssigned: () => [],
            anyAssigned: () => [],
            single: (id) => [id],
            include: (otherIds) => otherIds,
            exclude: (otherIds) => otherIds,
          ),
        ],
      ),
      exclude: (ids) => ExcludeIdsQueryParameter(
        ids: [
          ...ids,
          ...other.when(
            unset: () => [],
            notAssigned: () => [],
            anyAssigned: () => [],
            single: (id) => [id],
            include: (otherIds) => otherIds,
            exclude: (otherIds) => otherIds,
          ),
        ],
      ),
    );
  }

  IdQueryParameter toggleExclude(int id) {
    return when(
      unset: () => IdQueryParameter.exclude(ids: [id]),
      notAssigned: () => IdQueryParameter.exclude(ids: [id]),
      anyAssigned: () => IdQueryParameter.exclude(ids: [id]),
      single: (idValue) {
        return IdQueryParameter.exclude(ids: [id]);
      },
      include: (ids) {
        return IdQueryParameter.exclude(ids: [id]);
      },
      exclude: (ids) {
        final newIds = List<int>.from(ids);
        if (newIds.contains(id)) {
          newIds.remove(id);
        } else {
          newIds.add(id);
        }
        if (newIds.isEmpty) {
          return const IdQueryParameter.unset();
        }
        return IdQueryParameter.exclude(ids: newIds);
      },
    );
  }
}
// sealed class IdQueryParameter {
//   const IdQueryParameter();

//   Map<String, String> toQueryParameter(String field);
//   bool matches(int? id);

//   bool get isUnset => this is UnsetIdQueryParameter;
//   bool get isSet => this is IncludeIdsQueryParameter;
//   bool get isOnlyNotAssigned => this is NotAssignedIdQueryParameter;
//   bool get isOnlyAssigned => this is AnyAssignedIdQueryParameter;

//   factory IdQueryParameter.fromJson(Map<String, dynamic> json) {
//     final type = json['__type'] as String?;
//     switch (type) {
//       case 'UnsetIdQueryParameter':
//         return const UnsetIdQueryParameter();
//       case 'NotAssignedIdQueryParameter':
//         return const NotAssignedIdQueryParameter();
//       case 'AnyAssignedIdQueryParameter':
//         return const AnyAssignedIdQueryParameter();
//       case 'SetIdQueryParameter':
//         return IncludeIdsQueryParameter.fromJson(json);
//       default:
//         throw Exception('Unknown IdQueryParameter type: $type');
//     }
//   }

//   Map<String, dynamic> toJson();
// }

// class UnsetIdQueryParameter extends IdQueryParameter with EquatableMixin {
//   const UnsetIdQueryParameter();
//   @override
//   Map<String, String> toQueryParameter(String field) => {};

//   @override
//   bool matches(int? id) => true;

//   @override
//   Map<String, dynamic> toJson() => {"__type": 'UnsetIdQueryParameter'};

//   @override
//   List<Object?> get props => [];
// }

// class NotAssignedIdQueryParameter extends IdQueryParameter with EquatableMixin {
//   const NotAssignedIdQueryParameter();

//   @override
//   Map<String, String> toQueryParameter(String field) {
//     return {'${field}__isnull': '1'};
//   }

//   @override
//   List<Object?> get props => [];

//   @override
//   bool matches(int? id) => id == null;

//   @override
//   Map<String, dynamic> toJson() => {"__type": 'NotAssignedIdQueryParameter'};
// }

// class AnyAssignedIdQueryParameter extends IdQueryParameter with EquatableMixin {
//   const AnyAssignedIdQueryParameter();
//   @override
//   Map<String, String> toQueryParameter(String field) {
//     return {'${field}__isnull': '0'};
//   }

//   @override
//   List<Object?> get props => [];

//   @override
//   bool matches(int? id) => id != null;

//   @override
//   Map<String, dynamic> toJson() => {"__type": 'AnyAssignedIdQueryParameter'};
// }

// @JsonSerializable(ignoreUnannotated: true)
// class IncludeIdsQueryParameter extends IdQueryParameter with EquatableMixin {
//   @JsonKey(includeToJson: true, includeFromJson: false)
//   final __type = 'IncludeIdsQueryParameter';

//   @JsonKey()
//   final List<int> ids;

//   const IncludeIdsQueryParameter({required this.ids});

//   @override
//   Map<String, String> toQueryParameter(String field) {
//     return {'${field}__id__in': '$ids'};
//   }

//   @override
//   bool matches(int? id) => ids.contains(id);

//   @override
//   List<Object?> get props => [ids];

//   @override
//   Map<String, dynamic> toJson() => _$SetIdsQueryParameterToJson(this);
//   factory IncludeIdsQueryParameter.fromJson(Map<String, dynamic> json) {
//     return _$SetIdsQueryParameterFromJson(json);
//   }
// }
