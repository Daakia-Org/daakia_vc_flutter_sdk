import 'package:flutter/material.dart';

import '../../resources/colors/color.dart';
import '../../utils/utils.dart';
import '../../viewmodel/rtc_viewmodel.dart';
import 'initials_circle.dart';

class InvitedParticipantWidget extends StatefulWidget {
  const InvitedParticipantWidget({required this.viewModel, super.key});

  final RtcViewmodel viewModel;

  @override
  State<InvitedParticipantWidget> createState() =>
      _InvitedParticipantWidgetState();
}

class _InvitedParticipantWidgetState extends State<InvitedParticipantWidget> {
  bool isExpanded = false;
  bool _isRemindAllLoading = false;
  final Set<String> _remindedAttendees = {};
  final Set<String> _remindingAttendees = {};

  Future<void> _remindOne(String attendee) async {
    setState(() => _remindingAttendees.add(attendee));
    final success = await widget.viewModel.remindParticipant(attendee);
    if (!mounted) return;
    setState(() {
      _remindingAttendees.remove(attendee);
      if (success) _remindedAttendees.add(attendee);
    });
  }

  Future<void> _remindAll(List<String> remainingAttendees) async {
    setState(() => _isRemindAllLoading = true);
    final success = await widget.viewModel.remindAllParticipants(
      emails: remainingAttendees,
    );
    if (!mounted) return;
    setState(() {
      _isRemindAllLoading = false;
      if (success) {
        _remindedAttendees.addAll(remainingAttendees);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final invitedList = widget.viewModel.invitedParticipantList;
    final remainingAttendees = invitedList
        .map((invitee) => invitee.attendee)
        .whereType<String>()
        .where((attendee) => !_remindedAttendees.contains(attendee))
        .toList();
    final canRemindAll = !_isRemindAllLoading && remainingAttendees.isNotEmpty;
    // A sliver: the participants page builds rows only as they scroll in.
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Participants Not Joined (${invitedList.length})',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Row(
                children: [
                  ElevatedButton(
                    onPressed: canRemindAll
                        ? () => _remindAll(remainingAttendees)
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: themeColor,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: themeColor.withValues(
                        alpha: 0.4,
                      ),
                      disabledForegroundColor: Colors.white70,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      textStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: _isRemindAllLoading
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Remind All'),
                  ),
                  IconButton(
                    onPressed: () {
                      setState(() {
                        isExpanded = !isExpanded;
                      });
                    },
                    icon: Icon(
                      isExpanded
                          ? Icons.arrow_drop_down_sharp
                          : Icons.arrow_right_sharp,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (isExpanded)
          SliverList.builder(
            itemCount: invitedList.length,
            itemBuilder: (context, index) {
              final invitee = invitedList[index];
              final attendee = invitee.attendee;
              final isLoading =
                  attendee != null && _remindingAttendees.contains(attendee);
              final isReminded =
                  attendee != null && _remindedAttendees.contains(attendee);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Row(
                  children: [
                    InitialsCircle(initials: Utils.getInitials(attendee)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        attendee ?? "Unknown",
                        style: const TextStyle(color: Colors.white),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      tooltip: isReminded ? 'Reminded' : 'Remind',
                      onPressed: (attendee == null || isLoading || isReminded)
                          ? null
                          : () => _remindOne(attendee),
                      icon: isLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Icon(
                              isReminded
                                  ? Icons.notifications_active
                                  : Icons.notifications_active_outlined,
                              color: isReminded ? Colors.white38 : Colors.white,
                            ),
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }
}
