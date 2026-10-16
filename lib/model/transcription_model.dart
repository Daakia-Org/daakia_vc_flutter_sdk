import '../utils/json_parser.dart';

class TranscriptionModel {
  final String? id;
  final String name;
  final String transcription;
  final String timestamp;
  final String sourceLang;
  final String targetLang;
  final bool isFinal;
  final String? translatedTranscription;  // New field for translated text

  TranscriptionModel({
    required this.id,
    required this.name,
    required this.transcription,
    required this.timestamp,
    required this.sourceLang,
    required this.targetLang,
    this.isFinal = false,
    this.translatedTranscription,  // Initialize the new field
  });

  // Factory constructor to create an instance from JSON
  factory TranscriptionModel.fromJson(Map<String, dynamic> json) {
    return TranscriptionModel(
      id: json['id'] as String?,
      name: json['name'] as String,
      transcription: json['transcription'] as String,
      timestamp: json['timestamp'] as String,
      sourceLang: json['sourceLang'] as String,
      targetLang: json['targetLang'] as String,
      isFinal: JsonParser.toBool(json['isFinal']) ?? false,
      translatedTranscription: json['translatedTranscription'] as String?, // Handle the new field in fromJson
    );
  }

  // Method to convert instance to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'transcription': transcription,
      'timestamp': timestamp,
      'sourceLang': sourceLang,
      'targetLang': targetLang,
      'isFinal': isFinal,
      'translatedTranscription': translatedTranscription, // Include the new field in toJson
    };
  }

  // Copy function to create a new instance with updated values
  TranscriptionModel copyWith({
    String? id,
    String? name,
    String? transcription,
    String? timestamp,
    String? sourceLang,
    String? targetLang,
    bool? isFinal,
    String? translatedTranscription, // Allow updating the translatedTranscription
  }) {
    return TranscriptionModel(
      id: id ?? this.id,
      name: name ?? this.name,
      transcription: transcription ?? this.transcription,
      timestamp: timestamp ?? this.timestamp,
      sourceLang: sourceLang ?? this.sourceLang,
      targetLang: targetLang ?? this.targetLang,
      isFinal: isFinal ?? this.isFinal,
      translatedTranscription: translatedTranscription ?? this.translatedTranscription, // Update the translatedTranscription
    );
  }
}
