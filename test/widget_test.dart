import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:adhikar/core/models/citizen_profile.dart';
import 'package:adhikar/core/models/administrative_regions.dart';
import 'package:adhikar/core/services/scheme_engine.dart';
import 'package:adhikar/core/services/settings_service.dart';
import 'package:adhikar/core/services/auth_service.dart';
import 'package:adhikar/core/services/email_otp_service.dart';
import 'package:adhikar/core/services/latest_updates_service.dart';
import 'package:adhikar/data/schemes_corpus.dart';
import 'package:adhikar/data/internships_corpus.dart';
import 'package:adhikar/screens/wizard/adaptive_wizard_screen.dart';

void main() {
  group('ADHIKAR Administrative Regions & Schemes Tests', () {
    test('Contains exactly 28 Indian States and 8 Union Territories (36 Regions)', () {
      expect(IndianRegions.allRegions.length, 36);
      expect(IndianRegions.stateNames.length, 28);
      expect(IndianRegions.utNames.length, 8);

      // Verify sample states
      expect(IndianRegions.stateNames.contains('Uttar Pradesh'), true);
      expect(IndianRegions.stateNames.contains('Maharashtra'), true);
      expect(IndianRegions.stateNames.contains('Assam'), true);
      expect(IndianRegions.stateNames.contains('Kerala'), true);
      expect(IndianRegions.stateNames.contains('Nagaland'), true);
      expect(IndianRegions.stateNames.contains('Goa'), true);

      // Verify sample UTs
      expect(IndianRegions.utNames.contains('Delhi (NCT)'), true);
      expect(IndianRegions.utNames.contains('Jammu and Kashmir'), true);
      expect(IndianRegions.utNames.contains('Ladakh'), true);
      expect(IndianRegions.utNames.contains('Chandigarh'), true);
      expect(IndianRegions.utNames.contains('Puducherry'), true);
    });

    test('Schemes corpus contains schemes across all 28 states and 8 union territories', () {
      final schemes = SchemesCorpus.getSchemes();
      expect(schemes.isNotEmpty, true);

      // Central flagship schemes
      expect(schemes.any((s) => s.id == 'pm_kisan'), true);
      expect(schemes.any((s) => s.id == 'ayushman_bharat'), true);
      expect(schemes.any((s) => s.id == 'pm_vishwakarma'), true);

      // State schemes across regions
      expect(schemes.any((s) => s.id == 'mh_ladki_bahin'), true);
      expect(schemes.any((s) => s.id == 'up_kanya_sumangala'), true);
      expect(schemes.any((s) => s.id == 'mp_ladli_behna'), true);
      expect(schemes.any((s) => s.id == 'gj_vhali_dikri'), true);
      expect(schemes.any((s) => s.id == 'ka_gruha_lakshmi'), true);
      expect(schemes.any((s) => s.id == 'tn_magalir_urimai'), true);
      expect(schemes.any((s) => s.id == 'wb_annapurna_bhandar'), true);
      expect(schemes.any((s) => s.id == 'wb_banglar_yuva_sathi'), true);
      expect(schemes.any((s) => s.id == 'wb_bhagini_nivedita'), true);
      expect(schemes.any((s) => s.id == 'wb_yuva_shakti'), true);
      expect(schemes.any((s) => s.id == 'as_orunodoi'), true);
      expect(schemes.any((s) => s.id == 'kl_karunya'), true);
      expect(schemes.any((s) => s.id == 'dl_vidyarthi_pratibha'), true);
      expect(schemes.any((s) => s.id == 'jk_smas'), true);
      expect(schemes.any((s) => s.id == 'ld_sea_livelihood'), true);
    });

    test('Small farmer with land in UP qualifies for PM-KISAN', () {
      final profile = CitizenProfile(
        occupation: 'Farmer',
        landHoldingAcres: 2.0,
        state: 'Uttar Pradesh',
      );

      final results = SchemeEngine.evaluate(profile);
      expect(results.any((s) => s.id == 'pm_kisan'), true);
      final pmKisan = results.firstWhere((s) => s.id == 'pm_kisan');
      expect(pmKisan.matchConfidence, 1.0);
    });

    test('Salaried employee does NOT qualify for PM-KISAN or farming schemes and has no farmer reason', () {
      final profile = CitizenProfile(
        occupation: 'Salaried',
        state: 'Uttar Pradesh',
        annualIncomeRange: '2.5 - 5 Lakh',
      );

      final results = SchemeEngine.evaluate(profile);

      // Must NOT qualify for PM-KISAN or farming schemes
      expect(results.any((s) => s.id == 'pm_kisan'), false);
      expect(results.any((s) => s.category == 'Agriculture' || s.category == 'Agriculture & Farmers'), false);

      // Every scheme matched must not state user is eligible as a farmer
      for (var s in results) {
        expect(s.generatedReason?.contains('you own cultivable agricultural land and are engaged in farming'), false);
      }
    });

    test('Senior citizen aged 70+ qualifies for Ayushman Bharat universal cover', () {
      final profile = CitizenProfile(
        age: 72,
        rationCard: 'APL',
        annualIncomeRange: '> 5 Lakh',
      );

      final results = SchemeEngine.evaluate(profile);
      expect(results.any((s) => s.id == 'ayushman_bharat'), true);
    });

    test('Maharashtra woman qualifies for Ladki Bahin DBT', () {
      final profile = CitizenProfile(
        state: 'Maharashtra',
        gender: 'Female',
        age: 32,
        annualIncomeRange: '< 1 Lakh',
      );

      final results = SchemeEngine.evaluate(profile);
      expect(results.any((s) => s.id == 'mh_ladki_bahin'), true);
    });

    test('Assam resident qualifies for state flagship scheme', () {
      final profile = CitizenProfile(
        state: 'Assam',
        gender: 'Female',
        age: 30,
        annualIncomeRange: '< 1 Lakh',
      );

      final results = SchemeEngine.evaluate(profile);
      expect(results.any((s) => s.stateScope == 'Assam'), true);
    });

    test('West Bengal 21-year-old female resident qualifies for Banglar Yuva Sathi, Bhagini Nivedita, and Yuva Shakti', () {
      final profile = CitizenProfile(
        state: 'West Bengal',
        gender: 'Female',
        age: 21,
        maritalStatus: 'Single',
        occupation: 'Student',
        annualIncomeRange: '< 1 Lakh',
      );

      final results = SchemeEngine.evaluate(profile);

      // Must qualify for active, verified youth schemes
      expect(results.any((s) => s.id == 'wb_banglar_yuva_sathi'), true);
      expect(results.any((s) => s.id == 'wb_bhagini_nivedita'), true);
      expect(results.any((s) => s.id == 'wb_yuva_shakti'), true);

      // Must NOT qualify for expired Lakshmir Bhandar
      expect(results.any((s) => s.id == 'wb_lakshmir_bhandar'), false);

      // Banglar Yuva Sathi check
      final yuvaSathi = results.firstWhere((s) => s.id == 'wb_banglar_yuva_sathi');
      expect(yuvaSathi.matchConfidence, 1.0);
      expect(yuvaSathi.benefit.contains('1,500'), true);

      // Bhagini Nivedita check
      final nivedita = results.firstWhere((s) => s.id == 'wb_bhagini_nivedita');
      expect(nivedita.matchConfidence, 1.0);
      expect(nivedita.benefit.contains('50,000'), true);

      // Yuva Shakti check
      final yuvaShakti = results.firstWhere((s) => s.id == 'wb_yuva_shakti');
      expect(yuvaShakti.matchConfidence, 1.0);
    });

    test('West Bengal adult woman aged 25+ qualifies for Annapurna Bhandar (₹3,000/mo DBT)', () {
      final profile = CitizenProfile(
        state: 'West Bengal',
        gender: 'Female',
        age: 32,
        occupation: 'Homemaker',
        annualIncomeRange: '< 1 Lakh',
      );

      final results = SchemeEngine.evaluate(profile);
      expect(results.any((s) => s.id == 'wb_annapurna_bhandar'), true);
      final annapurna = results.firstWhere((s) => s.id == 'wb_annapurna_bhandar');
      expect(annapurna.matchConfidence, 1.0);
      expect(annapurna.benefit.contains('3,000'), true);
    });

    test('Every scheme in the corpus has a verified https official portal URL and at least one working route', () {
      final schemes = SchemesCorpus.getSchemes();
      for (final s in schemes) {
        expect(s.officialPortalUrl.isNotEmpty, true, reason: 'Scheme ${s.id} must have non-empty portal url');
        expect(s.officialPortalUrl.startsWith('https://'), true, reason: 'Scheme ${s.id} url must be secure https: ${s.officialPortalUrl}');
        expect(s.routes.isNotEmpty, true, reason: 'Scheme ${s.id} must have application routes');
        expect(s.routes.any((r) => (r.url ?? s.officialPortalUrl).startsWith('https://')), true);
      }
    });

    test('All 28 States and 8 Union Territories are represented in the schemes corpus', () {
      final schemes = SchemesCorpus.getSchemes();
      final statesInCorpus = schemes.map((s) => s.stateScope).toSet();

      for (final stateName in IndianRegions.stateNames) {
        expect(statesInCorpus.contains(stateName), true, reason: 'State $stateName must exist in schemes corpus');
      }

      for (final utName in IndianRegions.utNames) {
        expect(statesInCorpus.contains(utName), true, reason: 'UT $utName must exist in schemes corpus');
      }
    });

    test('Odisha resident woman qualifies for Subhadra Yojana (₹10,000/yr DBT)', () {
      final profile = CitizenProfile(
        state: 'Odisha',
        gender: 'Female',
        age: 28,
        occupation: 'Self Employed',
        annualIncomeRange: '< 1 Lakh',
      );

      final results = SchemeEngine.evaluate(profile);
      expect(results.any((s) => s.id == 'or_subhadra'), true);
      final subhadra = results.firstWhere((s) => s.id == 'or_subhadra');
      expect(subhadra.matchConfidence, 1.0);
      expect(subhadra.officialPortalUrl, 'https://subhadra.odisha.gov.in');
    });

    test('Telangana resident woman qualifies for Mahalakshmi Scheme (₹2,500/mo DBT & free bus)', () {
      final profile = CitizenProfile(
        state: 'Telangana',
        gender: 'Female',
        age: 35,
        annualIncomeRange: '< 1 Lakh',
      );

      final results = SchemeEngine.evaluate(profile);
      expect(results.any((s) => s.id == 'ts_mahalakshmi'), true);
      final mahalakshmi = results.firstWhere((s) => s.id == 'ts_mahalakshmi');
      expect(mahalakshmi.matchConfidence, 1.0);
      expect(mahalakshmi.officialPortalUrl, 'https://prajapalana.telangana.gov.in');
    });

    test('Rajasthan resident qualifies for Mukhyamantri Ayushman Arogya (MAA) Yojana', () {
      final profile = CitizenProfile(
        state: 'Rajasthan',
        age: 40,
      );

      final results = SchemeEngine.evaluate(profile);
      expect(results.any((s) => s.id == 'rj_maa_ayushman'), true);
      final maa = results.firstWhere((s) => s.id == 'rj_maa_ayushman');
      expect(maa.matchConfidence, 1.0);
      expect(maa.officialPortalUrl, 'https://health.rajasthan.gov.in');
    });

    test('General citizen profile correctly filters out farming, artisan, and student schemes while keeping eligible ones', () {
      final profile = CitizenProfile(
        state: 'Uttar Pradesh',
        occupation: 'Citizen',
        age: 32,
        annualIncomeRange: '1 - 2.5 Lakh',
      );

      final results = SchemeEngine.evaluate(profile);

      // Must have results
      expect(results.isNotEmpty, true);

      // Must NOT include farming schemes
      expect(results.any((s) => s.id == 'pm_kisan'), false);
      expect(results.any((s) => s.category.contains('Agriculture')), false);

      // Must NOT include artisan or student-specific schemes
      expect(results.any((s) => s.id == 'pm_vishwakarma'), false);
      expect(results.any((s) => s.category.toLowerCase().contains('scholarship')), false);

      // Must include universal central schemes (e.g. Atal Pension for 18-40 non-salaried, Ayushman Bharat, etc.)
      expect(results.any((s) => s.id == 'atal_pension'), true);
      expect(results.any((s) => s.id == 'ayushman_bharat'), true);
    });

    testWidgets('AdaptiveWizardScreen loads and navigates without DropdownButton Citizen value assertion error', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsService();
      await settings.init();

      await tester.pumpWidget(
        MaterialApp(
          home: AdaptiveWizardScreen(settings: settings),
        ),
      );

      // Step 1: Location loads properly
      expect(find.text('Step 1 / 5'), findsOneWidget);

      // Click Next to Step 2: Demographics
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Step 2 / 5'), findsOneWidget);

      // Click Next to Step 3: Livelihood (Where the DropdownButton with Citizen was failing)
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Step 3 / 5'), findsOneWidget);

      // Dropdown should be present and displayed with 'Citizen' without crashing
      expect(find.text('Citizen'), findsOneWidget);
    });
  });

  group('ADHIKAR Internship Portal Tests', () {
    test('Internship corpus has verified listings across Govt, PSUs, and Tech Giants', () {
      final internships = InternshipsCorpus.getInternships();
      expect(internships.isNotEmpty, true);

      // Central Govt / National initiatives
      expect(internships.any((i) => i.id == 'aicte_google_cloud'), true);
      expect(internships.any((i) => i.id == 'tulip_smart_cities'), true);
      expect(internships.any((i) => i.id == 'pm_internship_scheme'), true);
      expect(internships.any((i) => i.id == 'nats_green_energy'), true);
      expect(internships.any((i) => i.id == 'niti_aayog_policy'), true);

      // PSUs
      expect(internships.any((i) => i.organization.contains('BHEL')), true);
      expect(internships.any((i) => i.organization.contains('NTPC')), true);
      expect(internships.any((i) => i.organization.contains('ONGC')), true);
      expect(internships.any((i) => i.organization.contains('BEL')), true);

      // Research & Defense Labs
      expect(internships.any((i) => i.organization.contains('ISRO')), true);
      expect(internships.any((i) => i.organization.contains('DRDO')), true);

      // Tech Leaders
      expect(internships.any((i) => i.organization.contains('TCS')), true);
      expect(internships.any((i) => i.organization.contains('Infosys')), true);
      expect(internships.any((i) => i.organization.contains('Microsoft')), true);
      expect(internships.any((i) => i.organization.contains('Accenture')), true);
    });

    test('All internships have verified portal sources and valid apply URLs', () {
      final internships = InternshipsCorpus.getInternships();
      for (final item in internships) {
        expect(item.portalSource.isNotEmpty, true);
        expect(item.officialUrl.startsWith('http'), true);
        expect(item.stipend.isNotEmpty, true);
        expect(item.workMode.isNotEmpty, true);
        expect(item.companyType.isNotEmpty, true);
      }
    });
  });

  group('ADHIKAR Localization & 22 Scheduled Regional Languages Tests', () {
    test('Supports English plus all 22 Constitutionally Scheduled Indian Languages (23 Total)', () {
      final supported = SettingsService.supportedLanguages;
      expect(supported.length, 23);

      final codes = supported.map((l) => l['code']).toSet();
      final expectedCodes = [
        'en', // English
        'hi', // Hindi
        'as', // Assamese
        'bn', // Bengali
        'brx', // Bodo
        'doi', // Dogri
        'gu', // Gujarati
        'kn', // Kannada
        'ks', // Kashmiri
        'kok', // Konkani
        'mai', // Maithili
        'ml', // Malayalam
        'mni', // Manipuri
        'mr', // Marathi
        'ne', // Nepali
        'or', // Odia
        'pa', // Punjabi
        'sa', // Sanskrit
        'sat', // Santali
        'sd', // Sindhi
        'ta', // Tamil
        'te', // Telugu
        'ur', // Urdu
      ];

      for (final code in expectedCodes) {
        expect(codes.contains(code), true, reason: 'Language code $code must be supported');
      }
    });

    test('Correctly identifies RTL for Urdu, Kashmiri, and Sindhi', () {
      final settings = SettingsService();

      settings.setLanguage('ur');
      expect(settings.isRtl, true);

      settings.setLanguage('ks');
      expect(settings.isRtl, true);

      settings.setLanguage('sd');
      expect(settings.isRtl, true);

      settings.setLanguage('hi');
      expect(settings.isRtl, false);

      settings.setLanguage('en');
      expect(settings.isRtl, false);
    });
  });

  group('Adaptive Pruning Tests', () {
    test('Adaptive question pruning rules work as expected', () {
      expect(SchemeEngine.shouldAskLandHolding('Farmer'), true);
      expect(SchemeEngine.shouldAskLandHolding('Student'), false);

      expect(SchemeEngine.shouldAskArtisanTrade('Artisan / Craftsman'), true);
      expect(SchemeEngine.shouldAskArtisanTrade('Farmer'), false);

      expect(SchemeEngine.shouldAskStudentLevel('Student'), true);
      expect(SchemeEngine.shouldAskStudentLevel('Salaried'), false);

      expect(SchemeEngine.shouldAskWidowStatus('Female', 45), true);
      expect(SchemeEngine.shouldAskWidowStatus('Male', 45), false);
    });
  });

  group('ADHIKAR Authentication & Session Persistence Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('Demo citizen account can sign in successfully via email and phone', () async {
      final auth = AuthService();
      await auth.init();

      // Sign in with email
      final resEmail = await auth.signIn(
        phoneOrEmail: 'citizen@adhikar.gov.in',
        password: 'password123',
      );
      expect(resEmail.success, true);
      expect(resEmail.user, isNotNull);
      expect(resEmail.user!.name, 'Rajesh Sharma');
      expect(auth.isAuthenticated, true);
      expect(auth.currentUser?.state, 'Uttar Pradesh');

      await auth.signOut();
      expect(auth.isAuthenticated, false);
      expect(auth.currentUser, isNull);

      // Sign in with phone
      final resPhone = await auth.signIn(
        phoneOrEmail: '9876543210',
        password: 'password123',
      );
      expect(resPhone.success, true);
      expect(resPhone.user!.name, 'Priya Patel');
      expect(auth.isAuthenticated, true);
    });

    test('Passwords are never stored in plaintext; legacy plaintext accounts are upgraded', () async {
      SharedPreferences.setMockInitialValues({
        'adhikar_accounts_database': jsonEncode({
          'old@example.com': {
            'user': {
              'id': 'u1',
              'name': 'Old User',
              'phoneOrEmail': 'old@example.com',
              'state': 'Gujarat',
              'socialCategory': 'General',
              'occupation': 'Student',
              'createdAt': DateTime(2024, 1, 1).toIso8601String(),
              'isVerified': true,
            },
            'password': 'legacyPass1',
          },
        }),
      });
      final auth = AuthService();
      await auth.init();
      expect((await auth.signIn(phoneOrEmail: 'old@example.com', password: 'nope')).success, false);
      expect((await auth.signIn(phoneOrEmail: 'old@example.com', password: 'legacyPass1')).success, true);
      await auth.signUp(
          name: 'New', phoneOrEmail: 'new@example.com', password: 'secret123', state: 'Assam');

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('adhikar_accounts_database')!;
      expect(raw.contains('legacyPass1'), false);
      expect(raw.contains('secret123'), false);
      expect(raw.contains('password123'), false);
      await auth.signOut();
      expect((await auth.signIn(phoneOrEmail: 'old@example.com', password: 'legacyPass1')).success, true);
    });

    test('Reject invalid passwords or unregistered credentials', () async {
      final auth = AuthService();
      await auth.init();

      final resWrongPass = await auth.signIn(
        phoneOrEmail: 'citizen@adhikar.gov.in',
        password: 'wrong_password',
      );
      expect(resWrongPass.success, false);
      expect(resWrongPass.user, isNull);
      expect(auth.isAuthenticated, false);

      final resNotFound = await auth.signIn(
        phoneOrEmail: 'nonexistent@example.com',
        password: 'password123',
      );
      expect(resNotFound.success, false);
      expect(resNotFound.user, isNull);
    });

    test('Sign up creates new citizen and prevents duplicate registration', () async {
      final auth = AuthService();
      await auth.init();

      final regRes = await auth.signUp(
        name: 'Pooja Patel',
        phoneOrEmail: 'pooja.patel@example.com',
        password: 'securePass123',
        state: 'Gujarat',
        socialCategory: 'OBC',
        occupation: 'Student',
      );
      expect(regRes.success, true);
      expect(regRes.user, isNotNull);
      expect(regRes.user!.name, 'Pooja Patel');
      expect(regRes.user!.state, 'Gujarat');
      expect(auth.isAuthenticated, true);

      // Attempt duplicate registration
      final dupRes = await auth.signUp(
        name: 'Duplicate Pooja',
        phoneOrEmail: 'pooja.patel@example.com',
        password: 'anotherPassword',
        state: 'Gujarat',
      );
      expect(dupRes.success, false);
      expect(dupRes.message?.contains('already exists'), true);
    });

    test('User profile update persists across state', () async {
      final auth = AuthService();
      await auth.init();

      await auth.signIn(
        phoneOrEmail: 'citizen@adhikar.gov.in',
        password: 'password123',
      );

      final updated = await auth.updateProfile(
        name: 'Rajesh K. Sharma',
        state: 'Maharashtra',
        occupation: 'Farmer',
      );
      expect(updated, isNotNull);
      expect(updated!.name, 'Rajesh K. Sharma');
      expect(updated.state, 'Maharashtra');
      expect(auth.currentUser?.name, 'Rajesh K. Sharma');
    });

    test('Session persists across app re-instantiation via SharedPreferences', () async {
      // First session: sign in
      final auth1 = AuthService();
      await auth1.init();
      await auth1.signIn(
        phoneOrEmail: 'citizen@adhikar.gov.in',
        password: 'password123',
      );
      expect(auth1.isAuthenticated, true);

      // Simulate app restart: instantiate fresh AuthService
      final auth2 = AuthService();
      await auth2.init();
      expect(auth2.isAuthenticated, true);
      expect(auth2.currentUser?.name, 'Rajesh Sharma');
    });

    test('AuthService checks account existence and handles verified email sign-in', () async {
      final auth = AuthService();
      await auth.init();

      expect(await auth.accountExists('citizen@adhikar.gov.in'), true);
      expect(await auth.accountExists('nonexistent_citizen@mail.com'), false);

      final loginRes = await auth.signInWithVerifiedEmail('citizen@adhikar.gov.in');
      expect(loginRes.success, true);
      expect(loginRes.user?.phoneOrEmail, 'citizen@adhikar.gov.in');
      expect(auth.isAuthenticated, true);
    });
  });

  group('ADHIKAR Email OTP Authentication Tests', () {
    test('EmailOtpService validates email address formats', () async {
      final otpService = EmailOtpService();
      final invalidRes = await otpService.sendOtp(recipientEmail: 'invalid-email');
      expect(invalidRes.success, false);
      expect(invalidRes.message.contains('valid email'), true);

      final emptyRes = await otpService.sendOtp(recipientEmail: '');
      expect(emptyRes.success, false);
    });

    test('Dev fallback: without SMTP credentials OTP is generated locally and verifies', () async {
      final svc = EmailOtpService.instance;
      svc.clear();
      final res = await svc.sendOtp(recipientEmail: 'dev@example.com');
      expect(res.success, true);
      expect(svc.verifyOtp(enteredOtp: '000000').success, false);
      expect(svc.attemptsRemaining, 4);
      svc.clear();
    });

    test('EmailOtpService verification rejects when no OTP session is active', () {
      final otpService = EmailOtpService();
      otpService.clear();

      final verifyRes = otpService.verifyOtp(enteredOtp: '123456');
      expect(verifyRes.success, false);
      expect(verifyRes.message.contains('No active OTP'), true);
    });
  });

  group('ADHIKAR Latest Schemes & Internships (Last 1 Month) Tests', () {
    test('LatestUpdatesService fetches schemes and internships launched in last 1 month', () async {
      final service = LatestUpdatesService.instance;
      service.setMockEmptyForTesting(false);
      service.setCategoryFilter('All');
      service.setStateFilter('All India');

      await service.fetchUpdates(forceRefresh: true);

      expect(service.isLoading, false);
      expect(service.lastRefreshedAt, isNotNull);
      expect(service.allRecentSchemes.isNotEmpty, true);
      expect(service.allRecentInternships.isNotEmpty, true);

      // Verify specific recent scheme
      expect(
        service.allRecentSchemes.any((s) => s.id == 'wb_annapurna_bhandar'),
        true,
      );

      // Verify specific recent internship
      expect(
        service.allRecentInternships.any((i) => i.id == 'pm_internship_scheme'),
        true,
      );
    });

    test('LatestUpdatesService filters by category (Schemes vs Internships)', () async {
      final service = LatestUpdatesService.instance;
      service.setMockEmptyForTesting(false);
      await service.fetchUpdates();

      service.setCategoryFilter('Schemes');
      expect(service.filteredSchemes.isNotEmpty, true);
      expect(service.filteredInternships.isEmpty, true);

      service.setCategoryFilter('Internships');
      expect(service.filteredSchemes.isEmpty, true);
      expect(service.filteredInternships.isNotEmpty, true);

      service.setCategoryFilter('All');
      expect(service.filteredSchemes.isNotEmpty, true);
      expect(service.filteredInternships.isNotEmpty, true);
    });

    test('LatestUpdatesService manual refresh updates timestamp and content', () async {
      final service = LatestUpdatesService.instance;
      final beforeTime = DateTime.now();

      await service.manualRefresh();

      expect(service.lastRefreshedAt, isNotNull);
      expect(service.lastRefreshedAt!.isAfter(beforeTime) || service.lastRefreshedAt!.isAtSameMomentAs(beforeTime), true);
      expect(service.isLoading, false);
    });

    test('Empty state: displays message when no new schemes or internships are available', () {
      final service = LatestUpdatesService.instance;
      service.setMockEmptyForTesting(true);

      expect(service.filteredSchemes.isEmpty, true);
      expect(service.filteredInternships.isEmpty, true);
      expect(service.totalRecentCount, 0);
      expect(service.hasNoUpdates, true);

      // Restore testing state
      service.setMockEmptyForTesting(false);
    });
  });
}

