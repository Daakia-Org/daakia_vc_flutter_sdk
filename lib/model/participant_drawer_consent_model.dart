class ParticipantDrawerConsentModel {
  bool isAllowed;

  ParticipantDrawerConsentModel({required this.isAllowed});

  factory ParticipantDrawerConsentModel.fromJson(Map<String, dynamic> json) {
    final raw = json['is_allowed'];
    return ParticipantDrawerConsentModel(
      isAllowed: raw is bool ? raw : (raw as int? ?? 1) == 1,
    );
  }

  Map<String, dynamic> toJson() => {
    'is_allowed': isAllowed,
  };
}
