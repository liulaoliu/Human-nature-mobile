import 'package:dlaoshi_app/core/vocab_browse.dart';
import 'package:dlaoshi_app/core/vocab_browse_prefs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('默认值', () {
    test('没存过时是「本篇 / 单词 / 复习 / 最近」', () {
      const prefs = VocabBrowsePrefs();
      expect(prefs.scope, BrowseScope.article);
      expect(prefs.kind, BrowseKind.word);
      expect(prefs.status, BrowseStatus.due);
      expect(prefs.sort, 'recent');
      expect(prefs.includeMastered, isFalse);
      expect(prefs.pickedArticleId, isNull);
      expect(prefs.days, isEmpty);
    });
  });

  group('往返', () {
    test('全套条件存了再读一模一样', () {
      const prefs = VocabBrowsePrefs(
        scope: BrowseScope.picked,
        kind: BrowseKind.lang,
        status: BrowseStatus.lapsed,
        sort: 'due',
        includeMastered: true,
        pickedArticleId: 'A1',
        days: {'2026-11-01'},
      );
      final back = parseVocabBrowsePrefs(vocabBrowsePrefsToJson(prefs));
      expect(back, isNotNull);
      expect(back!.scope, BrowseScope.picked);
      expect(back.kind, BrowseKind.lang);
      expect(back.status, BrowseStatus.lapsed);
      expect(back.sort, 'due');
      expect(back.includeMastered, isTrue);
      expect(back.pickedArticleId, 'A1');
      expect(back.days, {'2026-11-01'});
    });

    test('pickedArticleId 为 null 时不写进 JSON', () {
      final json = vocabBrowsePrefsToJson(const VocabBrowsePrefs());
      expect(json.containsKey('pickedArticleId'), isFalse);
    });

    test('copyWith 能把 pickedArticleId 清成 null', () {
      const prefs = VocabBrowsePrefs(pickedArticleId: 'A1');
      expect(prefs.copyWith(pickedArticleId: () => null).pickedArticleId, isNull);
      expect(prefs.copyWith(pickedArticleId: () => 'B2').pickedArticleId, 'B2');
      expect(prefs.copyWith().pickedArticleId, 'A1', reason: '不传就保留');
    });
  });

  group('坏数据', () {
    test('不是 Map：回 null（当没存过）', () {
      expect(parseVocabBrowsePrefs(null), isNull);
      expect(parseVocabBrowsePrefs('oops'), isNull);
      expect(parseVocabBrowsePrefs(<Object>[]), isNull);
    });

    test('空 Map：整份回默认', () {
      final back = parseVocabBrowsePrefs(<String, Object?>{})!;
      expect(back.scope, BrowseScope.article);
      expect(back.sort, 'recent');
      expect(back.includeMastered, isFalse);
    });

    test('枚举名对不上：那一项回默认，别的照旧', () {
      final back = parseVocabBrowsePrefs(<String, Object?>{
        'scope': 'nope',
        'kind': 'word',
        'status': 42,
        'sort': '  ',
      })!;
      expect(back.scope, BrowseScope.article);
      expect(back.kind, BrowseKind.word);
      expect(back.status, BrowseStatus.due);
      expect(back.sort, 'recent');
    });

    test('日期列表里的非字符串 / 空串剔掉', () {
      final back = parseVocabBrowsePrefs(<String, Object?>{
        'pickedArticleId': ' A1 ',
        'days': ['2026-11-01', '', '  ', 7, null, ' 2026-11-02 '],
      })!;
      expect(back.pickedArticleId, 'A1');
      expect(back.days, {'2026-11-01', '2026-11-02'});
    });

    test('pickedArticleId 是空白串当没选', () {
      final back = parseVocabBrowsePrefs(
        <String, Object?>{'pickedArticleId': '  '},
      )!;
      expect(back.pickedArticleId, isNull);
    });

    test('老版本存的 articleId / pickedArticleIds 不再生效', () {
      final back = parseVocabBrowsePrefs(<String, Object?>{
        'scope': 'article',
        'articleId': 'A1',
        'pickedArticleIds': ['A2', 'A3'],
      })!;
      expect(back.pickedArticleId, isNull, reason: '本篇归全局，词库不再存它');
    });

    test('includeMastered 只认 true，别的都当 false', () {
      expect(
        parseVocabBrowsePrefs(<String, Object?>{'includeMastered': 'true'})!
            .includeMastered,
        isFalse,
      );
      expect(
        parseVocabBrowsePrefs(<String, Object?>{'includeMastered': true})!
            .includeMastered,
        isTrue,
      );
    });
  });

  test('存储键是 vocab:browse', () {
    expect(vocabBrowsePrefsKey, 'vocab:browse');
  });
}
