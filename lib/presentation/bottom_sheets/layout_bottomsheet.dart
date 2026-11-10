import 'package:flutter/material.dart';

import '../../resources/colors/color.dart';
import '../../viewmodel/rtc_viewmodel.dart';

/// Layout picker.
///
/// While watching someone else's screen share it offers web's two share
/// layouts: "Gallery + Content" keeps everyone in a strip under the share,
/// "Spotlight" (Speaker + Content) shows one card that follows the talker.
///
/// When nobody shares it offers "Speaker" (one big speaker with a strip,
/// the default) and "Grid" (everyone in equal tiles, a page at a time).
class LayoutBottomSheet extends StatelessWidget {
  const LayoutBottomSheet({required this.viewModel, super.key});

  final RtcViewmodel viewModel;

  @override
  Widget build(BuildContext context) {
    // Rebuilds in place for the switch; also follows the choices changing
    // underneath it (a share starting while the sheet is open).
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final forShare = viewModel.canChooseSpotlight;

    void choose(bool second) {
      if (forShare) {
        viewModel.spotlightSelected = second;
      } else {
        viewModel.gridSelected = second;
      }
      Navigator.pop(context);
    }

    final firstSelected =
        forShare ? !viewModel.spotlightSelected : !viewModel.gridSelected;

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
                  child: forShare
                      ? _LayoutCard(
                          title: 'Gallery',
                          subtitle: '+ Content',
                          selected: firstSelected,
                          preview: const _GalleryPreview(),
                          onTap: () => choose(false),
                        )
                      : _LayoutCard(
                          title: 'Speaker',
                          subtitle: 'Who is talking, big',
                          selected: firstSelected,
                          preview: const _SpeakerPreview(),
                          onTap: () => choose(false),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: forShare
                      ? _LayoutCard(
                          title: 'Spotlight',
                          subtitle: 'Speaker + Content',
                          selected: !firstSelected,
                          preview: const _SpotlightPreview(),
                          onTap: () => choose(true),
                        )
                      : _LayoutCard(
                          title: 'Grid',
                          subtitle: 'Everyone, equal tiles',
                          selected: !firstSelected,
                          preview: const _GridPreview(),
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
              AspectRatio(aspectRatio: 1, child: preview),
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

/// One big speaker, a strip of people under it.
class _SpeakerPreview extends StatelessWidget {
  const _SpeakerPreview();

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
            child: Container(
              decoration: BoxDecoration(
                color: _tileColor,
                border: Border.all(color: Colors.blue, width: 1.5),
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

/// Six equal tiles, two across.
class _GridPreview extends StatelessWidget {
  const _GridPreview();

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
          for (var row = 0; row < 3; row++) ...[
            if (row > 0) const SizedBox(height: 3),
            Expanded(
              child: Row(
                children: [
                  for (var col = 0; col < 2; col++) ...[
                    if (col > 0) const SizedBox(width: 3),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: _tileColor,
                          border: row == 0 && col == 0
                              ? Border.all(color: Colors.blue, width: 1.5)
                              : null,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
