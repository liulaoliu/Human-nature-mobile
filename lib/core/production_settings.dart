/// 「D老师奶牛工棚」的设置层：吃法 / 方向 / 难度 / 范围 / 题型等枚举与守卫。
///
/// 为什么单独一个文件：设置要存 SharedPreferences、要能被旧备份喂进来，
/// 是「外部输入」的第一道关；把它和「选词块 / 判分」的纯逻辑分开，
/// 改设置口径时不用翻整个产出训练。
///
/// 对应 Web 版 `src/core/production.ts` 的前半部分，语义逐条对齐。
library;

/// 三种吃法：
///
/// - [full]（全脂）：不设主题，按配置随机抽词块，AI 随机出情境；
/// - [skim]（脱脂奶）：围绕一个主题出情境，同样要求用上目标块；
/// - [yogurt]（风味酸奶）：用户粘贴中英对照，按句拆开逐句翻译。
enum ProductionMode { full, skim, yogurt }

/// 吃法的中文名（设置面板、提示词都用它）。
const Map<ProductionMode, String> productionModeLabel = <ProductionMode, String>{
  ProductionMode.full: '全脂',
  ProductionMode.skim: '脱脂奶',
  ProductionMode.yogurt: '风味酸奶',
};

/// 吃法的一句话说明（设置卡片副标题）。
const Map<ProductionMode, String> productionModeDesc = <ProductionMode, String>{
  ProductionMode.full: '不写主题；AI 随机定主题，可选从本机词库抽词 / 词组。',
  ProductionMode.skim: '先写主题；可选带上本机词 / 词组 / 习语，不选就纯主题出句。',
  ProductionMode.yogurt: '粘贴中文原文和英文参考译文；按句拆开，逐句翻译，批改后再重写。',
};

/// 翻译方向：默认中译英；风味酸奶可反过来练英译中。
enum ProductionDirection { zhEn, enZh }

/// 拆句方式：按句号问号分句，还是按行分。
enum YogurtSplitMode { sentence, line }

/// 难度档。
enum ProductionLevel { b1, b2, c1 }

/// 难度的中文名。
const Map<ProductionLevel, String> productionLevelLabel =
    <ProductionLevel, String>{
  ProductionLevel.b1: 'B1 基础',
  ProductionLevel.b2: 'B2 中阶',
  ProductionLevel.c1: 'C1 进阶',
};

/// 题型的提示方式：直接写 / 参考句挖空 / 参考句词序打乱。
enum ProductionVariant { translate, cloze, reorder }

/// 题型的提示方式中文名。
const Map<ProductionVariant, String> productionVariantLabel =
    <ProductionVariant, String>{
  ProductionVariant.translate: '给中文写英文',
  ProductionVariant.cloze: '参考句挖空',
  ProductionVariant.reorder: '参考句词序打乱',
};

/// 出题的「角度」。
enum ProductionAngle { daily, work, opinion, story, email }

/// 出题角度中文名。
const Map<ProductionAngle, String> productionAngleLabel =
    <ProductionAngle, String>{
  ProductionAngle.daily: '日常生活',
  ProductionAngle.work: '工作沟通',
  ProductionAngle.opinion: '表达观点',
  ProductionAngle.story: '讲一件事',
  ProductionAngle.email: '邮件 / 消息',
};

/// 语气。
enum ProductionTone { neutral, formal, casual }

/// 语气中文名。
const Map<ProductionTone, String> productionToneLabel = <ProductionTone, String>{
  ProductionTone.neutral: '中性',
  ProductionTone.formal: '正式',
  ProductionTone.casual: '口语',
};

/// 目标块范围。
enum ProductionScope { article, all, recent, weak, due, mistakes, theme }

/// 目标块范围中文名。
const Map<ProductionScope, String> productionScopeLabel =
    <ProductionScope, String>{
  ProductionScope.article: '本篇（有上下文）',
  ProductionScope.all: '全库（练迁移）',
  ProductionScope.recent: '最近练过',
  ProductionScope.weak: '薄弱',
  ProductionScope.due: '到期',
  ProductionScope.mistakes: '用错过',
  ProductionScope.theme: '匹配主题',
};

/// 目标块类型（只有这三类能进产出训练，用法笔记不进）。
enum ProductionTargetKind { word, phrase, idiom }

/// 可选的题数。
const List<int> productionPromptCounts = <int>[3, 5, 8];

/// 每题可选的目标块个数。
const List<int> productionTargetsPerPrompt = <int>[1, 2, 3];

/// 可选的「薄弱比例」。
const List<int> productionWeakRatios = <int>[0, 30, 50, 70];

