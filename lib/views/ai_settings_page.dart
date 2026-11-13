/// 「AI-deepseek 设置」页：服务地址 / API key / 模型 + 保存 + 测试连接。
///
/// 原来这一块摊在 `ai_batch_page.dart` 里（那页同时管连接、范围、进度、任务清单）。
/// 现在跑批收进阅读页的「AI-Batch Work」横条，连接设置搬到设置页 —— 一次配好，
/// 以后在文章页只管点开始。
///
/// key 只写本机 `shared_preferences`（`ai:config`），不进备份、不进 git。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/ai_config.dart';
import '../services/ai_client.dart' show AiErrorKind;
import '../theme/app_skin.dart' show SkinColors;
import '../viewmodels/ai_batch_view_model.dart';

/// AI 连接设置页。
class AiSettingsPage extends StatefulWidget {
  const AiSettingsPage({super.key});

  @override
  State<AiSettingsPage> createState() => _AiSettingsPageState();
}

class _AiSettingsPageState extends State<AiSettingsPage> {
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

  Future<void> _save(AiBatchViewModel vm) async {
    await vm.updateConfig(_collect(vm));
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
    // 先落配置再测：`vm.testConnection()` 读的是 VM 里的 config，不先写进去
    // 就会拿上次保存的旧 key / 旧地址去测（改了框却测不过，最容易误判成 key 失效）。
    await vm.updateConfig(config);
    if (!mounted) return;
    final reply = await vm.testConnection();
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testResult = reply.isOk
          ? '连接正常（模型回：${reply.text}）'
          : '连接失败：${reply.error}';
    });
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<AiBatchViewModel>();
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('AI-deepseek 设置')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('连接设置', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      'key 只存本机，不进备份、不进 git。当前显示：${vm.config.maskedApiKey}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _baseUrl,
                      decoration: const InputDecoration(
                        labelText: '服务地址',
                        hintText: defaultAiBaseUrl,
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _apiKey,
                      obscureText: _obscure,
                      decoration: InputDecoration(
                        labelText: 'API key',
                        border: const OutlineInputBorder(),
                        isDense: true,
                        suffixIcon: IconButton(
                          tooltip: _obscure ? '显示' : '隐藏',
                          icon: Icon(
                            _obscure ? Icons.visibility : Icons.visibility_off,
                          ),
                          onPressed: () =>
                              setState(() => _obscure = !_obscure),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _model,
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
                          onPressed: () => _save(vm),
                          icon: const Icon(Icons.save_outlined),
                          label: const Text('保存到本机'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _testing ? null : () => _test(vm),
                          icon: _testing
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.wifi_tethering),
                          label: const Text('测试连接'),
                        ),
                      ],
                    ),
                    if (_testResult.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        _testResult,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: _testResult.startsWith('连接正常')
                              ? SkinColors.of(context).success
                              : theme.colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('跑批怎么用', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(
                      '打开一篇文章 → 点顶栏的「AI-Batch Work」→ 点开始。'
                      '只跑当前这一篇里还没释义的词；跑过的不会重跑。',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 给页面之外的调用方（比如测试）一个错误文案的中文标签。
String aiErrorKindLabel(AiErrorKind kind) => switch (kind) {
      AiErrorKind.network => '网络',
      AiErrorKind.unauthorized => 'key 不对',
      AiErrorKind.rateLimited => '限流',
      AiErrorKind.server => '服务端',
      AiErrorKind.badResponse => '坏响应',
      AiErrorKind.empty => '空回复',
    };
