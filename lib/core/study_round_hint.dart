/// 背单词「空队列」的提示文案。
///
/// 单独放一个文件：`StudyViewModel` 的方法数已经贴着上帝类门禁（40），
/// 这几条文案是纯判断，挪出来后 ViewModel 只留一句 `_emptyRoundReason(...)` 的转发。
///
/// 原则：用户点了按钮什么都没发生，是最糟的体验 —— 所以每一条分支都要说清
/// 「为什么空」和「下一步去哪」。
library;

import '../models/vocab.dart';
import 'entry_kind.dart';
import 'study_pool.dart';
import 'study_prefs.dart';

/// 某个入口空队列时该说什么。
///
/// [deck] 决定用「词」还是「搭配」措辞；[articleId] 为空表示还没打开过文章。
String emptyRoundReason({
  required StudyEntry entry,
  required List<VocabItem> source,
  required StudyPrefs prefs,
  required StudyDeck deck,
  String? articleId,
}) {
  final thing = deck == StudyDeck.word ? '词' : '搭配';
  final noArticle = articleId == null || articleId.isEmpty;

  switch (entry) {
    case StudyEntry.learn:
      // 额度用完要单独说：池子里明明还有词，只是今天不许学了。
      if (prefs.newLimit > 0 &&
          prefs.remainingNew == 0 &&
          source.isNotEmpty) {
        return '今天的新词额度用完了（${prefs.newToday}/${prefs.newLimit}），'
            '明天再来，或去设置里调高上限';
      }
      if (noArticle) {
        return '还没打开过文章：先去精读里收几个$thing，回来就能学了';
      }
      if (source.isEmpty) {
        return '这篇还没有可学的$thing：先去精读里点词收词，再回来';
      }
      return '这篇的生$thing都学过了，去「复习」看看到期的';

    case StudyEntry.review:
      if (source.isEmpty) {
        return '没有到期的复习$thing：先去「学习」过一遍新$thing';
      }
      return '没有到期的复习$thing';

    case StudyEntry.recall:
      if (noArticle) {
        return '还没打开过文章：先去精读里读一篇';
      }
      if (source.isEmpty) {
        return '这篇还没有学过的$thing：先「学习」一轮再来回顾';
      }
      return '这篇没有可回顾的$thing';
  }
}
