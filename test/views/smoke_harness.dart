// 页面 smoke 测试的公共装配：和 test/widget_test.dart 保持同一套 Provider / SQLite 套路。
//
// 本文件不是 *_test.dart，flutter test 不会把它当用例收集，只给同目录的
// smoke 测试 import。把重复装配收在一处，避免每个文件各抄一份抄漏。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:dlaoshi_app/data/db/migrations.dart';
import 'package:dlaoshi_app/data/prefs_store.dart';
import 'package:dlaoshi_app/data/repositories/article_repository.dart';
import 'package:dlaoshi_app/data/repositories/learning_repository.dart';
import 'package:dlaoshi_app/data/repositories/vocab_repository.dart';
import 'package:dlaoshi_app/services/ai_client.dart' show AiReply;
import 'package:dlaoshi_app/services/article_import_service.dart';
import 'package:dlaoshi_app/services/backup_service.dart';
import 'package:dlaoshi_app/services/shadowing_recorder.dart';
import 'package:dlaoshi_app/services/shadowing_speech.dart';
import 'package:dlaoshi_app/viewmodels/ai_batch_view_model.dart';
import 'package:dlaoshi_app/viewmodels/backup_view_model.dart';
import 'package:dlaoshi_app/viewmodels/current_article_view_model.dart';
import 'package:dlaoshi_app/viewmodels/drill_sentence_view_model.dart';
import 'package:dlaoshi_app/viewmodels/drill_view_model.dart';
import 'package:dlaoshi_app/viewmodels/golden_view_model.dart';
import 'package:dlaoshi_app/viewmodels/intensive_view_model.dart';
import 'package:dlaoshi_app/viewmodels/pick_mode_view_model.dart';
import 'package:dlaoshi_app/viewmodels/production_view_model.dart';
import 'package:dlaoshi_app/viewmodels/reader_view_model.dart';
import 'package:dlaoshi_app/viewmodels/shadowing_view_model.dart';
import 'package:dlaoshi_app/viewmodels/speed_read_view_model.dart';
import 'package:dlaoshi_app/viewmodels/study_view_model.dart';
import 'package:dlaoshi_app/viewmodels/theme_view_model.dart';
import 'package:dlaoshi_app/viewmodels/vocab_browse_view_model.dart';
import 'package:dlaoshi_app/viewmodels/writing_view_model.dart';

/// 每个 *_test.dart 的 setUpAll 里调用一次。
void smokeInitFfi() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
}

/// 默认 800×600 放不下多张卡 / 长页，给个够高的屏幕。
void smokeUseTallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// 真 SQLite 是真实异步 IO，必须放在 runAsync 里。
Future<Database> smokeOpenDb(WidgetTester tester) async {
  late final Database db;
  await tester.runAsync(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await ensureSchema(db);
  });
  addTearDown(() async => tester.runAsync(() => db.close()));
  return db;
}

/// 想在测试里自己先 seed 数据时，用这两个拿仓库（和 [smokeApp] 内部是同一份 db）。
VocabRepository smokeVocabRepo(Database db) => VocabRepository(db);

LearningRepository smokeLearningRepo(Database db) => LearningRepository(db);

/// [smokeApp] 里装配的那份词库浏览 VM；测试想断言筛选项就取它。
///
/// 存成顶层变量而不是从 widget 树里捞：词库页的筛选面板是 modal，
/// 面板内外的 context 拿到的都是同一个 VM，直接引用最不容易写错。
late VocabBrowseViewModel smokeBrowse;

VocabBrowseViewModel smokeBrowseVm(WidgetTester tester) => smokeBrowse;

/// [smokeApp] 里装配的那份「当前文章」VM；要断言/预置当前文章就取它。
late CurrentArticleViewModel smokeCurrent;

/// [smokeApp] 里装配的那份精读工作流 VM；要断言七阶段就取它。
late IntensiveViewModel smokeIntensive;

/// [smokeApp] 里装配的那份金句课 VM；要预置一句再练就取它。
late GoldenViewModel smokeGolden;

