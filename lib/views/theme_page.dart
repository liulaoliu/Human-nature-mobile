/// 皮肤 / 主题设置页：深色、浅色、跟随系统。
///
/// 为什么不直接用一排放三个 `ChoiceChip`：这三个不是一个「筛选条件」，
/// 而是**互斥的一项选择**，用户要能读到每一项是干什么的。`RadioListTile`
/// 带副标题，扫一眼就懂；chip 得点一下才知道什么效果。
///
/// 目前只有一个皮肤（经典蓝），所以这一页就是「明暗三选一」。以后加皮肤
/// 在这一页下面再接一段「配色方案」就行 —— 明暗与配色是两件事，别合在一个
/// 枚举里：每种配色都要有浅色和深色两版。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme_prefs.dart';
import '../theme/app_skin.dart';
import '../viewmodels/theme_view_model.dart';

/// 皮肤设置页。
class ThemePage extends StatelessWidget {
  const ThemePage({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ThemeViewModel>();
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Scaffold(
      appBar: AppBar(title: const Text('皮肤')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('明暗', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      '选「跟随系统」就不用管了：手机切到深色，App 自己跟着切。',
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                    const SizedBox(height: 8),
                    // Flutter 3.32 起 RadioListTile 的 groupValue/onChanged 走
                    // `RadioGroup` 祖先统一管，逐个传已废弃。
                    RadioGroup<AppThemeMode>(
                      groupValue: vm.mode,
                      onChanged: (AppThemeMode? value) {
                        if (value != null) vm.setMode(value);
                      },
                      child: Column(
                        children: [
                          for (final mode in AppThemeMode.values)
                            RadioListTile<AppThemeMode>(
                              key: ValueKey('theme-mode-${mode.name}'),
                              contentPadding: EdgeInsets.zero,
                              value: mode,
                              title: Text(themeModeLabel[mode] ?? mode.name),
                              subtitle: Text(themeModeHint[mode] ?? ''),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const _SkinSection(),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('关于配色', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(
                      '现在只有「${AppSkin.classic.label}」一套配色，浅色和深色是它的两版。'
                      '以后加配色会出现在上面 —— 明暗和配色分开选，换配色不用重挑明暗。',
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
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

/// 配色方案（目前只有一个，所以显示成一行「已选」而不是给一个假的选择器）。
class _SkinSection extends StatelessWidget {
  const _SkinSection();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final scheme = theme.colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('配色', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.check_circle, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    AppSkin.classic.label,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                Text(
                  theme.brightness == Brightness.dark ? '深色版' : '浅色版',
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 色卡：让用户当场看到这个皮肤在这个明暗下长什么样。
            Row(
              children: [
                for (final color in <Color>[
                  scheme.primary,
                  scheme.secondary,
                  scheme.tertiary,
                  scheme.error,
                ])
                  Container(
                    width: 36,
                    height: 36,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
