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
      expect(prefs.articleId, isNull);
      expect(prefs.pickedArticleIds, isEmpty);
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
        articleId: 'A1',
        pickedArticleIds: {'A1', 'A2'},
        days: {'2026-11-01'},
      );
      final back = parseVocabBrowsePrefs(vocabBrowsePrefsToJson(prefs));
      expect(back, isNotNull);
      expect(back!.scope, BrowseScope.picked);
      expect(back.kind, BrowseKind.lang);
      expect(back.status, BrowseStatus.lapsed);
      expect(back.sort, 'due');
      expect(back.includeMastered, isTrue);
      expect(back.articleId, 'A1');
      expect(back.pickedArticleIds, {'A1', 'A2'});
      expect(back.days, {'2026-11-01'});
    });

    test('articleId 为 null 时不写进 JSON', () {
      final json = vocabBrowsePrefsToJson(const VocabBrowsePrefs());
      expect(json.containsKey('articleId'), isFalse);
    });

    test('copyWith 能把 articleId 清成 null', () {
      const prefs = VocabBrowsePrefs(articleId: 'A1');
      expect(prefs.copyWith(articleId: () => null).articleId, isNull);
      expect(prefs.copyWith(articleId: () => 'B2').articleId, 'B2');
      expect(prefs.copyWith().articleId, 'A1', reason: '不传就保留');
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

    test('列表里的非字符串 / 空串剔掉', () {
      final back = parseVocabBrowsePrefs(<String, Object?>{
        'pickedArticleIds': ['A1', '', '  ', 7, null, ' A2 '],
        'days': 'not-a-list',
      })!;
      expect(back.pickedArticleIds, {'A1', 'A2'});
      expect(back.days, isEmpty);
    });

    test('articleId 是空白串当没选', () {
      final back = parseVocabBrowsePrefs(<String, Object?>{'articleId': '  '})!;
      expect(back.articleId, isNull);
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