/// 和 main.dart 一致的整套 Provider 装配；十个 VM 全部 .value 注入、刻意不 dispose。
///
/// [study] 给调用方注入自己造好的实例（比如想先在测试里开好轮再看界面）；
/// 不给就用内部新建的那个，和以前一样。[quickDrill] 同理（拷打页要拿到它断言状态）。
Widget smokeApp(Database db, Widget home,
    {StudyViewModel? study, ThemeViewModel? theme, DrillViewModel? quickDrill}) {
  final articles = ArticleRepository(db);
  final vocab = VocabRepository(db);
  final learning = LearningRepository(db);
  final imports = ArticleImportService(articles);
  final prefs = PrefsStore.memory();
  final themeVm = theme ?? ThemeViewModel(prefsStore: prefs);
  final reader = ReaderViewModel(
    articlesRepo: articles,
    vocabRepo: vocab,
    importsService: imports,
  );
  final studyVm = study ??
      StudyViewModel(
        vocab: vocab,
        learning: learning,
        prefsStore: prefs,
      );
  // 全局「当前文章」：精读页是唯一写入方，其余页面只读。
  final current = CurrentArticleViewModel(
    articlesRepo: articles,
    prefsStore: prefs,
  );
  smokeCurrent = current;
  final browse = VocabBrowseViewModel(
    vocab: vocab,
    articles: articles,
    prefsStore: prefs,
    currentArticle: current,
  );
  smokeBrowse = browse;
  final production = ProductionViewModel(
    vocab: vocab,
    learning: learning,
    prefsStore: prefs,
  );
  final writing = WritingViewModel(learning: learning, prefsStore: prefs);
  final drill = DrillSentenceViewModel(learning: learning, prefsStore: prefs);
  final quickDrillVm = quickDrill ??
      DrillViewModel(
        vocab: vocab,
        learning: learning,
        articles: articles,
        currentArticle: current,
        prefsStore: prefs,
      );
  final golden = GoldenViewModel(
    articles: articles,
    learning: learning,
    prefsStore: prefs,
    currentArticle: current,
  );
  smokeGolden = golden;
  final intensive = IntensiveViewModel(
    vocab: vocab,
    learning: learning,
    articles: articles,
    currentArticle: current,
  );
  smokeIntensive = intensive;
  final backup = BackupViewModel(
    BackupService(
      articles: articles,
      vocab: vocab,
      learning: learning,
      prefsStore: prefs,
    ),
  );
  final shadowing = ShadowingViewModel(
    articles: articles,
    speech: SystemSpeech(),
    recorder: DeviceRecorder(),
    prefsStore: prefs,
    currentArticle: current,
  );
  final aiBatch = AiBatchViewModel(
    vocab: vocab,
    articles: articles,
    currentArticle: current,
    complete: (config, prompt) async => AiReply.ok(''),
    prefsStore: prefs,
  );
  final speedRead = SpeedReadViewModel(
    articles: articles,
    prefsStore: prefs,
    currentArticle: current,
  );
  // 精读与速读共用同一个开关，装配顺序也和 main.dart 一致。
  final pick = PickModeViewModel();
  return MultiProvider(
    providers: [
      Provider<ArticleRepository>.value(value: articles),
      Provider<VocabRepository>.value(value: vocab),
      Provider<LearningRepository>.value(value: learning),
      Provider<ArticleImportService>.value(value: imports),
      Provider<PrefsStore>.value(value: prefs),
      ChangeNotifierProvider<ThemeViewModel>.value(value: themeVm),
      ChangeNotifierProvider<CurrentArticleViewModel>.value(value: current),
      ChangeNotifierProvider<ReaderViewModel>.value(value: reader),
      ChangeNotifierProvider<PickModeViewModel>.value(value: pick),
      ChangeNotifierProvider<StudyViewModel>.value(value: studyVm),
      ChangeNotifierProvider<VocabBrowseViewModel>.value(value: browse),
      ChangeNotifierProvider<ProductionViewModel>.value(value: production),
      ChangeNotifierProvider<WritingViewModel>.value(value: writing),
      ChangeNotifierProvider<DrillSentenceViewModel>.value(value: drill),
      ChangeNotifierProvider<DrillViewModel>.value(value: quickDrillVm),
      ChangeNotifierProvider<IntensiveViewModel>.value(value: intensive),
      ChangeNotifierProvider<GoldenViewModel>.value(value: golden),
      ChangeNotifierProvider<BackupViewModel>.value(value: backup),
      ChangeNotifierProvider<ShadowingViewModel>.value(value: shadowing),
      ChangeNotifierProvider<SpeedReadViewModel>.value(value: speedRead),
      ChangeNotifierProvider<AiBatchViewModel>.value(value: aiBatch),
    ],
    child: MaterialApp(home: home),
  );
}