/// 一天从「到期」范围最多抽几个目标块，避免一次清几百个。
const int productionDueDailyCap = 6;
/// 产出训练的设置（整块可序列化，存 SharedPreferences）。
class ProductionSettings {
  const ProductionSettings({
    this.mode = ProductionMode.full,
    this.topic = '',
    this.angle = ProductionAngle.daily,
    this.tone = ProductionTone.neutral,
    this.level = ProductionLevel.b2,
    this.variant = ProductionVariant.translate,
    this.scope = ProductionScope.article,
    this.types = const <ProductionTargetKind>[
      ProductionTargetKind.word,
      ProductionTargetKind.phrase,
      ProductionTargetKind.idiom,
    ],
    this.promptCount = 5,
    this.targetsPerPrompt = 2,
    this.weakRatio = 30,
    this.fullUseChunks = true,
    this.skimUseChunks = false,
    this.sourceText = '',
    this.referenceText = '',
    this.yogurtDirection = ProductionDirection.zhEn,
    this.yogurtSplit = YogurtSplitMode.sentence,
    this.yogurtParagraph = true,
  });

  final ProductionMode mode;
  final String topic;
  final ProductionAngle angle;
  final ProductionTone tone;
  final ProductionLevel level;
  final ProductionVariant variant;
  final ProductionScope scope;
  final List<ProductionTargetKind> types;
  final int promptCount;
  final int targetsPerPrompt;
  final int weakRatio;

  /// 全脂是否带本机词块；关掉就是纯随机主题。
  final bool fullUseChunks;

  /// 脱脂奶是否带本机词块；默认关，选中后和全脂一样用目标块硬校验。
  final bool skimUseChunks;

  /// 风味酸奶草稿：原文 / 参考译文。体量不大，跟设置一起留在本机。
  final String sourceText;
  final String referenceText;
  final ProductionDirection yogurtDirection;
  final YogurtSplitMode yogurtSplit;

  /// 逐句结束后再加一道整段连写。
  final bool yogurtParagraph;

  ProductionSettings copyWith({
    ProductionMode? mode,
    String? topic,
    ProductionAngle? angle,
    ProductionTone? tone,
    ProductionLevel? level,
    ProductionVariant? variant,
    ProductionScope? scope,
    List<ProductionTargetKind>? types,
    int? promptCount,
    int? targetsPerPrompt,
    int? weakRatio,
    bool? fullUseChunks,
    bool? skimUseChunks,
    String? sourceText,
    String? referenceText,
    ProductionDirection? yogurtDirection,
    YogurtSplitMode? yogurtSplit,
    bool? yogurtParagraph,
  }) =>
      ProductionSettings(
        mode: mode ?? this.mode,
        topic: topic ?? this.topic,
        angle: angle ?? this.angle,
        tone: tone ?? this.tone,
        level: level ?? this.level,
        variant: variant ?? this.variant,
        scope: scope ?? this.scope,
        types: types ?? this.types,
        promptCount: promptCount ?? this.promptCount,
        targetsPerPrompt: targetsPerPrompt ?? this.targetsPerPrompt,
        weakRatio: weakRatio ?? this.weakRatio,
        fullUseChunks: fullUseChunks ?? this.fullUseChunks,
        skimUseChunks: skimUseChunks ?? this.skimUseChunks,
        sourceText: sourceText ?? this.sourceText,
        referenceText: referenceText ?? this.referenceText,
        yogurtDirection: yogurtDirection ?? this.yogurtDirection,
        yogurtSplit: yogurtSplit ?? this.yogurtSplit,
        yogurtParagraph: yogurtParagraph ?? this.yogurtParagraph,
      );

  @override
  bool operator ==(Object other) =>
      other is ProductionSettings &&
      other.mode == mode &&
      other.topic == topic &&
      other.angle == angle &&
      other.tone == tone &&
      other.level == level &&
      other.variant == variant &&
      other.scope == scope &&
      _sameKinds(other.types, types) &&
      other.promptCount == promptCount &&
      other.targetsPerPrompt == targetsPerPrompt &&
      other.weakRatio == weakRatio &&
      other.fullUseChunks == fullUseChunks &&
      other.skimUseChunks == skimUseChunks &&
      other.sourceText == sourceText &&
      other.referenceText == referenceText &&
      other.yogurtDirection == yogurtDirection &&
      other.yogurtSplit == yogurtSplit &&
      other.yogurtParagraph == yogurtParagraph;

  @override
  int get hashCode => Object.hash(
        mode,
        topic,
        angle,
        tone,
        level,
        variant,
        scope,
        promptCount,
        targetsPerPrompt,
        weakRatio,
        fullUseChunks,
        skimUseChunks,
        yogurtDirection,
        yogurtSplit,
        yogurtParagraph,
      );
}

