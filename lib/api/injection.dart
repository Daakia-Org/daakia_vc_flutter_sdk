import 'package:daakia_vc_flutter_sdk/utils/constants.dart';
import 'package:dio/dio.dart';

import '../model/base_list_response.dart';
import '../model/base_response.dart';
import '../service/daakia_vc_logger.dart';
import '../utils/utils.dart';
import 'api_client.dart';

RestClient? _apiClientInstance;

RestClient get apiClient => _apiClientInstance ??= RestClient(setDio());

Dio setDio() {
  final dio = Dio();
  dio.options.baseUrl = Constant.baseUrl;

  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        handler.next(options);
      },
      onResponse: (response, handler) {
        DaakiaVcLogger.logInfo(
          Utils.extractMessage("Success", response.data, response.requestOptions.path),
          attributes: {
            'endpoint': response.requestOptions.path,
            'method': response.requestOptions.method,
            'payload': response.requestOptions.data,
          },
        );
        handler.next(response);
      },
      onError: (DioException e, handler) {
        DaakiaVcLogger.logError(
          Utils.extractMessage("Error", e.requestOptions.data, e.requestOptions.path),
          error: e,
          stackTrace: e.stackTrace,
          attributes: {
            'endpoint': e.requestOptions.path,
            'method': e.requestOptions.method,
            'payload': e.requestOptions.data,
            'response': e.response?.data,
            'statusCode': e.response?.statusCode,
          },
        );
        handler.next(e);
      },
    ),
  );

  return dio;
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

/// Parses Dio errors into readable messages
String _getDioErrorMessage(DioException dioError) {
  switch (dioError.type) {
    case DioExceptionType.connectionTimeout:
      return "Connection timeout. Please try again.";
    case DioExceptionType.sendTimeout:
      return "Request timed out. Please try again.";
    case DioExceptionType.receiveTimeout:
      return "Server took too long to respond.";
    case DioExceptionType.badResponse:
      return "Server error: ${dioError.response?.statusCode} - ${dioError.response?.statusMessage}";
    case DioExceptionType.cancel:
      return "Request was cancelled.";
    case DioExceptionType.unknown:
    default:
      return "An unexpected error occurred.";
  }
}
