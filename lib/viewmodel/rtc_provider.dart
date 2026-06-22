import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../model/daakia_meeting_configuration.dart';
import '../model/meeting_details.dart';
import 'rtc_viewmodel.dart';
import 'package:livekit_client/livekit_client.dart';

class RtcProvider extends StatefulWidget {
  final Room room;
  final MeetingDetails meetingDetails;
  final Widget child;
  final DaakiaMeetingConfiguration? sdkConfiguration;

  const RtcProvider({
    required this.room,
    required this.meetingDetails,
    required this.child,
    this.sdkConfiguration,
    super.key,
  });

  @override
  RtcProviderState createState() => RtcProviderState();
}

class RtcProviderState extends State<RtcProvider> {
  late RtcViewmodel viewModel;

  @override
  void initState() {
    super.initState();
    viewModel = RtcViewmodel(widget.room, widget.meetingDetails, sdkConfiguration: widget.sdkConfiguration);
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<RtcViewmodel>.value(
      value: viewModel,
      child: widget.child,
    );
  }
}

