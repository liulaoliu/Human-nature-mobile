import 'package:flutter/material.dart';
import '../widgets/status_bar.dart';
import 'package:provider/provider.dart';

import '../core/ai_config.dart';
import '../core/ai_jobs.dart' show AiJob;
import '../services/ai_client.dart' show AiErrorKind;
import '../viewmodels/ai_batch_view_model.dart';

/// AI 跑批页：填一次 key、测试连接、把词库里缺释义的词批量补齐。
///
/// 平台能力（真 HTTP）在 `main.dart` 里注入 [AiClient.complete]；
/// 页面只做界面、不碰网络，测试可以整个离线跑。
class AiBatchPage extends StatefulWidget {
  const AiBatchPage({super.key});

  @override
  State<AiBatchPage> createState() => _AiBatchPageState();
}

class _AiBatchPageState extends State<AiBatchPage> {
  late final TextEditingController _baseUrl;
  late final TextEditingController _apiKey;
  late final TextEditingController _model;
  bool _obscure = true;
  bool _testing = false;
  String _testResult = '';

  @override
  void initState() {
    super.initState();
    final config = context.read<AiBatchViewModel>().config;
    _baseUrl = TextEditingController(text: config.baseUrl);
    _apiKey = TextEditingController(text: config.apiKey);
    _model = TextEditingController(text: config.model);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AiBatchViewModel>().bootstrap();
    });
  }

  @override
  void dispose() {
    _baseUrl.dispose();
    _apiKey.dispose();
    _model.dispose();
    super.dispose();
  }

  AiConfig _collect(AiBatchViewModel vm) => AiConfig(
        baseUrl: _baseUrl.text,
        apiKey: _apiKey.text,
        model: _model.text,
        temperature: vm.config.temperature,
      );

  Future<void> _saveConfig(AiBatchViewModel vm) async {
    final config = _collect(vm);
    await vm.updateConfig(config);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('设置已存到本机')),
    );
  }

  Future<void> _test(AiBatchViewModel vm) async {
    final config = _collect(vm);
    if (!config.hasApiKey) {
      setState(() => _testResult = '先填 API key 再测');
      return;
    }
    setState(() {
      _testing = true;
      _testResult = '';
    });
    final reply = await vm.testConnection();
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testResult = reply.isOk
          ? '连接正常（模型回：${reply.text}）'
          : '连接失败：${reply.error}';
    });
  }

  Future<void> _run(AiBatchViewModel vm) async {
    await _saveConfigSilently(vm);
    await vm.run();
  }

  Future<void> _resume(AiBatchViewModel vm) async {
    await _saveConfigSilently(vm);
    await vm.resume();
  }

  Future<void> _saveConfigSilently(AiBatchViewModel vm) async {
    final config = _collect(vm);
    if (config != vm.config) await vm.updateConfig(config);
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<AiBatchViewModel>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 跑批'),
        actions: [
          IconButton(
            tooltip: '重新按词库算待办',
            icon: const Icon(Icons.refresh),
            onPressed: vm.busy ? null : () => vm.refresh(),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (vm.error != null) StatusBar.error(message: vm.error!),
            if (vm.busy || vm.running) const LinearProgressIndicator(),
            if (vm.notice.isNotEmpty)
              StatusBar.notice(message: vm.notice, onClose: vm.clearNotice),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  _SettingsCard(
                    baseUrl: _baseUrl,
                    apiKey: _apiKey,
                    model: _model,
                    obscure: _obscure,
                    onToggleObscure: () =>
                        setState(() => _obscure = !_obscure),
                    masked: vm.config.maskedApiKey,
                    testing: _testing,
                    testResult: _testResult,
                    onSave: () => _saveConfig(vm),
                    onTest: () => _test(vm),
                  ),
                  const SizedBox(height: 16),
                  _ProgressCard(vm: vm),
                  const SizedBox(height: 16),
                  _JobsCard(vm: vm),
                ],
              ),
            ),
            _BottomBar(
              vm: vm,
              onRun: () => _run(vm),
              onResume: () => _resume(vm),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    required this.obscure,
    required this.onToggleObscure,
    required this.masked,
    required this.testing,
    required this.testResult,
    required this.onSave,
    required this.onTest,
  });

  final TextEditingController baseUrl;
  final TextEditingController apiKey;
  final TextEditingController model;
  final bool obscure;
  final VoidCallback onToggleObscure;
  final String masked;
  final bool testing;
  final String testResult;
  final VoidCallback onSave;
  final VoidCallback onTest;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('连接设置', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'key 只存本机，不进备份、不进 git。当前显示：$masked',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: baseUrl,
              decoration: const InputDecoration(
                labelText: '服务地址',
                hintText: defaultAiBaseUrl,
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: apiKey,
              obscureText: obscure,
              decoration: InputDecoration(
                labelText: 'API key',
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: IconButton(
                  tooltip: obscure ? '显示' : '隐藏',
                  icon: Icon(obscure ? Icons.visibility : Icons.visibility_off),
                  onPressed: onToggleObscure,
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: model,
              decoration: const InputDecoration(
                labelText: '模型',
                hintText: defaultAiModel,
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: onSave,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('保存到本机'),
                ),
                OutlinedButton.icon(
                  onPressed: testing ? null : onTest,
                  icon: testing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi_tethering),
                  label: const Text('测试连接'),
                ),
              ],
            ),
            if (testResult.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                testResult,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: testResult.startsWith('连接正常')
                      ? Colors.green
                      : theme.colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.vm});

  final AiBatchViewModel vm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final o = vm.outcome;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('本轮进度', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(vm.progressText, style: theme.textTheme.bodyLarge),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: vm.jobs.isEmpty
                  ? 0
                  : o.doneCount / vm.jobs.length,
            ),
            const SizedBox(height: 8),
            Text(
              vm.jobs.isEmpty
                  ? '词库里没有待查的词，都补齐了'
                  : '共 ${o.total} 块 · 完成 ${o.doneCount} · 失败 ${o.failedCount}'
                      ' · 还剩 ${o.remaining}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _JobsCard extends StatelessWidget {
  const _JobsCard({required this.vm});

  final AiBatchViewModel vm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (vm.jobs.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            '没有待办任务。去「精读」标几个生词，回来点刷新就能跑。',
            style: theme.textTheme.bodyMedium,
          ),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('任务清单', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            for (var i = 0; i < vm.jobs.length; i++) ...[
              _JobTile(
                job: vm.jobs[i],
                done: vm.doneIds.contains(vm.jobs[i].id),
                failed: vm.failedIds[vm.jobs[i].id],
                active: i == vm.index && vm.running,
              ),
              if (i != vm.jobs.length - 1) const Divider(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}

class _JobTile extends StatelessWidget {
  const _JobTile({
    required this.job,
    required this.done,
    required this.failed,
    required this.active,
  });

  final AiJob job;
  final bool done;
  final String? failed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    IconData icon;
    Color color;
    if (done) {
      icon = Icons.check_circle;
      color = Colors.green;
    } else if (failed != null) {
      icon = Icons.error_outline;
      color = theme.colorScheme.error;
    } else if (active) {
      icon = Icons.play_arrow;
      color = theme.colorScheme.primary;
    } else {
      icon = Icons.radio_button_unchecked;
      color = theme.colorScheme.onSurfaceVariant;
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(job.label, style: theme.textTheme.bodyMedium),
              Text(
                '${job.words.length} 个词 · ${job.id}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (failed != null)
                Text(
                  failed!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.vm,
    required this.onRun,
    required this.onResume,
  });

  final AiBatchViewModel vm;
  final VoidCallback onRun;
  final VoidCallback onResume;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final canStart = !vm.busy && !vm.running && vm.jobs.isNotEmpty;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton.icon(
            onPressed: canStart ? onRun : null,
            icon: const Icon(Icons.play_arrow),
            label: const Text('开始跑批'),
          ),
          if (vm.paused || vm.outcome.failedCount > 0)
            FilledButton.tonalIcon(
              onPressed: vm.busy ? null : onResume,
              icon: const Icon(Icons.play_circle_outline),
              label: const Text('继续'),
            ),
          if (vm.running)
            OutlinedButton.icon(
              onPressed: vm.pause,
              icon: const Icon(Icons.pause),
              label: const Text('暂停'),
            ),
          if (vm.outcome.failedCount > 0)
            OutlinedButton.icon(
              onPressed: vm.skipFailed,
              icon: const Icon(Icons.skip_next),
              label: const Text('跳过失败的'),
            ),
        ],
      ),
    );
  }
}



/// 给页面之外的调用方（比如 main 或测试）一个错误文案的中文标签。
String aiErrorKindLabel(AiErrorKind kind) => switch (kind) {
      AiErrorKind.network => '网络',
      AiErrorKind.unauthorized => 'key 不对',
      AiErrorKind.rateLimited => '限流',
      AiErrorKind.server => '服务端',
      AiErrorKind.badResponse => '坏响应',
      AiErrorKind.empty => '空回复',
    };


