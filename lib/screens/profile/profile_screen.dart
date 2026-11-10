import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/localization/app_translations.dart';
import '../../core/models/administrative_regions.dart';
import '../../core/services/settings_service.dart';
import '../../core/services/auth_service.dart';
import '../auth/sign_in_screen.dart';

class ProfileScreen extends StatefulWidget {
  final SettingsService settings;
  final AuthService auth;

  const ProfileScreen({
    super.key,
    required this.settings,
    required this.auth,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  void _showEditProfileDialog() {
    final user = widget.auth.currentUser;
    if (user == null) return;

    final nameController = TextEditingController(text: user.name);
    String selectedState = user.state;
    String selectedOccupation = user.occupation;

    final allStates = IndianRegions.stateNames;
    final occupations = [
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

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            return Container(
              padding: EdgeInsets.only(
                top: 20,
                left: 20,
                right: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.edit_rounded, color: AppTheme.accentSaffron),
                      const SizedBox(width: 8),
                      const Text(
                        'Edit Profile Details',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppTheme.primaryNavy),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Full Name',
                      prefixIcon: Icon(Icons.person_outline_rounded),
                    ),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: selectedState,
                    decoration: const InputDecoration(
                      labelText: 'State Jurisdiction',
                      prefixIcon: Icon(Icons.location_on_outlined),
                    ),
                    items: allStates
                        .map((st) => DropdownMenuItem(
                              value: st,
                              child: Text(
                                st,
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) setModalState(() => selectedState = val);
                    },
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: occupations.contains(selectedOccupation) ? selectedOccupation : 'Citizen',
                    decoration: const InputDecoration(
                      labelText: 'Occupation',
                      prefixIcon: Icon(Icons.work_outline_rounded),
                    ),
                    items: occupations
                        .map((o) => DropdownMenuItem(
                              value: o,
                              child: Text(
                                o,
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) setModalState(() => selectedOccupation = val);
                    },
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () async {
                      await widget.auth.updateProfile(
                        name: nameController.text.trim(),
                        state: selectedState,
                        occupation: selectedOccupation,
                      );
                      widget.settings.setSelectedState(selectedState);
                      if (ctx.mounted) Navigator.pop(ctx);
                      setState(() {});
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accentSaffron,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Save Changes', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _confirmSignOut() {
    final lang = widget.settings.currentLanguage;

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.logout_rounded, color: Colors.red.shade700, size: 22),
              ),
              const SizedBox(width: 12),
              Text(
                AppStrings.get('sign_out', lang),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ],
          ),
          content: Text(
            AppStrings.get('sign_out_confirm', lang),
            style: const TextStyle(fontSize: 13.5, color: Color(0xFF475569), height: 1.4),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.pop(ctx),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await widget.auth.signOut();
                if (!mounted) return;
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(
                    builder: (_) => SignInScreen(
                      settings: widget.settings,
                      auth: widget.auth,
                    ),
                  ),
                  (route) => false,
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text(AppStrings.get('sign_out', lang)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final lang = widget.settings.currentLanguage;
    final user = widget.auth.currentUser;

    final displayName = user?.name ?? 'Registered Citizen';
    final displayPhoneOrEmail = user?.phoneOrEmail ?? 'citizen@haqdaar.gov.in';
    final displayState = user?.state ?? widget.settings.selectedState;
    final displayCategory = user?.socialCategory ?? 'General';
    final displayOccupation = user?.occupation ?? 'Citizen';

    return Scaffold(
      backgroundColor: AppTheme.bgSurface,
      appBar: AppBar(
        title: Text(
          AppStrings.get('profile', lang),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit Profile',
            onPressed: _showEditProfileDialog,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // User Header Hero Card
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
                side: const BorderSide(color: AppTheme.borderSubtle),
              ),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  gradient: const LinearGradient(
                    colors: [
                      AppTheme.primaryNavy,
                      AppTheme.royalNavy,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 34,
                          backgroundColor: Colors.white,
                          child: CircleAvatar(
                            radius: 31,
                            backgroundColor: AppTheme.accentSaffron.withValues(alpha: 0.15),
                            child: Text(
                              displayName.isNotEmpty ? displayName[0].toUpperCase() : 'C',
                              style: const TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w900,
                                color: AppTheme.primaryNavy,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      displayName,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: AppTheme.forestGreen,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.verified_rounded, size: 12, color: Colors.white),
                                        SizedBox(width: 3),
                                        Text(
                                          'Verified',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                displayPhoneOrEmail,
                                style: const TextStyle(fontSize: 13, color: Colors.white70),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(Icons.location_on_rounded, size: 13, color: AppTheme.accentSaffron),
                                  const SizedBox(width: 3),
                                  Text(
                                    displayState,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Account Details Card
            Card(
              elevation: 1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: const BorderSide(color: AppTheme.borderSubtle),
              ),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.badge_outlined, color: AppTheme.primaryNavy, size: 18),
                        SizedBox(width: 8),
                        Text(
                          'Account & Entitlement Profile',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.primaryNavy),
                        ),
                      ],
                    ),
                    const Divider(height: 24, color: AppTheme.borderSubtle),
                    _buildProfileRow('Full Name', displayName),
                    _buildProfileRow('Contact Identifier', displayPhoneOrEmail),
                    _buildProfileRow('Home Jurisdiction', displayState),
                    _buildProfileRow('Occupation Profile', displayOccupation),
                    _buildProfileRow('Social Category', displayCategory),
                    _buildProfileRow('Citizen Verification', 'Aadhaar / Self-Attested'),
                    _buildProfileRow('Platform Version', 'Haqdaar v2.0 (Production)'),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Quick App Actions
            Card(
              elevation: 1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: const BorderSide(color: AppTheme.borderSubtle),
              ),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.edit_note_rounded, color: AppTheme.primaryNavy),
                    title: const Text('Update Profile Details', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _showEditProfileDialog,
                  ),
                  const Divider(height: 1, indent: 56, color: AppTheme.borderSubtle),
                  ListTile(
                    leading: const Icon(Icons.translate_rounded, color: AppTheme.accentSaffron),
                    title: const Text('Language Preference (23 Languages)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => widget.settings.toggleLanguage(),
                  ),
                  const Divider(height: 1, indent: 56, color: AppTheme.borderSubtle),
                  ListTile(
                    leading: const Icon(Icons.security_rounded, color: AppTheme.forestGreen),
                    title: const Text('Data Privacy & Grounded Verification', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    subtitle: const Text('No personal Aadhaar details stored on cloud servers', style: TextStyle(fontSize: 11.5)),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Prominent Sign Out Button
            Card(
              elevation: 0,
              color: Colors.red.shade50.withValues(alpha: 0.6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.red.shade200),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: _confirmSignOut,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.logout_rounded, color: Colors.red.shade700, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        AppStrings.get('sign_out', lang),
                        style: TextStyle(
                          color: Colors.red.shade700,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 8),
            Center(
              child: TextButton.icon(
                key: const Key('delete_account'),
                onPressed: _confirmDeleteAccount,
                icon: Icon(Icons.delete_forever_outlined, size: 18, color: Colors.red.shade900),
                label: Text(
                  widget.settings.isHindi ? 'मेरा खाता स्थायी रूप से हटाएं' : 'Delete my account permanently',
                  style: TextStyle(color: Colors.red.shade900, fontSize: 12.5),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  /// Right to erasure (DPDP Act 2023): removes the account and its sessions; cannot be undone.
  void _confirmDeleteAccount() {
    final isHi = widget.settings.isHindi;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isHi ? 'खाता हटाएं?' : 'Delete account?'),
        content: Text(isHi
            ? 'आपका खाता, सहेजी गई जानकारी और सभी लॉगिन स्थायी रूप से हटा दिए जाएंगे। इसे वापस नहीं किया जा सकता।'
            : 'Your account, saved details and all sign-ins will be permanently deleted. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(isHi ? 'रद्द करें' : 'Cancel')),
          ElevatedButton(
            key: const Key('confirm_delete_account'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade800, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(ctx);
              final result = await widget.auth.deleteAccount();
              if (!mounted) return;
              if (!result.success) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(result.message ?? 'Could not delete the account.'), backgroundColor: Colors.red.shade800),
                );
                return;
              }
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => SignInScreen(settings: widget.settings, auth: widget.auth)),
                (route) => false,
              );
            },
            child: Text(isHi ? 'स्थायी रूप से हटाएं' : 'Delete permanently'),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12.5, color: AppTheme.textMuted)),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textDark)),
        ],
      ),
    );
  }
}
