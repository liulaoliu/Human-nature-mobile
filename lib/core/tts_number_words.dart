// 把阿拉伯数字展开成英文单词，供 Kitten 那条「查 espeak 词典」的路径用。
//
// 为什么需要这一步：Kotlin 侧 `Phonemizer.convert` 里的 `expandDigits` 是**逐位**替换
// （`"30,000"` → `"three zero, zero zero zero"`、`"1990's"` → `"one nine nine zero's"`），
// 而 Kitten 的音素来自 `assets/tts/en-us.bin` 的 espeak 词典，只认单词。
// 不展开的话，「三十千兆瓦」会被读成「三点零零零」。
//
// 实现照抄 `package:phonemize` 的 `lib/src/expand.dart`（MIT，Copyright (c) 2026
// Abdul Momin Sakib）。那个文件没有 export，直接 import 会触发
// `implementation_imports`，项目又不许用 `// ignore:`，所以整段搬进来并补了测试。
// 改动只有：命名空间化、去掉本项目用不到的 `expandAbbreviations`（缩写由
// `normalizeTtsText` 自己处理）。
import 'package:number_to_words_english/number_to_words_english.dart';

const Map<int, String> _ones = {
  0: 'zero',
  1: 'one',
  2: 'two',
  3: 'three',
  4: 'four',
  5: 'five',
  6: 'six',
  7: 'seven',
  8: 'eight',
  9: 'nine',
};

String _numberToWords(int n) => n.toWords();

String _ordinalToWords(int n) {
  final base = _numberToWords(n);
  if (n % 100 >= 11 && n % 100 <= 13) return '${base}th';
  switch (n % 10) {
    case 1:
      return base.replaceFirst(RegExp(r'one$'), 'first');
    case 2:
      return base.replaceFirst(RegExp(r'two$'), 'second');
    case 3:
      return base.replaceFirst(RegExp(r'three$'), 'third');
    case 5:
      return base.replaceFirst(RegExp(r'five$'), 'fifth');
    case 8:
      return base.replaceFirst(RegExp(r'eight$'), 'eighth');
    case 9:
      return base.replaceFirst(RegExp(r'nine$'), 'ninth');
    default:
      return '${base}th';
  }
}

String _digitsToWords(String digits) =>
    digits.split('').map((d) => _ones[int.parse(d)]).join(' ');

/// 把文本里的数字展开成英文单词。幂等：没有数字时原样返回。
String expandTtsNumbers(String text) {
  // 货币：先处理 $，因为它带千分位与小数
  text = text.replaceAllMapped(
    RegExp(r'\$(\d+(?:,\d{3})*(?:\.\d{2})?)'),
    (m) {
      final amount = m.group(1)!;
      final value = double.parse(amount.replaceAll(',', ''));
      final dollars = value.floor();
      final cents = ((value - dollars) * 100).round();

      var result = '';
      if (dollars > 0) {
        result +=
            '${_numberToWords(dollars)}${dollars == 1 ? ' dollar' : ' dollars'}';
      }
      if (cents > 0) {
        if (dollars > 0) result += ' and ';
        result += '${_numberToWords(cents)}${cents == 1 ? ' cent' : ' cents'}';
      }
      return result.isEmpty ? 'zero dollars' : result;
    },
  );

  // 年份 1800–2099：读「nineteen ninety」而不是「one thousand nine hundred ninety」
  text = text.replaceAllMapped(
    RegExp(r'\b(1[89]\d{2}|20\d{2})\b'),
    (m) {
      final year = int.parse(m.group(1)!);
      if (year >= 2000) {
        if (year == 2000) return 'twenty hundred';
        if (year < 2010) return 'twenty oh ${_ones[year % 10]}';
        return 'twenty ${_numberToWords(year % 100)}';
      }
      final century = year ~/ 100;
      final remainder = year % 100;
      return '${_numberToWords(century)} '
          '${remainder < 10 ? 'oh ${_ones[remainder]}' : _numberToWords(remainder)}';
    },
  );

  // 时刻 10:30 / 9:05 pm
  text = text.replaceAllMapped(
    RegExp(
      r'\b(\d{1,2}):(\d{2})(?:\s*(am|pm))?\b',
      caseSensitive: false,
    ),
    (m) {
      final h = int.parse(m.group(1)!);
      final min = int.parse(m.group(2)!);
      final ampm = m.group(3);

      final hourNum = h == 0 ? 12 : (h > 12 ? h - 12 : h);
      var result = _numberToWords(hourNum);

      if (min == 0) {
        result += " o'clock";
      } else if (min < 10) {
        result += ' oh ${_numberToWords(min)}';
      } else {
        result += ' ${_numberToWords(min)}';
      }

      if (ampm != null) {
        result += ' ${ampm.toLowerCase().split('').join(' ')}';
      }
      return result;
    },
  );

  // 序数：1st → first、21st → twenty-first
  text = text.replaceAllMapped(
    RegExp(r'\b(\d+)(?:st|nd|rd|th)\b', caseSensitive: false),
    (m) => _ordinalToWords(int.parse(m.group(1)!)),
  );

  // 电话号码
  text = text.replaceAllMapped(
    RegExp(r'\b(?:\(\d{3}\)\s?|\d{3}-)\d{3}-\d{4}\b'),
    (m) => _digitsToWords(m.group(0)!.replaceAll(RegExp(r'\D'), '')),
  );

  // 小数：3.7 → three point seven
  text = text.replaceAllMapped(
    RegExp(r'\b(\d+)\.(\d+)\b'),
    (m) => '${_numberToWords(int.parse(m.group(1)!))} '
        'point ${_digitsToWords(m.group(2)!)}',
  );

  // 百分比
  text = text.replaceAllMapped(
    RegExp(r'\b(\d+(?:\.\d+)?)%'),
    (m) {
      final raw = m.group(1)!;
      final value = double.parse(raw);
      var result = _numberToWords(value.floor());
      if (raw.contains('.')) {
        result += ' point ${_digitsToWords(raw.split('.')[1])}';
      }
      return '$result percent';
    },
  );

  // 剩下的普通整数
  text = text.replaceAllMapped(
    RegExp(r'\b\d+\b'),
    (m) => _numberToWords(int.parse(m.group(0)!)),
  );

  return text.replaceAll(RegExp(r'\s+'), ' ').trim();
}
