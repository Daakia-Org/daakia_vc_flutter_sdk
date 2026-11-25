import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/injection.dart';
import '../../resources/colors/color.dart';
import '../../service/daakia_vc_logger.dart';
import '../../utils/storage_helper.dart';
import '../../utils/utils.dart';

enum EmailVerificationStep { email, code }

/// State of the pre-join email verification for meetings with
/// `email_verification_required`: email → one-time code → verified.
///
/// Lives in the pre-join state (not the card) so rotation, which remounts the
/// join form, doesn't lose the typed email, the code step or the countdown.
class EmailVerificationController extends ChangeNotifier {
  EmailVerificationController({required this.meetingUid, this.onVerified});

  final String meetingUid;

  /// Called with the email once it is verified (or restored from storage).
  final void Function(String email)? onVerified;

  final emailController = TextEditingController();
  final codeController = TextEditingController();

  EmailVerificationStep step = EmailVerificationStep.email;
  bool busy = false;
  String? error;
  String? info;
  int resendSeconds = 0;
  Timer? _timer;

  String? verifiedEmail;
  String? emailToken;

  bool get isVerified =>
      (verifiedEmail?.isNotEmpty ?? false) && (emailToken?.isNotEmpty ?? false);

  String get _email => emailController.text.trim();
  bool get isEmailValid => Utils.isValidEmail(_email);
  bool get isCodeValid => RegExp(r'^\d{6}$').hasMatch(codeController.text.trim());

  bool _disposed = false;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Shows [message] inside the card (e.g. Join tapped before verifying).
  void showError(String message) {
    error = message;
    _notify();
  }

  /// Clears the inline error after an edit and rebuilds the card, so the
  /// Send/Verify buttons follow what's typed.
  void onInputChanged() {
    error = null;
    _notify();
  }

  /// Picks up a still-valid verification saved for this meeting, so a rejoin
  /// doesn't ask for a new code.
  Future<void> restoreSaved() async {
    final saved = await StorageHelper().getEmailVerification(meetingUid);
    if (saved == null || _disposed) return;
    verifiedEmail = saved.email;
    emailToken = saved.token;
    emailController.text = saved.email;
    _notify();
    onVerified?.call(saved.email);
  }

  /// Pre-fills the email field (e.g. from the guest email) while unverified.
  void prefillEmail(String email) {
    if (isVerified || _email.isNotEmpty || email.trim().isEmpty) return;
    emailController.text = email.trim();
    _notify();
  }

  void _startCountdown(int seconds) {
    _timer?.cancel();
    resendSeconds = seconds;
    if (seconds <= 0) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      resendSeconds = resendSeconds - 1;
      if (resendSeconds <= 0) {
        resendSeconds = 0;
        t.cancel();
      }
      _notify();
    });
  }

  Future<void> sendCode() async {
    if (!isEmailValid || busy) return;
    final email = _email;
    busy = true;
    error = null;
    info = null;
    _notify();
    await networkRequestHandlerWithMessage(
      apiCall: () => apiClient.sendParticipantEmailOtp({
        "meeting_uid": meetingUid,
        "email": email,
      }),
      onSuccess: (response) {
        step = EmailVerificationStep.code;
        codeController.clear();
        info = "We sent a 6-digit code to $email";
        _startCountdown(response?.data?.resendAfterSeconds ?? 30);
      },
      onFailureResponse: (response) {
        // Resend cooldown: a code was already sent, so go to the code step
        // and count down what the server says is left.
        final retryAfter = response.data?.retryAfterSeconds;
        if (retryAfter != null && retryAfter > 0) {
          step = EmailVerificationStep.code;
          _startCountdown(retryAfter);
        }
      },
      onError: (message) {
        error = message.startsWith("Unexpected error")
            ? "Could not send the code. Please try again."
            : message;
      },
    );
    busy = false;
    _notify();
  }

  Future<void> verifyCode() async {
    final code = codeController.text.trim();
    if (!isCodeValid || busy) return;
    final email = _email;
    busy = true;
    error = null;
    _notify();
    await networkRequestHandlerWithMessage(
      apiCall: () => apiClient.verifyParticipantEmailOtp({
        "meeting_uid": meetingUid,
        "email": email,
        "otp": code,
      }),
      onSuccess: (response) {
        final token = response?.data?.emailToken;
        if (token == null || token.isEmpty) {
          error = response?.message ?? "Invalid verification code";
          return;
        }
        verifiedEmail = response?.data?.email ?? email;
        emailToken = token;
        info = null;
        _timer?.cancel();
        resendSeconds = 0;
      },
      onFailureResponse: (response) {
        final left = response.data?.attemptsLeft;
        error = "${response.message ?? "Invalid verification code"}"
            "${left != null ? " ($left ${left == 1 ? "attempt" : "attempts"} left)" : ""}";
      },
      onError: (message) {
        error ??= message.startsWith("Unexpected error")
            ? "Could not verify the code. Please try again."
            : message;
      },
    );
    busy = false;
    _notify();
    if (isVerified) {
      try {
        await StorageHelper()
            .saveEmailVerification(meetingUid, verifiedEmail!, emailToken!);
      } catch (e, st) {
        DaakiaVcLogger.captureException(e, stackTrace: st);
      }
      onVerified?.call(verifiedEmail!);
    }
  }

  /// Back to the email step from the code step.
  void changeEmail() {
    step = EmailVerificationStep.email;
    codeController.clear();
    error = null;
    info = null;
    _timer?.cancel();
    resendSeconds = 0;
    _notify();
  }

  /// Drops the verified email (and the saved token) so another one can be
  /// verified. [message] is shown in the card, e.g. the server's reason.
  Future<void> reset({String? message}) async {
    verifiedEmail = null;
    emailToken = null;
    step = EmailVerificationStep.email;
    codeController.clear();
    info = null;
    error = message;
    _timer?.cancel();
    resendSeconds = 0;
    _notify();
    await StorageHelper().clearEmailVerification(meetingUid);
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    emailController.dispose();
    codeController.dispose();
    super.dispose();
  }
}

