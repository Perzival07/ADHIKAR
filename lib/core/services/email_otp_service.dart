import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server/gmail.dart';

class OtpResult {
  final bool success;
  final String message;

  const OtpResult({
    required this.success,
    required this.message,
  });
}

class EmailOtpService extends ChangeNotifier {
  static final EmailOtpService _instance = EmailOtpService._internal();
  factory EmailOtpService() => _instance;
  EmailOtpService._internal();
  static EmailOtpService get instance => _instance;

  // SMTP credentials are NOT stored in source. Supply them at build/run time:
  //   flutter run --dart-define=SMTP_SENDER=you@gmail.com --dart-define=SMTP_APP_PASSWORD=xxxxxxxxxxxxxxxx
  // NOTE: anything passed this way is still compiled into the app. This is for
  // local development only; production should send OTPs from a backend.
  static const String _gmailSender =
      String.fromEnvironment('SMTP_SENDER', defaultValue: 'adhikar.connect@gmail.com');
  static const String _gmailAppPassword = String.fromEnvironment('SMTP_APP_PASSWORD');

  // Browsers cannot open raw SMTP sockets, so the mailer package can never work
  // on web; treat web as "not configured" instead of failing with a socket error.
  bool get _smtpConfigured => !kIsWeb && _gmailAppPassword.isNotEmpty;

  // State
  String? _pendingOtp;
  String? _targetEmail;
  DateTime? _otpGeneratedAt;
  int _attemptsRemaining = 5;
  bool _isSending = false;

  bool get isSending => _isSending;
  String? get targetEmail => _targetEmail;
  int get attemptsRemaining => _attemptsRemaining;

  // OTP validity duration: 5 minutes
  static const Duration otpValidity = Duration(minutes: 5);
  // Resend cooldown: 60 seconds
  static const Duration resendCooldown = Duration(seconds: 60);

  bool get isExpired {
    if (_otpGeneratedAt == null) return true;
    return DateTime.now().difference(_otpGeneratedAt!) > otpValidity;
  }

  int get resendSecondsLeft {
    if (_otpGeneratedAt == null) return 0;
    final diff = DateTime.now().difference(_otpGeneratedAt!);
    if (diff >= resendCooldown) return 0;
    return (resendCooldown - diff).inSeconds;
  }

  bool get canResend => resendSecondsLeft <= 0;

  /// Generate a secure 6-digit random code
  String _generateRandomOtp() {
    final random = Random.secure();
    final code = 100000 + random.nextInt(900000);
    return code.toString();
  }

