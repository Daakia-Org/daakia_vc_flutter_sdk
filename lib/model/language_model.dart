class LanguageModel {
  String? code;
  String? language;
  List<String>? support;
  String? icon;

  LanguageModel({this.code, this.language, this.support, this.icon});

  LanguageModel.fromJson(Map<String, dynamic> json) {
    code = json['code'];
    language = json['language'];
    support = (json['support'] as List<dynamic>?)?.cast<String>();
    icon = json['icon'];
  }

  Map<String, dynamic> toJson() {
    return {
      'code': code,
      'language': language,
      'support': support,
      'icon': icon,
    };
  }

  // Returns the language name without the country in parentheses.
  // "English (India)" → "English", "French" → "French"
  String get displayName {
    final name = language ?? '';
    final idx = name.indexOf(' (');
    return idx >= 0 ? name.substring(0, idx) : name;
  }
}
