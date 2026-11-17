// 一次性探针：把一批边界句子过一遍 App 真实的 prepareText，
// 输出 JSON 给 Python 侧做 A/B 渲染。用完即删。
import 'dart:convert';
import 'dart:io';

import 'package:dlaoshi_app/core/tts_number_words.dart';
import 'package:dlaoshi_app/core/tts_text.dart';

String prepareText(String text) {
  final normalized = normalizeTtsText(text);
  if (normalized.trim().isEmpty) return '';
  return expandTtsNumbers(normalized).trim();
}

const cases = <String>[
  // --- 数字 / 单位 / 年份 ---
  'In the 1990s the price rose 30,000 megawatts per year.',
  'The 1960s and 1980s were turbulent decades.',
  'Revenue hit \$14.7 billion, or 45% of GDP.',
  'She finished 1st, he was 2nd, and I came 3rd.',
  'The 3.7 percent rise left 7.62mm rounds on the shelf.',
  'A 1,000 page report was released in 2008.',
  'B2B sales of the 5G network grew in 2020.',
  'The 21st century began with a 4x4 truck and 99.9% certainty.',
  // --- 缩写 ---
  'The IMF, OECD and EU disagreed with the UK over GDP.',
  'NHS staff and the G20 leaders met in Beijing.',
  'WTI crude and OPEC quotas affected the CFTC ruling.',
  // --- 所有格 / 缩写词 ---
  "Cameron's government didn't say it's over.",
  "The companies' shares fell; the workers' union didn't budge.",
  "Britain's David Cameron was petting huskies.",
  // --- 连字符 / 复合词 ---
  'A post-truth era and two-thirds majority in long-term care.',
  'Mixed-race voters and clean-energy subsidies alarmed Brexiteers.',
  // --- 难词 / 专名 ---
  'Worcestershire and Staffordshire voters backed Narendra Modi.',
  'Erdogan and Maduro met Beijinger officials in Myitkyina.',
  'Encumbered assets and Gulenists complicated the cemaat affair.',
  // --- 同形异音 ---
  'I read the book he read yesterday.',
  'They live in a live broadcast of the lead pipe.',
  'Please present the present to the content team.',
  // --- 标点 / 引号 / 破折号 ---
  'He said, “This is fine”—and then left…',
  'The dog’s bone—the one it buried—was gone.',
  // --- 长短混合 ---
  'Reading makes perfect.',
  'The global economy has many ailments and few easy remedies.',
  'MOST companies worry about discriminating against their employees on the basis of race, gender or sexual preference.',
  // --- 全大写 / 短句 ---
  'BREAKING: THE MARKET CRASHED.',
  'Shh! Listen.',
];

void main() {
  final out = <Map<String, Object?>>[];
  for (final c in cases) {
    out.add({'src': c, 'prepared': prepareText(c)});
  }
  File('build/ab2_cases.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(out),
  );
  stdout.writeln('wrote ${out.length} cases');
  for (final o in out) {
    stdout.writeln('  ${o['src']}');
    stdout.writeln('    -> ${o['prepared']}');
  }
}
