import 'dart:convert';

import 'package:daakia_vc_flutter_sdk/enum/attendance_role_enum.dart';
import 'package:daakia_vc_flutter_sdk/utils/constants.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class StorageHelper {
  static const _prefix = "daakia_vc_flutter_sdk."; // Unique prefix for SDK keys

  Future<void> saveData(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("$_prefix$key", value);
  }

  Future<String?> getData(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString("$_prefix$key");
  }

  /// Wipes the SDK's stored state, except [Constant.deviceId]: that one
  /// identifies the install, not the meeting, and rotating it would make this
  /// device look like a new one to the duplicate-device checks.
  Future<void> clearSdkData() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs
        .getKeys()
        .where((k) => k.startsWith(_prefix) && k != "$_prefix${Constant.deviceId}")
        .toList();
    for (final key in keys) {
      await prefs.remove(key);
    }
  }

  Future<void> setMeetingUid(String value) async => await saveData(Constant.meetingUid, value);
  Future<String?> getMeetingUid() async => await getData(Constant.meetingUid);


  Future<void> setSessionUid(String value) async => await saveData(Constant.sessionUid, value);
  Future<String?> getSessionUid() async => await getData(Constant.sessionUid);


  Future<void> setAttendanceId(String value) async => await saveData(Constant.attendanceId, value);
  Future<String?> getAttendanceId() async => await getData(Constant.attendanceId);

  Future<void> setAttendanceRole(AttendanceRole value) async =>
      await saveData(Constant.attendanceRole, value.name);
  Future<AttendanceRole?> getAttendanceRole() async {
    final value = await getData(Constant.attendanceRole);
    if (value == null || value.isEmpty) return null;
    for (final role in AttendanceRole.values) {
      if (role.name == value) return role;
    }
    return null;
  }

  Future<void> setHostToken(String? value) async => await saveData(Constant.hostToken, value ?? "");
  Future<String?> getHostToken() async => await getData(Constant.hostToken);

  Future<void> setGuestUserName(String? value) async => await saveData(Constant.guestUserName, value ?? "");
  Future<String?> getGuestUserName() async => await getData(Constant.guestUserName);

  String _emailVerificationKey(String meetingUid) =>
      "${Constant.emailVerificationPrefix}$meetingUid";

  /// Keeps a participant's verified email and its `email_token` for one
  /// meeting, so rejoining (app restart, leaving and coming back) doesn't ask
  /// for a new code while the token is valid.
  Future<void> saveEmailVerification(
      String meetingUid, String email, String token) async {
    await saveData(_emailVerificationKey(meetingUid),
        jsonEncode({"email": email, "token": token}));
  }

  /// The saved verification for [meetingUid], or null when there is none or
  /// its token has expired (an expired one is removed).
  Future<({String email, String token})?> getEmailVerification(
      String meetingUid) async {
    final raw = await getData(_emailVerificationKey(meetingUid));
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final email = map["email"]?.toString() ?? "";
      final token = map["token"]?.toString() ?? "";
      if (email.isEmpty || token.isEmpty) return null;
      final expiry = _jwtExpiry(token);
      if (expiry == null || !expiry.isAfter(DateTime.now())) {
        await clearEmailVerification(meetingUid);
        return null;
      }
      return (email: email, token: token);
    } catch (_) {
      await clearEmailVerification(meetingUid);
      return null;
    }
  }

  Future<void> clearEmailVerification(String meetingUid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove("$_prefix${_emailVerificationKey(meetingUid)}");
  }

  /// Reads `exp` from a JWT without verifying it (the server does that); only
  /// used to drop a token that has certainly expired.
  static DateTime? _jwtExpiry(String token) {
    try {
      final parts = token.split(".");
      if (parts.length < 2) return null;
      final payload = jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
      final exp = payload is Map ? payload["exp"] : null;
      if (exp is! num) return null;
      return DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000);
    } catch (_) {
      return null;
    }
  }

  /// Fallback device id for platforms where DeviceIdProvider can't get one
  /// (an emulator with no ANDROID_ID, a simulator). A random id for this
  /// install, created on first use and kept until the app is reinstalled or
  /// its data cleared.
  Future<String> getOrCreateDeviceId() async {
    final existing = await getData(Constant.deviceId);
    if (existing != null && existing.isNotEmpty) return existing;
    final id = const Uuid().v4();
    await saveData(Constant.deviceId, id);
    return id;
  }
}
