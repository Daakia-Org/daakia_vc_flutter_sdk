import 'package:daakia_vc_flutter_sdk/events/rtc_events.dart';
import 'package:daakia_vc_flutter_sdk/presentation/widgets/language_selection_bottom_sheet.dart';
import 'package:daakia_vc_flutter_sdk/presentation/widgets/loader.dart';
import 'package:daakia_vc_flutter_sdk/presentation/widgets/transcription_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../model/language_model.dart';
import '../../utils/utils.dart';
import '../../viewmodel/rtc_viewmodel.dart';

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
  bool _isLanguageCardExpanded = true;
  bool _isSmartScrollCardExpanded = true;
  final ScrollController _scrollController = ScrollController();
  late final ScrollPhysics _scrollPhysics;
  // Latches to true the moment transcription becomes active; used to detect
  // the active→stopped transition and auto-close the screen for everyone.
  bool _wasTranscriptionActive = false;


  @override
  void initState() {
    super.initState();
    _isTranslationEnabled = widget.viewModel.isTranslationActive;
    _wasTranscriptionActive = widget.viewModel.isTranscriptionLanguageSelected;
    // Physics reads _isSmartScrollEnabled at call time via the closure, so one
    // stable instance is enough — no need to recreate on every build.
    _scrollPhysics = _AnchoredScrollPhysics(
      shouldAnchor: () => !_isSmartScrollEnabled,
    );
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

    final isActive = widget.viewModel.isTranscriptionLanguageSelected;

    // Close the screen for everyone when transcription is stopped.
    if (_wasTranscriptionActive && !isActive) {
      Navigator.of(context).maybePop();
      return;
    }
    if (isActive) _wasTranscriptionActive = true;

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

    final isTranslationAllowed =
        widget.viewModel.meetingDetails.features?.isVoiceTextTranslationAllowed() ==
            true;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => LanguageSelectionBottomSheet(
        languages: widget.viewModel.languages,
        initialSourceLanguage: sourceLanguage,
        initialTargetLanguage: widget.viewModel.translationLanguage,
        isSourceLanguageLocked: widget.viewModel.isTranscriptionStarter ||
            widget.viewModel.hasUsedParticipantLanguage,
        isTranslationAllowed: isTranslationAllowed,
        onApply: _onLanguageApplied,
      ),
    );
  }

  void _onLanguageApplied(LanguageModel source, LanguageModel? target) {
    if (!widget.viewModel.isTranscriptionLanguageSelected) {
      // First time: start the transcription agent with the chosen source language.
      _startTranscriptionAgent(source);
    } else if (!widget.viewModel.isTranscriptionStarter &&
        !widget.viewModel.hasUsedParticipantLanguage) {
      // Non-starters get exactly one source-language change per session.
      widget.viewModel.updateParticipantLanguage(source);
    }
    // else: source is locked — starter or already used one-time change.

    // Update translation target and activate/deactivate translation.
    widget.viewModel.translationLanguage = target;
    final translationOn = target != null;
    widget.viewModel.isTranslationActive = translationOn;
    setState(() => _isTranslationEnabled = translationOn);
  }

  void _startTranscriptionAgent(LanguageModel selectedLanguage) {
    widget.viewModel.setTranscriptionLanguage(selectedLanguage, () {
      if (widget.viewModel.isTranscriptionLanguageSelected) {
        widget.viewModel.startTranscriptionAgent(selectedLanguage);
      }
    });
  }

  Future<void> _handleDownload() async {
    setState(() => _isLoading = true);

    final formattedTranscript = Utils.getFormattedTranscriptToSave(
      widget.viewModel.transcriptionList,
    );

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
        ? widget.viewModel.languages
            .firstWhere(
              (l) => l.code == sourceLangCode,
              orElse: () =>
                  LanguageModel(code: sourceLangCode, language: sourceLangCode),
            )
            .displayName
        : sourceLangCode;

    final targetName = widget.viewModel.translationLanguage?.displayName;
    return targetName != null ? '$sourceName → $targetName ▾' : '$sourceName ▾';
  }

  @override
  Widget build(BuildContext context) {
    final isTranslationAllowed =
        widget.viewModel.meetingDetails.features?.isVoiceTextTranslationAllowed() ==
            true;
    final transcriptionStarted =
        widget.viewModel.isTranscriptionLanguageSelected;
    final canControl = transcriptionStarted &&
        (widget.viewModel.isHost() || widget.viewModel.isCoHost());

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
          if (canControl)
            IconButton(
              icon: const Icon(Icons.download, color: Colors.white),
              onPressed: _handleDownload,
            ),
          if (canControl)
            IconButton(
              tooltip: 'Stop captions',
              icon: const Icon(Icons.stop_circle_outlined,
                  color: Colors.redAccent),
              onPressed: () => widget.viewModel.stopTranscription(),
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
              if (transcriptionStarted)
                _LiveTranslationCard(
                  isTranslationAllowed: isTranslationAllowed,
                  isSourceLanguageLocked:
                      widget.viewModel.isTranscriptionStarter ||
                          widget.viewModel.hasUsedParticipantLanguage,
                  isExpanded: _isLanguageCardExpanded,
                  isEnabled: _isTranslationEnabled,
                  languageLabel: _languageLabel(),
                  onExpansionToggle: () => setState(
                      () => _isLanguageCardExpanded = !_isLanguageCardExpanded),
                  onToggle: isTranslationAllowed
                      ? (value) {
                          setState(() => _isTranslationEnabled = value);
                          widget.viewModel.isTranslationActive = value;
                          if (value &&
                              widget.viewModel.translationLanguage == null) {
                            _openLanguagePicker();
                          }
                        }
                      : null,
                  onLanguageTap: _openLanguagePicker,
                ),
              if (transcriptionStarted)
                _SmartScrollCard(
                  isEnabled: _isSmartScrollEnabled,
                  isExpanded: _isSmartScrollCardExpanded,
                  onExpansionToggle: () => setState(() =>
                      _isSmartScrollCardExpanded = !_isSmartScrollCardExpanded),
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
      physics: _scrollPhysics,
      itemCount: widget.viewModel.transcriptionList.length,
      itemBuilder: (context, index) {
        final reversedIndex =
            widget.viewModel.transcriptionList.length - 1 - index;
        return TranscriptionBubble(
          transcriptionData:
              widget.viewModel.transcriptionList[reversedIndex],
          viewModel: widget.viewModel,
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Scroll physics that anchors the viewport to the current content when new
// items are inserted at the leading edge of a reverse:true list.
//
// adjustPositionForNewDimensions runs during the layout phase — before paint —
// so the correction is applied in the same frame and produces zero visual jerk.
// When shouldAnchor() returns false (smart scroll is on, or user is at the
// very bottom), it falls through to default behaviour.
// ---------------------------------------------------------------------------

class _AnchoredScrollPhysics extends ScrollPhysics {
  final ValueGetter<bool> shouldAnchor;

  const _AnchoredScrollPhysics({required this.shouldAnchor, super.parent});

  @override
  _AnchoredScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      _AnchoredScrollPhysics(
          shouldAnchor: shouldAnchor, parent: buildParent(ancestor));

  @override
  double adjustPositionForNewDimensions({
    required ScrollMetrics oldPosition,
    required ScrollMetrics newPosition,
    required bool isScrolling,
    required double velocity,
  }) {
    // Only anchor when the user is scrolled away from the bottom (pixels > 0).
    // At offset 0 the new item appears naturally at the bottom — no adjustment.
    if (shouldAnchor() && newPosition.pixels > 0) {
      final delta =
          newPosition.maxScrollExtent - oldPosition.maxScrollExtent;
      if (delta > 0) return newPosition.pixels + delta;
    }
    return super.adjustPositionForNewDimensions(
      oldPosition: oldPosition,
      newPosition: newPosition,
      isScrolling: isScrolling,
      velocity: velocity,
    );
  }
}

// ---------------------------------------------------------------------------
// Private card widgets
// ---------------------------------------------------------------------------

class _LiveTranslationCard extends StatelessWidget {
  final bool isTranslationAllowed;
  final bool isSourceLanguageLocked;
  final bool isExpanded;
  final bool isEnabled;
  final String languageLabel;
  final VoidCallback onExpansionToggle;
  // Null when translation is not allowed (toggle is hidden in that case).
  final ValueChanged<bool>? onToggle;
  final VoidCallback onLanguageTap;

  const _LiveTranslationCard({
    required this.isTranslationAllowed,
    required this.isSourceLanguageLocked,
    required this.isExpanded,
    required this.isEnabled,
    required this.languageLabel,
    required this.onExpansionToggle,
    required this.onLanguageTap,
    this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final decoration = BoxDecoration(
      color: const Color(0xFF1A1A2E),
      borderRadius: BorderRadius.circular(12),
    );

    if (!isExpanded) {
      // Collapsed: slim bar — icon box removed, just title + controls.
      return Container(
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: decoration,
        child: Row(
          children: [
            Text(
              isTranslationAllowed ? 'Live Translation' : 'Speak Language',
              style: const TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            if (isTranslationAllowed) ...[
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
            const Spacer(),
            GestureDetector(
              onTap: onExpansionToggle,
              child: const Icon(Icons.expand_more, color: Colors.white38),
            ),
          ],
        ),
      );
    }

    // Expanded: original layout with lock indicator and chevron.
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: decoration,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SvgPicture.asset(
            'packages/daakia_vc_flutter_sdk/assets/icons/ic_translate_chats_colored.svg',
            width: 22,
            height: 22,
          ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      isTranslationAllowed
                          ? 'Live Translation'
                          : 'Speak Language',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    if (isTranslationAllowed) ...[
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
                  ],
                ),
                GestureDetector(
                  onTap: onLanguageTap,
                  child: Row(
                    children: [
                      if (isSourceLanguageLocked)
                        const Padding(
                          padding: EdgeInsets.only(right: 4),
                          child: Icon(Icons.lock_outline,
                              size: 13, color: Colors.white38),
                        ),
                      Flexible(
                        child: Text(
                          languageLabel,
                          style: const TextStyle(
                              color: Colors.white60, fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (isTranslationAllowed && onToggle != null)
            _TranslationToggle(isEnabled: isEnabled, onChanged: onToggle!),
          GestureDetector(
            onTap: onExpansionToggle,
            child: const Icon(Icons.expand_less, color: Colors.white54),
          ),
        ],
      ),
    );
  }
}

class _SmartScrollCard extends StatelessWidget {
  final bool isEnabled;
  final bool isExpanded;
  final VoidCallback onExpansionToggle;
  final ValueChanged<bool> onToggle;

  const _SmartScrollCard({
    required this.isEnabled,
    required this.isExpanded,
    required this.onExpansionToggle,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final decoration = BoxDecoration(
      color: const Color(0xFF1A1A2E),
      borderRadius: BorderRadius.circular(12),
    );

    if (!isExpanded) {
      // Collapsed: slim bar — icon box removed.
      return Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: decoration,
        child: Row(
          children: [
            const Text(
              'Smart Scroll',
              style: TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: isEnabled ? Colors.blue : Colors.grey,
                shape: BoxShape.circle,
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: onExpansionToggle,
              child: const Icon(Icons.expand_more, color: Colors.white38),
            ),
          ],
        ),
      );
    }

    // Expanded: original layout.
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: decoration,
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
          GestureDetector(
            onTap: onExpansionToggle,
            child: const Icon(Icons.expand_less, color: Colors.white54),
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