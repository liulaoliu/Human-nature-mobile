import 'package:dlaoshi_app/core/vocab/library.dart';
import 'package:dlaoshi_app/core/vocab/tombstones.dart';
import 'package:dlaoshi_app/models/vocab.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/vocab_fixture.dart';

const now = '2026-10-24T12:00:00.000Z';

VocabLibrary _lib(List<VocabItem> items) => VocabLibrary(items: items);

VocabItem _bank({
  String? meaning,
  String createdAt = '2026-10-01T00:00:00.000Z',
  String updatedAt = '2026-10-01T00:00:00.000Z',
}) =>
    vocabItem(
      id: 'vocab:bank',
      word: 'bank',
      lemma: 'bank',
      meaning: meaning,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );

void main() {
  test('墓碑键格式', () {
    expect(itemTombstoneKey('v1'), 'item:v1');
    expect(articleTombstoneKey('art-1', 'bank'), 'article:art-1\u0000bank');
  });

  test('同一 key 只留最新时间的墓碑', () {
    var lib = addItemTombstone(_lib([_bank()]), _bank(), at: '2026-10-01T00:00:00.000Z');
    lib = addItemTombstone(lib, _bank(), at: now);
    expect(lib.tombstones, hasLength(1));
    expect(lib.tombstones.single.at, now);

    // 更旧的时间不会覆盖新的。
    final again = addItemTombstone(lib, _bank(), at: '2026-09-01T00:00:00.000Z');
    expect(again.tombstones.single.at, now);
  });

  test('mergeTombstones 取并集、同 key 留更晚', () {
    final a = [
      VocabTombstone(
        kind: VocabTombstoneKind.item,
        key: itemTombstoneKey('v1'),
        at: '2026-10-01T00:00:00.000Z',
      ),
    ];
    final b = [
      VocabTombstone(
        kind: VocabTombstoneKind.item,
        key: itemTombstoneKey('v1'),
        at: now,
      ),
      VocabTombstone(
        kind: VocabTombstoneKind.article,
        key: articleTombstoneKey('art-1', 'bank'),
        at: now,
      ),
    ];
    final out = mergeTombstones(a, b);
    expect(out, hasLength(2));
    expect(
      out.firstWhere((t) => t.key == itemTombstoneKey('v1')).at,
      now,
    );
  });

  test('applyTombstones 只删比墓碑旧的；空墓碑原样返回', () {
    final lib = _lib([_bank()]);
    expect(identical(applyTombstones(lib), lib), isTrue);

    final killed = addItemTombstone(lib, _bank(), at: now);
    expect(applyTombstones(killed).items, isEmpty);

    final readded = killed.copyWith(
      items: [_bank(updatedAt: '2999-01-01T00:00:00.000Z')],
    );
    expect(applyTombstones(readded).items, hasLength(1));
  });

  test('删全库词条会连带删掉各篇收录', () {
    final lib = VocabLibrary(
      items: [_bank()],
      articleEntries: [articleEntry(articleId: 'art-1', lemma: 'bank')],
    );
    final killed = addItemTombstone(lib, _bank(), at: now);
    expect(applyTombstones(killed).articleEntries, isEmpty);
  });

  test('篇墓碑只删那一篇那一条', () {
    final lib = VocabLibrary(
      items: [_bank()],
      articleEntries: [
        articleEntry(articleId: 'art-1', lemma: 'bank'),
        articleEntry(articleId: 'art-2', lemma: 'bank'),
      ],
    );
    final killed = addArticleTombstone(lib, 'art-1', 'bank', at: now);
    final out = applyTombstones(killed);
    expect(out.articleEntries.single.articleId, 'art-2');
  });

  test('librarySignature / sameLibrary 只看 id+lemma+updatedAt 等结构指纹', () {
    final a = _lib([_bank()]);
    final b = _lib([_bank()]);
    expect(sameLibrary(a, b), isTrue);

    // 只改释义不算「内容变了」：签名只用于判断要不要回写服务端，字段级差异由合并负责。
    expect(sameLibrary(a, _lib([_bank(meaning: '银行')])), isTrue);

    final newer = _lib([_bank(updatedAt: '2026-10-25T00:00:00.000Z')]);
    expect(sameLibrary(a, newer), isFalse);
    expect(librarySignature(a), isNotEmpty);
  });

  test('mergeLibrariesForSync 合并句子原文表（本机优先）', () {
    final local = _lib([_bank()]).copyWith(sentenceTexts: const {'k': '本机'});
    final server = _lib([_bank()]).copyWith(
      sentenceTexts: const {'k': '服务端', 'k2': '只服务端有'},
    );
    final merged = mergeLibrariesForSync(local, server);
    expect(merged.sentenceTexts['k'], '本机');
    expect(merged.sentenceTexts['k2'], '只服务端有');
  });
}
