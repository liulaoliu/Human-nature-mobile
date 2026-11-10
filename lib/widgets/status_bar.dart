/// 全局共用的状态条：错误（红）与一次性提示（可关掉）。
///
/// 以前每个页面都自带一份私有 `_ErrorBar` / `_NoticeBar`（10 份 + 7 份），
/// 样式已经悄悄漂移：提示条右内边距有 6 也有 8，关闭图标有默认大小也有
/// `size: 18`。集中到这里后只留一种口径，改配色/间距也只改一处。
library;

import 'package:flutter/material.dart';

/// 页面顶部/底部的状态条。用命名构造区分两种语义：
/// - [StatusBar.error]：错误，红色底，不可关；
/// - [StatusBar.notice]：一次性提示，次要色底，点右边叉关掉。
class StatusBar extends StatelessWidget {
  const StatusBar.error({required this.message, super.key})
      : _error = true,
        onClose = null;

  const StatusBar.notice({
    required this.message,
    required this.onClose,
    super.key,
  }) : _error = false;

  final String message;
  final VoidCallback? onClose;
  final bool _error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: _error ? scheme.errorContainer : scheme.secondaryContainer,
      padding: _error
          ? const EdgeInsets.symmetric(horizontal: 16, vertical: 10)
          : const EdgeInsets.fromLTRB(16, 6, 8, 6),
      child: _error
          ? Text(message, style: TextStyle(color: scheme.onErrorContainer))
          : Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    message,
                    style: TextStyle(color: scheme.onSecondaryContainer),
                  ),
                ),
                IconButton(
                  tooltip: '知道了',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: onClose,
                ),
              ],
            ),
    );
  }
}
