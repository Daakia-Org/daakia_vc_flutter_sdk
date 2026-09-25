class MeetingStatusData {
  bool? inMeeting;
  List<ActiveMeetingItem>? meetings;

  MeetingStatusData({this.inMeeting, this.meetings});

  MeetingStatusData.fromJson(Map<String, dynamic> json) {
    inMeeting = json['in_meeting'];
    if (json['meetings'] != null) {
      meetings = (json['meetings'] as List)
          .map((e) => ActiveMeetingItem.fromJson(e as Map<String, dynamic>))
          .toList();
    }
  }
}

class ActiveMeetingItem {
  String? meetingUid;
  String? name;
  String? platform;

  /// The `device_id` the session joined with (from its join metadata). Null
  /// for sessions that joined before the SDK started sending one.
  String? deviceId;

  ActiveMeetingItem(
      {this.meetingUid, this.name, this.platform, this.deviceId});

  ActiveMeetingItem.fromJson(Map<String, dynamic> json) {
    meetingUid = json['meeting_uid'];
    name = json['name'];
    platform = json['platform'];
    deviceId = json['device_id'];
  }
}
