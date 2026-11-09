import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/db/app_database.dart';
import 'data/prefs_store.dart';
import 'data/repositories/article_repository.dart';
import 'data/repositories/learning_repository.dart';
import 'data/repositories/vocab_repository.dart';
import 'services/article_import_service.dart';
import 'viewmodels/production_view_model.dart';
import 'viewmodels/reader_view_model.dart';
import 'viewmodels/study_view_model.dart';
import 'viewmodels/vocab_browse_view_model.dart';
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
      ],
      child: MaterialApp(
        title: 'D老师帮你办',
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
