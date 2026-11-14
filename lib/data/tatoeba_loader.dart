// 离线例句的按需加载：读 asset → 在后台 isolate 里只抽需要的词。
//
// 为什么不一次把 6.5MB 全解析进内存：整表大约十万行，解析成对象要几十 MB，
// 而「一键处理」一次只关心生词本里那几百个词。抽完就丢，内存峰值小得多。
library;

import 'dart:isolate';

import 'package:flutter/services.dart' show rootBundle;

import '../core/tatoeba.dart';

/// asset 路径（与 pubspec.yaml 的 `assets/tatoeba/` 对应）。
const String tatoebaAsset = 'assets/tatoeba/tatoeba-en.tsv';

/// 读 asset 并抽出 [words]（词形 / 原形都放进来）的例句。
///
/// [loader] 只给测试用；[background] = false 时在当前 isolate 解析
/// （测试里不折腾 isolate，也方便断言）。
Future<Map<String, List<TatoebaExample>>> loadTatoebaExamples(
  Set<String> words, {
  Future<String?> Function()? loader,
  bool background = true,
}) async {
  if (words.isEmpty) return const {};
  final text = await (loader ?? _readAsset)();
  if (text == null || text.trim().isEmpty) return const {};
  if (!background) return examplesForWords(text, words);
  // 闭包捕获的两份数据都会复制进 isolate；返回的只有目标词的例句。
  return Isolate.run(() => examplesForWords(text, words));
}

Future<String?> _readAsset() async {
  try {
    return await rootBundle.loadString(tatoebaAsset);
  } on Object {
    // 没打包 / 读失败：例句那一步自动降级，不拖垮别的步骤。
    return null;
  }
}
