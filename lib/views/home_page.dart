import 'package:flutter/material.dart';

import 'articles_page.dart';
import 'production_page.dart';
import 'study_page.dart';
import 'vocab_browse_page.dart';

/// 首页：三条主链路（精读 / 背单词 / 产出训练）的入口。
///
/// 三条都接通了；「词库」是看收录情况的旁路页。
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('D老师帮你办')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('今天想练什么？', style: theme.textTheme.titleLarge),
          const SizedBox(height: 16),
          _EntryCard(
            icon: Icons.menu_book_outlined,
            title: '精读',
            subtitle: '逐句读、选词、看语言点',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ArticlesPage()),
            ),
          ),
          _EntryCard(
            icon: Icons.style_outlined,
            title: '背单词',
            subtitle: '单词与搭配分开背',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const StudyPage()),
            ),
          ),
          _EntryCard(
            icon: Icons.folder_open_outlined,
            title: '词库',
            subtitle: '按范围 / 状态 / 日期筛，看全部收录',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const VocabBrowsePage()),
            ),
          ),
          _EntryCard(
            icon: Icons.edit_note_outlined,
            title: '产出训练',
            subtitle: '全脂 / 脱脂 / 风味酸奶',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ProductionPage()),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            '词库、精读、背单词、产出训练已接通；小课堂与跟读还在移植中。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  /// 接通了才给：未接通的入口点了没反应比显示「开发中」更糟。
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final enabled = onTap != null;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(icon, color: enabled ? theme.colorScheme.primary : muted),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: enabled
            ? const Icon(Icons.chevron_right)
            : Text('开发中', style: TextStyle(color: muted)),
        onTap: onTap,
      ),
    );
  }
}

