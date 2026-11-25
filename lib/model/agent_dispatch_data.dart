import '../utils/json_parser.dart';

class AgentDispatchData {
  final bool? deleted;
  final String? dispatchId;

  AgentDispatchData({
    this.deleted,
    this.dispatchId,
  });

  factory AgentDispatchData.fromJson(Map<String, dynamic> json) {
    return AgentDispatchData(
      deleted: JsonParser.toBool(json['deleted']),
      dispatchId: json['dispatch_id'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'deleted': deleted,
      'dispatch_id': dispatchId,
    };
  }
}
