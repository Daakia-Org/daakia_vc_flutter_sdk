import 'package:flutter/material.dart';

import '../../resources/colors/color.dart';
import '../../viewmodel/rtc_viewmodel.dart';

/// Layout picker shown while watching someone else's screen share. Same names
/// as web: "Gallery + Content" keeps everyone in a strip under the share,
/// "Spotlight" (Speaker + Content) shows one card that follows the talker.
class LayoutBottomSheet extends StatelessWidget {
  const LayoutBottomSheet({required this.viewModel, super.key});

  final RtcViewmodel viewModel;

  @override
  Widget build(BuildContext context) {
    void choose(bool spotlight) {
      viewModel.spotlightSelected = spotlight;
      Navigator.pop(context);
    }

    return Container(
      width: double.maxFinite,
      color: emptyVideoColor,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(width: 50, height: 5, color: Colors.white),
            ),
            const SizedBox(height: 20),
            const Text(
              'Layout',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _LayoutCard(
                    title: 'Gallery',
                    subtitle: '+ Content',
                    selected: !viewModel.spotlightSelected,
                    preview: const _GalleryPreview(),
                    onTap: () => choose(false),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _LayoutCard(
                    title: 'Spotlight',
                    subtitle: 'Speaker + Content',
                    selected: viewModel.spotlightSelected,
                    preview: const _SpotlightPreview(),
                    onTap: () => choose(true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LayoutCard extends StatelessWidget {
  const _LayoutCard({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.preview,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final Widget preview;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '$title $subtitle',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? themeColor : Colors.white24,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(aspectRatio: 3 / 4, child: preview),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (selected)
                    Icon(Icons.check_circle, color: themeColor, size: 20),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const _shareColor = Color(0xFF4A5160);
const _tileColor = Color(0xFF2C313B);

/// Share on top, a strip of people under it.
class _GalleryPreview extends StatelessWidget {
  const _GalleryPreview();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Container(color: _shareColor),
              ),
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 22,
            child: Row(
              children: [
                for (var i = 0; i < 3; i++) ...[
                  if (i > 0) const SizedBox(width: 3),
                  Expanded(child: Container(color: _tileColor)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Share on top, one floating speaker card under it.
class _SpotlightPreview extends StatelessWidget {
  const _SpotlightPreview();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          const Spacer(),
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Container(color: _shareColor),
          ),
          Expanded(
            flex: 2,
            child: Center(
              child: FractionallySizedBox(
                widthFactor: 0.4,
                heightFactor: 0.8,
                child: Container(
                  decoration: BoxDecoration(
                    color: _tileColor,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.blue, width: 1.5),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
