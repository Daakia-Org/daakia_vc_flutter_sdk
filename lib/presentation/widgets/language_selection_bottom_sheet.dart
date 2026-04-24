import 'package:flutter/material.dart';

import '../../model/language_model.dart';

class LanguageSelectionBottomSheet extends StatefulWidget {
  final List<LanguageModel> languages;
  final LanguageModel? initialSourceLanguage;
  final LanguageModel? initialTargetLanguage;
  final void Function(LanguageModel source, LanguageModel? target) onApply;

  const LanguageSelectionBottomSheet({
    required this.languages,
    required this.onApply,
    this.initialSourceLanguage,
    this.initialTargetLanguage,
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
    final picked = await showModalBottomSheet<LanguageModel>(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        expand: false,
        builder: (_, controller) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                isSource ? 'From (Source Language)' : 'To (Target Language)',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const Divider(color: Colors.white24, height: 1),
            Expanded(
              child: ListView.builder(
                controller: controller,
                itemCount: widget.languages.length,
                itemBuilder: (context, index) {
                  final lang = widget.languages[index];
                  final isSelected = isSource
                      ? lang.code == _sourceLanguage?.code
                      : lang.code == _targetLanguage?.code;
                  return ListTile(
                    title: Text(
                      lang.language ?? '',
                      style: const TextStyle(color: Colors.white),
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
        ),
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
                  'Select Language',
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
            const Text(
              'From (Source Language)',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 8),
            _LanguageDropdownTile(
              label: _sourceLanguage?.language ?? 'Select language',
              onTap: () => _pickLanguage(isSource: true),
            ),
            const SizedBox(height: 16),
            const Text(
              'To (Target Language)',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 8),
            _LanguageDropdownTile(
              label: _targetLanguage?.language ?? 'Select language',
              onTap: () => _pickLanguage(isSource: false),
            ),
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
                onPressed: _sourceLanguage == null
                    ? null
                    : () {
                        widget.onApply(_sourceLanguage!, _targetLanguage);
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

class _LanguageDropdownTile extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _LanguageDropdownTile({required this.label, required this.onTap});

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
            const Icon(Icons.language, color: Colors.white70, size: 20),
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