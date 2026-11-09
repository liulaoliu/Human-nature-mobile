/// 「D老师奶牛工棚」的 ViewModel：设置 → 选目标块 → 出题 → 收尾落库。
///
/// 三层分工：
///   - **纯函数**在 `core/production*.dart`（选块、拼提示词、解析、判分、进度）；
///   - **本文件**负责「准备与收尾」：三份落盘（设置 / 会话草稿 / 练习记录）与出题；
///     一道题的作答 → 批改 → 跳过 → 重写在 [ProductionSession] 里；
///   - **界面**只读 getter、只调方法，不自己拼提示词、不自己算进度。
///
/// 为什么草稿要单独存：出题靠 AI，粘结果时可能切走半小时。草稿按「文章 + 吃法」
/// 各留一组（`productionDraftKey`），换吃法不会把暂停的那组顶掉。
library;

import 'package:flutter/foundation.dart';

import '../core/activity/activity.dart'
    show ActivityCat, addActivity, dayKeyLocal;
import '../core/learning.dart';
import '../core/production.dart';
import '../core/production_draft.dart';
import '../core/production_history.dart';
import '../core/production_prompts.dart';
import '../core/production_yogurt.dart';
import '../core/writing.dart';
import '../core/writing_record_json.dart';
import '../data/prefs_store.dart';
import '../data/repositories/learning_repository.dart';
import '../data/repositories/vocab_repository.dart';
import '../models/vocab.dart';
import 'production_session.dart';

/// 一次会话最多带几道题（AI 最多回 12 道，多留一点余量）。
const int productionMaxPrompts = 12;

/// 奶牛工棚页的 ViewModel。
class ProductionViewModel extends ChangeNotifier {
  ProductionViewModel({
    required VocabRepository vocab,
    required LearningRepository learning,
    PrefsStore? prefsStore,
  })  : _vocabRepo = vocab,
        _learningRepo = learning,
        _store = prefsStore ?? PrefsStore.memory() {
    session = ProductionSession(
      settingsOf: () => _settings,
      articleIdOf: () => articleId,
      articleTitleOf: () => _articleTitle,
      appendRecord: _appendRecord,
    )..addListener(_onSessionChanged);
  }

  final VocabRepository _vocabRepo;
  final LearningRepository _learningRepo;
  final PrefsStore _store;

  /// 一道题的生命周期（作答 / 批改 / 跳过 / 重写）。
  late final ProductionSession session;

  VocabLibrary _library = const VocabLibrary();
  List<WritingRecord> _history = const <WritingRecord>[];
  Map<String, ProductionDraft> _drafts = <String, ProductionDraft>{};
  ProductionSettings _settings = defaultProductionSettings;

  String _articleId = '';
  String _articleTitle = '';
  Set<String> _docLemmas = const <String>{};

  ProductionTargetPool _pool = const ProductionTargetPool();

  bool _busy = false;
  String? _error;
  String _notice = '';

  /// 当前设置（吃法 / 主题 / 难度 / 范围 / 题数）。
  ProductionSettings get settings => _settings;

  /// 当前词库（选目标块用）。
  VocabLibrary get library => _library;

  /// 全部仿写记录（含普通仿写 / 金句课）；本页只读其中 `production` 那批。
  List<WritingRecord> get history => _history;

  /// 暂停中的草稿表（键是 `文章::吃法`）。
  Map<String, ProductionDraft> get drafts => _drafts;

  /// 上一次选出来的目标块池（含「不够」提示）。
  ProductionTargetPool get pool => _pool;

  /// 正在读写。
  bool get busy => _busy;

  /// 出错原因（本层或会话层的，谁有先给谁）。
  String? get error => _error ?? session.error;

  /// 一次性提示（选块回退、句数不一致、草稿已存之类）。
  String get notice => _notice;

  /// 当前文章 id（`manual` 表示没挂在文章上）。
  String get articleId => _articleId.isEmpty ? 'manual' : _articleId;

  /// 有没有当前吃法的草稿可续。
  ProductionDraft? get resumableDraft {
    final draft = _drafts[productionDraftKey(articleId, _settings.mode)];
    if (draft == null || draft.prompts.isEmpty) return null;
    return draft;
  }

  /// 进度从记录现算，界面直接读这里。
  List<ProductionProgress> get progress =>
      deriveProductionProgress(productionRecords(_history));

  /// 初始化：读词库 + 读学习记录（含历史）+ 读设置 + 读草稿。
  Future<void> bootstrap() => _guard(() async {
        _library = await _vocabRepo.load() ?? const VocabLibrary();
        final data = await _learningRepo.load();
        _history = writingRecordsFromJson(data.writingHistory);
        _settings = _store.loadProductionSettings();
        _drafts = _store.loadProductionDrafts();
      });

