import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../viewmodel/rtc_viewmodel.dart';
import '../widgets/host_control_switch.dart';

class WebinarControls extends StatelessWidget {
  const WebinarControls({super.key});

  @override
  Widget build(BuildContext context) {
    final viewModel = Provider.of<RtcViewmodel>(context);

    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Toolbar
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const Text(
                    'Host Control',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const Divider(color: Colors.white, thickness: 0.8),

              // Message
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  'Stay in control of your meetings with advanced host options.',
                  style: TextStyle(color: Colors.white, fontSize: 15),
                  textAlign: TextAlign.center,
                ),
              ),

              // Webinar Mode Switch
              HostControlSwitch(
                title: 'Workshop mode',
                subtitle:
                    'If turned ON, all participants except Hosts / CoHosts stay muted with their camera off.',
                value: viewModel.isWebinarModeEnable,
                isEnable: viewModel.meetingDetails.features?.isWorkshopEnabled() == true,
                onChanged: (value) {
                  viewModel.isWebinarModeEnable = value;
                  viewModel.updateAudioPermission(value);
                  viewModel.updateVideoPermission(value);
                  viewModel.isParticipantDrawerHidden = value;
                  viewModel.updateParticipantDrawerConsent(value);
                },
                isDividerRequired: false,
              ),

              // Participants Audio Switch
              HostControlSwitch(
                title: 'Participants Audio',
                subtitle: 'If turned off, participants can unmute themselves.',
                value: viewModel.isAudioModeEnable,
                isEnable: viewModel.meetingDetails.features?.isWorkshopEnabled() == true &&
                    viewModel.isWebinarModeEnable,
                onChanged: (value) {
                  viewModel.isAudioModeEnable = value;
                  viewModel.updateAudioPermission(value);
                },
                isChild: true,
                isDividerRequired: false,
              ),

              // Participants Video Switch
              HostControlSwitch(
                title: 'Participants Video',
                subtitle:
                    'If turned off, participants can turn their camera on.',
                value: viewModel.isVideoModeEnable,
                isEnable: viewModel.meetingDetails.features?.isWorkshopEnabled() == true &&
                    viewModel.isWebinarModeEnable,
                onChanged: (value) {
                  viewModel.isVideoModeEnable = value;
                  viewModel.updateVideoPermission(value);
                },
                isChild: true,
                isDividerRequired: false,
              ),

              // Hide Participant List Switch
              HostControlSwitch(
                title: 'Hide Participant list',
                subtitle:
                    'If turned on, participants cannot open the participant list.',
                value: viewModel.isParticipantDrawerHidden,
                isEnable: viewModel.meetingDetails.features?.isWorkshopEnabled() == true &&
                    viewModel.isWebinarModeEnable,
                onChanged: (value) {
                  viewModel.isParticipantDrawerHidden = value;
                  viewModel.updateParticipantDrawerConsent(value);
                },
                isChild: true,
                isDividerRequired: false,
              ),

              const Divider(color: Colors.white),

              // Chat Attachment Download
              HostControlSwitch(
                title: 'Chat attachment download',
                subtitle:
                    'If turned ON, all participants will be able to download attachments sent in chat.',
                value: viewModel.isChatAttachmentDownloadEnable,
                isEnable: viewModel.meetingDetails.features
                        ?.isConferenceChatAttachmentAllowed() ==
                    true,
                onChanged: (value) {
                  viewModel.isChatAttachmentDownloadEnable = value;
                  viewModel.updateChatAttachmentConsent(value);
                },
              ),

              // Screen Share
              HostControlSwitch(
                title: 'Allow Screen Share',
                subtitle:
                    'If turned ON, all participants can share their screen without host permission.',
                value: viewModel.isScreenShareEnable,
                isEnable: viewModel.meetingDetails.features
                        ?.isScreenShareRequestAllowed() ==
                    true,
                onChanged: (value) {
                  viewModel.isScreenShareEnable = value;
                  viewModel.updateScreenShareConsent(value);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
