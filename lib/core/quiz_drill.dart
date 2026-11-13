/// 「快速拷打」的分档规则（纯函数）。
///
/// Web 版有七档（`src/core/intensiveDrill.ts` + `src/reader/hooks/useIntensiveActions.ts`
/// 的 `DRILL_KINDS`）。这里先落三档能跑的（记忆 / 词块 / 错题包围战），
/// 其余四档保留枚举与文案 —— 界面要能把「还没做」说清楚，而不是干脆看不见。
///
/// 每档的题量各记各的（键 `reader:drillLimits`），默认 10 题。
library;

import 'quiz.dart';

/// 拷打分档。
enum QuizDrillKind {
  memory, // 记忆拷打：拼写 + 看词选义 + 词形辨析
  chunk, // 词块拷打：搭配填空 + 例句填空 + 搭配默写 + 介词填空 + 习语填空
  deep, // 英英释义
  mark, // 语法标记
  grammar, // 语法·结构（文章级）
  listen, // 听力
  siege, // 错题包围战（错题本混编，打到全对）
}

/// 每档对应的题型（照 Web `useIntensiveActions.ts:37-44`）。
const Map<QuizDrillKind, List<QuizKind>> quizDrillKinds = <QuizDrillKind, List<QuizKind>>{
  QuizDrillKind.memory: <QuizKind>[QuizKind.spell, QuizKind.meaning, QuizKind.choice],
  QuizDrillKind.chunk: <QuizKind>[
    QuizKind.usage,
    QuizKind.cloze,
    QuizKind.collocation,
    QuizKind.prep,
    QuizKind.idiom,
  ],
  QuizDrillKind.deep: <QuizKind>[QuizKind.define, QuizKind.defineChoice],
  QuizDrillKind.mark: <QuizKind>[QuizKind.mark],
  QuizDrillKind.grammar: <QuizKind>[
    QuizKind.grammar,
    QuizKind.phraseBlank,
    QuizKind.translate2,
    QuizKind.functionWord,
    QuizKind.ordering,
  ],
  QuizDrillKind.listen: <QuizKind>[QuizKind.listen],
  QuizDrillKind.siege: <QuizKind>[
    QuizKind.spell,
    QuizKind.meaning,
    QuizKind.choice,
    QuizKind.usage,
    QuizKind.cloze,
    QuizKind.collocation,
    QuizKind.prep,
  ],
};

const Map<QuizDrillKind, String> quizDrillLabel = <QuizDrillKind, String>{
  QuizDrillKind.memory: '记忆拷打',
  QuizDrillKind.chunk: '词块拷打',
  QuizDrillKind.deep: '英英释义',
  QuizDrillKind.mark: '语法标记',
  QuizDrillKind.grammar: '语法·结构',
  QuizDrillKind.listen: '听力拷打',
  QuizDrillKind.siege: '错题包围战',
};

const Map<QuizDrillKind, String> quizDrillHint = <QuizDrillKind, String>{
  QuizDrillKind.memory: '拼写 · 看词选义 · 词形辨析',
  QuizDrillKind.chunk: '搭配 · 例句 · 介词 · 习语',
  QuizDrillKind.deep: '英英释义，写出来或选出来',
  QuizDrillKind.mark: '可数 / 及物 / 可分级',
  QuizDrillKind.grammar: '中译英 · 结构 · 功能词 · 排序',
  QuizDrillKind.listen: '听音填空',
  QuizDrillKind.siege: '错题本混编，打到全对',
};

/// 首批能跑的档位（其余在界面上标「待开」）。
const List<QuizDrillKind> quizDrillReady = <QuizDrillKind>[
  QuizDrillKind.memory,
  QuizDrillKind.chunk,
  QuizDrillKind.siege,
];

/// 这一档能做吗。
bool quizDrillImplemented(QuizDrillKind kind) => quizDrillReady.contains(kind);

/// 题数档位（Web `DRILL_LIMIT_OPTIONS`）与默认值。
const List<int> drillLimitOptions = <int>[5, 10, 15, 20, 30];
const int defaultDrillLimit = 10;

/// 这个数是不是合法档位。
bool isDrillLimit(int n) => drillLimitOptions.contains(n);

/// 宽容解析：不在档位里就回默认 10（不做四舍五入 —— 5 和 10 差一倍）。
int normalizeDrillLimit(Object? raw) {
  if (raw is int) return isDrillLimit(raw) ? raw : defaultDrillLimit;
  if (raw is num) {
    final n = raw.toInt();
    return isDrillLimit(n) ? n : defaultDrillLimit;
  }
  if (raw is String) {
    final n = int.tryParse(raw.trim());
    if (n != null) return isDrillLimit(n) ? n : defaultDrillLimit;
  }
  return defaultDrillLimit;
}

/// 每档题量的存储键。
const String drillLimitsKey = 'reader:drillLimits';

/// 读一份「每档各多少题」。坏数据逐档回默认，不整份丢。
///
/// 兼容三种形状：`{"memory":10}`、旧版平铺 `{"memory":{"limit":10}}`、
/// 以及非 Map（回全默认）。
Map<QuizDrillKind, int> parseDrillLimits(Object? raw) {
  final out = <QuizDrillKind, int>{
    for (final k in QuizDrillKind.values) k: defaultDrillLimit,
  };
  if (raw is! Map) return out;
  for (final k in QuizDrillKind.values) {
    final v = raw[k.name];
    if (v is Map) {
      out[k] = normalizeDrillLimit(v['limit']);
    } else if (v != null) {
      out[k] = normalizeDrillLimit(v);
    }
  }
  return out;
}

/// 写回去（存平铺 int，读得回来）。
Map<String, Object?> drillLimitsToJson(Map<QuizDrillKind, int> limits) => <String, Object?>{
      for (final k in QuizDrillKind.values) k.name: normalizeDrillLimit(limits[k]),
    };

/// 一轮的题量：档位与「候选池里真能出多少」取小。
int drillRoundCount(int limit, int available) {
  final want = normalizeDrillLimit(limit);
  if (available <= 0) return 0;
  return want <= available ? want : available;
}
