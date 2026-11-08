/// 学习记录「一份对象 → 各段 JSON 值」的翻译。
///
/// 写库那侧（`learning_write.dart`）刻意按 **JSON 形状** 处理：Web 版
/// `server/sqliteLearningWrite.ts` 就是这么写的，坏字段一律「当空 / 整条跳过」，
/// 从不抛错。Dart 里有强类型记录（[PracticeRecord] 等）反而要多写一遍守卫，
/// 所以这里先把强类型摊成 JSON 形状，再交给同一套写入函数 —— 两边只有一份守卫。
///
/// 反方向（行 → 对象）在 `learning_read.dart`，两边的字段名必须一一对上，
/// `learning_repository_test.dart` 用「写进去再读出来逐字段相等」盯着这条。
library;

import '../../core/activity/activity.dart';
import '../../core/learning.dart';

/// 取某一段的 JSON 值（各段形状与 Web 版 `LearningOut` 的字段一致）。
///
/// 五段长期资产（仿写 / 回译 / 金句 / 错因 / 工棚）本来就是原始 JSON 列表，
/// 原样返回、不做二次翻译。
Object? learningSectionJson(LearningData data, LearningSection key) => switch (key) {
      LearningSection.practice => <Object?>[
          for (final r in data.practice)
            <String, Object?>{
              'at': r.at,
              'kind': r.kind.name,
              'total': r.total,
              'correct': r.correct,
              if (r.seconds != null) 'seconds': r.seconds,
              if (r.articleId != null) 'articleId': r.articleId,
            },
        ],
      LearningSection.mistakes => <Object?>[
          for (final r in data.mistakes)
            <String, Object?>{
              'id': r.id,
              'kind': r.kind.name,
              'at': r.at,
              'count': r.count,
              'label': r.label,
              if (r.itemId != null) 'itemId': r.itemId,
              if (r.question != null) 'question': r.question!.toJson(),
              if (r.articleId != null) 'articleId': r.articleId,
              if (r.text != null) 'text': r.text,
            },
        ],
      LearningSection.readDone => <Object?>[
          for (final r in data.readDone)
            <String, Object?>{
              'day': r.day,
              'articleId': r.articleId,
              'title': r.title,
              'at': r.at,
            },
        ],
      LearningSection.writingHistory => data.writingHistory,
      LearningSection.backTranslations => data.backTranslations,
      LearningSection.retells => <Object?>[for (final r in data.retells) r.toJson()],
      LearningSection.activity => <Object?>[
          for (final r in data.activity)
            <String, Object?>{
              'day': r.day,
              'counts': <String, Object?>{
                for (final e in r.counts.entries) e.key.name: e.value,
              },
            },
        ],
      LearningSection.studyDays => <Object?>[
          for (final r in data.studyDays)
            <String, Object?>{'day': r.day, 'seconds': r.seconds, 'cards': r.cards},
        ],
      LearningSection.sessions => <Object?>[
          for (final r in data.sessions)
            <String, Object?>{'at': r.at, 'seconds': r.seconds, 'picked': r.picked},
        ],
      LearningSection.studiedDays => <Object?>[for (final r in data.studiedDays) r.toJson()],
      LearningSection.skimmed => List<String>.of(data.skimmed),
      LearningSection.kindStats => <String, Object?>{
          for (final e in data.kindStats.entries)
            e.key: <String, Object?>{
              for (final s in e.value.entries)
                s.key: <String, Object?>{'total': s.value.total, 'correct': s.value.correct},
            },
        },
      LearningSection.answerEvents => <Object?>[
          for (final e in data.answerEvents)
            <String, Object?>{
              'at': e.at,
              'day': e.day,
              'articleId': e.articleId,
              'source': e.source.name,
              'kind': e.kind,
              'cat': e.cat.name,
              'correct': e.correct,
              if (e.questionId != null) 'questionId': e.questionId,
            },
        ],
      LearningSection.goldenDrills => data.goldenDrills,
      LearningSection.writingErrorProgress => data.writingErrorProgress,
      LearningSection.productionProgress => data.productionProgress,
    };

/// 一份学习记录摊成 `section.name → JSON 值`（快照 / 导出 / 写入共用）。
Map<String, Object?> learningToJson(LearningData data) => <String, Object?>{
      for (final key in LearningSection.values) key.name: learningSectionJson(data, key),
    };

/// 活动聚合里出现过的分类（写 `activity_days` 时按它逐个落行）。
List<MapEntry<String, int>> activityCountEntries(DayActivity day) =>
    <MapEntry<String, int>>[
      for (final e in day.counts.entries) MapEntry<String, int>(e.key.name, e.value),
    ];
