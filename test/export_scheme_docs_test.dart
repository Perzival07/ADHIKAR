import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:adhikar/data/schemes_corpus.dart';

import '../tool/export_scheme_docs.dart';

Map<String, String> _frontMatter(String text) {
  final lines = const LineSplitter().convert(text);
  expect(lines.first, '---');
  final end = lines.indexOf('---', 1);
  expect(end, greaterThan(1), reason: 'front-matter must be closed');
  final out = <String, String>{};
  for (final l in lines.sublist(1, end)) {
    final i = l.indexOf(': ');
    expect(i, greaterThan(0), reason: 'bad front-matter line: $l');
    out[l.substring(0, i)] = l.substring(i + 2);
  }
  return out;
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('scheme_docs_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('exports one English and one Hindi file per scheme with valid front-matter', () {
    final schemes = SchemesCorpus.getSchemes();
    final written = exportSchemeDocs(tmp.path);
    expect(written, schemes.length * 2);
    final files = tmp.listSync().whereType<File>().toList();
    expect(files.length, schemes.length * 2);
    expect(schemes.map((s) => s.id).toSet().length, schemes.length, reason: 'scheme ids must be unique');

    const required = [
      'scheme_id', 'name', 'state_scope', 'is_central', 'category', 'gender_eligibility', 'income_ceiling',
      'min_age', 'max_age', 'education_level', 'official_portal_url', 'last_verified_date', 'language',
      'source_type', 'status',
    ];
    for (final s in schemes) {
      final en = _frontMatter(File('${tmp.path}/${s.id}.md').readAsStringSync());
      final hi = _frontMatter(File('${tmp.path}/${s.id}.hi.md').readAsStringSync());
      for (final k in required) {
        expect(en.containsKey(k), true, reason: '${s.id}.md missing $k');
        expect(hi.containsKey(k), true, reason: '${s.id}.hi.md missing $k');
      }
      expect(jsonDecode(en['scheme_id']!), s.id);
      expect(jsonDecode(en['language']!), 'en');
      expect(jsonDecode(hi['language']!), 'hi');
    }
  });

  test('export is deterministic (byte-identical on re-run)', () {
    exportSchemeDocs(tmp.path);
    final first = {for (final f in tmp.listSync().whereType<File>()) f.path: f.readAsStringSync()};
    exportSchemeDocs(tmp.path);
    for (final e in first.entries) {
      expect(File(e.key).readAsStringSync(), e.value);
    }
  });

  test('documents contain the sections RAG relies on', () {
    exportSchemeDocs(tmp.path);
    final text = File('${tmp.path}/pm_kisan.md').readAsStringSync();
    for (final h in ['## Summary', '## Benefit', '## Eligibility', '## Documents Required', '## How to Apply', '## Caveats', '## Source']) {
      expect(text.contains(h), true, reason: h);
    }
  });
}
