import 'package:flutter/material.dart';

import '../../model/remote_activity_data.dart';
import '../../presentation/widgets/initials_circle.dart';
import '../../resources/colors/color.dart';
import '../../utils/utils.dart';
import '../../viewmodel/rtc_viewmodel.dart';

/// Tells a host or co-host that someone is waiting in the lobby, without
/// covering the meeting.
///
/// Stays until the request is handled, the person stops waiting or the host
/// closes it; heartbeats for a request already shown don't bring it back, only
/// someone new does. Several people collapse into one card that offers Admit
/// all and the full list. Hidden while the participants page, which has its
/// own lobby list, is open.
class LobbyRequestBanner extends StatefulWidget {
  final RtcViewmodel viewModel;

  /// Opens the participants page, where every waiting person is listed.
  final VoidCallback onView;

  const LobbyRequestBanner({
    required this.viewModel,
    required this.onView,
    super.key,
  });

  @override
  State<LobbyRequestBanner> createState() => _LobbyRequestBannerState();
}

class _LobbyRequestBannerState extends State<LobbyRequestBanner> {
  /// Requests answered from this banner whose answer is still in flight, so a
  /// double tap doesn't send it twice.
  final Set<String> _answered = {};

  bool _admittingAll = false;

  RtcViewmodel get _viewModel => widget.viewModel;

  void _answer(RemoteActivityData request, bool admit) {
    final id = request.requestId ?? "";
    if (!_answered.add(id)) return;
    setState(() {});
    _viewModel.acceptParticipant(request: request, accept: admit);
  }

  void _admitAll(List<RemoteActivityData> requests) {
    if (_admittingAll) return;
    setState(() => _admittingAll = true);
    _viewModel.acceptParticipant(
        request: requests.first, accept: true, acceptAll: true);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) {
        final requests = _visibleRequests();
        final child = requests.isEmpty
            ? const SizedBox(width: double.infinity)
            : _buildCard(requests);
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SizeTransition(
              sizeFactor: animation,
              child: child,
            ),
          ),
          child: KeyedSubtree(
            key: ValueKey(requests.length == 1
                ? requests.first.requestId
                : requests.length > 1
                    ? 'many'
                    : 'none'),
            child: child,
          ),
        );
      },
    );
  }

  List<RemoteActivityData> _visibleRequests() {
    if (!_viewModel.isHost() && !_viewModel.isCoHost()) return const [];
    if (_viewModel.isParticipantPageOpen) return const [];
    if (!_viewModel.hasNewLobbyRequest) return const [];
    final requests = _viewModel.lobbyRequestList;
    // Answered requests leave the list once the server confirms.
    _answered.removeWhere((id) => !requests.any((r) => r.requestId == id));
    if (requests.isEmpty) _admittingAll = false;
    return requests
        .where((r) => !_answered.contains(r.requestId))
        .toList();
  }

  Widget _buildCard(List<RemoteActivityData> requests) {
    final single = requests.length == 1 ? requests.first : null;
    return Padding(
      // Same inset as the room notices stacked under it.
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Material(
        color: const Color(0xFF1C1C2E),
        elevation: 6,
        shadowColor: Colors.black54,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Colors.white12),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  single != null
                      ? InitialsCircle(
                          initials: Utils.getInitials(single.displayName),
                          size: 40,
                        )
                      : _CountCircle(count: requests.length),
                  const SizedBox(width: 12),
                  Expanded(
                    child: single != null
                        ? _Texts(
                            title: _nameOf(single),
                            subtitle: 'wants to join',
                          )
                        : _Texts(
                            title: '${requests.length} people want to join',
                            subtitle: _summarise(requests),
                          ),
                  ),
                  IconButton(
                    tooltip: 'Hide',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close_rounded,
                        color: Colors.white54, size: 20),
                    onPressed: _viewModel.dismissLobbyBanner,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: single != null
                      ? [
                          _SecondaryButton(
                            label: 'Deny',
                            onPressed: () => _answer(single, false),
                          ),
                          const SizedBox(width: 8),
                          _PrimaryButton(
                            label: 'Admit',
                            onPressed: () => _answer(single, true),
                          ),
                        ]
                      : [
                          _SecondaryButton(
                            label: 'View',
                            onPressed: widget.onView,
                          ),
                          const SizedBox(width: 8),
                          _PrimaryButton(
                            label: 'Admit all',
                            onPressed: _admittingAll
                                ? null
                                : () => _admitAll(requests),
                          ),
                        ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _nameOf(RemoteActivityData request) {
    final name = request.displayName?.trim();
    return name == null || name.isEmpty ? 'Someone' : name;
  }

  /// "Asha, Ravi and 2 others".
  static String _summarise(List<RemoteActivityData> requests) {
    final names = requests.map(_nameOf).toList();
    if (names.length <= 2) return names.join(' and ');
    final rest = names.length - 2;
    return '${names[0]}, ${names[1]} and $rest ${rest == 1 ? 'other' : 'others'}';
  }
}

class _Texts extends StatelessWidget {
  final String title;
  final String subtitle;

  const _Texts({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
      ],
    );
  }
}

class _CountCircle extends StatelessWidget {
  final int count;

  const _CountCircle({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: themeColor,
        shape: BoxShape.circle,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.people_alt_rounded, color: Colors.white, size: 16),
          const SizedBox(width: 2),
          Text(
            '$count',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  const _PrimaryButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: themeColor,
        foregroundColor: Colors.white,
        disabledBackgroundColor: themeColor.withValues(alpha: 0.5),
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const _SecondaryButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: const BorderSide(color: Colors.white38),
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
    );
  }
}
