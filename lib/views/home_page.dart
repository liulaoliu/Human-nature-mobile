import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../viewmodels/study_view_model.dart';
import 'ai_batch_page.dart';
import 'articles_page.dart';
import 'backup_page.dart';
import 'golden_page.dart';
import 'production_page.dart';
import 'settings_page.dart';
import 'shadowing_page.dart';
import 'speed_read_page.dart';
import 'study_page.dart';
import 'vocab_browse_page.dart';
import 'writing_page.dart';

/// 首页：十条主链路的入口 + 左侧抽屉（设置）。
///
/// 全部接通；「词库」是看收录情况的旁路页，「速读」是一句一句计时读、超时就地拷打，
/// 「小课堂」是仿写与历史，「金句课」是挑句、填空拼句与金句本，「备份」是整库导出与导入，
/// 「跟读」是听标准音 + 自己读 + 当场判，
/// 「AI 跑批」是拿本机 key 批量补齐词库里缺的释义。
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    // 首页要显示「候选 N 个」，所以进来先读一次词库。
    // 用可空查法：单独的 smoke 测试只挂 HomePage 时没有 Provider，不该炸。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final vm = context.read<StudyViewModel?>();
      if (vm != null && !vm.busy) vm.bootstrap();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final counts =
        context.select<StudyViewModel?, int>((vm) => vm?.poolCounts.total ?? 0);
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(title: const Text('D哥帮你办')),
      drawer: const _HomeDrawer(),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('今天想练什么？', style: theme.textTheme.titleLarge),
          const SizedBox(height: 16),
          _EntryCard(
            icon: Icons.menu_book_outlined,
            title: '精读',
            subtitle: '逐句读、选词、看语言点',
            onTap: () => _open(const ArticlesPage()),
          ),
          _EntryCard(
            icon: Icons.style_outlined,
            title: '背单词',
            subtitle: '单词与搭配分开背',
            note: counts > 0 ? '候选 $counts 个' : null,
            onTap: () => _open(const StudyPage()),
          ),
          _EntryCard(
            icon: Icons.folder_open_outlined,
            title: '词库',
            subtitle: '按范围 / 状态 / 日期筛，看全部收录',
            onTap: () => _open(const VocabBrowsePage()),
          ),
          _EntryCard(
            icon: Icons.speed_outlined,
            title: '速读',
            subtitle: '一句一句计时读，超时就地拷打',
            onTap: () => _open(const SpeedReadPage()),
          ),
          _EntryCard(
            icon: Icons.edit_note_outlined,
            title: '产出训练',
            subtitle: '全脂 / 脱脂 / 风味酸奶',
            onTap: () => _open(const ProductionPage()),
          ),
          _EntryCard(
            icon: Icons.school_outlined,
            title: '小课堂',
            subtitle: '拿范句仿写、看批改与历史',
            onTap: () => _open(const WritingPage()),
          ),
          _EntryCard(
            icon: Icons.auto_stories_outlined,
            title: '金句课',
            subtitle: '挑金句、填空拼句、全库金句本',
            onTap: () => _open(const GoldenPage()),
          ),
          _EntryCard(
            icon: Icons.backup_outlined,
            title: '备份',
            subtitle: '导出整库 / 覆盖导入 / 合并导入',
            onTap: () => _open(const BackupPage()),
          ),
          _EntryCard(
            icon: Icons.record_voice_over_outlined,
            title: '跟读',
            subtitle: '听标准音、自己读、当场判一下',
            onTap: () => _open(const ShadowingPage()),
          ),
          _EntryCard(
            icon: Icons.smart_toy_outlined,
            title: 'AI 跑批',
            subtitle: '批量补齐词库里缺的释义',
            onTap: () => _open(const AiBatchPage()),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  void _open(Widget page) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }
}

/// 左侧抽屉：设置入口 + 以后的「所有设置都放这里」。
class _HomeDrawer extends StatelessWidget {
  const _HomeDrawer();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(color: scheme.primaryContainer),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text('D哥帮你办', style: theme.textTheme.titleLarge),
                      const SizedBox(height: 4),
                      Text(
                        '精读 · 背单词 · 速读 · 产出',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '设置',
                  icon: const Icon(Icons.settings),
                  onPressed: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
                    );
                  },
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('设置'),
            subtitle: const Text('背单词范围、牌组、锤炼阈值'),
            onTap: () {
              Navigator.of(context).pop();
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
              );
            },
          ),
          const Divider(height: 1),
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
    this.note,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  /// 小字备注（比如「候选 10892 个」）。
  final String? note;

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
        title: Row(
          children: [
            Text(title),
            if (note != null) ...[
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  note!,
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
        subtitle: Text(subtitle),
        trailing: enabled
            ? const Icon(Icons.chevron_right)
            : Text('开发中', style: TextStyle(color: muted)),
        onTap: onTap,
      ),
    );
  }
}
