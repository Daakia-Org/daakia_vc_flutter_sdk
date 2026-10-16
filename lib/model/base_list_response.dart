import '../utils/constants.dart';
import '../utils/json_parser.dart';

class BaseListResponse<T> {
  int? success;
  String? message;
  List<T>? data;

  BaseListResponse({this.success, this.message, this.data});

  factory BaseListResponse.fromJson(
      Map<String, dynamic> json,
      T Function(dynamic) fromJsonT,
      ) {
    final rawData = json['data'];
    final success = JsonParser.toFlagInt(json['success']);
    // Failure responses carry `data: {}` (e.g. "Meeting is not running");
    // there's no list to parse, and the caller only reads the message. On
    // success a non-list still fails the cast, so a real contract change is
    // reported.
    final hasList = rawData != null &&
        (rawData is List || success == Constant.successResCheckValue);
    return BaseListResponse<T>(
      success: success,
      message: json['message'],
      data: hasList
          ? (rawData as List<dynamic>)
              .map((item) => fromJsonT(item as Map<String, dynamic>))
              .toList()
          : null,
    );
  }
}
