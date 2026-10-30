import 'package:daakia_vc_flutter_sdk/presentation/dialog/leave_confirmation_dialog.dart';
import 'package:daakia_vc_flutter_sdk/presentation/widgets/initials_circle.dart';
import 'package:daakia_vc_flutter_sdk/resources/colors/color.dart';
import 'package:daakia_vc_flutter_sdk/rtc/inactive_meeting_watcher.dart';
import 'package:daakia_vc_flutter_sdk/utils/utils.dart';
import 'package:daakia_vc_flutter_sdk/viewmodel/rtc_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';

/// Asks a host or co-host before they leave (not end) the meeting.
///
///   nobody else here            -> the regular leave confirmation
///   another host/co-host stays  -> leave confirmation naming who's left
///   only participants stay      -> "Leave without a host?", with the option
///                                  to make one of them co-host first
///
/// Resolves to true when the caller should go ahead and leave. When a co-host
/// was picked, that has already gone through by then.
Future<bool> confirmModeratorLeave(
    BuildContext context, RtcViewmodel viewModel) async {
  final session = viewModel.useCallTerminology ? 'call' : 'meeting';
  final others = _othersInRoom(viewModel.room);
  if (others.isEmpty) {
    return confirmLeaveMeeting(context,
        useCallTerminology: viewModel.useCallTerminology);
  }

  if (others.any(_isModerator)) {
    return showLeaveConfirmationDialog(
      context,
      title: 'Leave the $session?',
      message: '${_peopleStillHere(others.length)} in the $session. '
          'It will carry on after you leave.',
      confirmLabel: 'Leave $session',
    );
  }

  final choice = await showDialog<_HostLeaveChoice>(
    context: context,
    builder: (_) =>
        _NoHostLeftDialog(session: session, othersCount: others.length),
  );
  if (choice == _HostLeaveChoice.leave) return true;
  if (choice != _HostLeaveChoice.assignCoHost || !context.mounted) {
    return false;
  }

  final assigned = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _AssignCoHostDialog(viewModel: viewModel, session: session),
  );
  return assigned == true;
}

/// Everyone still here apart from this device, bots left out.
List<Participant> _othersInRoom(Room room) {
  final self = room.localParticipant?.identity;
  return InactiveMeetingRules.humans(room)
      .where((p) => p.identity != self)
      .toList();
}

bool _isModerator(Participant p) =>
    Utils.isHost(p.metadata) || Utils.isCoHost(p.metadata);

String _peopleStillHere(int count) => count == 1
    ? '1 participant is still'
    : '$count participants are still';

enum _HostLeaveChoice { assignCoHost, leave }

const Color _danger = Color(0xFFD32F2F);

/// Same card as [LeaveConfirmationDialog]: white, rounded, clamped so a
/// landscape phone scrolls the content instead of losing the buttons.
class _DialogCard extends StatelessWidget {
  const _DialogCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final maxHeight = media.size.height - media.viewInsets.vertical - 96;
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: maxHeight.clamp(160.0, 560.0),
          minWidth: 280,
          maxWidth: 360,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: children),
        ),
      ),
    );
  }
}

class _DialogHeader extends StatelessWidget {
  const _DialogHeader(
      {required this.icon,
      required this.color,
      required this.title,
      required this.message});

  final IconData icon;
  final Color color;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 30),
        ),
        const SizedBox(height: 20),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.black87,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.black54,
            fontSize: 14,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

Widget _filledButton(
    {required String label,
    required Color color,
    required VoidCallback? onPressed,
    bool busy = false}) {
  return SizedBox(
    width: double.infinity,
    height: 48,
    child: ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        disabledBackgroundColor: color.withValues(alpha: 0.4),
        disabledForegroundColor: Colors.white,
        elevation: 0,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white),
            )
          : Text(label,
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
    ),
  );
}

