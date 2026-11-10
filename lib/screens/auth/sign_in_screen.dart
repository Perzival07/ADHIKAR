import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/localization/app_translations.dart';
import '../../core/services/settings_service.dart';
import '../../core/services/auth_service.dart';
import '../main_navigation_screen.dart';
import 'sign_up_screen.dart';
import 'otp_verification_screen.dart';

class SignInScreen extends StatefulWidget {
  final SettingsService settings;
  final AuthService auth;

  const SignInScreen({
    super.key,
    required this.settings,
    required this.auth,
  });

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleSignIn() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final result = await widget.auth.signIn(
      phoneOrEmail: _identifierController.text.trim(),
      password: _passwordController.text.trim(),
    );

    if (!mounted) return;
    setState(() => _isLoading = false);


    if (result.success) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => MainNavigationScreen(
            settings: widget.settings,
            auth: widget.auth,
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  result.message ?? 'Authentication failed',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.red.shade800,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  void _quickDemoSignIn() {
    _identifierController.text = 'citizen@adhikar.gov.in';
    _passwordController.text = 'password123';
    _handleSignIn();
  }

  Future<void> _handleOtpSignIn() async {
    final emailInput = _identifierController.text.trim().toLowerCase();

    String? targetEmail;
    if (emailInput.isNotEmpty && emailInput.contains('@') && emailInput.contains('.')) {
      targetEmail = emailInput;
    } else {
      final emailPromptController = TextEditingController(text: emailInput);
      targetEmail = await showDialog<String>(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: const [
              Icon(Icons.mark_email_read_rounded, color: AppTheme.accentSaffron),
              SizedBox(width: 10),
              Text('Sign In with OTP', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Enter your registered email address. We will send a 6-digit verification code to log in securely.',
                style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: emailPromptController,
                keyboardType: TextInputType.emailAddress,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'e.g. citizen@gmail.com',
                  prefixIcon: const Icon(Icons.email_outlined, color: AppTheme.primaryNavy),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentSaffron),
              onPressed: () {
                final email = emailPromptController.text.trim().toLowerCase();
                if (email.contains('@') && email.contains('.')) {
                  Navigator.pop(dialogCtx, email);
                } else {
                  ScaffoldMessenger.of(dialogCtx).showSnackBar(
                    const SnackBar(content: Text('Please enter a valid email address.')),
                  );
                }
              },
              child: const Text('Send OTP', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    }

    if (targetEmail == null || targetEmail.isEmpty) return;

    setState(() => _isLoading = true);

    final exists = !widget.auth.canCheckAccounts || await widget.auth.accountExists(targetEmail);
    if (!exists) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No account found for $targetEmail. Please Sign Up first.'),
          backgroundColor: Colors.red.shade800,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final otpResult = await widget.auth.requestOtp(email: targetEmail, purpose: 'login');

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (otpResult.success) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => OtpVerificationScreen(
            email: targetEmail!,
            purpose: OtpPurpose.signIn,
            settings: widget.settings,
            auth: widget.auth,
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(otpResult.message),
          backgroundColor: Colors.red.shade800,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showLanguageSelector(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        String query = '';
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            final filtered = SettingsService.supportedLanguages.where((l) {
              final q = query.toLowerCase().trim();
              if (q.isEmpty) return true;
              return l['name']!.toLowerCase().contains(q) ||
                  l['native']!.toLowerCase().contains(q) ||
                  l['code']!.toLowerCase().contains(q);
            }).toList();

            return DraggableScrollableSheet(
              initialChildSize: 0.7,
              maxChildSize: 0.9,
              minChildSize: 0.4,
              expand: false,
              builder: (context, scrollController) {
                return Container(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.translate_rounded, color: AppTheme.accentSaffron),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Choose Language (23 Languages)',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        decoration: InputDecoration(
                          hintText: 'Search language (हिंदी, বাংলা, தமிழ்...)',
                          prefixIcon: const Icon(Icons.search_rounded, size: 20),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onChanged: (val) => setModalState(() => query = val),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: ListView.separated(
                          controller: scrollController,
                          itemCount: filtered.length,
                          separatorBuilder: (context, index) =>
                              const Divider(height: 1, color: AppTheme.borderSubtle),
                          itemBuilder: (context, i) {
                            final l = filtered[i];
                            final isSelected = widget.settings.currentLanguage == l['code'];
                            return ListTile(
                              dense: true,
                              title: Text(
                                l['native']!,
                                style: TextStyle(
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                  fontSize: 15,
                                  color: isSelected ? AppTheme.accentSaffron : AppTheme.textDark,
                                ),
                              ),
                              subtitle: Text(l['name']!),
                              trailing: isSelected
                                  ? const Icon(Icons.check_circle_rounded, color: AppTheme.accentSaffron)
                                  : null,
                              onTap: () {
                                widget.settings.setLanguage(l['code']!);
                                Navigator.pop(ctx);
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final lang = widget.settings.currentLanguage;

    return Scaffold(
      backgroundColor: AppTheme.bgSurface,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top Bar with Language Selector
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ActionChip(
                    avatar: const Icon(Icons.translate_rounded, size: 16, color: AppTheme.primaryNavy),
                    label: Text(
                      SettingsService.supportedLanguages.firstWhere(
                        (l) => l['code'] == lang,
                        orElse: () => {'native': 'Language'},
                      )['native']!,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.primaryNavy),
                    ),
                    backgroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: const BorderSide(color: AppTheme.borderSubtle),
                    ),
                    onPressed: () => _showLanguageSelector(context),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Official Logo Showcase
              Center(
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primaryNavy.withValues(alpha: 0.08),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Image.asset(
                      'assets/images/logo.png',
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Header text
              Text(
                AppStrings.get('welcome_back', lang),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.primaryNavy,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                AppStrings.get('welcome_subtitle', lang),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.textMuted,
                  height: 1.4,
                ),
              ),

              const SizedBox(height: 28),

              // Sign In Card Form
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22),
                  side: const BorderSide(color: AppTheme.borderSubtle),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Identifier Field
                        Text(
                          AppStrings.get('phone_or_email', lang),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: AppTheme.textDark,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _identifierController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: InputDecoration(
                            hintText: 'e.g. 9876543210 or name@domain.com',
                            prefixIcon: const Icon(Icons.person_outline_rounded, color: AppTheme.primaryNavy, size: 20),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Please enter your phone number or email.';
                            }
                            return null;
                          },
                        ),

                        const SizedBox(height: 18),

                        // Password Field
                        Text(
                          AppStrings.get('password', lang),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: AppTheme.textDark,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          decoration: InputDecoration(
                            hintText: '••••••••',
                            prefixIcon: const Icon(Icons.lock_outline_rounded, color: AppTheme.primaryNavy, size: 20),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                size: 20,
                                color: AppTheme.textMuted,
                              ),
                              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().length < 6) {
                              return 'Password must be at least 6 characters.';
                            }
                            return null;
                          },
                        ),

                        const SizedBox(height: 24),

                        // Primary Sign In Button
                        ElevatedButton(
                          onPressed: _isLoading ? null : _handleSignIn,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.accentSaffron,
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      AppStrings.get('sign_in', lang),
                                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(width: 8),
                                    const Icon(Icons.arrow_forward_rounded, size: 18),
                                  ],
                                ),
                        ),

                        const SizedBox(height: 12),

                        // Sign In with Email OTP
                        OutlinedButton.icon(
                          onPressed: _isLoading ? null : _handleOtpSignIn,
                          icon: const Icon(Icons.mark_email_read_rounded, color: AppTheme.primaryNavy, size: 18),
                          label: const Text(
                            'Sign In with Email OTP',
                            style: TextStyle(
                              color: AppTheme.primaryNavy,
                              fontWeight: FontWeight.bold,
                              fontSize: 13.5,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: AppTheme.primaryNavy.withValues(alpha: 0.6)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),

                        const SizedBox(height: 12),

                        // Quick Demo Sign In
                        OutlinedButton.icon(
                          onPressed: _quickDemoSignIn,
                          icon: const Icon(Icons.bolt_rounded, color: AppTheme.forestGreen, size: 18),
                          label: Text(
                            AppStrings.get('guest_signin', lang),
                            style: const TextStyle(
                              color: AppTheme.forestGreen,
                              fontWeight: FontWeight.bold,
                              fontSize: 13.5,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: AppTheme.forestGreen.withValues(alpha: 0.4)),
                            backgroundColor: AppTheme.mintLight.withValues(alpha: 0.5),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Sign Up Navigation Link
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    AppStrings.get('dont_have_account', lang),
                    style: const TextStyle(fontSize: 13, color: AppTheme.textMuted),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => SignUpScreen(
                            settings: widget.settings,
                            auth: widget.auth,
                          ),
                        ),
                      );
                    },
                    child: Text(
                      AppStrings.get('sign_up', lang),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13.5,
                        color: AppTheme.primaryNavy,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
