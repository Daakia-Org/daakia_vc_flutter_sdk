import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:retrofit/error_logger.dart';

import '../utils/constants.dart';
import 'daakia_vc_sentry_service.dart';

/// Reports backend contract breaks (a field changing type on us) to Sentry.
///
/// Retrofit's generated client wraps *only* the `fromJson` call in a try/catch
/// and hands the failure to a [ParseErrorLogger] together with the request
/// options and the raw response. So this fires exclusively when a response
/// failed to deserialize — normal traffic, HTTP errors and timeouts never reach
/// here. That is what keeps this from becoming "log every API call".
///
/// Wired up in `lib/api/injection.dart` via `RestClient(dio, errorLogger: ...)`.
class ApiParseErrorLogger implements ParseErrorLogger {
  const ApiParseErrorLogger();

  @override
  void logError(
    Object error,
    StackTrace stackTrace,
    RequestOptions options, {
    Response<dynamic>? response,
  }) {
    try {
      ApiParseErrorReporter.report(
        error: error,
        stackTrace: stackTrace,
        options: options,
        response: response,
      );
    } catch (e) {
      // Reporting must never turn a recoverable parse failure into a crash.
      debugPrint('ApiParseErrorLogger failed: $e');
    }
  }
}

class ApiParseErrorReporter {
  ApiParseErrorReporter._();

  /// Signatures already sent this session. A retrying screen can hit the same
  /// broken endpoint dozens of times; Sentry only needs it once per run to
  /// still count the user as affected.
  static final Set<String> _reported = <String>{};

  /// Guard rails so a huge payload can't blow past event size limits.
  static const int _maxSkeletonEntries = 60;
  static const int _maxSuspectFields = 8;
  static const int _maxDepth = 6;

  static void report({
    required Object error,
    required StackTrace stackTrace,
    required RequestOptions options,
    Response<dynamic>? response,
  }) {
    final env = environmentLabel(Constant.baseUrl);
    final endpoint = options.path;
    final method = options.method;

    final diagnosis = diagnose(error: error, body: response?.data);
    final suspects = diagnosis.fields;
    final origin = modelFrame(stackTrace);

    final signature = [
      env,
      method,
      endpoint,
      error.runtimeType.toString(),
      diagnosis.expectedType ?? '-',
      diagnosis.actualType ?? '-',
      origin ?? '-',
      suspects.join(','),
    ].join('|');
    if (!_reported.add(signature)) return;

    final exception = ApiContractException(
      environment: env,
      method: method,
      endpoint: endpoint,
      expectedType: diagnosis.expectedType,
      actualType: diagnosis.actualType,
      fields: suspects,
      origin: origin,
      originalError: error.toString(),
    );

    DaakiaVcSentryService.captureException(
      exception,
      stackTrace: stackTrace,
      // Tags stay short and low-cardinality so they remain useful as Sentry
      // search facets. Anything long goes into contexts below.
      context: <String, Object?>{
        'event': 'api_parse_failure',
        'api_env': env,
        'api_endpoint': endpoint,
        'api_method': method,
        'expected_type': diagnosis.expectedType,
        'actual_type': diagnosis.actualType,
        'model': origin,
        'status_code': response?.statusCode,
      },
      contexts: <String, Object?>{
        'API contract': <String, Object?>{
          'base_url': Constant.baseUrl,
          'endpoint': '$method $endpoint',
          'expected_type': diagnosis.expectedType ?? 'n/a',
          'actual_type': diagnosis.actualType ?? 'n/a',
          'model': origin ?? 'unknown',
          'suspect_fields':
              suspects.isEmpty ? 'could not localise' : suspects.join(', '),
          'original_error': error.toString(),
          'sdk': '${Constant.sdkName}@${Constant.sdkVersion}',
          // Types only, never values.
          'response_shape': diagnosis.shape,
        },
      },
      // The title carries a variable field list, which would otherwise split one
      // problem across several Sentry issues. Group on what is actually stable:
      // the endpoint and the model that failed.
      fingerprint: <String>[
        'api-parse-failure',
        env,
        endpoint,
        origin ?? diagnosis.actualType ?? 'unknown',
      ],
    );

    debugPrint('[ApiParseError] ${exception.title}');
  }