bool _sameKinds(List<ProductionTargetKind> a, List<ProductionTargetKind> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// 默认设置。
const ProductionSettings defaultProductionSettings = ProductionSettings();

/// 外部输入（SharedPreferences / 旧备份）守卫：坏字段逐项回默认，不炸整页。
ProductionSettings normalizeProductionSettings(Object? raw) {
  if (raw is! Map) return defaultProductionSettings;
  var out = defaultProductionSettings;

  final mode = _enumByName(ProductionMode.values, raw['mode']);
  if (mode != null) out = out.copyWith(mode: mode);
  if (raw['topic'] is String) {
    out = out.copyWith(topic: _clip((raw['topic'] as String).trim(), 200));
  }
  if (raw['sourceText'] is String) {
    out = out.copyWith(sourceText: _clip(raw['sourceText'] as String, 50000));
  }
  if (raw['referenceText'] is String) {
    out = out.copyWith(referenceText: _clip(raw['referenceText'] as String, 50000));
  }
  final dir = _enumByName(ProductionDirection.values, raw['yogurtDirection']);
  if (dir != null) out = out.copyWith(yogurtDirection: dir);
  final split = _enumByName(YogurtSplitMode.values, raw['yogurtSplit']);
  if (split != null) out = out.copyWith(yogurtSplit: split);
  if (raw['yogurtParagraph'] is bool) {
    out = out.copyWith(yogurtParagraph: raw['yogurtParagraph'] as bool);
  }
  if (raw['fullUseChunks'] is bool) {
    out = out.copyWith(fullUseChunks: raw['fullUseChunks'] as bool);
  }
  if (raw['skimUseChunks'] is bool) {
    out = out.copyWith(skimUseChunks: raw['skimUseChunks'] as bool);
  }
  final angle = _enumByName(ProductionAngle.values, raw['angle']);
  if (angle != null) out = out.copyWith(angle: angle);
  final tone = _enumByName(ProductionTone.values, raw['tone']);
  if (tone != null) out = out.copyWith(tone: tone);
  final level = _enumByName(ProductionLevel.values, raw['level']);
  if (level != null) out = out.copyWith(level: level);
  final variant = _enumByName(ProductionVariant.values, raw['variant']);
  if (variant != null) out = out.copyWith(variant: variant);
  final scope = _enumByName(ProductionScope.values, raw['scope']);
  if (scope != null) out = out.copyWith(scope: scope);

  final rawTypes = raw['types'];
  if (rawTypes is List) {
    final types = <ProductionTargetKind>[];
    for (final t in rawTypes) {
      final k = _enumByName(ProductionTargetKind.values, t);
      if (k != null && !types.contains(k)) types.add(k);
    }
    if (types.isNotEmpty) out = out.copyWith(types: types);
  }
  final count = raw['promptCount'];
  if (count is num && productionPromptCounts.contains(count.toInt())) {
    out = out.copyWith(promptCount: count.toInt());
  }
  final perPrompt = raw['targetsPerPrompt'];
  if (perPrompt is num &&
      productionTargetsPerPrompt.contains(perPrompt.toInt())) {
    out = out.copyWith(targetsPerPrompt: perPrompt.toInt());
  }
  final weak = raw['weakRatio'];
  if (weak is num && productionWeakRatios.contains(weak.toInt())) {
    out = out.copyWith(weakRatio: weak.toInt());
  }
  return out;
}

/// 设置序列化成可存进 SharedPreferences 的 Map。
Map<String, Object?> productionSettingsToJson(ProductionSettings s) =>
    <String, Object?>{
      'mode': s.mode.name,
      'topic': s.topic,
      'angle': s.angle.name,
      'tone': s.tone.name,
      'level': s.level.name,
      'variant': s.variant.name,
      'scope': s.scope.name,
      'types': <String>[for (final t in s.types) t.name],
      'promptCount': s.promptCount,
      'targetsPerPrompt': s.targetsPerPrompt,
      'weakRatio': s.weakRatio,
      'fullUseChunks': s.fullUseChunks,
      'skimUseChunks': s.skimUseChunks,
      'sourceText': s.sourceText,
      'referenceText': s.referenceText,
      'yogurtDirection': s.yogurtDirection.name,
      'yogurtSplit': s.yogurtSplit.name,
      'yogurtParagraph': s.yogurtParagraph,
    };
T? _enumByName<T extends Enum>(List<T> values, Object? raw) {
  if (raw is! String) return null;
  for (final v in values) {
    if (v.name == raw) return v;
  }
  return null;
}

String _clip(String s, int max) => s.length <= max ? s : s.substring(0, max);