/// pumpWidget + 让 initState 的 bootstrap 真实 IO 走完；
/// 不用 pumpAndSettle（不少页面常驻 LinearProgressIndicator，永远 settle 不了）。
Future<void> smokePump(WidgetTester tester, Widget app) async {
  await tester.pumpWidget(app);
  await tester.pump();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 30)),
  );
  await tester.pump();
  await tester.pump();
}

/// 收尾消掉 pending Timer（sqflite 事务锁 / 250ms 防抖草稿 / TTS 都会排 Timer）。
///
/// 原来是硬写 6 轮 `100ms 真实等待 + 500ms 假时钟`，两个问题：
/// 1. **短的页面白等**（一个纯展示页也要跑 3.6 秒假时钟），20 个页面叠起来就是
///    `test/views` 整体变慢的一大块；
/// 2. **长的页面可能不够**——只要某轮里又排了一个新 Timer（比如草稿防抖在第二轮
///    的 IO 回调里才被创建），固定 6 轮只是碰巧够，改了页面就可能不够，
///    而失败信息是 `A Timer is still pending...`，很难一眼看出是这个原因。
///
/// 改成「安静下来就停」：每轮等到有真正 IO 时让出 `smokeIoSlice`（`runAsync`
/// 走真实时钟，sqflite 的 Future 才有机会完成），再前进 `smokeSettleTick` 的
/// 假时钟把新排的 Timer 都触发掉。连续 [smokeQuietRounds] 轮都没再排帧，
/// 就认为稳定了；最多 [smokeMaxSettleRounds] 轮兜底，避免真的活着的动画把
/// 测试挂死（页面常驻 `LinearProgressIndicator` 时永远 settle 不了，所以不能
/// 用 `pumpAndSettle`）。
Future<void> smokeFinish(WidgetTester tester) async {
  var quiet = 0;
  for (var round = 0; round < smokeMaxSettleRounds; round++) {
    await tester.runAsync(() => Future<void>.delayed(smokeIoSlice));
    await tester.pump(smokeSettleTick);
    // 「还有活动」= 有排帧，或有正在跑的 ticker（转圈 / 录音波形这类）。
    // 真在动的页面永远安静不下来，靠 smokeMaxSettleRounds 兜底。
    if (tester.binding.hasScheduledFrame ||
        tester.binding.transientCallbackCount > 0) {
      quiet = 0;
      continue;
    }
    if (++quiet >= smokeQuietRounds) return;
  }
}

/// 每轮让真实 IO 走的时长（sqflite / 文件读写在这个窗口里完成）。
const Duration smokeIoSlice = Duration(milliseconds: 100);

/// 每轮推进的假时钟（把这一轮新排的 Timer 都触发掉）。
const Duration smokeSettleTick = Duration(milliseconds: 500);

/// 连续多少轮「没排帧」才算安静下来。取 2 是为了给「安静轮里才被创建、
/// 时长又不超过一轮」的 Timer 留一次机会。
const int smokeQuietRounds = 2;

/// 兜底上限：真有常驻定时器时别把测试挂死。
const int smokeMaxSettleRounds = 12;
