class AnnotationStroke {
  final String id;
  final String fromIdentity;
  final String tool; // pen | highlighter | line | rectangle | arrow
  final String color; // '#rrggbb'
  final double width;
  final List<List<double>> points; // [[x, y, pressure], ...] — normalised 0–1

  const AnnotationStroke({
    required this.id,
    required this.fromIdentity,
    required this.tool,
    required this.color,
    required this.width,
    required this.points,
  });

  factory AnnotationStroke.fromJson(Map<String, dynamic> json) {
    return AnnotationStroke(
      id: json['id'] as String,
      fromIdentity: json['fromIdentity'] as String? ?? '',
      tool: json['tool'] as String,
      color: json['color'] as String,
      width: (json['width'] as num).toDouble(),
      points: (json['points'] as List)
          .map((p) => (p as List).map((v) => (v as num).toDouble()).toList())
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'fromIdentity': fromIdentity,
        'tool': tool,
        'color': color,
        'width': width,
        'points': points,
      };
}
