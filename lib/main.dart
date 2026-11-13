import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/db/app_database.dart';
import 'data/prefs_store.dart';
import 'data/repositories/article_repository.dart';
import 'data/repositories/learning_repository.dart';
import 'data/repositories/vocab_repository.dart';
import 'services/ai_client.dart';
import 'services/article_import_service.dart';
import 'services/audio_playback.dart';
import 'services/backup_service.dart';
import 'services/shadowing_recorder.dart';
import 'services/shadowing_speech.dart';
import 'theme/app_skin.dart';
import 'theme/app_theme.dart';
import 'viewmodels/ai_batch_view_model.dart';
import 'viewmodels/backup_view_model.dart';
import 'viewmodels/current_article_view_model.dart';
import 'viewmodels/drill_sentence_view_model.dart';
import 'viewmodels/drill_view_model.dart';
import 'viewmodels/golden_view_model.dart';
import 'viewmodels/intensive_view_model.dart';
import 'viewmodels/production_view_model.dart';
import 'viewmodels/pick_mode_view_model.dart';
import 'viewmodels/reader_view_model.dart';
import 'viewmodels/shadowing_view_model.dart';
import 'viewmodels/speed_read_view_model.dart';
import 'viewmodels/study_view_model.dart';
import 'viewmodels/theme_view_model.dart';
import 'viewmodels/vocab_browse_view_model.dart';
import 'viewmodels/writing_view_model.dart';
import 'views/article_context_sync.dart';
import 'views/home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = await openAppDatabase();
  final articles = ArticleRepository(db);
  final vocab = VocabRepository(db);
  final learning = LearningRepository(db);
  final imports = ArticleImportService(articles);
  final prefs = await PrefsStore.open();
  runApp(
    DlaoshiApp(
      articles: articles,
      vocab: vocab,
      learning: learning,
      imports: imports,
      prefs: prefs,
    ),
  );
}

/// 应用根：装配仓储 → ViewModel → 界面。
class DlaoshiApp extends StatelessWidget {
  const DlaoshiApp({
    super.key,
    required this.articles,
    required this.vocab,
    required this.learning,
    required this.imports,
    required this.prefs,
  });

  final ArticleRepository articles;
  final VocabRepository vocab;
  final LearningRepository learning;
  final ArticleImportService imports;
  final PrefsStore prefs;

