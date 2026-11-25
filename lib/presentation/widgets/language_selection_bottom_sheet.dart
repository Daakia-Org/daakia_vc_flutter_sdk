import 'package:flutter/material.dart';

import '../../model/language_model.dart';
import '../../utils/utils.dart';

class LanguageSelectionBottomSheet extends StatefulWidget {
  final List<LanguageModel> languages;
  final LanguageModel? initialSourceLanguage;
  final LanguageModel? initialTargetLanguage;
  // When true, source language is locked (transcription already running) and
  // the speak-language picker is hidden. Only translation language can change.
  final bool isSourceLanguageLocked;
  // When false, translation is not part of the plan — the read-language picker
  // and target-language field are hidden entirely.
  final bool isTranslationAllowed;
  final void Function(LanguageModel source, LanguageModel? target) onApply;

  const LanguageSelectionBottomSheet({
    required this.languages,
    required this.onApply,
    this.initialSourceLanguage,
    this.initialTargetLanguage,
    this.isSourceLanguageLocked = false,
    this.isTranslationAllowed = true,
    super.key,
  });

  @override
  State<LanguageSelectionBottomSheet> createState() =>
      _LanguageSelectionBottomSheetState();
}

class _LanguageSelectionBottomSheetState
    extends State<LanguageSelectionBottomSheet> {
  LanguageModel? _sourceLanguage;
  LanguageModel? _targetLanguage;

  @override
  void initState() {
    super.initState();
    _sourceLanguage = widget.initialSourceLanguage;
    _targetLanguage = widget.initialTargetLanguage;
  }

  Future<void> _pickLanguage({required bool isSource}) async {
    final currentSelection = isSource ? _sourceLanguage : _targetLanguage;
    final picked = await Utils.showAdaptiveSheet<LanguageModel>(
      context,
      backgroundColor: const Color(0xFF1A1A2E),
      // The picker sizes itself around the keyboard and scrolls its own list.
      forceFullHeight: true,
      scrollable: false,
      builder: (_) => _LanguagePickerSheet(
        title: isSource ? 'From (Speak Language)' : 'To (Read Language)',
        languages: widget.languages,
        selectedLanguage: currentSelection,
      ),
    );
    if (picked != null) {
      setState(() {
        if (isSource) {
          _sourceLanguage = picked;
        } else {
          _targetLanguage = picked;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A2E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white30,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Live Caption',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (!widget.isSourceLanguageLocked) ...[
              const Text(
                'Choose a language that you will speak.',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 8),
              _LanguageDropdownTile(
                label: _sourceLanguage?.displayName ?? 'Select language',
                iconUrl: _sourceLanguage?.icon,
                onTap: () => _pickLanguage(isSource: true),
              ),
              const SizedBox(height: 16),
            ],
            if (widget.isTranslationAllowed) ...[
              const Text(
                'Choose a language you prefer to read.',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 8),
              _LanguageDropdownTile(
                label: _targetLanguage?.displayName ?? 'Select language',
                iconUrl: _targetLanguage?.icon,
                onTap: () => _pickLanguage(isSource: false),
              ),
              const SizedBox(height: 24),
            ] else
              const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  disabledBackgroundColor: Colors.blue.withValues(alpha: 0.4),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () {
                  final source =
                      _sourceLanguage ?? widget.initialSourceLanguage;
                  if (source == null) return;
                  widget.onApply(source, _targetLanguage);
                  Navigator.pop(context);
                },
                child: const Text(
                  'Apply',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Searchable language picker — opened when the user taps a dropdown tile.
// ---------------------------------------------------------------------------

class _LanguagePickerSheet extends StatefulWidget {
  final String title;
  final List<LanguageModel> languages;
  final LanguageModel? selectedLanguage;

  const _LanguagePickerSheet({
    required this.title,
    required this.languages,
    this.selectedLanguage,
  });

  @override
  State<_LanguagePickerSheet> createState() => _LanguagePickerSheetState();
}

class _LanguagePickerSheetState extends State<_LanguagePickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  late List<LanguageModel> _filtered;

  @override
  void initState() {
    super.initState();
    _filtered = widget.languages;
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      _filtered = query.isEmpty
          ? widget.languages
          : widget.languages
              .where((l) =>
                  l.language?.toLowerCase().contains(query) == true)
              .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final keyboardHeight = media.viewInsets.bottom;
    final isKeyboardOpen = keyboardHeight > 0;
    final isLandscape = media.orientation == Orientation.landscape;
    // A landscape phone has ~150dp above the keyboard: drop the handle and
    // title so the search field and some results still fit.
    final isCompact = isKeyboardOpen && isLandscape;

    // The modal sheet does not avoid the keyboard by itself, so without this
    // padding the keyboard covered the whole sheet, search field included.
    return Padding(
      padding: EdgeInsets.only(bottom: keyboardHeight),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double heightFactor =
              isKeyboardOpen ? 1.0 : (isLandscape ? 0.9 : 0.65);
          return SizedBox(
            height: constraints.maxHeight * heightFactor,
            child: _buildContent(isCompact),
          );
        },
      ),
    );
  }

  Widget _buildContent(bool isCompact) {
    return Column(
      children: [
        if (!isCompact) ...[
          // Handle bar
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 8),
            child: Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white30,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Text(
              widget.title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ] else
          const SizedBox(height: 8),
        // Search field
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            controller: _searchController,
            autofocus: false,
            // Enter closes the keyboard, so a keyboard with no hide key
            // still has a way out.
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => FocusManager.instance.primaryFocus?.unfocus(),
            onTapOutside: Utils.dismissKeyboardOnTapOutside,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Search languages…',
              hintStyle: const TextStyle(color: Colors.white38),
              prefixIcon:
                  const Icon(Icons.search, color: Colors.white54, size: 20),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close,
                          color: Colors.white54, size: 18),
                      onPressed: () => _searchController.clear(),
                    )
                  : null,
              filled: true,
              fillColor: const Color(0xFF252540),
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        const Divider(color: Colors.white12, height: 1),
        Expanded(
          child: _filtered.isEmpty
              ? const Center(
                  child: Text(
                    'No languages found',
                    style: TextStyle(color: Colors.white54),
                  ),
                )
              : ListView.builder(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  itemCount: _filtered.length,
                  itemBuilder: (context, index) {
                    final lang = _filtered[index];
                    final isSelected =
                        lang.code == widget.selectedLanguage?.code;
                    return ListTile(
                      leading: _FlagAvatar(iconUrl: lang.icon),
                      title: Text(
                        lang.displayName,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                      trailing: isSelected
                          ? const Icon(Icons.check, color: Colors.blue)
                          : null,
                      onTap: () => Navigator.pop(context, lang),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _FlagAvatar extends StatelessWidget {
  final String? iconUrl;

  const _FlagAvatar({this.iconUrl});

  // Convert SVG URL (flagcdn.com/xx.svg) to a PNG URL (flagcdn.com/w40/xx.png)
  // so we can use Image.network with a reliable errorBuilder.
  static String? _pngUrl(String? svgUrl) {
    if (svgUrl == null) return null;
    return svgUrl
        .replaceFirst('flagcdn.com/', 'flagcdn.com/w40/')
        .replaceFirst('.svg', '.png');
  }

  @override
  Widget build(BuildContext context) {
    final url = _pngUrl(iconUrl);
    return CircleAvatar(
      radius: 14,
      backgroundColor: Colors.white10,
      child: ClipOval(
        child: url != null
            ? Image.network(
                url,
                width: 28,
                height: 28,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.language,
                  size: 16,
                  color: Colors.white54,
                ),
              )
            : const Icon(Icons.language, size: 16, color: Colors.white54),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _LanguageDropdownTile extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final String? iconUrl;

  const _LanguageDropdownTile({
    required this.label,
    required this.onTap,
    this.iconUrl,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white24),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            _FlagAvatar(iconUrl: iconUrl),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(color: Colors.white),
              ),
            ),
            const Icon(Icons.keyboard_arrow_down, color: Colors.white70),
          ],
        ),
      ),
    );
  }
}
