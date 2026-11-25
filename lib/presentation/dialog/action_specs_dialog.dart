import 'package:flutter/material.dart';

import '../../utils/participant_action_specs.dart';
import '../../viewmodel/rtc_viewmodel.dart';
import 'pariticipant_dialog_controls.dart';

/// Shows [ParticipantActionSpec]s in the same card-style menu the participant
/// section's more-options dialog uses, so every "3-dot" menu on the
/// participants page looks and behaves the same.
///
/// [buildActions] is re-run whenever the viewmodel notifies, and is handed the
/// dialog's own context so actions can pop it.
Future<void> showActionSpecsDialog({
  required BuildContext context,
  required RtcViewmodel viewModel,
  required List<ParticipantActionSpec> Function(BuildContext dialogContext)
      buildActions,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => ActionSpecsDialog(
      viewModel: viewModel,
      buildActions: buildActions,
    ),
  );
}

class ActionSpecsDialog extends StatelessWidget {
  const ActionSpecsDialog({
    required this.viewModel,
    required this.buildActions,
    super.key,
  });

  final RtcViewmodel viewModel;
  final List<ParticipantActionSpec> Function(BuildContext dialogContext)
      buildActions;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: viewModel,
      builder: (dialogContext, _) {
        final actions = buildActions(dialogContext)
            .where((action) => action.visible)
            .toList();
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          backgroundColor: Colors.transparent,
          child: Card(
            color: Colors.grey[900],
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Callers are expected to hide their menu button when
                  // nothing applies; this is the safety net so a stale menu
                  // (a permission revoked while it was open) says something
                  // instead of rendering an empty card.
                  if (actions.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                      child: Text(
                        'No actions available',
                        style: TextStyle(color: Colors.white70, fontSize: 15),
                      ),
                    ),
                  for (final action in actions)
                    CustomTextItem(
                      icon: action.icon,
                      text: action.label,
                      onTap: action.onTap,
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