  /// The SDK has no environment config of its own — the host app injects a base
  /// URL via `DaakiaSdk.initialize`. Derive a label from it so reports say which
  /// backend they came from; [Constant.baseUrl] is reported verbatim too, so an
  /// unrecognised host is never ambiguous.
  static String environmentLabel(String baseUrl) {
    final host = Uri.tryParse(baseUrl)?.host.toLowerCase() ?? '';
    if (host.isEmpty) return 'unknown';
    const markers = ['stag', 'dev', 'test', 'uat', 'local'];
    return markers.any(host.contains) ? 'staging' : 'prod';
  }

  /// Works out which field broke, from the error message plus the raw body.
  /// Pure and transport-free so it can be tested directly.
  static ApiParseDiagnosis diagnose({required Object error, dynamic body}) {
    // path -> every runtime type seen at that path. Two types on one path is
    // itself the smoking gun: the backend is inconsistent across list items.
    final shape = <String, Set<String>>{};
    _walk(body, '', shape, 0);

    final mismatch = _TypeMismatch.from(error);
    final checkedField = _checkedJsonField(error);

    final suspects = <String>[];
    if (checkedField != null) {
      suspects.add(checkedField);
    } else if (mismatch != null) {
      for (final entry in shape.entries) {
        if (entry.value.contains(mismatch.actual)) {
          suspects.add(entry.key);
          if (suspects.length >= _maxSuspectFields) break;
        }
      }
    }

    return ApiParseDiagnosis(
      expectedType: mismatch?.expected,
      actualType: mismatch?.actual,
      fields: suspects,
      shape: _renderShape(shape),
    );
  }

  /// Pulls the failing model out of the stack, e.g. `RtcData.fromJson
  /// (rtc_data.dart:26)`.
  ///
  /// This is what pins the field down when the type scan is ambiguous — a
  /// response with twelve strings gives twelve candidates for a `String`
  /// mismatch, but the frame names the exact class and line. Works in debug and
  /// profile builds; a release stack is obfuscated until Sentry symbolicates it,
  /// so this returns null there and the field scan carries the report.
  static String? modelFrame(StackTrace stackTrace) {
    // Two shapes to catch: a hand-written `RtcData.fromJson`, and the
    // json_serializable frame `_$RtcDataFromJson` — which has no dot, so it
    // needs its own alternative. Whichever appears first is the deepest, and so
    // the most precise. The location tolerates both `package:` and `file:///`
    // URIs, and only the file's basename is kept.
    final frame = RegExp(
      r'(?:([A-Za-z_$][\w$]*\.fromJson)|(_\$[A-Za-z_$][\w$]*FromJson))'
      r'[^(]*\([^)]*?([\w$]+\.dart):(\d+)',
    ).firstMatch(stackTrace.toString());
    if (frame == null) return null;

    final name = frame.group(1) ?? frame.group(2);
    return '$name (${frame.group(3)}:${frame.group(4)})';
  }

  /// Walks the decoded JSON recording *types only* — never values. Response
  /// bodies carry tokens, emails and phone numbers, and none of that belongs in
  /// an error report. The shape alone is what diagnoses a type change.
  ///
  /// List indices collapse to `[*]` so a 200-item list yields one entry per
  /// field instead of two hundred, while still merging the types seen across
  /// every item.
  static void _walk(
    dynamic value,
    String path,
    Map<String, Set<String>> out,
    int depth,
  ) {
    if (out.length >= _maxSkeletonEntries || depth > _maxDepth) return;

    if (value is Map) {
      if (path.isNotEmpty) out.putIfAbsent(path, () => {}).add('Map');
      for (final entry in value.entries) {
        final child = path.isEmpty ? '${entry.key}' : '$path.${entry.key}';
        _walk(entry.value, child, out, depth + 1);
        if (out.length >= _maxSkeletonEntries) return;
      }
      return;
    }

    if (value is List) {
      if (path.isNotEmpty) out.putIfAbsent(path, () => {}).add('List');
      for (final item in value) {
        _walk(item, '$path[*]', out, depth + 1);
        if (out.length >= _maxSkeletonEntries) return;
      }
      return;
    }

    out
        .putIfAbsent(path.isEmpty ? '<root>' : path, () => {})
        .add(jsonTypeOf(value));
  }

  static List<String> _renderShape(Map<String, Set<String>> shape) {
    return shape.entries
        .where((e) => !const {'Map', 'List'}.containsAll(e.value))
        .take(_maxSkeletonEntries)
        .map((e) {
          final types = e.value.toList()..sort();
          // "int|bool" on one path means the backend is not even self-consistent.
          return '${e.key}: ${types.join('|')}';
        })
        .toList();
  }

