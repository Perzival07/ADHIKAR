// Runs the real Dart SchemeEngine over a list of profiles and writes the expected output.
// Used to prove the Python eligibility-service matches the Dart engine.
//
//   dart run tool/dump_engine_parity.dart <profiles.json> <out.json>
import 'dart:convert';
import 'dart:io';

import 'package:adhikar/core/models/citizen_profile.dart';
import 'package:adhikar/core/services/scheme_engine.dart';

CitizenProfile fromMap(Map<String, dynamic> m) => CitizenProfile(
      state: m['state'],
      district: m['district'],
      age: m['age'],
      gender: m['gender'],
      maritalStatus: m['maritalStatus'],
      occupation: m['occupation'],
      landHoldingAcres: (m['landHoldingAcres'] as num).toDouble(),
      artisanTrade: m['artisanTrade'],
      studentLevel: m['studentLevel'],
      socialCategory: m['socialCategory'],
      rationCard: m['rationCard'],
      annualIncomeRange: m['annualIncomeRange'],
      disabilityStatus: m['disabilityStatus'],
      hasGirlChildUnder10: m['hasGirlChildUnder10'],
    );

void main(List<String> args) {
  final profiles = (jsonDecode(File(args[0]).readAsStringSync()) as List).cast<Map<String, dynamic>>();
  final out = <Map<String, dynamic>>[];
  for (final p in profiles) {
    final results = SchemeEngine.evaluate(fromMap(p));
    out.add({
      'profile': p,
      'eligible': {
        for (final s in results) s.id: {'score': s.matchConfidence, 'reason': s.generatedReason},
      },
    });
  }
  File(args[1]).writeAsStringSync(const JsonEncoder.withIndent(' ').convert(out));
  stdout.writeln('Wrote ${out.length} profiles to ${args[1]}');
}
