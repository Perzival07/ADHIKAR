import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/localization/app_translations.dart';
import '../../core/models/administrative_regions.dart';
import '../../core/services/settings_service.dart';
import '../../core/services/auth_service.dart';
import 'otp_verification_screen.dart';

class SignUpScreen extends StatefulWidget {
  final SettingsService settings;
  final AuthService auth;

  const SignUpScreen({
    super.key,
    required this.settings,
    required this.auth,
  });

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  String _selectedState = 'Uttar Pradesh';
  String _selectedCategory = 'General';
  String _selectedOccupation = 'Citizen';
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;

  final List<String> _categories = ['General', 'OBC', 'SC', 'ST', 'EWS'];
  final List<String> _occupations = [
    'Citizen',
    'Farmer',
    'Student',
    'Artisan / Craftsman',
    'Street Vendor',
    'Daily Wage / Laborer',
    'Self-Employed',
    'Salaried',
    'Homemaker',
    'Senior Citizen',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.settings.selectedState != 'All India' &&
        IndianRegions.stateNames.contains(widget.settings.selectedState)) {
      _selectedState = widget.settings.selectedState;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _identifierController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleSignUp() async {
    if (!_formKey.currentState!.validate()) return;

    if (_passwordController.text != _confirmPasswordController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Passwords do not match. Please verify.'),
          backgroundColor: Colors.red.shade800,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final email = _identifierController.text.trim().toLowerCase();
    setState(() => _isLoading = true);

    // Local demo mode can check for an existing account; the server never reveals that (no enumeration).
    final exists = widget.auth.canCheckAccounts && await widget.auth.accountExists(email);
    if (exists) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('An account with this email already exists. Please Sign In.'),
          backgroundColor: Colors.red.shade800,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Send a 6-digit code (from the server in remote mode)
    final otpResult = await widget.auth.requestOtp(
      email: email,
      purpose: 'signup',
      name: _nameController.text.trim(),
    );

    if (!mounted) return;
    setState(() => _isLoading = false);


    if (otpResult.success) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => OtpVerificationScreen(
            email: email,
            name: _nameController.text.trim(),
            password: _passwordController.text.trim(),
            state: _selectedState,
            socialCategory: _selectedCategory,
            occupation: _selectedOccupation,
            purpose: OtpPurpose.signUp,
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

  @override
  Widget build(BuildContext context) {
    final lang = widget.settings.currentLanguage;
    final allStates = IndianRegions.stateNames;

    return Scaffold(
      backgroundColor: AppTheme.bgSurface,
      appBar: AppBar(
        title: Text(
          AppStrings.get('sign_up', lang),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Logo badge
              Center(
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primaryNavy.withValues(alpha: 0.08),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Image.asset(
                      'assets/images/logo.png',
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              Text(
                'Register with ADHIKAR',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.primaryNavy,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Unlock personalized welfare matching and verified opportunities.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  color: AppTheme.textMuted,
                  height: 1.4,
                ),
              ),

              const SizedBox(height: 24),

              // Sign Up Card Form
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
                        // Full Name
                        Text(
                          AppStrings.get('full_name', lang),
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.textDark),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _nameController,
                          decoration: const InputDecoration(
                            hintText: 'e.g. Ramesh Kumar',
                            prefixIcon: Icon(Icons.person_outline_rounded, color: AppTheme.primaryNavy, size: 20),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter your name.' : null,
                        ),

                        const SizedBox(height: 16),

                        // Email Address with OTP badge
                        Row(
                          children: [
                            const Text(
                              'Email Address',
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.textDark),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppTheme.forestGreen.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'OTP Verification',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.forestGreen,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _identifierController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            hintText: 'e.g. citizen@gmail.com',
                            prefixIcon: Icon(Icons.email_outlined, color: AppTheme.primaryNavy, size: 20),
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'Please enter your email address.';
                            }
                            final clean = v.trim().toLowerCase();
                            if (!clean.contains('@') || !clean.contains('.')) {
                              return 'Please enter a valid email (e.g. name@domain.com).';
                            }
                            return null;
                          },
                        ),

                        const SizedBox(height: 16),

                        // State / UT Jurisdiction
                        const Text(
                          'State / UT Jurisdiction',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.textDark),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          isExpanded: true,
                          initialValue: _selectedState,
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.location_on_outlined, color: AppTheme.primaryNavy, size: 20),
                          ),
                          items: allStates.map((st) {
                            return DropdownMenuItem(
                              value: st,
                              child: Text(
                                st,
                                style: const TextStyle(fontSize: 13.5),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) setState(() => _selectedState = val);
                          },
                        ),

                        const SizedBox(height: 16),

                        // Social Category & Occupation Row
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Category',
                                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.textDark),
                                  ),
                                  const SizedBox(height: 8),
                                  DropdownButtonFormField<String>(
                                    isExpanded: true,
                                    initialValue: _selectedCategory,
                                    decoration: const InputDecoration(isDense: true),
                                    items: _categories
                                        .map((c) => DropdownMenuItem(
                                              value: c,
                                              child: Text(
                                                c,
                                                style: const TextStyle(fontSize: 13),
                                                overflow: TextOverflow.ellipsis,
                                                maxLines: 1,
                                              ),
                                            ))
                                        .toList(),
                                    onChanged: (val) {
                                      if (val != null) setState(() => _selectedCategory = val);
                                    },
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Occupation',
                                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.textDark),
                                  ),
                                  const SizedBox(height: 8),
                                  DropdownButtonFormField<String>(
                                    isExpanded: true,
                                    initialValue: _selectedOccupation,
                                    decoration: const InputDecoration(isDense: true),
                                    items: _occupations
                                        .map((o) => DropdownMenuItem(
                                              value: o,
                                              child: Text(
                                                o,
                                                style: const TextStyle(fontSize: 13),
                                                overflow: TextOverflow.ellipsis,
                                                maxLines: 1,
                                              ),
                                            ))
                                        .toList(),
                                    onChanged: (val) {
                                      if (val != null) setState(() => _selectedOccupation = val);
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        // Password
                        Text(
                          AppStrings.get('password', lang),
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.textDark),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          decoration: InputDecoration(
                            hintText: 'At least 8 characters',
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
                          validator: (v) => (v == null || v.trim().length < 8) ? 'Password must be at least 8 characters.' : null,
                        ),

                        const SizedBox(height: 16),

                        // Confirm Password
                        const Text(
                          'Confirm Password',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.textDark),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _confirmPasswordController,
                          obscureText: _obscureConfirmPassword,
                          decoration: InputDecoration(
                            hintText: 'Re-enter password',
                            prefixIcon: const Icon(Icons.lock_reset_rounded, color: AppTheme.primaryNavy, size: 20),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscureConfirmPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                size: 20,
                                color: AppTheme.textMuted,
                              ),
                              onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                            ),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Please confirm your password.' : null,
                        ),

                        const SizedBox(height: 24),

                        // Submit Button
                        ElevatedButton(
                          onPressed: _isLoading ? null : _handleSignUp,
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
                                  children: const [
                                    Text(
                                      'Verify via Email OTP',
                                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                                    ),
                                    SizedBox(width: 8),
                                    Icon(Icons.arrow_forward_rounded, size: 18, color: Colors.white),
                                  ],
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Back to Sign In Link
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    AppStrings.get('already_have_account', lang),
                    style: const TextStyle(fontSize: 13, color: AppTheme.textMuted),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      AppStrings.get('sign_in', lang),
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
