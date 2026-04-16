import 'dart:async';

import 'package:daakia_vc_flutter_sdk/events/rtc_events.dart';
import 'package:daakia_vc_flutter_sdk/presentation/widgets/loader.dart';
import 'package:daakia_vc_flutter_sdk/presentation/widgets/transcription_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';

import '../../model/language_model.dart';
import '../../utils/utils.dart';
import '../../viewmodel/rtc_viewmodel.dart';
import '../dialog/language_select_dialog.dart';
import '../dialog/transcript_download_choice_dialog.dart';

class TranscriptionScreen extends StatefulWidget {
  final RtcViewmodel viewModel;

  const TranscriptionScreen(this.viewModel, {super.key});

  @override
  State<TranscriptionScreen> createState() => _TranscriptionScreenState();
}

class _TranscriptionScreenState extends State<TranscriptionScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<LanguageModel> _filteredLanguages = [];
  var _isLoading = false;
  Timer? _pollingTimer;

  @override
  initState() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      fetchTranscriptionLanguage();
      _searchController.addListener(_filterLanguages);
      _startTranscription();
    });
    super.initState();
  }

  @override
  void dispose() {
    _searchController.removeListener(_filterLanguages);
    _pollingTimer?.cancel(); // Stop the polling when the screen is closed
    super.dispose();
  }

  void _startTranscription() {
    if (widget.viewModel.isTranscriptionLanguageSelected) {
      widget.viewModel.startTranscription();
    }
  }

  void fetchTranscriptionLanguage() async {
    setState(() {
      _isLoading = true;
    });
    try {
      if (widget.viewModel.languages.isNotEmpty) {
        _filteredLanguages = List.from(widget.viewModel.languages);
      } else {
        final languages = await widget.viewModel.fetchLanguages();
        widget.viewModel.languages = languages;
        _filteredLanguages = List.from(widget.viewModel.languages);
      }
    } on Exception catch (e) {
      debugPrint('Error fetching languages: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> handleDownloadButtonPressed() async {
    String formattedTranscript;

    final isTranslationAllowed = widget.viewModel.meetingDetails.features!
        .isVoiceTextTranslationAllowed();

    if (isTranslationAllowed) {
      final choice = await showDialog<TranscriptDownloadChoice>(
        context: context,
        builder: (context) => TranscriptDownloadChoiceDialog(
          isEnabled: widget.viewModel.translationLanguage != null,
        ),
      );

      if (choice == null) return;

      setState(() {
        _isLoading = true;
      });

      formattedTranscript = (choice == TranscriptDownloadChoice.translated)
          ? Utils.getTranslatedTranscriptFormattedToSave(
              widget.viewModel.transcriptionList)
          : Utils.getTranscriptFormattedToSave(
              widget.viewModel.transcriptionList);
    } else {
      setState(() {
        _isLoading = true;
      });
      formattedTranscript = Utils.getTranscriptFormattedToSave(
          widget.viewModel.transcriptionList);
    }

    final result = await Utils.saveDataToFile(
      formattedTranscript,
      "caption_${widget.viewModel.meetingDetails.meetingUid}_${DateTime.now().millisecondsSinceEpoch}",
    );

    setState(() {
      _isLoading = false;
    });

    if (result.isSuccess) {
      widget.viewModel.sendEvent(ShowTranscriptionDownload(
        message: "File saved successfully!",
        path: result.filePath,
      ));
    } else {
      widget.viewModel.sendMessageToUI("Failed to save file!");
    }
  }

  void handleSelectTranslationButtonPressed() {
    showDialog(
      context: context,
      builder: (_) => LanguageSelectDialog(
        languages: widget.viewModel.languages,
        // Provide the list of languages
        onLanguageSelected: (language) {
          widget.viewModel.translationLanguage = language;
        },
      ),
    );
  }

  void _filterLanguages() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredLanguages = widget.viewModel.languages
          .where((lang) => lang.language!.toLowerCase().contains(query))
          .toList();
    });
  }

  @Deprecated("This API is no longer supported. Please use `_startTranscriptionAgent()` instead.")
  void _handleLanguageSelection(LanguageModel selectedLanguage) {
    widget.viewModel.setTranscriptionLanguage(selectedLanguage, () {
      _startTranscription();
    });
  }

  void _startTranscriptionAgent(LanguageModel selectedLanguage) {
    widget.viewModel.setTranscriptionLanguage(selectedLanguage, () {
      if (widget.viewModel.isTranscriptionLanguageSelected) {
        widget.viewModel.startTranscriptionAgent(selectedLanguage);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(
        title: const Text(
          "Live Captions",
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (widget.viewModel.meetingDetails.features!
                  .isVoiceTextTranslationAllowed() &&
              widget.viewModel.isTranscriptionLanguageSelected)
            IconButton(
              icon: SvgPicture.asset(
                'assets/icons/ic_translate_chats_colored.svg',
                package: 'daakia_vc_flutter_sdk',
                fit: BoxFit.fill,
                height: 25,
                width: 25,
              ),
              color: Colors.white,
              onPressed: () => handleSelectTranslationButtonPressed(),
            ),
          if (widget.viewModel.isTranscriptionLanguageSelected &&
              (widget.viewModel.isHost() || widget.viewModel.isCoHost()))
            IconButton(
              icon: const Icon(Icons.download),
              color: Colors.white,
              onPressed: () => handleDownloadButtonPressed(),
            ),
        ],
        automaticallyImplyLeading: true,
        centerTitle: true,
        elevation: 5,
      ),
      body: Stack(
        children: [
          // Main UI
          if ((widget.viewModel.isHost() || widget.viewModel.isCoHost()) &&
              !widget.viewModel.isTranscriptionLanguageSelected)
            Column(
              children: [
                const SizedBox(
                  height: 20,
                ),
                // Search Bar
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search languages...',
                      hintStyle: const TextStyle(color: Colors.white54),
                      prefixIcon: const Icon(Icons.search, color: Colors.white),
                      filled: true,
                      fillColor: Colors.grey[800],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8.0),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                // Language List
                Expanded(
                  child: _filteredLanguages.isEmpty
                      ? const Center(
                          child: Text(
                            'No languages found',
                            style: TextStyle(color: Colors.white),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _filteredLanguages.length,
                          itemBuilder: (context, index) {
                            final language = _filteredLanguages[index];
                            return ListTile(
                              title: Text(
                                language.language ?? '',
                                style: const TextStyle(color: Colors.white),
                              ),
                              onTap: () => _startTranscriptionAgent(language),
                            );
                          },
                        ),
                ),
              ],
            ),
          if (widget.viewModel.isTranscriptionLanguageSelected)
            ListView.builder(
              reverse: true,
              itemCount: widget.viewModel.transcriptionList.length,
              itemBuilder: (context, index) {
                final reversedIndex =
                    widget.viewModel.transcriptionList.length - 1 - index;
                final transcriptionData =
                    widget.viewModel.transcriptionList[reversedIndex];
                return TranscriptionBubble(
                  transcriptionData: transcriptionData,
                  viewModel: widget.viewModel,
                );
              },
            ),
          const SizedBox(
            height: 30,
          ),
          // Loader Overlay
          if (_isLoading) const CustomLoader()
        ],
      ),
    );
  }
}
