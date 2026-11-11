import 'package:flutter/material.dart';
import 'package:paperless_mobile/api/models/models.dart';

IconData getCustomFieldIcon(DataTypeEnum dataType) {
  return switch (dataType) {
    DataTypeEnum.string => Icons.text_fields,
    DataTypeEnum.integer => const IconData(0x2115), //Natural numbers
    DataTypeEnum.float => const IconData(0x211D), //Real numbers
    DataTypeEnum.boolean => Icons.check_box,
    DataTypeEnum.date => Icons.calendar_today,
    DataTypeEnum.select => Icons.list,
    DataTypeEnum.documentlink => Icons.link,
    DataTypeEnum.url => Icons.public,
    DataTypeEnum.monetary => Icons.attach_money,
    DataTypeEnum.longtext => Icons.notes,
  };
}
