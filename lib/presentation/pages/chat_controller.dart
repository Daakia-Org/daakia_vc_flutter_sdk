import 'package:daakia_vc_flutter_sdk/events/rtc_events.dart';
import 'package:daakia_vc_flutter_sdk/presentation/pages/private_chat_page.dart';
import 'package:daakia_vc_flutter_sdk/presentation/widgets/loader.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../viewmodel/rtc_viewmodel.dart';
import 'chat_page.dart';

class ChatController extends StatefulWidget {
  const ChatController(
      {required this.viewModel, this.identity = "", this.name = "", super.key});

  final String identity;
  final String name;
  final RtcViewmodel viewModel;

  @override
  State<ChatController> createState() => _ChatControllerState();
}

class _ChatControllerState extends State<ChatController>
    with SingleTickerProviderStateMixin {
  bool _isLoading = false;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      collectChatEvents(widget.viewModel);
    });

    final isPublicChatAllowed =
    widget.viewModel.meetingDetails.features!.isPublicChatAllowed();
    final isPrivateChatAllowed =
    widget.viewModel.meetingDetails.features!.isPrivateChatAllowed();

    final tabCount =
        (isPublicChatAllowed ? 1 : 0) + (isPrivateChatAllowed ? 1 : 0);
    final initialIndex = (widget.identity.isEmpty || tabCount == 1) ? 0 : 1;

    widget.viewModel.isChatOpen = !isPrivateChatInitiallyOpen;
    widget.viewModel.isPrivateChatOpen = isPrivateChatInitiallyOpen;

    _tabController = TabController(
        length: tabCount, vsync: this, initialIndex: initialIndex);

    _tabController.addListener(_onTabChanged);
    _updateTabStates(_tabController.index);
  }


  void _onTabChanged() {
    if (!_tabController.indexIsChanging) {
      _updateTabStates(_tabController.index);
    }
  }

  bool get isPrivateChatInitiallyOpen {
    final isPublicChatAllowed =
    widget.viewModel.meetingDetails.features!.isPublicChatAllowed();
    final isPrivateChatAllowed =
    widget.viewModel.meetingDetails.features!.isPrivateChatAllowed();

    final tabCount =
        (isPublicChatAllowed ? 1 : 0) + (isPrivateChatAllowed ? 1 : 0);
    final initialIndex = (widget.identity.isEmpty || tabCount == 1) ? 0 : 1;

    // If index 1 or only private chat is allowed → private chat is open
    if (tabCount == 1 && isPrivateChatAllowed && !isPublicChatAllowed) {
      return true;
    }

    return initialIndex == 1;
  }

  void _updateTabStates(int index) {
    // Both start false
    widget.viewModel.isChatOpen = false;
    widget.viewModel.isPrivateChatOpen = false;

    // Determine which is open
    if (index == 0) {
      // If public chat exists first
      if (widget.viewModel.meetingDetails.features!.isPublicChatAllowed()) {
        widget.viewModel.isChatOpen = true;
      } else {
        widget.viewModel.isPrivateChatOpen = true;
      }
    } else if (index == 1) {
      widget.viewModel.isPrivateChatOpen = true;
    }
    setState(() {});
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    widget.viewModel.cancelMainChatControllerEvent();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {

    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(statusBarColor: Colors.black),
    );

    final isPublicChatAllowed =
        widget.viewModel.meetingDetails.features!.isPublicChatAllowed();
    final isPrivateChatAllowed =
        widget.viewModel.meetingDetails.features!.isPrivateChatAllowed();

    final totalPrivateUnread = widget.viewModel.getUnreadCountPrivateChat();
    final totalPublicUnread = widget.viewModel.getUnReadCount();

    final tabs = <Tab>[];
    final views = <Widget>[];

    if (isPublicChatAllowed) {
      tabs.add(_buildTab("All Chat", totalPublicUnread));
      views.add(ChatPage(viewModel: widget.viewModel));
    }

    if (isPrivateChatAllowed) {
      tabs.add(_buildTab("Private Chat", totalPrivateUnread));
      views.add(PrivateChatPage(
        viewModel: widget.viewModel,
        identity: widget.identity,
        name: widget.name,
      ));
    }

    if (tabs.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text("Chats", style: TextStyle(color: Colors.white)),
          backgroundColor: Colors.black,
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: const Center(
          child: Text(
            "Chat is disabled",
            style: TextStyle(color: Colors.white),
          ),
        ),
        backgroundColor: Colors.black,
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(
        title: const Text("Chats", style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.grey,
          tabs: tabs,
        ),
      ),
      body: Stack(
        children: [
          TabBarView(controller: _tabController, children: views),
          if (_isLoading) const CustomLoader(),
        ],
      ),
    );
  }

  // Badge anchors to the label text itself, so it stays at the text's
  // top-end corner regardless of how wide the tab cell is.
  Tab _buildTab(String title, int unread) {
    return Tab(
      child: Badge(
        isLabelVisible: unread > 0,
        label: Text('$unread', style: const TextStyle(color: Colors.white)),
        backgroundColor: Colors.red,
        offset: const Offset(16, -6),
        child: Text(title),
      ),
    );
  }

  bool isEventAdded = false;

  void collectChatEvents(RtcViewmodel? viewModel) {
    if (isEventAdded) return;
    isEventAdded = true;
    setState(() {});
    viewModel?.mainChatController.listen((event) {
      if (event is ShowLoading) {
        if (mounted) {
          setState(() {
            _isLoading = true;
          });
        }
      } else if (event is StopLoading) {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      } else if (event is UpdateView) {
        setState(() {});
      }
    });
  }
}
