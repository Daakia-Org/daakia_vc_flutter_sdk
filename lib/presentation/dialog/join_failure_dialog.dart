import 'package:flutter/material.dart';

import '../../resources/colors/color.dart';
import '../../utils/join_failure.dart';

/// Shows [failure] and resolves to true when the user wants to try again.
Future<bool> showJoinFailureDialog(
  BuildContext context,
  JoinFailure failure,
) async {
  final retry = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => JoinFailureDialog(failure: failure),
  );
  return retry ?? false;
}

/// The join-failed card: what went wrong, in the user's words, and what they
/// can do about it.
///
/// The raw LiveKit exception is still reachable behind "Technical details" so
/// testers and support can quote it, but it never greets the participant — a
/// stack-trace-looking error on a join screen reads as a broken app, and that
/// is exactly the impression this dialog exists to avoid.
class JoinFailureDialog extends StatefulWidget {
  const JoinFailureDialog({super.key, required this.failure});

  final JoinFailure failure;

  @override
  State<JoinFailureDialog> createState() => _JoinFailureDialogState();
}

class _JoinFailureDialogState extends State<JoinFailureDialog> {
  bool _showTechnicalDetail = false;
  bool _showAllTips = false;

  /// Best tip first, the rest behind "Show more".
  List<String> _visibleTips(JoinFailure failure) =>
      _showAllTips ? failure.tips : failure.tips.take(1).toList();

  @override
  Widget build(BuildContext context) {
    final failure = widget.failure;
    final media = MediaQuery.of(context);
    // A phone in landscape is only ~360dp tall and a Dialog already gives up
    // 24dp of inset top and bottom, so clamp rather than let the tips list
    // push the buttons off the card.
    final maxHeight = media.size.height - media.viewInsets.vertical - 96;

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: maxHeight.clamp(160.0, 680.0),
          minWidth: 280,
          maxWidth: 400,
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                // A visible scrollbar matters here: when the tips don't fit,
                // the content clips through a line of text, which reads as a
                // rendering fault unless something says "there is more".
                child: Scrollbar(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: themeColor.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.wifi_tethering_error_rounded,
                            color: themeColor,
                            size: 32,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          failure.title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.black87,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          failure.message,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.black54,
                            fontSize: 14,
                            height: 1.4,
                          ),
                        ),
                        if (failure.tips.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.04),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  'What you can try',
                                  style: TextStyle(
                                    color: Colors.black87,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                // Only the first tip by default. Tips are
                                // ordered best-first, and a blocked user reads
                                // the headline and one action before they stop
                                // — a wall of advice gets dismissed unread.
                                // The rest stay one tap away rather than gone.
                                for (final tip in _visibleTips(failure))
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          '•  ',
                                          style: TextStyle(
                                            color: Colors.black54,
                                            fontSize: 13,
                                            height: 1.4,
                                          ),
                                        ),
                                        Expanded(
                                          child: Text(
                                            tip,
                                            style: const TextStyle(
                                              color: Colors.black54,
                                              fontSize: 13,
                                              height: 1.4,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                if (failure.tips.length > 1)
                                  GestureDetector(
                                    onTap: () => setState(
                                        () => _showAllTips = !_showAllTips),
                                    behavior: HitTestBehavior.opaque,
                                    child: Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text(
                                        _showAllTips
                                            ? 'Show less'
                                            : 'Show ${failure.tips.length - 1} more',
                                        style: const TextStyle(
                                          color: themeColor,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (failure.canRetry)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: themeColor,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text(
                      'Try Again',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(
                    failure.canRetry ? 'Cancel' : 'Close',
                    style: const TextStyle(color: Colors.black54),
                  ),
                ),
              ),
              // Outside the scroll view on purpose. Inside it, a long tips list
              // pushed this below the fold with no scroll hint, so it read as
              // absent — and an escape hatch nobody can find is no escape hatch.
              _buildTechnicalDetail(failure),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTechnicalDetail(JoinFailure failure) {
    if (failure.technicalDetail.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton(
          onPressed: () =>
              setState(() => _showTechnicalDetail = !_showTechnicalDetail),
          child: Text(
            _showTechnicalDetail
                ? 'Hide technical details'
                : 'Technical details',
            style: const TextStyle(color: Colors.black38, fontSize: 12),
          ),
        ),
        if (_showTechnicalDetail)
          ConstrainedBox(
            // Bounded and scrollable: exception text has no length limit, and
            // this sits below the buttons where it cannot be allowed to grow.
            constraints: const BoxConstraints(maxHeight: 120),
            child: SingleChildScrollView(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  failure.technicalDetail,
                  style: const TextStyle(
                    color: Colors.black45,
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
