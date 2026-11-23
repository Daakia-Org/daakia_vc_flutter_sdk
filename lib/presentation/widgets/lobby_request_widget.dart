import 'package:daakia_vc_flutter_sdk/presentation/widgets/participant_tile.dart';
import 'package:daakia_vc_flutter_sdk/viewmodel/rtc_viewmodel.dart';
import 'package:flutter/material.dart';

class LobbyRequestWidget extends StatefulWidget {
  const LobbyRequestWidget({required this.viewModel, super.key});

  final RtcViewmodel viewModel;

  @override
  State<LobbyRequestWidget> createState() => _LobbyRequestWidgetState();
}

class _LobbyRequestWidgetState extends State<LobbyRequestWidget> {
  @override
  Widget build(BuildContext context) {
    final requests = widget.viewModel.getLobbyRequestList();
    if (requests.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    // A sliver: the participants page builds rows only as they scroll in.
    return SliverMainAxisGroup(
      slivers: [
        const SliverToBoxAdapter(
          child: Column(
            children: [
              Text(
                'Waiting in Lobby',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 10.0),
            ],
          ),
        ),
        SliverList.builder(
          itemCount: requests.length,
          itemBuilder: (context, index) {
            var lobbyRequest = widget.viewModel.getLobbyRequestList()[index];
            return ParticipantTile(
              participant: lobbyRequest.identity,
              isForLobby: true,
              lobbyRequest: lobbyRequest,
            );
          },
        ),
        SliverToBoxAdapter(
          child: Column(
            children: [
              const SizedBox(height: 10.0),
              Center(
                child: TextButton(
                  onPressed: () {
                    widget.viewModel.acceptParticipant(
                      request: widget.viewModel.getLobbyRequestList()[0],
                      accept: true,
                      acceptAll: true,
                    );
                  },
                  child: const Text(
                    'Accept All',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20.0,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const Divider(color: Colors.white, thickness: 1.0),
              const SizedBox(height: 20.0),
            ],
          ),
        ),
      ],
    );
  }
}
