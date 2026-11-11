import 'package:json_annotation/json_annotation.dart';
import 'package:paperless_mobile/api/constants/api_date_format.dart';

/// A JSON converter for document calendar dates.
///
/// In Paperless-ngx, a document's `created` date represents a calendar date (day/month/year).
/// The server may return it as `YYYY-MM-DD`, `YYYY-MM-DDTHH:mm:ssZ`, or with a timezone offset
/// like `YYYY-MM-DDTHH:mm:ss+02:00`.
///
/// Standard `DateTime.parse()` converts strings with timezone offsets (e.g. `+02:00` or `+01:00`)
/// into UTC around midnight, which shifts the date to the previous day (e.g. `2023-10-09 22:00:00Z`).
/// This converter isolates the calendar date part (`YYYY-MM-DD`), preventing timezone-induced
/// date shifts.
class DocumentDateJsonConverter extends JsonConverter<DateTime, String> {
  const DocumentDateJsonConverter();

  @override
  DateTime fromJson(String json) {
    final datePart = json.split('T').first;
    return DateTime.parse(datePart);
  }

  @override
  String toJson(DateTime object) {
    return apiDateFormat.format(object);
  }
}
