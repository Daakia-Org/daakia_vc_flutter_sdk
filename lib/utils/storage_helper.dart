import 'package:daakia_vc_flutter_sdk/enum/attendance_role_enum.dart';
import 'package:daakia_vc_flutter_sdk/utils/constants.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  Future<void> clearSdkData() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith(_prefix)).toList();
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
}
