/// 「拼提示词 → 复制 → 粘回结果」的通用面板。
///
/// 手机上没有 API key 也能用：提示词复制到剪贴板，粘到网页版 AI，
/// 再把回答整段粘回来，由 `core/analyzer_parse.dart` 解析成结构化数据。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 面板返回值：用户点了「应用」时是粘回的文本，直接关掉是 null。
class AiPasteSheet extends StatefulWidget {
  const AiPasteSheet({
    super.key,
    required this.title,
    required this.prompt,
    required this.hint,
    required this.onApply,
  });

  /// 面板标题，如「查词」。
  final String title;

  /// 要复制给 AI 的提示词。
  final String prompt;

  /// 结果框的提示语（说明期望的输出格式）。
  final String hint;

  /// 应用粘回的文本；返回错误提示（null 表示成功，面板会自己关掉）。
  final Future<String?> Function(String raw) onApply;

  @override
  State<AiPasteSheet> createState() => _AiPasteSheetState();
}

class _AiPasteSheetState extends State<AiPasteSheet> {
  final TextEditingController _result = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _result.dispose();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.prompt));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('提示词已复制，粘到 AI 里跑一下')),
    );
  }

  Future<void> _pasteIn() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    final text = data?.text ?? '';
    if (text.isEmpty) {
      setState(() => _error = '剪贴板里没有文本');
      return;
    }
    setState(() {
      _result.text = text;
      _error = null;
    });
  }

  Future<void> _apply() async {
    final raw = _result.text.trim();
    if (raw.isEmpty) {
      setState(() => _error = '先把 AI 的结果粘进来');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final failure = await widget.onApply(raw);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = failure;
    });
    if (failure == null) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(widget.title, style: theme.textTheme.titleMedium),
                ),
                TextButton.icon(
                  onPressed: _copy,
                  icon: const Icon(Icons.copy_all, size: 18),
                  label: const Text('复制提示词'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              constraints: const BoxConstraints(maxHeight: 140),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  widget.prompt,
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _result,
              minLines: 4,
              maxLines: 10,
              decoration: InputDecoration(
                labelText: '把 AI 的结果粘到这里',
                helperText: widget.hint,
                helperMaxLines: 3,
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: '从剪贴板粘贴',
                  onPressed: _pasteIn,
                  icon: const Icon(Icons.paste),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _apply,
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('应用'),
            ),
          ],
        ),
      ),
    );
  }
}
