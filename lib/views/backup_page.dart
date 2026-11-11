import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../widgets/status_bar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/backup_parse.dart';
import '../services/backup_service.dart';
import '../viewmodels/backup_view_model.dart';

/// 开发用的真数据样本：一份完整备份 JSON（约 33MB）。
///
/// 只在 debug 包的「备份 → 导入内置样本」里读它。改数据就替换这个文件。
const String sampleBackupAsset =
    'assets/data/economist-backup-2026-11-10.json';

/// 备份页：导出整库、覆盖导入、合并导入。
///
/// 平台能力都在这一层：写临时文件 + 分享（`share_plus`）、选文件（`file_picker`）。
/// ViewModel 只收文本、只吐结果，这样测试能用内存库跑。
class BackupPage extends StatefulWidget {
  const BackupPage({super.key});

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  bool _sharing = false;

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<BackupViewModel>();
    return Scaffold(
      appBar: AppBar(title: const Text('备份')),
      body: SafeArea(
        child: Column(
          children: [
            if (vm.error != null) StatusBar.error(message: vm.error!),
            if (vm.busy) const LinearProgressIndicator(),
            if (vm.notice.isNotEmpty)
              StatusBar.notice(message: vm.notice, onClose: vm.clearNotice),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  _HintCard(),
                  const SizedBox(height: 16),
                  _ExportCard(
                    busy: _sharing || vm.busy,
                    onExport: () => _export(vm),
                  ),
                  const SizedBox(height: 16),
                  _ImportCard(
                    busy: vm.busy,
                    onPick: (bool replace) => _pickAndImport(vm, replace),
                  ),
                  // 开发用：把仓库里那份真备份一键灌进来（只在 debug 包出现）。
                  if (kDebugMode) ...[
                    const SizedBox(height: 16),
                    _SampleCard(
                      busy: vm.busy,
                      onImport: () => _importSample(vm),
                    ),
                  ],
                  if (vm.lastImport != null) ...[
                    const SizedBox(height: 16),
                    _ResultCard(result: vm.lastImport!),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _export(BackupViewModel vm) async {
    final result = await vm.export();
    if (!mounted || result == null) return;
    setState(() => _sharing = true);
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/${result.fileName}');
      await file.writeAsString(result.json, flush: true);
      await SharePlus.instance.share(
        ShareParams(
          files: <XFile>[XFile(file.path)],
          fileNameOverrides: <String>[result.fileName],
          subject: 'D哥帮你办 · 备份 ${result.fileName}',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('文件写不出去：$e')),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _pickAndImport(BackupViewModel vm, bool replace) async {
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: replace ? '选一份备份：整份替换' : '选一份备份：合并进来',
      type: FileType.custom,
      allowedExtensions: <String>['json'],
      withData: true,
    );
    if (!mounted || picked == null || picked.files.isEmpty) return;

    final platformFile = picked.files.first;
    String? text;
    try {
      final bytes = platformFile.bytes;
      if (bytes != null) {
        text = utf8.decode(bytes);
      } else if (platformFile.path != null) {
        text = await File(platformFile.path!).readAsString();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('这个文件读不出来：$e')),
      );
      return;
    }
    if (!mounted) return;
    if (text == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('这个文件读不出来：既没有内容也没有路径')),
      );
      return;
    }

    final parsed = vm.peek(text);
    if (!mounted) return;
    if (parsed == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('这不是本应用的备份文件')),
      );
      return;
    }
    if (replace) {
      final ok = await _confirmReplace(parsed);
      if (!mounted || !ok) return;
    }
    if (replace) {
      await vm.replace(text);
    } else {
      await vm.merge(text);
    }
  }

  /// 开发用：把 `assets/data/` 里那份真备份读进来，走覆盖导入。
  ///
  /// 只在 debug 包显示按钮；正式包不会引用这份 33MB 的样本。
  Future<void> _importSample(BackupViewModel vm) async {
    String text;
    try {
      text = await rootBundle.loadString(sampleBackupAsset);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('样本读不出来：$e')),
      );
      return;
    }
    if (!mounted) return;
    final parsed = vm.peek(text);
    if (parsed == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('样本不是本应用的备份文件')),
      );
      return;
    }
    final ok = await _confirmReplace(parsed);
    if (!mounted || !ok) return;
    await vm.replace(text);
  }

  Future<bool> _confirmReplace(ParsedBackup parsed) async {
    final int articleCount = parsed.articles.length;
    final int vocabCount = parsed.library?.items.length ?? 0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('整份替换？'),
        content: Text(
          '会用这份文件覆盖现在的全部内容：文章 $articleCount 篇、生词 $vocabCount 个。\n'
          '当前库里的东西不会留着（备份文件里有的除外）。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('覆盖'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }
}

class _HintCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('怎么用', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              '导出：把词库、文章、背单词进度、仿写与金句记录打包成一个 JSON 文件，存到手机或发给自己。\n'
              '覆盖导入：新手机第一次搬家时用 —— 文件里有什么就是什么。\n'
              '合并导入：两台设备各有记录时用 —— 词库互相补充，练习记录按天累加；'
              '同一份文件重复合并会被认出来，不会翻倍。',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _ExportCard extends StatelessWidget {
  const _ExportCard({required this.busy, required this.onExport});

  final bool busy;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('导出', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              '整库导出一个 JSON 文件。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: busy ? null : onExport,
              icon: const Icon(Icons.ios_share),
              label: const Text('导出并分享'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImportCard extends StatelessWidget {
  const _ImportCard({required this.busy, required this.onPick});

  final bool busy;
  final void Function(bool replace) onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('导入', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              '新手机搬家选「覆盖导入」；两台设备合记录选「合并导入」。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: <Widget>[
                FilledButton.tonalIcon(
                  onPressed: busy ? null : () => onPick(false),
                  icon: const Icon(Icons.merge_type),
                  label: const Text('合并导入'),
                ),
                OutlinedButton.icon(
                  onPressed: busy ? null : () => onPick(true),
                  icon: const Icon(Icons.restore),
                  label: const Text('覆盖导入'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 开发用卡片：一键导入仓库里的真数据样本（只在 debug 包出现）。
class _SampleCard extends StatelessWidget {
  const _SampleCard({required this.busy, required this.onImport});

  final bool busy;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Text('开发用', style: theme.textTheme.titleMedium),
                const SizedBox(width: 8),
                Chip(
                  label: const Text('debug'),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '把仓库里那份真备份（10,892 词 / 50 篇）灌进来，'
              '省得每次都去选文件。正式包不会显示这个按钮。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: busy ? null : onImport,
              icon: const Icon(Icons.science_outlined),
              label: const Text('导入内置样本'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.result});

  final BackupImportResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('上一次导入', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(result.summary),
            if (result.errors.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final String line in result.errors.take(5))
                Text(
                  '· $line',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              if (result.errors.length > 5)
                Text(
                  '…还有 ${result.errors.length - 5} 条',
                  style: theme.textTheme.bodySmall,
                ),
            ],
          ],
        ),
      ),
    );
  }
}