  /// 挂在某篇文章上（「本篇」范围与参考文章标题都要它）。
  void setArticleContext(
    String? articleId, {
    String articleTitle = '',
    Set<String> docLemmas = const <String>{},
  }) {
    _articleId = articleId ?? '';
    _articleTitle = articleTitle;
    _docLemmas = docLemmas;
    notifyListeners();
  }

  /// 改设置并落盘（坏值已在 [normalizeProductionSettings] 挡过，这里直接存）。
  Future<void> updateSettings(ProductionSettings next) async {
    _settings = next;
    notifyListeners();
    try {
      await _store.saveProductionSettings(next);
    } catch (e) {
      _error = '设置存不进去：$e';
      notifyListeners();
    }
  }

  /// 选目标块。返回选到几个（0 就是没得练）。
  int buildTargets() {
    final s = _settings;
    final pool = buildProductionTargets(BuildProductionTargetsOptions(
      items: _library.items,
      scope: s.scope,
      articleIdentity: _articleId,
      docLemmas: _docLemmas,
      types: s.types,
      limit: s.promptCount * s.targetsPerPrompt,
      weakRatio: s.weakRatio,
      theme: s.topic,
      progress: _progressLikes(),
    ));
    _pool = pool;
    _notice = pool.note;
    notifyListeners();
    return pool.targets.length;
  }

  /// 拼「目标块题」的提示词（全脂 / 脱脂奶带词块时）。没选到目标块返回 null。
  String? buildPackPrompt() {
    final s = _settings;
    if (_pool.targets.isEmpty) {
      _error = '还没选到目标块，先点「选目标块」';
      notifyListeners();
      return null;
    }
    return buildProductionPackPrompt(BuildProductionPackInput(
      mode: s.mode,
      topic: s.topic,
      angle: s.angle,
      tone: s.tone,
      level: s.level,
      articleTitle: _articleTitle,
      targets: _pool.targets,
      promptCount: s.promptCount,
      targetsPerPrompt: s.targetsPerPrompt,
    ));
  }

  /// 拼「纯主题题」的提示词（不带本机词块时）。
  String buildTopicPrompt() => buildTopicPackPrompt(BuildTopicPackInput(
        topic: _settings.topic,
        angle: _settings.angle,
        tone: _settings.tone,
        level: _settings.level,
        articleTitle: _articleTitle,
        promptCount: _settings.promptCount,
        randomTopic: _settings.mode == ProductionMode.full &&
            !_settings.fullUseChunks,
      ));

  /// 粘回 AI 结果。成功返回 null，失败返回给用户看的中文原因。
  String? applyPack(String raw) {
    final s = _settings;
    final withTargets = s.mode != ProductionMode.yogurt &&
        (s.mode == ProductionMode.full ? s.fullUseChunks : s.skimUseChunks);
    final prompts = withTargets
        ? parseProductionPack(raw, _pool.targets, maxPrompts: productionMaxPrompts)
        : parseTopicPack(raw, maxPrompts: productionMaxPrompts);
    if (prompts == null) {
      _error = '没认出题目 JSON；请确认粘的是 AI 返回的 {"prompts":[...]}';
      notifyListeners();
      return _error;
    }
    final quality = withTargets
        ? validateProductionPack(
            prompts,
            s.promptCount,
            s.targetsPerPrompt,
            requireModel: s.variant != ProductionVariant.translate,
          )
        : validateTopicPack(prompts, s.promptCount);
    if (!quality.ok) {
      _error = quality.reason;
      notifyListeners();
      return quality.reason;
    }
    _error = null;
    _notice = '';
    session.begin(prompts);
    notifyListeners();
    return null;
  }

  /// 风味酸奶：把粘贴的中英对照拆成对子（不经过 AI）。
  YogurtPairResult? yogurtPairs() => pairYogurtTexts(
        _settings.sourceText,
        _settings.referenceText,
        mode: _settings.yogurtSplit,
      );

  /// 风味酸奶：编译成逐句题目。句数不一致时把 warning 放进 notice。
  String? buildYogurt() {
    final result = buildYogurtPrompts(
      _settings.sourceText,
      _settings.referenceText,
      direction: _settings.yogurtDirection,
      mode: _settings.yogurtSplit,
      paragraph: _settings.yogurtParagraph,
    );
    if (result == null) {
      _error = '原文和参考译文都要有内容，才能拆句';
      notifyListeners();
      return _error;
    }
    _error = null;
    _notice = result.warning;
    session.begin(result.prompts);
    notifyListeners();
    return null;
  }

