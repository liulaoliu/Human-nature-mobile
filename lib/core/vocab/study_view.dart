import '../../models/vocab.dart';
import 'review.dart';

/// 当前卡与两道门禁的派生（纯函数）。
///
/// 优先取词库最新（评分 / 编辑后立刻反映），队列快照兜底；组末拼写测试时换成测试里的词。
/// 规则本身都在 `review.dart`，这里只负责「先看谁、再套哪条」。
/// 与 Web 版 `src/core/vocab/studyView.ts` 一一对应。
class StudyCardViewParams {
  const StudyCardViewParams({
    required this.library,
    required this.queue,
    required this.index,
    required this.roundTotal,
    required this.retrying,
    required this.meaningCleared,
    this.roundCard,
  });

  final VocabLibrary library;
  final List<VocabItem>? queue;
  final int index;

  /// 本轮总数（进度分母）；加练卡从它之后开始。
  final int roundTotal;

  /// 收尾「重练忘记的」：标过不认识的词也要先选释义。
  final bool retrying;

  /// 本卡是否已经通过「选中文释义」这一关。
  final bool meaningCleared;

  /// 组末拼写测试的当前词；非空时整页显示它。
  final VocabItem? roundCard;
}

class StudyCardView {
  const StudyCardView({
    required this.card,
    required this.isExtraCard,
    required this.relearning,
    required this.meaningRequired,
    required this.meaningGate,
  });

  final VocabItem? card;

  /// 忘记 / 模糊后被追加到队尾的加练卡。
  final bool isExtraCard;
  final bool relearning;
  final bool meaningRequired;
  final bool meaningGate;
}

StudyCardView studyCardView(StudyCardViewParams params) {
  final queue = params.queue;
  final index = params.index;
  VocabItem? card;
  if (params.roundCard != null) {
    card = params.roundCard;
  } else if (queue != null && index >= 0 && index < queue.length) {
    final snapshot = queue[index];
    VocabItem? latest;
    for (final it in params.library.items) {
      if (it.id == snapshot.id) {
        latest = it;
        break;
      }
    }
    card = latest ?? snapshot;
  }
  final isExtraCard = queue != null && params.roundTotal > 0 && index >= params.roundTotal;
  final relearning = card != null && isRelearning(card);
  final meaningRequired = card != null &&
      !relearning &&
      needsMeaningCheck(card, extra: isExtraCard, retrying: params.retrying) &&
      canQuizMeaning(card, params.library.items);
  return StudyCardView(
    card: card,
    isExtraCard: isExtraCard,
    relearning: relearning,
    meaningRequired: meaningRequired,
    meaningGate: meaningRequired && !params.meaningCleared,
  );
}
