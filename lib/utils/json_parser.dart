/// Tolerant readers for flag fields in backend and data-channel JSON.
///
/// The backend sends feature/permission flags inconsistently: some endpoints
/// return `true`/`false`, others `1`/`0`, and the same key can differ between
/// endpoints (e.g. `is_start_now`). It is migrating everything to booleans, so
/// a model must never assume one shape — a direct `json['x']` assignment or an
/// `as bool` cast throws a type error the moment the shape changes.
///
/// Use [toBool] for fields typed `bool`, and [toFlagInt] for fields still typed
/// `int` (read as `== 1` at call sites), so both shapes keep working.
class JsonParser {
  JsonParser._();

  /// Reads `true`/`false`, any number (non-zero is true) and the strings
  /// `"true"`/`"false"`/`"1"`/`"0"`/`"yes"`/`"no"`. Returns null for null or
  /// anything unrecognised so the caller's fallback decides.
  static bool? toBool(dynamic value) {
    if (value == null) return null;
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      switch (value.trim().toLowerCase()) {
        case 'true':
        case '1':
        case 'yes':
          return true;
        case 'false':
        case '0':
        case 'no':
          return false;
      }
    }
    return null;
  }

  /// Reads an int flag, mapping booleans to `1`/`0` so `== 1` checks keep
  /// working after the backend switches the field to `true`/`false`. Returns
  /// null for null or anything unrecognised.
  static int? toFlagInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    final asBool = toBool(value);
    if (asBool != null) return asBool ? 1 : 0;
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  /// Reads a number sent as a number or a numeric string, keeping fractions.
  /// Returns null for null, booleans, NaN/infinity or anything unrecognised.
  static num? toNum(dynamic value) {
    final parsed = value is num
        ? value
        : value is String
            ? num.tryParse(value.trim())
            : null;
    return parsed != null && parsed.isFinite ? parsed : null;
  }
}
