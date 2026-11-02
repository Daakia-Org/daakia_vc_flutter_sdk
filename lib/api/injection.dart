import 'dart:io';

import 'package:daakia_vc_flutter_sdk/utils/constants.dart';
import 'package:dio/dio.dart';

import '../model/base_list_response.dart';
import '../model/base_response.dart';
import '../service/api_parse_error_reporter.dart';
import '../service/daakia_vc_logger.dart';
import '../utils/utils.dart';
import 'api_client.dart';

RestClient? _apiClientInstance;

/// `errorLogger` fires only when a response body fails to deserialize — that is
/// the backend silently changing a field's type on us. See
/// [ApiParseErrorLogger]; successful calls never reach it.
RestClient get apiClient => _apiClientInstance ??=
    RestClient(setDio(), errorLogger: const ApiParseErrorLogger());

String? _liveKitToken;
String? _liveKitTokenMeetingUid;

/// Remembers the LiveKit access token of the room this device joined, so every
/// call to our API carries it as `x-livekit-token`. The backend verifies the
/// JWT, which makes it proof of who is calling: it keeps this device's own
/// attendance on a rejoin and authorises host / co-host actions for guests who
/// have no login. `x-self-identity` can't do that, since everyone in the room
/// can see everyone's identity.
///
/// Kept after the meeting closes on purpose: a rejoin's `/join` needs it.
void setLiveKitToken(String meetingUid, String token) {
  _liveKitTokenMeetingUid = meetingUid;
  _liveKitToken = token.isEmpty ? null : token;
}

/// Drops the remembered token unless it belongs to [meetingUid]; another
/// meeting's token is never valid proof.
void clearLiveKitTokenUnlessFor(String meetingUid) {
  if (_liveKitTokenMeetingUid == meetingUid) return;
  _liveKitTokenMeetingUid = null;
  _liveKitToken = null;
}

/// Only our own API gets the token: it grants this device's room access.
bool _isOwnApi(Uri uri) => uri.host == Uri.tryParse(Constant.baseUrl)?.host;

Dio setDio() {
  final dio = Dio();
  dio.options.baseUrl = Constant.baseUrl;

  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        final token = _liveKitToken;
        if (token != null && _isOwnApi(options.uri)) {
          options.headers['x-livekit-token'] = token;
        }
        handler.next(options);
      },
      onResponse: (response, handler) {
        DaakiaVcLogger.logInfo(
          Utils.extractMessage("Success", response.data, response.requestOptions.path),
          attributes: {
            'endpoint': response.requestOptions.path,
            'method': response.requestOptions.method,
            'payload': _loggablePayload(response.requestOptions.data),
          },
        );
        handler.next(response);
      },
      onError: (DioException e, handler) {
        // Every failure is logged to Datadog. Only `badResponse` — the backend
        // actually answered with a non-2xx — reaches Sentry; timeouts, cancels
        // and connection drops are the user's network, not a defect, and would
        // bury real issues.
        final isServerFault = e.type == DioExceptionType.badResponse;
        DaakiaVcLogger.logError(
          Utils.extractMessage("Error", e.requestOptions.data, e.requestOptions.path),
          error: e,
          stackTrace: e.stackTrace,
          attributes: {
            'endpoint': e.requestOptions.path,
            'method': e.requestOptions.method,
            'payload': _loggablePayload(e.requestOptions.data),
            'response': e.response?.data,
            'statusCode': e.response?.statusCode,
            'dioErrorType': e.type.name,
          },
          reportToSentry: isServerFault,
        );
        handler.next(e);
      },
    ),
  );

  return dio;
}

/// Datadog can't serialize a [FormData] (attachment uploads) and drops the
/// whole log's attributes, so log its field names and file names instead.
Object? _loggablePayload(Object? data) {
  if (data is! FormData) return data;
  return {
    'fields': {for (final f in data.fields) f.key: f.value},
    'files': [for (final f in data.files) '${f.key}: ${f.value.filename}'],
  };
}

/// Generic API request handler
Future<void> networkRequestHandler<T>({
  required Future<BaseResponse<T>> Function() apiCall,
  Function(T?)? onSuccess,
  Function(String)? onError,
}) async {
  try {
    final response = await apiCall();
    if (response.success == Constant.successResCheckValue) {
      onSuccess?.call(response.data);
    } else {
      onError?.call(response.message ?? "Unknown error occurred.");
    }
  } on DioException catch (dioError) {
    onError?.call(_getDioErrorMessage(dioError));
  } catch (e, st) {
    DaakiaVcLogger.captureException(e, stackTrace: st);
    onError?.call("Unexpected error: ${e.toString()}");
  }
}

/// Generic API request handler with message
Future<void> networkRequestHandlerWithMessage<T>({
  required Future<BaseResponse<T>> Function() apiCall,
  Function(BaseResponse<T>?)? onSuccess,
  Function(String)? onError,
}) async {
  try {
    final response = await apiCall();
    if (response.success == Constant.successResCheckValue) {
      onSuccess?.call(response);
    } else {
      onError?.call(response.message ?? "Unknown error occurred.");
    }
  } catch (e) {
    onError?.call("Unexpected error: ${e.toString()}");
  }
}

Future<void> networkListRequestHandler<T>({
  required Future<BaseListResponse<T>> Function() apiCall,
  Function(List<T>? data)? onSuccess,
  Function(String)? onError,
}) async {
  try {
    final response = await apiCall();
    if (response.success == Constant.successResCheckValue) {
      onSuccess?.call(response.data);
    } else {
      onError?.call(response.message ?? "Unknown error occurred.");
    }
  } on DioException catch (dioError) {
    onError?.call(_getDioErrorMessage(dioError));
  } catch (e) {
    onError?.call("Unexpected error: ${e.toString()}");
  }
}

/// Parses Dio errors into readable messages.
///
/// These are shown to participants verbatim, so they name the likely cause
/// rather than the exception. "An unexpected error occurred" for what is really
/// a phone that walked out of Wi-Fi range reads as an app fault, and gets
/// reported to us as one.
String _getDioErrorMessage(DioException dioError) {
  switch (dioError.type) {
    case DioExceptionType.connectionError:
      return "Can't reach the server. Please check your internet connection and try again.";
    case DioExceptionType.connectionTimeout:
      return "The connection timed out. Your network looks slow — please check it and try again.";
    case DioExceptionType.sendTimeout:
      return "The request timed out. Please check your connection and try again.";
    case DioExceptionType.receiveTimeout:
      return "The server took too long to respond. Please try again.";
    case DioExceptionType.transformTimeout:
      return "The response took too long to process. Please try again.";
    case DioExceptionType.badCertificate:
      return "Secure connection failed. If you're on a public or office network, it may be blocking the connection.";
    case DioExceptionType.badResponse:
      return "Server error: ${dioError.response?.statusCode} - ${dioError.response?.statusMessage}";
    case DioExceptionType.cancel:
      return "Request was cancelled.";
    case DioExceptionType.unknown:
      // Dio reports a dead socket as `unknown` on some platforms, so read the
      // wrapped error rather than defaulting to the useless generic message.
      final wrapped = dioError.error;
      if (wrapped is SocketException || wrapped is HttpException) {
        return "Can't reach the server. Please check your internet connection and try again.";
      }
      return "Something went wrong. Please check your connection and try again.";
  }
}
