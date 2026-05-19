import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:provider/provider.dart';

import '../../viewmodel/rtc_viewmodel.dart';

const _annotationColors = [
  '#FF0000',
  '#FF8C00',
  '#FFFF00',
  '#00CC44',
  '#0066FF',
  '#9900CC',
  '#000000',
  '#FFFFFF',
  '#FF69B4',
];

const _annotationWidths = [2.0, 4.0, 8.0, 14.0];

class AnnotationToolbar extends StatelessWidget {
  final String sharerIdentity;
  final Room room;

  const AnnotationToolbar({
    super.key,
    required this.sharerIdentity,
    required this.room,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<RtcViewmodel>(builder: (context, viewModel, _) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.75),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Tool buttons
              _ToolButton(tool: 'pen', icon: Icons.edit, viewModel: viewModel),
              _ToolButton(tool: 'highlighter', icon: Icons.highlight, viewModel: viewModel),
              _ToolButton(tool: 'line', icon: Icons.horizontal_rule, viewModel: viewModel),
              _ToolButton(tool: 'rectangle', icon: Icons.crop_square, viewModel: viewModel),
              _ToolButton(tool: 'arrow', icon: Icons.arrow_right_alt, viewModel: viewModel),
              const _Divider(),
              // Color swatches
              ..._annotationColors.map((c) => _ColorButton(color: c, viewModel: viewModel)),
              const _Divider(),
              // Stroke width buttons
              ..._annotationWidths.map((w) => _WidthButton(width: w, viewModel: viewModel)),
              const _Divider(),
              // Undo
              _ActionButton(
                icon: Icons.undo,
                tooltip: 'Undo',
                onTap: () async {
                  final localId = room.localParticipant?.identity ?? '';
                  final stroke = viewModel.undoLastAnnotationStroke(sharerIdentity, localId);
                  if (stroke != null) {
                    await viewModel.publishAnnotationData(room, {
                      'action': 'annotation_remove',
                      'sharerIdentity': sharerIdentity,
                      'ids': [stroke.id],
                    });
                  }
                },
              ),
              // Clear all
              _ActionButton(
                icon: Icons.delete_sweep,
                tooltip: 'Clear all',
                onTap: () async {
                  viewModel.clearAnnotationStrokes(sharerIdentity);
                  await viewModel.publishAnnotationData(room, {
                    'action': 'annotation_clear',
                    'sharerIdentity': sharerIdentity,
                  });
                },
              ),
              // Close annotation mode
              _ActionButton(
                icon: Icons.close,
                tooltip: 'Close',
                onTap: () => viewModel.setAnnotationActive(false),
              ),
            ],
          ),
        ),
      );
    });
  }
}

class _ToolButton extends StatelessWidget {
  final String tool;
  final IconData icon;
  final RtcViewmodel viewModel;

  const _ToolButton({
    required this.tool,
    required this.icon,
    required this.viewModel,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = viewModel.annotationTool == tool;
    return GestureDetector(
      onTap: () => viewModel.setAnnotationTool(tool),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: isActive ? Colors.white.withValues(alpha: 0.25) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}

class _ColorButton extends StatelessWidget {
  final String color;
  final RtcViewmodel viewModel;

  const _ColorButton({required this.color, required this.viewModel});

  Color get _parsedColor {
    final hex = color.replaceFirst('#', '');
    return Color(int.parse('FF$hex', radix: 16));
  }

  @override
  Widget build(BuildContext context) {
    final isActive = viewModel.annotationColor == color;
    return GestureDetector(
      onTap: () => viewModel.setAnnotationColor(color),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: _parsedColor,
          shape: BoxShape.circle,
          border: Border.all(
            color: isActive ? Colors.white : Colors.white38,
            width: isActive ? 2.5 : 1,
          ),
        ),
      ),
    );
  }
}

class _WidthButton extends StatelessWidget {
  final double width;
  final RtcViewmodel viewModel;

  const _WidthButton({required this.width, required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final isActive = viewModel.annotationWidth == width;
    final dotSize = (width * 0.8).clamp(3.0, 12.0);
    return GestureDetector(
      onTap: () => viewModel.setAnnotationWidth(width),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: isActive ? Colors.white.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Center(
          child: Container(
            width: dotSize,
            height: dotSize,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.all(6),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      width: 1,
      height: 24,
      color: Colors.white30,
    );
  }
}
