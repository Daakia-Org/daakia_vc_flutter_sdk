import 'package:daakia_vc_flutter_sdk/events/rtc_events.dart';
import 'package:daakia_vc_flutter_sdk/presentation/widgets/language_selection_bottom_sheet.dart';
import 'package:daakia_vc_flutter_sdk/presentation/widgets/loader.dart';
import 'package:daakia_vc_flutter_sdk/presentation/widgets/transcription_bubble.dart';
import 'package:flutter/material.dart';

import '../../model/language_model.dart';
import '../../utils/utils.dart';
import '../../viewmodel/rtc_viewmodel.dart';
import '../dialog/transcript_download_choice_dialog.dart';

class TranscriptionScreen extends StatefulWidget {
  final RtcViewmodel viewModel;

  const TranscriptionScreen(this.viewModel, {super.key});

  @override
  State<TranscriptionScreen> createState() => _TranscriptionScreenState();
}

class _TranscriptionScreenState extends State<TranscriptionScreen> {
  bool _isLoading = false;
  bool _isTranslationEnabled = false;
  bool _isSmartScrollEnabled = true;
  final ScrollController _scrollController = ScrollController();

  // Remembers the last chosen translation language when the toggle is turned off.
  LanguageModel? _savedTranslationLanguage;

  @override
  void initState() {
    super.initState();
    _isTranslationEnabled = widget.viewModel.translationLanguage != null;
    _savedTranslationLanguage = widget.viewModel.translationLanguage;
    widget.viewModel.addListener(_onViewModelChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchLanguagesIfNeeded();
      // Hosts/co-hosts who haven't started transcription are dropped straight
      // into the language picker so they can kick things off.
      if (!widget.viewModel.isTranscriptionLanguageSelected &&
          (widget.viewModel.isHost() || widget.viewModel.isCoHost())) {
        _openLanguagePicker();
      }
    });
  }

  @override
  void dispose() {
    widget.viewModel.removeListener(_onViewModelChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onViewModelChanged() {
    if (!mounted) return;
    setState(() {});
    if (_isSmartScrollEnabled && _scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _fetchLanguagesIfNeeded() async {
    if (widget.viewModel.languages.isNotEmpty) return;
    setState(() => _isLoading = true);
    try {
      final languages = await widget.viewModel.fetchLanguages();
      widget.viewModel.languages = languages;
    } catch (e) {
      debugPrint('Error fetching languages: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _openLanguagePicker() {
    final sourceLangCode =
        widget.viewModel.transcriptionLanguageData?.sourceLang;
    final sourceLanguage = sourceLangCode != null
        ? widget.viewModel.languages.firstWhere(
            (l) => l.code == sourceLangCode,
            orElse: () =>
                LanguageModel(code: sourceLangCode, language: sourceLangCode),
          )
        : null;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => LanguageSelectionBottomSheet(
        languages: widget.viewModel.languages,
        initialSourceLanguage: sourceLanguage,
        initialTargetLanguage: _savedTranslationLanguage,
        onApply: _onLanguageApplied,
      ),
    );
  }

  void _onLanguageApplied(LanguageModel source, LanguageModel? target) {
    if (!widget.viewModel.isTranscriptionLanguageSelected) {
      // First time: start the transcription agent with the chosen source language.
      _startTranscriptionAgent(source);
    } else {
      // Already running: update source language via the participant language API.
      widget.viewModel.updateParticipantLanguage(source);
    }

    // Update translation target on the viewmodel (drives per-message translation).
    widget.viewModel.translationLanguage = target;
    _savedTranslationLanguage = target;

    setState(() {
      _isTranslationEnabled = target != null;
    });
  }

  void _startTranscriptionAgent(LanguageModel selectedLanguage) {
    widget.viewModel.setTranscriptionLanguage(selectedLanguage, () {
      if (widget.viewModel.isTranscriptionLanguageSelected) {
        widget.viewModel.startTranscriptionAgent(selectedLanguage);
      }
    });
  }

  Future<void> _handleDownload() async {
    final isTranslationAllowed = widget.viewModel.meetingDetails.features!
        .isVoiceTextTranslationAllowed();

    String formattedTranscript;

    if (isTranslationAllowed) {
      final choice = await showDialog<TranscriptDownloadChoice>(
        context: context,
        builder: (context) => TranscriptDownloadChoiceDialog(
          isEnabled: widget.viewModel.translationLanguage != null,
        ),
      );
      if (choice == null) return;
      setState(() => _isLoading = true);
      formattedTranscript = (choice == TranscriptDownloadChoice.translated)
          ? Utils.getTranslatedTranscriptFormattedToSave(
              widget.viewModel.transcriptionList)
          : Utils.getTranscriptFormattedToSave(
              widget.viewModel.transcriptionList);
    } else {
      setState(() => _isLoading = true);
      formattedTranscript = Utils.getTranscriptFormattedToSave(
          widget.viewModel.transcriptionList);
    }

    final result = await Utils.saveDataToFile(
      formattedTranscript,
      "caption_${widget.viewModel.meetingDetails.meetingUid}_${DateTime.now().millisecondsSinceEpoch}",
    );

    setState(() => _isLoading = false);

    if (result.isSuccess) {
      widget.viewModel.sendEvent(ShowTranscriptionDownload(
        message: "File saved successfully!",
        path: result.filePath,
      ));
    } else {
      widget.viewModel.sendMessageToUI("Failed to save file!");
    }
  }

  String _languageLabel() {
    final sourceLangCode =
        widget.viewModel.transcriptionLanguageData?.sourceLang;
    if (sourceLangCode == null) return 'Set language';

    final sourceName = widget.viewModel.languages.isNotEmpty
        ? (widget.viewModel.languages
                .firstWhere(
                  (l) => l.code == sourceLangCode,
                  orElse: () => LanguageModel(
                      code: sourceLangCode, language: sourceLangCode),
                )
                .language ??
            sourceLangCode)
        : sourceLangCode;

    final targetName = widget.viewModel.translationLanguage?.language;
    return targetName != null ? '$sourceName → $targetName ▾' : '$sourceName ▾';
  }

  @override
  Widget build(BuildContext context) {
    final isTranslationAllowed =
        widget.viewModel.meetingDetails.features?.isVoiceTextTranslationAllowed() ==
            true;
    final canDownload = widget.viewModel.isTranscriptionLanguageSelected &&
        (widget.viewModel.isHost() || widget.viewModel.isCoHost());
    final transcriptionStarted =
        widget.viewModel.isTranscriptionLanguageSelected;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D0D),
        automaticallyImplyLeading: false,
        centerTitle: true,
        title: const Text(
          'Live Caption',
          style: TextStyle(color: Colors.white),
        ),
        actions: [
          if (canDownload)
            IconButton(
              icon: const Icon(Icons.download, color: Colors.white),
              onPressed: _handleDownload,
            ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              if (transcriptionStarted && isTranslationAllowed)
                _LiveTranslationCard(
                  isEnabled: _isTranslationEnabled,
                  languageLabel: _languageLabel(),
                  onToggle: (value) {
                    setState(() => _isTranslationEnabled = value);
                    if (!value) {
                      _savedTranslationLanguage =
                          widget.viewModel.translationLanguage;
                      widget.viewModel.translationLanguage = null;
                    } else {
                      widget.viewModel.translationLanguage =
                          _savedTranslationLanguage;
                      if (_savedTranslationLanguage == null) {
                        _openLanguagePicker();
                      }
                    }
                  },
                  onLanguageTap: _openLanguagePicker,
                ),
              if (transcriptionStarted)
                _SmartScrollCard(
                  isEnabled: _isSmartScrollEnabled,
                  onToggle: (value) =>
                      setState(() => _isSmartScrollEnabled = value),
                ),
              Expanded(child: _buildTranscriptionList(transcriptionStarted)),
            ],
          ),
          if (_isLoading) const CustomLoader(),
        ],
      ),
    );
  }

  Widget _buildTranscriptionList(bool transcriptionStarted) {
    if (!transcriptionStarted) {
      return const Center(
        child: Text(
          'Live captions have not started yet.',
          style: TextStyle(color: Colors.white54),
        ),
      );
    }

    if (widget.viewModel.transcriptionList.isEmpty) {
      return const Center(
        child: Text(
          'Waiting for captions…',
          style: TextStyle(color: Colors.white54),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      itemCount: widget.viewModel.transcriptionList.length,
      itemBuilder: (context, index) {
        final reversedIndex =
            widget.viewModel.transcriptionList.length - 1 - index;
        return TranscriptionBubble(
          transcriptionData:
              widget.viewModel.transcriptionList[reversedIndex],
          viewModel: widget.viewModel,
          showTranslation: _isTranslationEnabled,
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Private card widgets
// ---------------------------------------------------------------------------

class _LiveTranslationCard extends StatelessWidget {
  final bool isEnabled;
  final String languageLabel;
  final ValueChanged<bool> onToggle;
  final VoidCallback onLanguageTap;

  const _LiveTranslationCard({
    required this.isEnabled,
    required this.languageLabel,
    required this.onToggle,
    required this.onLanguageTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.translate, color: Colors.blue, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Live Translation',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: isEnabled ? Colors.green : Colors.grey,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
                GestureDetector(
                  onTap: onLanguageTap,
                  child: Text(
                    languageLabel,
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
          _TranslationToggle(isEnabled: isEnabled, onChanged: onToggle),
        ],
      ),
    );
  }
}

class _SmartScrollCard extends StatelessWidget {
  final bool isEnabled;
  final ValueChanged<bool> onToggle;

  const _SmartScrollCard({required this.isEnabled, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.vertical_align_bottom,
                color: Colors.blue, size: 22),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Smart Scroll',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                Text(
                  'Keep view on latest updates',
                  style: TextStyle(color: Colors.white60, fontSize: 13),
                ),
              ],
            ),
          ),
          Switch(
            value: isEnabled,
            onChanged: onToggle,
            activeThumbColor: Colors.blue,
            activeTrackColor: Colors.blue.withValues(alpha: 0.5),
          ),
        ],
      ),
    );
  }
}

class _TranslationToggle extends StatelessWidget {
  final bool isEnabled;
  final ValueChanged<bool> onChanged;

  const _TranslationToggle(
      {required this.isEnabled, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!isEnabled),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isEnabled ? Colors.blue : const Color(0xFF2A2A3E),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isEnabled ? 'On' : 'Off',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              isEnabled
                  ? Icons.check_circle_outline
                  : Icons.pause_circle_outline,
              color: Colors.white,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}