  /// Runtime type of a decoded JSON leaf, normalised to the names that show up
  /// in `_TypeError` messages.
  static String jsonTypeOf(dynamic value) {
    if (value == null) return 'Null';
    if (value is bool) return 'bool';
    if (value is int) return 'int';
    if (value is double) return 'double';
    if (value is num) return 'num';
    if (value is String) return 'String';
    if (value is List) return 'List';
    if (value is Map) return 'Map';
    return value.runtimeType.toString();
  }

  /// `CheckedFromJsonException` names the offending key outright. Only thrown
  /// when a model opts into `@JsonSerializable(checked: true)`, but when it is
  /// available it beats any amount of inference.
  static String? _checkedJsonField(Object error) {
    if (error is CheckedFromJsonException) {
      final key = error.key;
      if (key == null || key.isEmpty) return null;
      return '${error.className ?? 'model'}.$key';
    }
    return null;
  }

  @visibleForTesting
  static void resetForTest() => _reported.clear();
}

/// What [ApiParseErrorReporter.diagnose] could work out about a parse failure.
class ApiParseDiagnosis {
  const ApiParseDiagnosis({
    required this.fields,
    required this.shape,
    this.expectedType,
    this.actualType,
  });

  /// The type the model declared, verbatim (nullability intact), or null when
  /// the error was not a type error.
  final String? expectedType;

  /// The type the backend actually sent.
  final String? actualType;

  /// JSON paths in the response whose value matches [actualType]. Usually one;
  /// empty when the field could not be localised.
  final List<String> fields;

  /// `path: type` lines describing the response — types only, no values.
  final List<String> shape;
}

/// The expected/actual pair pulled out of a Dart type error message, e.g.
/// `type 'bool' is not a subtype of type 'int?' in type cast`.
class _TypeMismatch {
  const _TypeMismatch(this.actual, this.expected);

  final String actual;
  final String expected;

  static final RegExp _pattern =
      RegExp(r"type '([^']+)' is not a subtype of type '([^']+)'");

  static _TypeMismatch? from(Object error) {
    final match = _pattern.firstMatch(error.toString());
    if (match == null) return null;
    return _TypeMismatch(
      _normalize(match.group(1)!),
      // Keep the declared type verbatim so nullability stays visible.
      match.group(2)!,
    );
  }

  /// Collapses SDK-internal collection names (`_Map<String, dynamic>`,
  /// `_GrowableList<dynamic>`, `_JsonMap`) onto the plain names produced by
  /// [ApiParseErrorReporter.jsonTypeOf] so the two can be compared.
  static String _normalize(String type) {
    var name = type.trim();
    if (name.endsWith('?')) name = name.substring(0, name.length - 1);
    final generic = name.indexOf('<');
    if (generic != -1) name = name.substring(0, generic);
    while (name.startsWith('_')) {
      name = name.substring(1);
    }
    if (name.contains('Map')) return 'Map';
    if (name.contains('List')) return 'List';
    return name;
  }
}

/// Carries the diagnosis into Sentry. Its [toString] becomes the issue title,
/// so it leads with the environment, endpoint and field.
class ApiContractException implements Exception {
  ApiContractException({
    required this.environment,
    required this.method,
    required this.endpoint,
    required this.fields,
    required this.originalError,
    this.expectedType,
    this.actualType,
    this.origin,
  });

  final String environment;
  final String method;
  final String endpoint;
  final String? expectedType;
  final String? actualType;
  final List<String> fields;

  /// `RtcData.fromJson (rtc_data.dart:26)`, when the stack was readable.
  final String? origin;
  final String originalError;

  /// How many suspect fields the title names before collapsing the rest.
  static const int _titleFieldLimit = 3;

  String get title {
    final buffer = StringBuffer('[$environment] $method $endpoint');
    if (expectedType != null && actualType != null) {
      buffer.write(" — expected '$expectedType' but got '$actualType'");
    }
    if (fields.isNotEmpty) {
      // A common type (int, String) matches many fields, and listing them all
      // makes the title unreadable. The full list is still in the report body,
      // and [origin] is what actually pins the field down.
      final shown = fields.take(_titleFieldLimit).join(', ');
      final extra = fields.length - _titleFieldLimit;
      buffer.write(extra > 0 ? ' at $shown (+$extra more)' : ' at $shown');
    }
    if (origin != null) {
      buffer.write(' in $origin');
    }
    return buffer.toString();
  }

  @override
  String toString() => 'ApiContractException: $title ($originalError)';
}