/// Pre-join step for meetings that need a verified email: enter email, get a
/// 6-digit code, verify; then a compact "Verified as …" row.
///
/// Errors stay inside the card rather than in snackbars, which the keyboard
/// would hide.
class EmailVerificationCard extends StatelessWidget {
  const EmailVerificationCard({
    super.key,
    required this.controller,
    required this.fieldDecoration,
  });

  final EmailVerificationController controller;

  /// The pre-join page's text field style, so the card's fields match it.
  final InputDecoration Function({required String label, required IconData icon})
      fieldDecoration;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (controller.isVerified) return _buildVerified();
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: themeColor.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: themeColor.withValues(alpha: 0.18)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(),
              const SizedBox(height: 12),
              if (controller.step == EmailVerificationStep.email)
                ..._buildEmailStep(context)
              else
                ..._buildCodeStep(context),
              if (controller.error != null) ...[
                const SizedBox(height: 8),
                Text(
                  controller.error!,
                  style: const TextStyle(color: Colors.red, fontSize: 13),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader() {
    return const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.mark_email_read_outlined, color: themeColor, size: 22),
        SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Verify your email",
                style: TextStyle(
                  color: Colors.black87,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 2),
              Text(
                "This meeting requires a verified email to join.",
                style: TextStyle(color: Colors.black54, fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _buildEmailStep(BuildContext context) {
    return [
      TextField(
        controller: controller.emailController,
        onTapOutside: Utils.dismissKeyboardOnTapOutside,
        decoration: fieldDecoration(
          label: 'Email',
          icon: Icons.mail_outline_rounded,
        ),
        style: const TextStyle(color: Colors.black87),
        keyboardType: TextInputType.emailAddress,
        autofillHints: const [AutofillHints.email],
        autocorrect: false,
        enabled: !controller.busy,
        textInputAction: TextInputAction.send,
        onChanged: (_) => controller.onInputChanged(),
        onSubmitted: (_) => controller.sendCode(),
      ),
      const SizedBox(height: 10),
      _primaryButton(
        label: "Send code",
        enabled: controller.isEmailValid,
        onPressed: controller.sendCode,
      ),
    ];
  }

  List<Widget> _buildCodeStep(BuildContext context) {
    final email = controller.emailController.text.trim();
    return [
      Row(
        children: [
          Expanded(
            child: Text(
              controller.info ?? "Enter the code sent to $email",
              style: const TextStyle(color: Colors.black87, fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: controller.busy ? null : controller.changeEmail,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              "Change",
              style: TextStyle(color: themeColor, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      TextField(
        controller: controller.codeController,
        onTapOutside: Utils.dismissKeyboardOnTapOutside,
        decoration: fieldDecoration(
          label: '6-digit code',
          icon: Icons.password_rounded,
        ).copyWith(counterText: ""),
        style: const TextStyle(
          color: Colors.black87,
          fontSize: 18,
          letterSpacing: 6,
          fontWeight: FontWeight.w600,
        ),
        keyboardType: TextInputType.number,
        autofillHints: const [AutofillHints.oneTimeCode],
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(6),
        ],
        maxLength: 6,
        enabled: !controller.busy,
        textInputAction: TextInputAction.done,
        onChanged: (value) {
          controller.onInputChanged();
          // Verify as soon as the sixth digit is in, as code fields on
          // phones usually do.
          if (value.length == 6) {
            FocusManager.instance.primaryFocus?.unfocus();
            controller.verifyCode();
          }
        },
        onSubmitted: (_) => controller.verifyCode(),
      ),
      const SizedBox(height: 10),
      _primaryButton(
        label: "Verify",
        enabled: controller.isCodeValid,
        onPressed: controller.verifyCode,
      ),
      Center(
        child: TextButton(
          onPressed: controller.resendSeconds > 0 || controller.busy
              ? null
              : controller.sendCode,
          child: Text(
            controller.resendSeconds > 0
                ? "Resend code in ${controller.resendSeconds}s"
                : "Resend code",
            style: TextStyle(
              color: controller.resendSeconds > 0 ? Colors.black38 : themeColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    ];
  }

  Widget _primaryButton({
    required String label,
    required bool enabled,
    required Future<void> Function() onPressed,
  }) {
    return SizedBox(
      height: 46,
      child: FilledButton(
        onPressed: enabled && !controller.busy ? onPressed : null,
        style: FilledButton.styleFrom(
          backgroundColor: themeColor,
          disabledBackgroundColor: themeColor.withValues(alpha: 0.35),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: controller.busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }

  Widget _buildVerified() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.verified_rounded, color: Colors.green, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                text: "Verified as ",
                style: const TextStyle(color: Colors.black54, fontSize: 13),
                children: [
                  TextSpan(
                    text: controller.verifiedEmail,
                    style: const TextStyle(
                      color: Colors.black87,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(
            onPressed: () => controller.reset(),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              minimumSize: const Size(0, 40),
            ),
            child: const Text(
              "Change",
              style: TextStyle(color: themeColor, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