  @override
  Widget build(BuildContext context) {
    // 全 App 共用一个 HTTP 客户端：产出训练（奶牛工棚）与 AI 跑批读同一份
    // `ai:config`，共用一份连接池；关掉只在 AiBatchViewModel 那边做一次。
    final aiClient = AiClient();
    return MultiProvider(
      providers: [
        Provider<ArticleRepository>.value(value: articles),
        Provider<VocabRepository>.value(value: vocab),
        Provider<LearningRepository>.value(value: learning),
        Provider<ArticleImportService>.value(value: imports),
        Provider<PrefsStore>.value(value: prefs),
        // 主题：全局外观，放在所有 VM 之前（MaterialApp 要读它）。
        ChangeNotifierProvider<ThemeViewModel>(
          create: (_) => ThemeViewModel(prefsStore: prefs),
        ),
        // 当前文章：全局唯一的一份「本篇」，别的模块都读它（精读页是唯一写入方）。
        // 必须排在所有读它的 VM 之前。
        ChangeNotifierProvider<CurrentArticleViewModel>(
          create: (_) => CurrentArticleViewModel(
            articlesRepo: articles,
            prefsStore: prefs,
          ),
        ),
        ChangeNotifierProvider<ReaderViewModel>(
          create: (_) => ReaderViewModel(
            articlesRepo: articles,
            vocabRepo: vocab,
            importsService: imports,
          ),
        ),
        // 选词模式：精读与速读共用同一份开关（用户明确要求复用）。
        ChangeNotifierProvider<PickModeViewModel>(
          create: (_) => PickModeViewModel(),
        ),
        ChangeNotifierProvider<StudyViewModel>(
          create: (_) => StudyViewModel(
            vocab: vocab,
            learning: learning,
            prefsStore: prefs,
            speech: SystemSpeech(),
          ),
        ),
        ChangeNotifierProvider<VocabBrowseViewModel>(
          create: (context) => VocabBrowseViewModel(
            vocab: vocab,
            articles: articles,
            prefsStore: prefs,
            // 词库的「本篇」只有一处来源：全局当前文章。
            currentArticle: context.read<CurrentArticleViewModel>(),
          ),
        ),
        ChangeNotifierProvider<ProductionViewModel>(
          create: (_) => ProductionViewModel(
            vocab: vocab,
            learning: learning,
            prefsStore: prefs,
            // 出题 / 批改都是一键直连；没配 key 时自动退回手动粘贴那条路。
            complete: aiClient.complete,
          ),
        ),
        ChangeNotifierProvider<WritingViewModel>(
          create: (_) => WritingViewModel(learning: learning, prefsStore: prefs),
        ),
        ChangeNotifierProvider<DrillSentenceViewModel>(
          create: (_) => DrillSentenceViewModel(
            learning: learning,
            prefsStore: prefs,
          ),
        ),
        // 快速拷打：按全局当前篇取词（没选篇时退回全库）。
        ChangeNotifierProvider<DrillViewModel>(
          create: (context) => DrillViewModel(
            vocab: vocab,
            learning: learning,
            articles: articles,
            currentArticle: context.read<CurrentArticleViewModel>(),
            prefsStore: prefs,
          ),
        ),
        // 精读工作流：一篇材料从看懂到产出的七步，仿写挂在第 6 步。
        ChangeNotifierProvider<IntensiveViewModel>(
          create: (context) => IntensiveViewModel(
            vocab: vocab,
            learning: learning,
            articles: articles,
            currentArticle: context.read<CurrentArticleViewModel>(),
          ),
        ),
        ChangeNotifierProvider<GoldenViewModel>(
          create: (context) => GoldenViewModel(
            articles: articles,
            learning: learning,
            prefsStore: prefs,
            // 默认挑全局当前篇那一篇（页内仍可「换一篇」）。
            currentArticle: context.read<CurrentArticleViewModel>(),
          ),
        ),
        ChangeNotifierProvider<BackupViewModel>(
          create: (_) => BackupViewModel(
            BackupService(
              articles: articles,
              vocab: vocab,
              learning: learning,
              prefsStore: prefs,
            ),
          ),
        ),
        ChangeNotifierProvider<ShadowingViewModel>(
          create: (context) => ShadowingViewModel(
            articles: articles,
            speech: SystemSpeech(engine: prefs.loadTtsEngine()),
            recorder: DeviceRecorder(),
            playback: AudioPlayback(),
            prefsStore: prefs,
            // 默认跟全局当前篇（页内仍可「换一篇」）。
            currentArticle: context.read<CurrentArticleViewModel>(),
          ),
        ),
        ChangeNotifierProvider<SpeedReadViewModel>(
          create: (context) => SpeedReadViewModel(
            articles: articles,
            prefsStore: prefs,
            // 默认读全局当前篇（页内仍可「换一篇」）。
            currentArticle: context.read<CurrentArticleViewModel>(),
          ),
        ),
        ChangeNotifierProvider<AiBatchViewModel>(
          create: (context) {
            // 真 HTTP 客户端在根上装配（与奶牛工棚共用一个实例）；页面和
            // ViewModel 只认一个回调，测试里换成假回调就能整条链路离线跑。
            // client 由 provider 生命周期托管：VM 销毁时顺带关掉它自己 new 的连接池。
            return AiBatchViewModel(
              vocab: vocab,
              articles: articles,
              // 默认跑全局当前篇（页内仍可换；全局没选就空着，不退回第一篇）。
              currentArticle: context.read<CurrentArticleViewModel>(),
              complete: aiClient.complete,
              prefsStore: prefs,
              onDispose: aiClient.close,
            );
          },
        ),
      ],
      child: Consumer<ThemeViewModel>(
        builder: (BuildContext context, ThemeViewModel themeVm, Widget? _) {
          // 皮肤只有一个（经典蓝），但 light/dark 各生成一份交给 MaterialApp ——
          // 跟随系统时由 Flutter 自己按系统明暗选，CP 不需要手动读亮度。
          return MaterialApp(
            title: 'D哥帮你办',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(skin: AppSkin.classic),
            darkTheme: AppTheme.dark(skin: AppSkin.classic),
            themeMode: themeModeOf(themeVm.mode),
            // 全局「当前文章」→ 各模块的「本篇」上下文，挂在根部与当前页面无关。
            home: const ArticleContextSync(child: HomePage()),
          );
        },
      ),
    );
  }
}
