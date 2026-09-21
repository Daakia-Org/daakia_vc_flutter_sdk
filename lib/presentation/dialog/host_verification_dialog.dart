import 'package:flutter/material.dart';

import '../../resources/colors/color.dart';
import '../../utils/utils.dart';

/// Asks a host for the meeting's email and PIN before they can join as host.
///
/// [onVerify] runs the check and resolves to an error message to show, or
/// null on success (the caller closes the dialog then). Errors are shown
/// inside the card rather than as snackbars: with the keyboard up, a snackbar
/// on the page behind is hidden under it.
///
/// Portrait stacks everything vertically. A landscape phone leaves only
/// ~150dp above the keyboard, so there the card goes wide instead: title and
/// actions share a header row, with Email and PIN side by side below it, so
/// every field and button stays visible while typing.
class HostVerificationDialog extends StatefulWidget {
  const HostVerificationDialog({
    super.key,
    required this.onVerify,
    required this.onCancel,
  });

  final Future<String?> Function(String email, String pin) onVerify;
  final VoidCallback onCancel;

  @override
  State<HostVerificationDialog> createState() => _HostVerificationDialogState();
}

class _HostVerificationDialogState extends State<HostVerificationDialog> {
  final _emailController = TextEditingController();
  final _pinController = TextEditingController();
  final _emailFocus = FocusNode();
  final _pinFocus = FocusNode();

  String? _emailError;
  String? _pinError;
  String? _serverError;
  bool _obscurePin = true;
  // PINs are usually numeric, so start on the number pad, but they can
  // contain letters too; the field has a toggle to switch keyboards.
  bool _pinUsesLetters = false;
  bool _verifying = false;

  @override
  void dispose() {
    _emailController.dispose();
    _pinController.dispose();
    _emailFocus.dispose();
    _pinFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_verifying) return;
    final email = _emailController.text.trim();
    final pin = _pinController.text.trim();

    setState(() {
      _emailError = Utils.isValidEmail(email)
          ? null
          : 'Enter a valid email address';
      _pinError = pin.isEmpty ? 'Enter your PIN' : null;
      _serverError = null;
    });
    if (_emailError != null) return _emailFocus.requestFocus();
    if (_pinError != null) return _pinFocus.requestFocus();

