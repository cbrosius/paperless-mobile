import 'package:json_annotation/json_annotation.dart';

@JsonEnum(alwaysCreate: true)
enum DataTypeEnum {
  string,
  url,
  date,
  boolean,
  integer,
  float,
  monetary,
  documentlink,
  select,
  longtext;

  @override
  String toString() => name;
}
