class RaisedHand {
  final String identity;
  final int timeStamp;

  RaisedHand({
    required this.identity,
    required this.timeStamp,
  });

  factory RaisedHand.fromJson(Map<String, dynamic> json) {
    return RaisedHand(
      identity: json['identity'] as String,
      timeStamp: json['timeStamp'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'identity': identity,
      'timeStamp': timeStamp,
    };
  }
}
