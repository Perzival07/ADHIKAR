// Exports SchemesCorpus to the RAG documents folder (backend/data/scheme_docs).
//
//   dart run tool/export_scheme_docs.dart [outDir]
//
// Output is deterministic (same input -> byte-identical files): one <scheme_id>.md (English) and
// one <scheme_id>.hi.md (Hindi) per scheme, each with YAML front-matter matching SchemeDocMeta.
import 'dart:convert';
import 'dart:io';

import 'package:haqdaar/core/models/scheme_model.dart';
import 'package:haqdaar/data/schemes_corpus.dart';

const defaultOutDir = 'backend/data/scheme_docs';

String _q(String s) => jsonEncode(s); // JSON strings are valid YAML double-quoted scalars

String _frontMatter(SchemeModel s, String lang) {
  final b = StringBuffer('---\n')
    ..writeln('scheme_id: ${_q(s.id)}')
    ..writeln('name: ${_q(lang == 'hi' ? s.nameHi : s.name)}')
    ..writeln('state_scope: ${_q(s.stateScope)}')
    ..writeln('is_central: ${s.isCentral}')
    ..writeln('category: ${_q(s.category)}')
    ..writeln('gender_eligibility: ${_q(s.genderEligibility)}')
    ..writeln('income_ceiling: ${_q(s.incomeCeiling)}')
    ..writeln('min_age: ${s.minAge ?? 'null'}')
    ..writeln('max_age: ${s.maxAge ?? 'null'}')
    ..writeln('education_level: ${_q(s.educationLevel)}')
    ..writeln('official_portal_url: ${_q(s.officialPortalUrl)}')
    ..writeln('last_verified_date: ${_q(s.lastVerifiedDate)}')
    ..writeln('language: ${_q(lang)}')
    ..writeln('source_type: "corpus"')
    ..writeln('status: ${_q(s.isVerified ? 'verified' : 'unverified')}')
    // extras used by eligibility-service (ignored by the SchemeDocMeta contract)
    ..writeln('application_status: ${_q(s.applicationStatus)}')
    ..writeln('deadline: ${_q(s.deadline)}')
    ..writeln('is_expired: ${s.isExpired}')
    ..writeln('announced_date: ${s.announcedDate == null ? 'null' : _q(s.announcedDate!)}')
    ..writeln('ministry: ${_q(s.ministry)}')
    ..writeln('department: ${_q(s.department)}')
    ..writeln('---');
  return b.toString();
}

String _eligibilityLines(SchemeModel s, bool hi) {
  final l = <String>[];
  final region = s.isCentral || s.stateScope == 'All' ? (hi ? 'पूरे भारत में' : 'All India') : s.stateScope;
  l.add('- ${hi ? 'क्षेत्र' : 'Region'}: $region');
  if (s.minAge != null || s.maxAge != null) {
    l.add('- ${hi ? 'आयु' : 'Age'}: ${s.minAge ?? 0}${s.maxAge != null ? '–${s.maxAge}' : '+'}');
  }
  l.add('- ${hi ? 'आय सीमा' : 'Income ceiling'}: ${s.incomeCeiling}');
  if (s.genderEligibility != 'All') l.add('- ${hi ? 'लिंग' : 'Gender'}: ${s.genderEligibility}');
  if (s.educationLevel != 'All') l.add('- ${hi ? 'शिक्षा स्तर' : 'Education level'}: ${s.educationLevel}');
  l.add('- ${hi ? 'आवेदन स्थिति' : 'Application status'}: ${s.applicationStatus} (${s.deadline})');
  return l.join('\n');
}

String renderSchemeDoc(SchemeModel s, String lang) {
  final hi = lang == 'hi';
  final b = StringBuffer(_frontMatter(s, lang))
    ..writeln('# ${hi ? s.nameHi : s.name}')
    ..writeln()
    ..writeln('## ${hi ? 'सारांश' : 'Summary'}')
    ..writeln(hi ? s.summaryHi : s.summary)
    ..writeln()
    ..writeln('## ${hi ? 'लाभ' : 'Benefit'}')
    ..writeln(hi ? s.benefitHi : s.benefit)
    ..writeln()
    ..writeln('## ${hi ? 'पात्रता' : 'Eligibility'}')
    ..writeln(hi ? s.defaultPlainReasonHi : s.defaultPlainReason)
    ..writeln()
    ..writeln(_eligibilityLines(s, hi))
    ..writeln()
    ..writeln('## ${hi ? 'आवश्यक दस्तावेज़' : 'Documents Required'}');
  for (final d in s.documents) {
    final name = hi ? d.nameHi : d.name;
    final tip = hi ? d.tipHi : d.tip;
    b.writeln('- **$name** (${d.issuingAuthority})${d.isRequired ? '' : hi ? ' [वैकल्पिक]' : ' [optional]'}: $tip');
  }
  b
    ..writeln()
    ..writeln('## ${hi ? 'आवेदन कैसे करें' : 'How to Apply'}');
  for (final r in s.routes) {
    b.writeln('### ${hi ? r.titleHi : r.title} (${r.type.name})');
    b.writeln(hi ? r.instructionsHi : r.instructions);
    if (r.url != null) b.writeln('Link: ${r.url}');
    b.writeln();
  }
  b
    ..writeln('## ${hi ? 'सावधानियाँ' : 'Caveats'}')
    ..writeln(s.verificationCaveat)
    ..writeln()
    ..writeln('## ${hi ? 'स्रोत' : 'Source'}')
    ..writeln('${hi ? 'आधिकारिक पोर्टल' : 'Official portal'}: ${s.officialPortalUrl}')
    ..writeln('${hi ? 'अंतिम सत्यापन' : 'Last verified'}: ${s.lastVerifiedDate}')
    ..writeln('${hi ? 'स्रोत' : 'Source'}: ${s.officialSource}; ${s.provenance}')
    ..writeln('${hi ? 'विभाग' : 'Department'}: ${s.department}')
    ..writeln('${hi ? 'समय-सीमा' : 'Timeline'}: ${s.timeline}');
  return b.toString();
}

/// Writes all documents; returns the number of files written.
int exportSchemeDocs(String outDir) {
  final dir = Directory(outDir)..createSync(recursive: true);
  var n = 0;
  for (final s in SchemesCorpus.getSchemes()) {
    File('${dir.path}/${s.id}.md').writeAsStringSync(renderSchemeDoc(s, 'en'));
    File('${dir.path}/${s.id}.hi.md').writeAsStringSync(renderSchemeDoc(s, 'hi'));
    n += 2;
  }
  return n;
}

void main(List<String> args) {
  final out = args.isNotEmpty ? args.first : defaultOutDir;
  final n = exportSchemeDocs(out);
  stdout.writeln('Exported $n files to $out');
}
