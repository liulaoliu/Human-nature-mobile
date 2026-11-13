/// 设置页（第一级：目录）。
///
/// 为什么改成两级：设置项越来越多（背诵 / 朗读 / 皮肤 / 关于），一页滚到底
/// 既难找又容易被看漏。第一级只放「进哪一块」，点进去才是开关。
///
/// 例外：牌组（单词 / 搭配）每天可能换，在首页「背单词」那一行的小按键里；
/// 学哪一批（学习 / 复习 / 回顾）在背单词页选。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme_prefs.dart';
import '../viewmodels/theme_view_model.dart';
import 'backup_page.dart';
import 'speed_settings_page.dart';
import 'study_settings_page.dart';
import 'theme_page.dart';

/// 设置页（目录）。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: const [
            _EntryCard(
              icon: Icons.school_outlined,
              title: '背诵设置',
              subtitle: '每组词数、每天新词上限、锤炼阈值、朗读',
              page: StudySettingsPage(),
              key: ValueKey('settings-entry-study'),
            ),
            SizedBox(height: 12),
            _EntryCard(
              icon: Icons.speed_outlined,
              title: '速读设置',
              subtitle: '语速、超时是否拷打',
              page: SpeedSettingsPage(),
              key: ValueKey('settings-entry-speed'),
            ),
            SizedBox(height: 12),
            _EntryCard(
              icon: Icons.palette_outlined,
              title: '皮肤',
              subtitle: '深色 / 浅色 / 跟随系统',
              page: ThemePage(),
              key: ValueKey('settings-entry-theme'),
            ),
            SizedBox(height: 12),
            _EntryCard(
              icon: Icons.backup_outlined,
              title: '备份',
              subtitle: '导出整库 / 覆盖导入 / 合并导入',
              page: BackupPage(),
              key: ValueKey('settings-entry-backup'),
            ),
            SizedBox(height: 16),
            _AboutSection(),
          ],
        ),
      ),
    );
  }
}

/// 一个入口卡片：图标 + 标题 + 副标题 + 右箭头。
class _EntryCard extends StatelessWidget {
  const _EntryCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.page,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget page;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(icon, color: theme.colorScheme.primary),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => page),
        ),
      ),
    );
  }
}

/// 关于。
class _AboutSection extends StatelessWidget {
  const _AboutSection();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final vm = context.watch<ThemeViewModel>();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('关于', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'D哥帮你办 · 精读 / 背单词 / 速读 / 产出训练 / 小课堂 / 金句课',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '当前外观：${themeModeLabel[vm.mode] ?? vm.mode.name}',
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
