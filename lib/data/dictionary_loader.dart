/// 离线词典的加载与缓存。
///
/// 对应 Web 版 `src/adapters/dictionary.ts`：那边用 `fetch` 从 `public/` 拉
/// `ecdict.tsv`（7.8MB）+ 变体表（1.1MB）+ 近似词表（0.3MB），解析在主线程要几百毫秒；
/// 安卓侧把三份文件打进 `assets/ecdict/`，用 `rootBundle` 读，逻辑一致。
///
/// **加载失败不抛错**：没有数据文件时所有用到词典的功能自动降级
/// （退到词库自带释义 / 让用户手填），而不是让阅读页打不开。
library;

import 'dart:convert';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/services.dart' show ByteData, rootBundle;

import '../../core/ecdict.dart';

const String _assetDir = 'assets/ecdict';

Ecdict? _dict;
Future<bool>? _loading;

/// 已经加载好的词典；没好就是 null（调用方要能用「没有词典」跑下去）。
Ecdict? dictionary() => _dict;

/// 词典是否可用。
bool dictionaryReady() => _dict != null;

/// 测试注入用：换掉当前词典（传 null 清空）。
void setDictionary(Ecdict? value) {
  _dict = value;
}

/// 加载词典。并发调用共用同一个 Future；已加载直接返回 true。
///
/// [loader] 只给测试用（默认读 `assets/ecdict/*.tsv`）：
/// 单测里不该去碰 `rootBundle`，也不该真读 9MB 的文本。
Future<bool> loadDictionary({
  Future<String?> Function(String name)? loader,
}) async {
  if (_dict != null) return true;
  final pending = _loading;
  if (pending != null) return pending;
  final task = _load(loader ?? _loadAsset, background: loader == null);
  _loading = task;
  try {
    return await task;
  } finally {
    _loading = null;
  }
}

/// 清掉缓存（释放内存 / 测试隔离用）。
void resetDictionary() {
  _dict = null;
  _loading = null;
}

Future<bool> _load(
  Future<String?> Function(String name) loader, {
  required bool background,
}) async {
  try {
    final words = await loader('words.tsv');
    // 没有主表就等于没有词典：变体表和近似词表单独存在也没用。
    if (words == null || words.isEmpty) return false;
    final forms = await loader('forms.tsv') ?? '';
    final near = await loader('near.tsv') ?? '';
    // 真机 9MB 解析要几秒：放到后台 isolate，别把首帧冻住。
    // 测试注入 loader 时在主 isolate 解析（快、可断言）。
    _dict = background
        ? await compute(_parseEcdictTask, (words, forms, near))
        : parseEcdict(words, forms, near);
    return true;
  } catch (_) {
    return false;
  }
}

/// `compute` 的入口（必须是顶层函数）。
Ecdict _parseEcdictTask((String, String, String) input) =>
    parseEcdict(input.$1, input.$2, input.$3);

Future<String?> _loadAsset(String name) async {
  try {
    final data = await rootBundle.load('$_assetDir/$name');
    return _decodeUtf8(data);
  } catch (_) {
    return null;
  }
}

/// `rootBundle.load` 给的是字节；词典是 UTF-8 文本（含少量非法字节，容错解）。
String _decodeUtf8(ByteData data) {
  final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  return utf8.decode(bytes, allowMalformed: true);
}