  /// Sends a 6-digit OTP code to the citizen's email address
  Future<OtpResult> sendOtp({
    required String recipientEmail,
    String? recipientName,
  }) async {
    final email = recipientEmail.trim().toLowerCase();
    if (email.isEmpty || !email.contains('@') || !email.contains('.')) {
      return const OtpResult(
        success: false,
        message: 'Please enter a valid email address.',
      );
    }

    _isSending = true;
    notifyListeners();

    final otp = _generateRandomOtp();
    final name = recipientName?.trim().isNotEmpty == true ? recipientName!.trim() : 'Citizen';

    // Local development without SMTP credentials: skip the email and print the
    // code to the debug console instead, so sign-up/sign-in can still be tried.
    if (!_smtpConfigured) {
      if (kDebugMode) {
        debugPrint('[DEV ONLY] SMTP not configured. OTP for $email is $otp');
        _pendingOtp = otp;
        _targetEmail = email;
        _otpGeneratedAt = DateTime.now();
        _attemptsRemaining = 5;
        _isSending = false;
        notifyListeners();
        return OtpResult(
          success: true,
          message: 'Dev mode: email is not configured. Check the debug console for the OTP for $email.',
        );
      }
      _isSending = false;
      notifyListeners();
      return const OtpResult(
        success: false,
        message: 'Email verification is not available right now. Please try again later.',
      );
    }

    final smtpServer = gmail(_gmailSender, _gmailAppPassword);

    final htmlContent = '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>ADHIKAR Verification Code</title>
</head>
<body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; background-color: #f4f6f9; margin: 0; padding: 24px;">
  <div style="max-width: 520px; margin: 0 auto; background: #ffffff; border-radius: 16px; overflow: hidden; box-shadow: 0 4px 16px rgba(0,0,0,0.06); border: 1px solid #e2e8f0;">
    <div style="background: linear-gradient(135deg, #0D1B2A 0%, #1E3E62 100%); padding: 26px 20px; text-align: center;">
      <h1 style="color: #ffffff; margin: 0; font-size: 26px; font-weight: 800; letter-spacing: -0.5px;">ADHIKAR • अधिकार</h1>
      <p style="color: #FF9933; margin: 6px 0 0 0; font-size: 13px; font-weight: 700; letter-spacing: 0.5px; text-transform: uppercase;">Citizen Welfare & Empowerment</p>
    </div>
    <div style="padding: 32px 26px;">
      <h2 style="color: #0f172a; font-size: 19px; margin: 0 0 12px 0; font-weight: 700;">Email Verification Code</h2>
      <p style="color: #475569; font-size: 14.5px; line-height: 1.6; margin: 0 0 20px 0;">
        Hello <strong>$name</strong>,<br><br>
        Thank you for joining <strong>ADHIKAR</strong>. To complete your account verification, enter the following 6-digit OTP in the app:
      </p>
      <div style="background: #f8fafc; border: 2px dashed #0D1B2A; border-radius: 12px; padding: 18px; text-align: center; margin: 24px 0;">
        <span style="font-size: 36px; font-weight: 800; letter-spacing: 10px; color: #0D1B2A; font-family: 'Courier New', Courier, monospace;">$otp</span>
      </div>
      <div style="background: #fef3c7; border-left: 4px solid #f59e0b; padding: 10px 14px; border-radius: 6px; margin: 20px 0;">
        <p style="color: #92400e; font-size: 13px; font-weight: 600; margin: 0;">
          ⏰ This code is valid for 5 minutes only.
        </p>
      </div>
      <p style="color: #64748b; font-size: 12.5px; line-height: 1.5; margin: 20px 0 0 0;">
        If you did not request this code, no action is needed. Do not share this OTP with anyone for your safety.
      </p>
    </div>
    <div style="background: #f1f5f9; padding: 16px; text-align: center; border-top: 1px solid #e2e8f0;">
      <p style="color: #64748b; font-size: 11.5px; margin: 0;">
        Official Automated Email • ADHIKAR Citizen Assistance Platform<br>
        Sent via <a href="mailto:$_gmailSender" style="color: #0D1B2A; text-decoration: none; font-weight: 600;">$_gmailSender</a>
      </p>
    </div>
  </div>
</body>
</html>
''';

    final textContent = 'Hello $name,\n\nYour ADHIKAR verification code is: $otp\n\nThis code is valid for 5 minutes. Do not share this code with anyone.\n\nADHIKAR Citizen Welfare Portal';

    final message = Message()
      ..from = Address(_gmailSender, 'ADHIKAR Portal')
      ..recipients.add(email)
      ..subject = 'Your ADHIKAR Verification Code: $otp'
      ..text = textContent
      ..html = htmlContent;

    try {
      final sendReport = await send(message, smtpServer);
      debugPrint('OTP email sent successfully: ${sendReport.toString()}');

      _pendingOtp = otp;
      _targetEmail = email;
      _otpGeneratedAt = DateTime.now();
      _attemptsRemaining = 5;
      _isSending = false;
      notifyListeners();

      return OtpResult(
        success: true,
        message: 'A 6-digit OTP has been sent to $email. Please check your inbox.',
      );
    } catch (e) {
      debugPrint('Failed to send OTP email: $e');
      _isSending = false;
      notifyListeners();

      return OtpResult(
        success: false,
        message: 'Failed to send OTP to $email. Error: ${e.toString()}',
      );
    }
  }

  /// Verifies user-entered 6-digit OTP
  OtpResult verifyOtp({
    required String enteredOtp,
  }) {
    if (_pendingOtp == null || _targetEmail == null) {
      return const OtpResult(
        success: false,
        message: 'No active OTP verification session found. Please request a new OTP.',
      );
    }

    if (isExpired) {
      return const OtpResult(
        success: false,
        message: 'This OTP has expired. Please tap "Resend Code" to get a new one.',
      );
    }

    if (_attemptsRemaining <= 0) {
      return const OtpResult(
        success: false,
        message: 'Too many incorrect attempts. Please request a new OTP.',
      );
    }

    final cleanEntered = enteredOtp.trim().replaceAll(' ', '');

    if (cleanEntered == _pendingOtp) {
      // Success! Clear pending OTP
      _pendingOtp = null;
      notifyListeners();
      return const OtpResult(
        success: true,
        message: 'Email verified successfully!',
      );
    } else {
      _attemptsRemaining--;
      notifyListeners();
      return OtpResult(
        success: false,
        message: 'Invalid verification code. $_attemptsRemaining attempt(s) remaining.',
      );
    }
  }

  /// Reset the session
  void clear() {
    _pendingOtp = null;
    _targetEmail = null;
    _otpGeneratedAt = null;
    _attemptsRemaining = 5;
    _isSending = false;
    notifyListeners();
  }
}
