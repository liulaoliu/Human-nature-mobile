import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/db/app_database.dart';
import 'data/prefs_store.dart';
import 'data/repositories/article_repository.dart';
import 'data/repositories/learning_repository.dart';
import 'data/repositories/vocab_repository.dart';
import 'services/ai_client.dart';
import 'services/article_import_service.dart';
import 'services/backup_service.dart';
import 'services/shadowing_recorder.dart';
import 'services/shadowing_speech.dart';
import 'viewmodels/ai_batch_view_model.dart';
import 'viewmodels/backup_view_model.dart';
import 'viewmodels/drill_sentence_view_model.dart';
import 'viewmodels/golden_view_model.dart';
import 'viewmodels/production_view_model.dart';
import 'viewmodels/reader_view_model.dart';
import 'viewmodels/shadowing_view_model.dart';
import 'viewmodels/speed_read_view_model.dart';
import 'viewmodels/study_view_model.dart';
import 'viewmodels/vocab_browse_view_model.dart';
import 'viewmodels/writing_view_model.dart';
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
    return MultiProvider(
      providers: [
        Provider<ArticleRepository>.value(value: articles),
        Provider<VocabRepository>.value(value: vocab),
        Provider<LearningRepository>.value(value: learning),
        Provider<ArticleImportService>.value(value: imports),
        Provider<PrefsStore>.value(value: prefs),
        ChangeNotifierProvider<ReaderViewModel>(
          create: (_) => ReaderViewModel(
            articlesRepo: articles,
            vocabRepo: vocab,
            importsService: imports,
          ),
        ),
        ChangeNotifierProvider<StudyViewModel>(
          create: (_) => StudyViewModel(
            vocab: vocab,
            learning: learning,
            prefsStore: prefs,
          ),
        ),
        ChangeNotifierProvider<VocabBrowseViewModel>(
          create: (_) => VocabBrowseViewModel(vocab: vocab, articles: articles),
        ),
        ChangeNotifierProvider<ProductionViewModel>(
          create: (_) => ProductionViewModel(
            vocab: vocab,
            learning: learning,
            prefsStore: prefs,
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
        ChangeNotifierProvider<GoldenViewModel>(
          create: (_) => GoldenViewModel(
            articles: articles,
            learning: learning,
            prefsStore: prefs,
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
          create: (_) => ShadowingViewModel(
            articles: articles,
            speech: SystemSpeech(),
            recorder: DeviceRecorder(),
            prefsStore: prefs,
          ),
        ),
        ChangeNotifierProvider<SpeedReadViewModel>(
          create: (_) => SpeedReadViewModel(articles: articles, prefsStore: prefs),
        ),
        ChangeNotifierProvider<AiBatchViewModel>(
          create: (_) {
            // 真 HTTP 客户端在这一层装配；页面和 ViewModel 只认一个回调，
            // 测试里换成假回调就能整条链路离线跑。
            // client 由 provider 生命周期托管：VM 销毁时顺带关掉它自己 new 的连接池。
            final client = AiClient();
            return AiBatchViewModel(
              vocab: vocab,
              articles: articles,
              complete: client.complete,
              prefsStore: prefs,
              onDispose: client.close,
            );
          },
        ),
      ],
      child: MaterialApp(
        title: 'D哥帮你办',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF3D7EFF),
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        home: const HomePage(),
      ),
    );
  }
}
