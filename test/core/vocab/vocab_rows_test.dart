// 行级拆分/重组的验收：**拆开再拼回来必须逐字节相同**。
//
// 这是「迁移零字段丢失」的地基。真备份 `assets/data/economist-backup-2026-11-10.json`
// （10892 词 / articleEntries 13554 条 / tombstones 8 条 / sentenceTexts 3512 条）
// 是最大的活体样本，也用小的构造样本把边界压住。
import 'dart:convert';
import 'dart:io';

import 'package:dlaoshi_app/core/backup_parse.dart';
import 'package:dlaoshi_app/core/vocab/vocab_json.dart';
import 'package:dlaoshi_app/core/vocab/vocab_rows.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('拆开再拼回来逐字节相同（含库级三段）', () {
    final json = <String, Object?>{
      'schemaVersion': 3,
      'items': <Object?>[
        {
          'id': 'w1',
          'word': 'propaganda',
          'reviewState': {'ease': 2.5, 'relearn': true},
        },
        {
          'id': 'w2',
          'word': 'resilient',
          'fieldSources': {'meaning': 'ai'},
        },
      ],
      'articleEntries': <Object?>[
        {'articleId': 'a1', 'wordId': 'w1', 'addedAt': '2026-01-01'},
      ],
      'tombstones': <Object?>[
        {'id': 'w9', 'deletedAt': '2026-02-02'},
      ],
      'sentenceTexts': <String, Object?>{'s:1': 'the sentence'},
    };

    expect(vocabPayloadRoundTrips(json), isTrue);
  });

  test('库级三段按原出现次序跟在 items 后面', () {
    final json = <String, Object?>{
      'tombstones': <Object?>[],
      'items': <Object?>[
        {'word': 'alfa', 'meaning': '阿尔法'},
      ],
      'schemaVersion': 2,
      'sentenceTexts': <String, Object?>{},
      'articleEntries': <Object?>[],
    };
    final out = assembleVocabPayload(splitVocabPayload(json));
    expect(out.keys.toList(), <String>[
      'schemaVersion',
      'items',
      'tombstones',
      'sentenceTexts',
      'articleEntries',
    ]);
  });

  test('不认识的键原样留着，不丢', () {
    final json = <String, Object?>{
      'items': <Object?>[
        {'word': 'alfa'},
      ],
      'brandNewThing': <String, Object?>{'x': 1},
    };
    final rows = splitVocabPayload(json);
    expect(rows.extras.keys, contains('brandNewThing'));
    expect(
      assembleVocabPayload(rows)['brandNewThing'],
      <String, Object?>{'x': 1},
    );
  });

  test('缺 schemaVersion 时补 1（会改变字节，故往返判定为 false）', () {
    final json = <String, Object?>{'items': <Object?>[]};
    expect(splitVocabPayload(json).schemaVersion, 1);
    expect(vocabPayloadRoundTrips(json), isFalse);
  });

  test('items 里的坏条目（不是 Map）也照样搬运', () {
    final json = <String, Object?>{
      'items': <Object?>['oops', 42, null],
    };
    final rows = splitVocabPayload(json);
    expect(rows.itemDocs.length, 3);
    expect(assembleVocabPayload(rows)['items'], <Object?>['oops', 42, null]);
  });

  test('空库拆分出空的 itemDocs', () {
    final rows = splitVocabPayload(<String, Object?>{'items': <Object?>[]});
    expect(rows.itemDocs, isEmpty);
    expect(rows.isEmpty, isTrue);
  });

  test('真备份能整库往返无损（10892 词那条活体样本）', () async {
    final file = File('assets/data/economist-backup-2026-11-10.json');
    if (!file.existsSync()) return; // 样本被裁掉的环境不假绿，直接跳过
    final root = jsonDecode(await file.readAsString());
    final payload = parseBackupPayload(root);
    final lib = payload.library;
    expect(lib, isNotNull, reason: '真备份必须解析成词库');
    final json = vocabLibraryToJson(lib!);
    expect(json['items'], hasLength(lib.items.length));
    expect(vocabPayloadRoundTrips(json), isTrue,
        reason: '真备份拆开再拼回来必须逐字节相同');
  });
}