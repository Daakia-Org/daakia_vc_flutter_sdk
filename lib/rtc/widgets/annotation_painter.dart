import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../model/annotation_stroke.dart';

class VideoContentBounds {
  final double left;
  final double top;
  final double width;
  final double height;

  const VideoContentBounds({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  @override
  bool operator ==(Object other) =>
      other is VideoContentBounds &&
      other.left == left &&
      other.top == top &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(left, top, width, height);
}

/// Calculates the actual rendered video area inside a container, accounting
/// for letterboxing (object-fit: contain equivalent).
VideoContentBounds getRenderedVideoContentBounds({
  required double containerWidth,
  required double containerHeight,
  required double videoWidth,
  required double videoHeight,
}) {
  if (containerWidth <= 0 ||
      containerHeight <= 0 ||
      videoWidth <= 0 ||
      videoHeight <= 0) {
    return VideoContentBounds(
        left: 0, top: 0, width: containerWidth, height: containerHeight);
  }

  final containerAspect = containerWidth / containerHeight;
  final videoAspect = videoWidth / videoHeight;

  double renderWidth, renderHeight, offsetX, offsetY;

  if (containerAspect > videoAspect) {
    // Black bars on left and right
    renderHeight = containerHeight;
    renderWidth = containerHeight * videoAspect;
    offsetX = (containerWidth - renderWidth) / 2;
    offsetY = 0;
  } else {
    // Black bars on top and bottom
    renderWidth = containerWidth;
    renderHeight = containerWidth / videoAspect;
    offsetX = 0;
    offsetY = (containerHeight - renderHeight) / 2;
  }

  return VideoContentBounds(
    left: offsetX,
    top: offsetY,
    width: renderWidth,
    height: renderHeight,
  );
}

/// Scales stroke width proportionally relative to a 720px reference height.
double getStrokeContentScale(double contentHeight) {
  const referenceHeight = 720.0;
  return contentHeight / referenceHeight;
}

/// Converts a normalised coordinate (0–1) to a canvas pixel offset.
Offset normalisedToCanvas(double nx, double ny, VideoContentBounds bounds) {
  return Offset(
    bounds.left + nx * bounds.width,
    bounds.top + ny * bounds.height,
  );
}

/// Converts a canvas pixel offset to a normalised coordinate (0–1).
/// Returns null if the point is outside the video content area.
List<double>? canvasToNormalised(Offset position, VideoContentBounds bounds) {
  final nx = (position.dx - bounds.left) / bounds.width;
  final ny = (position.dy - bounds.top) / bounds.height;
  if (nx < 0 || nx > 1 || ny < 0 || ny > 1) return null;
  return [nx, ny, 0.5]; // pressure defaults to 0.5 on mobile
}

class AnnotationPainter extends CustomPainter {
  final List<AnnotationStroke> strokes;
  final VideoContentBounds bounds;

  const AnnotationPainter({required this.strokes, required this.bounds});

  @override
  void paint(Canvas canvas, Size size) {
    final scale = getStrokeContentScale(bounds.height);
    for (final stroke in strokes) {
      _drawStroke(canvas, stroke, scale);
    }
  }

  void _drawStroke(Canvas canvas, AnnotationStroke stroke, double scale) {
    if (stroke.points.isEmpty) return;

    final color = _parseColor(stroke.color);
    final paint = Paint()
      ..color = stroke.tool == 'highlighter'
          ? color.withValues(alpha: 0.35)
          : color
      ..strokeWidth = stroke.width * scale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    switch (stroke.tool) {
      case 'pen':
      case 'highlighter':
        _drawFreehand(canvas, stroke.points, paint);
      case 'line':
        if (stroke.points.length < 2) return;
        final p1 = normalisedToCanvas(
            stroke.points.first[0], stroke.points.first[1], bounds);
        final p2 = normalisedToCanvas(
            stroke.points.last[0], stroke.points.last[1], bounds);
        canvas.drawLine(p1, p2, paint);
      case 'rectangle':
        if (stroke.points.length < 2) return;
        final p1 = normalisedToCanvas(
            stroke.points.first[0], stroke.points.first[1], bounds);
        final p2 = normalisedToCanvas(
            stroke.points.last[0], stroke.points.last[1], bounds);
        canvas.drawRect(Rect.fromPoints(p1, p2), paint);
      case 'arrow':
        if (stroke.points.length < 2) return;
        _drawArrow(canvas, stroke.points, paint, scale);
    }
  }

  void _drawFreehand(
      Canvas canvas, List<List<double>> points, Paint paint) {
    if (points.length == 1) {
      final p = normalisedToCanvas(points[0][0], points[0][1], bounds);
      canvas.drawCircle(
          p, paint.strokeWidth / 2, paint..style = PaintingStyle.fill);
      return;
    }

    final path = Path();
    final first = normalisedToCanvas(points[0][0], points[0][1], bounds);
    path.moveTo(first.dx, first.dy);

    for (int i = 1; i < points.length - 1; i++) {
      final curr =
          normalisedToCanvas(points[i][0], points[i][1], bounds);
      final next =
          normalisedToCanvas(points[i + 1][0], points[i + 1][1], bounds);
      final midX = (curr.dx + next.dx) / 2;
      final midY = (curr.dy + next.dy) / 2;
      path.quadraticBezierTo(curr.dx, curr.dy, midX, midY);
    }

    final last = normalisedToCanvas(points.last[0], points.last[1], bounds);
    path.lineTo(last.dx, last.dy);
    canvas.drawPath(path, paint..style = PaintingStyle.stroke);
  }

  void _drawArrow(Canvas canvas, List<List<double>> points, Paint paint,
      double scale) {
    final p1 =
        normalisedToCanvas(points.first[0], points.first[1], bounds);
    final p2 =
        normalisedToCanvas(points.last[0], points.last[1], bounds);
    canvas.drawLine(p1, p2, paint);

    final angle = (p2 - p1).direction;
    final arrowSize = 12.0 * scale;
    const arrowAngle = 0.45; // radians
    final path = Path();
    path.moveTo(p2.dx, p2.dy);
    path.lineTo(
      p2.dx - arrowSize * math.cos(angle - arrowAngle),
      p2.dy - arrowSize * math.sin(angle - arrowAngle),
    );
    path.moveTo(p2.dx, p2.dy);
    path.lineTo(
      p2.dx - arrowSize * math.cos(angle + arrowAngle),
      p2.dy - arrowSize * math.sin(angle + arrowAngle),
    );
    canvas.drawPath(path, paint);
  }

  Color _parseColor(String hex) {
    final cleaned = hex.replaceFirst('#', '');
    return Color(int.parse('FF$cleaned', radix: 16));
  }

  @override
  bool shouldRepaint(AnnotationPainter oldDelegate) =>
      oldDelegate.strokes != strokes || oldDelegate.bounds != bounds;
}
