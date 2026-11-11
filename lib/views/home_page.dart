import 'package:flutter/material.dart';

import 'ai_batch_page.dart';
import 'articles_page.dart';
import 'backup_page.dart';
import 'golden_page.dart';
import 'production_page.dart';
import 'shadowing_page.dart';
import 'speed_read_page.dart';
import 'study_page.dart';
import 'vocab_browse_page.dart';
import 'writing_page.dart';

/// 首页：九条主链路的入口（精读 / 背单词 / 词库 / 速读 / 产出训练 / 小课堂 / 金句课 / 备份 / 跟读）+ AI 跑批。
///
/// 全部接通；「词库」是看收录情况的旁路页，「速读」是一句一句计时读、超时就地拷打，
/// 「小课堂」是仿写与历史，「金句课」是挑句、填空拼句与金句本，「备份」是整库导出与导入，
/// 「跟读」是听标准音 + 自己读 + 当场判，
/// 「AI 跑批」是拿本机 key 批量补齐词库里缺的释义。
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('D哥帮你办')),
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
            icon: Icons.speed_outlined,
            title: '速读',
            subtitle: '一句一句计时读，超时就地拷打',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SpeedReadPage()),
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
          _EntryCard(
            icon: Icons.school_outlined,
            title: '小课堂',
            subtitle: '拿范句仿写、看批改与历史',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const WritingPage()),
            ),
          ),
          _EntryCard(
            icon: Icons.auto_stories_outlined,
            title: '金句课',
            subtitle: '挑金句、填空拼句、全库金句本',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const GoldenPage()),
            ),
          ),
          _EntryCard(
            icon: Icons.backup_outlined,
            title: '备份',
            subtitle: '导出整库 / 覆盖导入 / 合并导入',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const BackupPage()),
            ),
          ),
          _EntryCard(
            icon: Icons.record_voice_over_outlined,
            title: '跟读',
            subtitle: '听标准音、自己读、当场判一下',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ShadowingPage()),
            ),
          ),
          _EntryCard(
            icon: Icons.smart_toy_outlined,
            title: 'AI 跑批',
            subtitle: '批量补齐词库里缺的释义',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const AiBatchPage()),
            ),
          ),
          const SizedBox(height: 24),
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