  /// 风味酸奶重新拆句后，按当前题原文找回同一句（对子改了不该把题号甩到第 1 题）。
  void remapYogurt(List<YogurtPair> pairs) {
    if (!session.hasPrompts) return;
    final result = remapYogurtPrompts(
      session.prompts,
      session.index,
      pairs,
      direction: _settings.yogurtDirection,
      paragraph: _settings.yogurtParagraph,
      warning: _notice,
    );
    if (result == null) {
      session.begin(const <ProductionPrompt>[]);
      return;
    }
    _notice = result.warning;
    session.restore(result.prompts, result.index);
  }

  /// 暂停：把当前题 / 作答 / 批改存成草稿（按「文章 + 吃法」一组）。
  Future<void> saveDraft() async {
    if (!session.hasPrompts) return;
    final key = productionDraftKey(articleId, _settings.mode);
    final draft = ProductionDraft(
      sessionId: session.task?.sessionId ?? '',
      articleId: articleId,
      at: DateTime.now().toUtc().toIso8601String(),
      mode: _settings.mode,
      sessionTopic: _settings.topic,
      prompts: session.prompts,
      index: session.index,
      answer: session.answer,
      feedback: session.feedback?.toJson(),
      previousFeedback: session.previousFeedback?.toJson(),
      hits: session.task?.hits ?? const <ProductionTargetHit>[],
      round: session.round,
      notice: _notice,
    );
    _drafts = mergeProductionDraftMaps(
      _drafts,
      <String, ProductionDraft>{key: draft},
    );
    notifyListeners();
    try {
      await _store.saveProductionDrafts(_drafts);
      _notice = '已暂停，下次进「${productionModeLabel[_settings.mode]}」会接着做';
    } catch (e) {
      _error = '草稿存不进去：$e';
    }
    notifyListeners();
  }

  /// 接着上次做。
  void resumeDraft() {
    final draft = resumableDraft;
    if (draft == null) return;
    _notice = draft.notice;
    _error = null;
    session.hydrate(draft);
    notifyListeners();
  }

  /// 丢掉当前吃法的草稿。
  Future<void> discardDraft() async {
    final key = productionDraftKey(articleId, _settings.mode);
    if (!_drafts.containsKey(key)) return;
    _drafts = <String, ProductionDraft>{..._drafts}..remove(key);
    notifyListeners();
    try {
      await _store.saveProductionDrafts(_drafts);
    } catch (e) {
      _error = '草稿删不掉：$e';
      notifyListeners();
    }
  }

  /// 清掉一次性提示与错误。
  void clearNotice() {
    final hadError = _error != null || session.error != null;
    if (_notice.isEmpty && !hadError) return;
    _notice = '';
    _error = null;
    session.clearError();
    notifyListeners();
  }

  @override
  void dispose() {
    session
      ..removeListener(_onSessionChanged)
      ..dispose();
    super.dispose();
  }

  /// 会话层改了（作答 / 批改 / 换题）→ 页面跟着重建。
  void _onSessionChanged() => notifyListeners();

  List<ProductionProgressLike> _progressLikes() => <ProductionProgressLike>[
        for (final p in progress)
          ProductionProgressLike(
            key: p.key,
            kind: p.kind,
            text: p.text,
            attempts: p.attempts,
            hits: p.hits,
            misses: p.misses,
            dueAt: p.dueAt,
            lastAt: p.lastAt,
          ),
      ];

  /// 追加一条记录并落盘（整段重写：`writing_records` 是先清后插）。
  ///
  /// 重复粘回同一份批改不刷历史（同题 / 同稿 / 同文字只留一条）；真写了才算
  /// 今天的「写」活动 —— 跳过稿照 Web `skip()` 的语义**不记账**。
  Future<bool> _appendRecord(WritingRecord record) async {
    final next = hasSameWritingAttempt(_history, record)
        ? _history
        : addWritingRecord(_history, record);
    final appended = next.length != _history.length;
    final counted = appended && productionTaskOf(record)?.skipped != true;
    try {
      final data = await _learningRepo.load();
      data.writingHistory = writingRecordsToJson(next);
      if (counted) {
        data.activity = addActivity(
          data.activity,
          dayKeyLocal(),
          ActivityCat.write,
        );
      }
      await _learningRepo.write(data, <LearningSection>[
        LearningSection.writingHistory,
        if (counted) LearningSection.activity,
      ]);
      _history = next;
      notifyListeners();
      return true;
    } catch (e) {
      _error = '记录存不进去：$e';
      notifyListeners();
      return false;
    }
  }

  Future<void> _guard(Future<void> Function() body) async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await body();
    } catch (e) {
      _error = '$e';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}