Widget _textButton(
    {required String label,
    required VoidCallback? onPressed,
    Color color = Colors.black54}) {
  return SizedBox(
    width: double.infinity,
    height: 44,
    child: TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(foregroundColor: color),
      child: Text(label, style: const TextStyle(fontSize: 15)),
    ),
  );
}

/// The host is about to leave participants behind with nobody to manage them.
class _NoHostLeftDialog extends StatelessWidget {
  const _NoHostLeftDialog({required this.session, required this.othersCount});

  final String session;
  final int othersCount;

  @override
  Widget build(BuildContext context) {
    return _DialogCard(
      children: [
        _DialogHeader(
          icon: Icons.admin_panel_settings_rounded,
          color: _danger,
          title: 'Leave without a host?',
          message: '${_peopleStillHere(othersCount)} in the $session and '
              'nobody else can manage it. Make someone co-host before you '
              'leave.',
        ),
        const SizedBox(height: 24),
        _filledButton(
          label: 'Assign co-host',
          color: themeColor,
          onPressed: () =>
              Navigator.pop(context, _HostLeaveChoice.assignCoHost),
        ),
        const SizedBox(height: 4),
        _textButton(
          label: 'Leave anyway',
          color: _danger,
          onPressed: () => Navigator.pop(context, _HostLeaveChoice.leave),
        ),
        _textButton(
          label: 'Cancel',
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }
}

/// Picks who becomes co-host, makes them co-host, and only then lets the
/// host leave. Resolves to true once the role change went through.
class _AssignCoHostDialog extends StatefulWidget {
  const _AssignCoHostDialog({required this.viewModel, required this.session});

  final RtcViewmodel viewModel;
  final String session;

  @override
  State<_AssignCoHostDialog> createState() => _AssignCoHostDialogState();
}

class _AssignCoHostDialogState extends State<_AssignCoHostDialog> {
  String? _selected;
  bool _busy = false;
  String? _error;

  void _assign() {
    final identity = _selected;
    if (identity == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    widget.viewModel.makeCoHost(
      identity,
      true,
      onDone: () {
        if (mounted) Navigator.pop(context, true);
      },
      onFailed: (message) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _error = message;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.viewModel.room;
    // The list follows the room: someone may leave while the host is choosing.
    return ListenableBuilder(
      listenable: room,
      builder: (context, _) {
        final candidates = _othersInRoom(room)
            .where((p) => !_isModerator(p))
            .toList()
          ..sort((a, b) =>
              a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        if (_selected != null &&
            !candidates.any((p) => p.identity == _selected)) {
          _selected = null;
        }

        return PopScope(
          canPop: !_busy,
          child: _DialogCard(
            children: [
              _DialogHeader(
                icon: Icons.admin_panel_settings_rounded,
                color: themeColor,
                title: 'Choose a co-host',
                message:
                    'They can manage the ${widget.session} after you leave.',
              ),
              const SizedBox(height: 16),
              if (candidates.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Everyone else has left.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black54, fontSize: 14),
                  ),
                )
              else
                for (final p in candidates) _candidateTile(p),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: _danger, fontSize: 13),
                ),
              ],
              const SizedBox(height: 16),
              _filledButton(
                label: 'Make co-host and leave',
                color: themeColor,
                busy: _busy,
                onPressed: _selected == null || _busy ? null : _assign,
              ),
              const SizedBox(height: 4),
              _textButton(
                label: 'Cancel',
                onPressed: _busy ? null : () => Navigator.pop(context, false),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _candidateTile(Participant p) {
    final name = p.name.isNotEmpty ? p.name : p.identity;
    final initials = Utils.getInitials(name);
    final selected = p.identity == _selected;
    return Material(
      color: selected ? themeColor.withValues(alpha: 0.08) : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: _busy ? null : () => setState(() => _selected = p.identity),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              InitialsCircle(
                initials: initials,
                size: 32,
                backgroundColor:
                    Utils.generateUniqueColorFromInitials(initials),
                textStyle: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.black87, fontSize: 15),
                ),
              ),
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: selected ? themeColor : Colors.black38,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
