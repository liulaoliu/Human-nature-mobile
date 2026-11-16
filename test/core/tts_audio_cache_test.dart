import 'dart:convert';

import 'package:dlaoshi_app/core/tts_audio_cache.dart';
import 'package:dlaoshi_app/models/tts_audio.dart';
import 'package:flutter_test/flutter_test.dart';

TtsAudioEntry _entry({
  String articleId = 'saved:1',
  String voice = 'af_heart',
  String revision = 'rev',
  int lastUsedMs = 1000,
  Map<String, String>? files,
}) {
  return TtsAudioEntry(
    articleId: articleId,
    title: 'Title $articleId',
    voice: voice,
    revision: revision,
    createdAtMs: 500,
    lastUsedMs: lastUsedMs,
    bytes: 1200,
    sentenceCount: 3,
    files: files ?? {'deadbeef': 'deadbeef.aac'},
  );
}

void main() {
  group('ttsAudioKey', () {
    test('同样输入永远同一个 key', () {
      final a = ttsAudioKey('Hello world.', 'af_heart', 'rev');
      final b = ttsAudioKey('Hello world.', 'af_heart', 'rev');
      expect(a, b);
      expect(a, matches(RegExp(r'^[0-9a-f]{8}$')));
    });

    test('文本 / 音色 / 版本任一变化都换 key', () {
      final base = ttsAudioKey('Hello world.', 'af_heart', 'rev');
      expect(ttsAudioKey('Hello world!', 'af_heart', 'rev'), isNot(base));
      expect(ttsAudioKey('Hello world.', 'am_michael', 'rev'), isNot(base));
      expect(ttsAudioKey('Hello world.', 'af_heart', 'rev2'), isNot(base));
    });

    test('文件名固定为 key.aac', () {
      final key = ttsAudioKey('x', 'af_heart', 'rev');
      expect(ttsAudioFileName('x', 'af_heart', 'rev'), '$key.aac');
    });
  });

  group('ttsAudioArticleDirName', () {
    test('冒号等字符被替换，且稳定', () {
      final a = ttsAudioArticleDirName('saved:1792152675652');
      final b = ttsAudioArticleDirName('saved:1792152675652');
      expect(a, b);
      expect(a, isNot(contains(':')));
      expect(a, matches(RegExp(r'^[A-Za-z0-9._-]+$')));
    });

    test('不同 id 不会撞目录', () {
      expect(
        ttsAudioArticleDirName('saved:1'),
        isNot(ttsAudioArticleDirName('saved:2')),
      );
    });
  });

  group('estimateTtsAudioBytes', () {
    test('150 词按 150wpm 约 1 分钟，64kbps 约 480000 字节', () {
      final text = List.filled(150, 'word').join(' ');
      expect(estimateTtsAudioBytes(text), 480000);
    });

    test('空文本是 0', () {
      expect(estimateTtsAudioBytes('   '), 0);
      expect(estimateTtsAudioBytes('中文没有英文词'), 0);
    });

    test('词越多估得越大', () {
      expect(
        estimateTtsAudioBytes('one two three'),
        lessThan(estimateTtsAudioBytes('one two three four five six')),
      );
    });
  });

  group('formatTtsAudioBytes', () {
    test('B / KB / MB', () {
      expect(formatTtsAudioBytes(0), '0 B');
      expect(formatTtsAudioBytes(1024), '1 KB');
      expect(formatTtsAudioBytes(1536 * 1024), '1.5 MB');
    });
  });

  group('ttsAudioEvictions', () {
    test('不超过上限不淘汰', () {
      expect(
        ttsAudioEvictions([
          _entry(articleId: 'a'),
          _entry(articleId: 'b'),
        ], keepArticleId: 'a'),
        isEmpty,
      );
    });

    test('第三篇进来淘汰最久没用的', () {
      final evicted = ttsAudioEvictions([
        _entry(articleId: 'old', lastUsedMs: 100),
        _entry(articleId: 'mid', lastUsedMs: 200),
        _entry(articleId: 'new', lastUsedMs: 300),
      ], keepArticleId: 'new');
      expect(evicted, ['old']);
    });

    test('正在看的那篇永远保留，哪怕最旧', () {
      final evicted = ttsAudioEvictions([
        _entry(articleId: 'current', lastUsedMs: 100),
        _entry(articleId: 'b', lastUsedMs: 200),
        _entry(articleId: 'c', lastUsedMs: 300),
      ], keepArticleId: 'current');
      expect(evicted, ['b']);
    });

    test('时间相同按 id 排序，结果确定', () {
      final evicted = ttsAudioEvictions([
        _entry(articleId: 'b', lastUsedMs: 100),
        _entry(articleId: 'a', lastUsedMs: 100),
        _entry(articleId: 'c', lastUsedMs: 100),
      ], keepArticleId: 'c');
      expect(evicted, ['a']);
    });
  });

  group('parseTtsAudioIndex', () {
    test('编码后再解析能还原', () {
      final index = TtsAudioIndex(
        articles: [
          _entry(articleId: 'a'),
          _entry(articleId: 'b', voice: 'am_michael', lastUsedMs: 200),
        ],
      );
      final parsed = parseTtsAudioIndex(encodeTtsAudioIndex(index));
      expect(parsed.dropped, 0);
      expect(parsed.index.articles, index.articles);
    });

    test('坏 JSON / 错版本按空索引处理', () {
      expect(parseTtsAudioIndex('{oops').dropped, 1);
      expect(parseTtsAudioIndex('[]').dropped, 1);
      expect(
        parseTtsAudioIndex(jsonEncode({'version': 2, 'articles': []})).dropped,
        1,
      );
    });

    test('坏条目逐条丢弃，好条目留下', () {
      final good = _entry(articleId: 'good');
      final entriesJson =
          (ttsAudioIndexToJson(
                    TtsAudioIndex(articles: [good]),
                  )['articles']
                  as List)
              .cast<Map>();
      final parsed = parseTtsAudioIndex(
        jsonEncode({
          'version': 1,
          'articles': [
            ...entriesJson,
            {'articleId': ''},
            {'articleId': 'x', 'files': 'bad'},
          ],
        }),
      );
      expect(parsed.index.articles.length, 1);
      expect(parsed.index.articles.single.articleId, 'good');
      expect(parsed.dropped, 2);
    });

    test('文件名带路径穿越一律拒绝', () {
      final bad = _entry(files: {'deadbeef': '../evil.aac'});
      final entriesJson =
          (ttsAudioIndexToJson(
                    TtsAudioIndex(articles: [bad]),
                  )['articles']
                  as List)
              .cast<Map>();
      final parsed = parseTtsAudioIndex(
        jsonEncode({'version': 1, 'articles': entriesJson}),
      );
      expect(parsed.index.articles, isEmpty);
      expect(parsed.dropped, 1);
    });
  });
}
