import '../utils/json_parser.dart';

class BaseResponse<T> {
  int? success;
  String? message;
  T? data;

  BaseResponse({this.success, this.message, this.data});

  BaseResponse.fromJson(
      Map<String, dynamic> json,
      T Function(dynamic json) fromJsonT,
      ) {
    success = JsonParser.toFlagInt(json['success']);
    message = json['message'];

    if (json['data'] != null) {
      if (json['data'] is List) {
        // T must be List<SomeModel>
        data = (json['data'] as List).map((item) => fromJsonT(item)).toList() as T;
      } else {
        data = fromJsonT(json['data']);
      }
    } else {
      data = null;
    }
  }


  Map<String, dynamic> toJson(Map<String, dynamic> Function(T) toJsonT) {
    final Map<String, dynamic> json = {};
    json['success'] = success;
    json['message'] = message;
    if (data != null) {
      json['data'] = toJsonT(data as T);
    } else {
      json['data'] = null; // Include null explicitly if data is empty
    }
    return json;
  }
}