    // Drop the keyboard so the result (spinner, then error or close) is
    // visible, especially in landscape where the keyboard fills the screen.
    FocusScope.of(context).unfocus();
    setState(() => _verifying = true);
    final error = await widget.onVerify(email, pin);
    if (!mounted) return;
    setState(() {
      _verifying = false;
      _serverError = error;
    });
  }

  void _togglePinKeyboard() {
    setState(() => _pinUsesLetters = !_pinUsesLetters);
    // Android ignores a keyboardType change on a live input connection (the
    // framework's TextInput.updateConfig isn't acted on), so the keyboard
    // wouldn't switch until the field refocused. Once the rebuild has applied
    // the new type, reconnect by unfocusing and refocusing synchronously:
    // closing the connection only schedules the keyboard hide as a
    // microtask, and the reconnect lands first, so the keyboard swaps layout
    // without dropping.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final focusManager = FocusManager.instance;
      if (_pinFocus.hasFocus) {
        _pinFocus.unfocus();
        focusManager.applyFocusChangesIfNeeded();
      }
      _pinFocus.requestFocus();
      focusManager.applyFocusChangesIfNeeded();
    });
  }

  void _cancel() {
    widget.onCancel();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;

    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: isLandscape
          ? const EdgeInsets.symmetric(horizontal: 24, vertical: 8)
          : const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: isLandscape ? 600 : 400),
        // Safety net for unusually short screens or large text scales.
        child: SingleChildScrollView(
          padding: isLandscape
              ? const EdgeInsets.fromLTRB(20, 8, 20, 10)
              : const EdgeInsets.fromLTRB(24, 24, 24, 20),
          child: isLandscape ? _buildLandscape() : _buildPortrait(),
        ),
      ),
    );
  }

  Widget _buildPortrait() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _icon(size: 56),
        const SizedBox(height: 16),
        const Text(
          'Host verification',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.black87,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Enter the host email and PIN for this meeting.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.black54, fontSize: 14, height: 1.4),
        ),
        const SizedBox(height: 20),
        _emailField(),
        const SizedBox(height: 12),
        _pinField(),
        if (_serverError != null) ...[
          const SizedBox(height: 12),
          _serverErrorBanner(),
        ],
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(child: _cancelButton()),
            const SizedBox(width: 12),
            Expanded(child: _verifyButton()),
          ],
        ),
      ],
    );
  }

  Widget _buildLandscape() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            _icon(size: 36),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Host verification',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.black87,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            _cancelButton(compact: true),
            const SizedBox(width: 8),
            _verifyButton(compact: true),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _emailField(dense: true)),
            const SizedBox(width: 12),
            Expanded(child: _pinField(dense: true)),
          ],
        ),
        if (_serverError != null) ...[
          const SizedBox(height: 10),
          _serverErrorBanner(),
        ],
      ],
    );
  }

  Widget _icon({required double size}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: themeColor.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.admin_panel_settings_outlined,
        color: themeColor,
        size: size * 0.55,
      ),
    );
  }

  Widget _emailField({bool dense = false}) {
    return TextField(
      controller: _emailController,
      focusNode: _emailFocus,
      autofocus: true,
      enabled: !_verifying,
      keyboardType: TextInputType.emailAddress,
      textInputAction: TextInputAction.next,
      autofillHints: const [AutofillHints.email],
      autocorrect: false,
      style: const TextStyle(color: Colors.black87),
      onChanged: (_) {
        if (_emailError != null || _serverError != null) {
          setState(() => _emailError = _serverError = null);
        }
      },
      onSubmitted: (_) => _pinFocus.requestFocus(),
      decoration: _decoration(
        label: 'Email',
        icon: Icons.mail_outline_rounded,
        error: _emailError,
        dense: dense,
      ),
    );
  }

  Widget _pinField({bool dense = false}) {
    return TextField(
      controller: _pinController,
      focusNode: _pinFocus,
      enabled: !_verifying,
      keyboardType: _pinUsesLetters
          ? TextInputType.visiblePassword
          : TextInputType.number,
      obscureText: _obscurePin,
      autocorrect: false,
      enableSuggestions: false,
      textInputAction: TextInputAction.done,
      style: const TextStyle(color: Colors.black87),
      onChanged: (_) {
        if (_pinError != null || _serverError != null) {
          setState(() => _pinError = _serverError = null);
        }
      },
      onSubmitted: (_) => _submit(),
      decoration: _decoration(
        label: 'PIN',
        icon: Icons.lock_outline_rounded,
        error: _pinError,
        dense: dense,
        suffix: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              visualDensity: dense ? VisualDensity.compact : null,
              tooltip: _pinUsesLetters ? 'Use number pad' : 'Use letters',
              icon: Icon(
                _pinUsesLetters ? Icons.dialpad_rounded : Icons.abc_rounded,
                size: 22,
              ),
              onPressed: _togglePinKeyboard,
            ),
            IconButton(
              visualDensity: dense ? VisualDensity.compact : null,
              tooltip: _obscurePin ? 'Show PIN' : 'Hide PIN',
              icon: Icon(
                _obscurePin
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                size: 20,
              ),
              onPressed: () => setState(() => _obscurePin = !_obscurePin),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _decoration({
    required String label,
    required IconData icon,
    String? error,
    bool dense = false,
    Widget? suffix,
  }) {
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: color, width: width),
        );
    return InputDecoration(
      labelText: label,
      errorText: error,
      isDense: dense,
      filled: true,
      fillColor: const Color(0xFFF6F6F9),
      prefixIcon: Icon(icon, size: 20),
      suffixIcon: suffix,
      // The default 48dp icon box sets the field's minimum height; shrink it
      // so the landscape layout fits above the keyboard.
      prefixIconConstraints: dense
          ? const BoxConstraints(minWidth: 44, minHeight: 40)
          : null,
      suffixIconConstraints: dense
          ? const BoxConstraints(minWidth: 44, minHeight: 40)
          : null,
      labelStyle: const TextStyle(color: Colors.black54),
      floatingLabelStyle: const TextStyle(color: themeColor),
      border: border(Colors.black12),
      enabledBorder: border(Colors.black12),
      disabledBorder: border(Colors.black12),
      focusedBorder: border(themeColor, 1.5),
      errorBorder: border(Colors.red.shade400),
      focusedErrorBorder: border(Colors.red.shade400, 1.5),
    );
  }

  Widget _serverErrorBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline_rounded,
            color: Colors.red.shade700,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _serverError!,
              style: TextStyle(color: Colors.red.shade700, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  // compact: drop the 48dp tap-target padding and shorten, for the landscape
  // header row where every dp of height counts.
  Widget _cancelButton({bool compact = false}) {
    return TextButton(
      onPressed: _cancel,
      style: TextButton.styleFrom(
        foregroundColor: Colors.black54,
        minimumSize: Size(0, compact ? 36 : 44),
        tapTargetSize: compact ? MaterialTapTargetSize.shrinkWrap : null,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: const Text('Cancel'),
    );
  }

  Widget _verifyButton({bool compact = false}) {
    return FilledButton(
      onPressed: _verifying ? null : _submit,
      style: FilledButton.styleFrom(
        backgroundColor: themeColor,
        disabledBackgroundColor: themeColor.withValues(alpha: 0.6),
        minimumSize: Size(96, compact ? 36 : 44),
        tapTargetSize: compact ? MaterialTapTargetSize.shrinkWrap : null,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: _verifying
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Text('Verify'),
    );
  }
}
