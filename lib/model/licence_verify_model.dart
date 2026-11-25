import '../utils/json_parser.dart';

class LicenceVerifyModel{
  bool? userVerified;

  LicenceVerifyModel({this.userVerified});

  LicenceVerifyModel.fromJson(Map<String, dynamic> json) {
    userVerified = JsonParser.toBool(json['user_verified']);
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['user_verified'] = userVerified;
    return data;
  }
}