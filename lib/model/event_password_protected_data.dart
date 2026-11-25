import '../utils/json_parser.dart';

class EventPasswordProtectedData{
  bool? passwordVerified;
  String? participantEmail;

  /// Advanced password refused: the meeting needs a verified email first.
  bool? emailVerificationRequired;

  /// Advanced password refused: the code belongs to a different invitee
  /// than the verified email.
  bool? emailMismatch;

  EventPasswordProtectedData({this.passwordVerified, this.participantEmail});

  EventPasswordProtectedData.fromJson(Map<String, dynamic> json) {
    passwordVerified = JsonParser.toBool(json['password_verified']);
    participantEmail = json['participant_email'];
    emailVerificationRequired =
        JsonParser.toBool(json['email_verification_required']);
    emailMismatch = JsonParser.toBool(json['email_mismatch']);
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['password_verified'] = passwordVerified;
    data['participant_email'] = participantEmail;
    return data;
  }
}