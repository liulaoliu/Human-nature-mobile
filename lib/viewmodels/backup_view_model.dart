/// 备份页的状态：导出 / 覆盖导入 / 合并导入。
///
/// 为什么平台能力（选文件、分享）不放这里：ViewModel 要能在 `flutter test` 里
/// 用内存库跑，一旦 import `file_picker` / `share_plus` 就得起平台通道。
/// 所以这里只收**文本**、只吐**结果**，读写文件与分享由页面做。
library;

import 'package:flutter/foundation.dart';

import '../core/backup_parse.dart';
import '../services/backup_service.dart';

/// 备份 ViewModel。
class BackupViewModel extends ChangeNotifier {
  BackupViewModel(this._service);

  final BackupService _service;

  bool _busy = false;
  String? _error;
  String _notice = '';
  BackupExportResult? _lastExport;
  BackupImportResult? _lastImport;

  bool get busy => _busy;
  String? get error => _error;
  String get notice => _notice;

  /// 上一次导出的结果（页面拿它去写文件 + 分享）。
  BackupExportResult? get lastExport => _lastExport;

  /// 上一次导入的结果。
  BackupImportResult? get lastImport => _lastImport;

  /// 导出整库。失败返回 null，原因在 [error]。
  Future<BackupExportResult?> export() async {
    if (_busy) return null;
    _busy = true;
    _error = null;
    _notice = '';
    notifyListeners();
    try {
      final result = await _service.exportAll();
      _lastExport = result;
      _notice = '导出好了：${result.summary}';
      return result;
    } catch (e) {
      _error = '导出失败：$e';
      return null;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// 覆盖导入（整份替换）。
  ///
  /// 坏数据只计数不中断 —— 但要说到明处：`notice` 里带上「跳过 N 条」，
  /// 用户才知道那份文件不是完美的。
  Future<BackupImportResult?> replace(String text) =>
      _run(text, (String raw) => _service.replace(raw), isMerge: false);

  /// 合并导入（词库互补、记录累加、同一份文件只合并一次）。
  Future<BackupImportResult?> merge(String text) =>
      _run(text, (String raw) => _service.merge(raw), isMerge: true);

  Future<BackupImportResult?> _run(
    String text,
    Future<BackupImportResult> Function(String raw) run, {
    required bool isMerge,
  }) async {
    if (_busy) return null;
    _busy = true;
    _error = null;
    _notice = '';
    notifyListeners();
    try {
      final result = await run(text);
      _lastImport = result;
      _notice = isMerge ? '合并完成：${result.summary}' : '导入完成：${result.summary}';
      return result;
    } on FormatException {
      _error = '这不是 JSON 备份文件';
      return null;
    } catch (e) {
      _error = '导入失败：$e';
      return null;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// 只解析、不落库：给界面「先看看这份文件是什么」用。
  ParsedBackup? peek(String text) {
    try {
      return _service.parse(text);
    } catch (_) {
      return null;
    }
  }

  void clearNotice() {
    if (_notice.isEmpty) return;
    _notice = '';
    notifyListeners();
  }
}
