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

  ActiveMeetingItem({this.meetingUid, this.name});

  ActiveMeetingItem.fromJson(Map<String, dynamic> json) {
    meetingUid = json['meeting_uid'];
    name = json['name'];
  }
}
