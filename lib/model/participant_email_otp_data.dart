import '../utils/json_parser.dart';

/// `data` of the participant email OTP endpoints
/// (`rtc/meeting/participant-email/send-otp` and `.../verify-otp`).
///
/// Send success: [email], [expiresInSeconds], [resendAfterSeconds].
/// Send refused for the resend cooldown: [retryAfterSeconds].
/// Verify success: [email], [emailToken].
/// Verify refused for a wrong code: [attemptsLeft].
class ParticipantEmailOtpData {
  String? email;
  String? emailToken;
  int? expiresInSeconds;
  int? resendAfterSeconds;
  int? retryAfterSeconds;
  int? attemptsLeft;

  ParticipantEmailOtpData({
    this.email,
    this.emailToken,
    this.expiresInSeconds,
    this.resendAfterSeconds,
    this.retryAfterSeconds,
    this.attemptsLeft,
  });

  ParticipantEmailOtpData.fromJson(Map<String, dynamic> json) {
    email = json['email']?.toString();
    emailToken = json['email_token']?.toString();
    expiresInSeconds = JsonParser.toFlagInt(json['expires_in_seconds']);
    resendAfterSeconds = JsonParser.toFlagInt(json['resend_after_seconds']);
    retryAfterSeconds = JsonParser.toFlagInt(json['retry_after_seconds']);
    attemptsLeft = JsonParser.toFlagInt(json['attempts_left']);
  }

  Map<String, dynamic> toJson() => {
        'email': email,
        'email_token': emailToken,
        'expires_in_seconds': expiresInSeconds,
        'resend_after_seconds': resendAfterSeconds,
        'retry_after_seconds': retryAfterSeconds,
        'attempts_left': attemptsLeft,
      };
}
