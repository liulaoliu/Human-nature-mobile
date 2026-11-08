/// 派生投影：把 `vocab` / `articles` 的 JSON payload 摊到可查询的关系表里。
///
/// 为什么单独一层：事实来源永远是 JSON payload，派生表只是「同一次事务里重建的副本」。
/// 重建逻辑全是 db 语句，混在 [ensureSchema] 里很难看出「哪些是事实、哪些是投影」。
///
/// 这里只接 [DatabaseExecutor]、不持有连接、不管事务 —— 事务由调用方包。
/// 对应 Web 版 `server/sqliteProjection.ts` + `server/sqliteVocab.ts`。
library;

import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'sql_util.dart';

/// 词条的挂靠表（删词条时按这些先删，再删 `words`）。
const List<String> wordChildTables = <String>[
  'word_usage',
  'word_phrases',
  'word_idioms',
  'word_tags',
  'word_grammar_marks',
  'word_examples',
  'word_contexts',
  'word_confusables',
];

/// `vocab.payload` / `articles.payload` 是 TEXT，形状不可信；
/// 这里只做「字符串 → JSON」，返回 `Object?` 由下游统一收窄。
Object? parsePayload(Object? payload) {
  if (payload == null) return null;
  final raw = payload is String ? payload : payload.toString();
  try {
    return jsonDecode(raw);
  } catch (_) {
    return null;
  }
}

/// 删一篇文章的全部派生行（按外键顺序，先删词条再删挂靠表）。
Future<void> deleteArticleProjection(DatabaseExecutor db, String articleId) async {
  await db.rawDelete(
    'DELETE FROM lang_point_terms WHERE lang_point_id IN '
    '(SELECT id FROM lang_points WHERE article_id = ?)',
    <Object?>[articleId],
  );
  for (final table in <String>[
    'lang_points',
    'article_collocations',
    'article_sentence_vocab',
    'article_sentence_tags',
    'article_sentences',
    'article_paragraph_sentences',
    'article_paragraphs',
  ]) {
    await db.rawDelete('DELETE FROM $table WHERE article_id = ?', <Object?>[articleId]);
  }
}

/// 文章 JSON → `article_sentences` / `lang_points` / ... 派生表。
Future<void> rebuildArticleProjection(DatabaseExecutor db, Object? article) async {
  final art = asRecord(article);
  final articleId = asText(art?['id']) ?? '';
  await deleteArticleProjection(db, articleId);

  // paragraphs[{id, sentenceIds}]
  final paragraphs = asList<Object?>(art?['paragraphs']);
  for (var pi = 0; pi < paragraphs.length; pi++) {
    final p = asRecord(paragraphs[pi]);
    if (p == null) continue;
    final pid = asText(p['id']) ?? 'p${pi + 1}';
    await db.rawInsert(
      'INSERT INTO article_paragraphs (article_id, id, ordinal) VALUES (?, ?, ?)',
      <Object?>[articleId, pid, pi],
    );
    final sids = asList<Object?>(p['sentenceIds']);
    for (var si = 0; si < sids.length; si++) {
      await db.rawInsert(
        'INSERT INTO article_paragraph_sentences '
        '(article_id, paragraph_id, sentence_id, ordinal) VALUES (?, ?, ?, ?)',
        <Object?>[articleId, pid, asText(sids[si]) ?? '', si],
      );
    }
  }

  final sentences = asList<Object?>(art?['sentences']);
  for (var si = 0; si < sentences.length; si++) {
    final s = asRecord(sentences[si]);
    if (s == null) continue;
    final sid = asText(s['id']) ?? 's${si + 1}';
    // reviewState 只认对象（数组也放行，读字段全是 null），与原判断一致。
    final review = asRecord(s['reviewState']) ?? const <String, Object?>{};
    final audio = asRecord(s['audio']);
    await db.rawInsert(
      'INSERT OR REPLACE INTO article_sentences ('
      'article_id, id, para_id, ordinal, text, audio_start, audio_end, translation, grammar_note, '
      'review_ease, review_due, review_interval, review_repetitions, review_lapses'
      ') VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      <Object?>[
        articleId,
        sid,
        asText(s['paraId']) ?? '',
        si,
        asText(s['text']) ?? '',
        audio == null ? null : asNum(audio['start']),
        audio == null ? null : asNum(audio['end']),
        asText(s['translation']),
        asText(s['grammarNote']),
        asNum(review['ease'], 2.5),
        asText(review['due']),
        asNum(review['interval']),
        asNum(review['repetitions']),
        asNum(review['lapses']),
      ],
    );

    final collocations = asList<Object?>(s['collocations']);
    for (var i = 0; i < collocations.length; i++) {
      await db.rawInsert(
        'INSERT INTO article_collocations (article_id, sentence_id, ordinal, text) '
        'VALUES (?, ?, ?, ?)',
        <Object?>[articleId, sid, i, asText(collocations[i]) ?? ''],
      );
    }
    final vocab = asList<Object?>(s['vocab']);
    for (var i = 0; i < vocab.length; i++) {
      await db.rawInsert(
        'INSERT INTO article_sentence_vocab (article_id, sentence_id, ordinal, word) '
        'VALUES (?, ?, ?, ?)',
        <Object?>[articleId, sid, i, asText(vocab[i]) ?? ''],
      );
    }
    final tags = asList<Object?>(s['tags']);
    for (var i = 0; i < tags.length; i++) {
      await db.rawInsert(
        'INSERT INTO article_sentence_tags (article_id, sentence_id, ordinal, text) '
        'VALUES (?, ?, ?, ?)',
        <Object?>[articleId, sid, i, asText(tags[i]) ?? ''],
      );
    }

    // languages 数组优先；老数据可能只有单对象 language 字段，兜成单元素数组。
    final languages = asList<Object?>(s['languages']);
    final langs = languages.isNotEmpty
        ? languages
        : (asRecord(s['language']) == null ? const <Object?>[] : <Object?>[s['language']]);
    for (var li = 0; li < langs.length; li++) {
      final l = asRecord(langs[li]);
      if (l == null) continue;
      final lpId = '$articleId:$sid:lang:$li';
      await db.rawInsert(
        'INSERT INTO lang_points (id, article_id, sentence_id, ordinal, source, structure, grammar, at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        <Object?>[
          lpId,
          articleId,
          sid,
          li,
          asText(l['source']) ?? 'ai',
          asText(l['structure']),
          asText(l['grammar']),
          asText(l['at']),
        ],
      );
      for (final entry in <String, Object?>{
        'idiom': l['idioms'],
        'phrase': l['phrases'],
        'usage': l['usage'],
      }.entries) {
        final values = asList<Object?>(entry.value);
        for (var i = 0; i < values.length; i++) {
          await db.rawInsert(
            'INSERT INTO lang_point_terms (lang_point_id, kind, ordinal, text) VALUES (?, ?, ?, ?)',
            <Object?>[lpId, entry.key, i, asText(values[i]) ?? ''],
          );
        }
      }
    }
  }
}

/// 全库重建（迁移用）：词库 + 所有文章。
Future<void> rebuildAllProjections(DatabaseExecutor db) async {
  final vocabRow = await db.rawQuery('SELECT payload FROM vocab WHERE id = 1');
  await rebuildVocabProjection(
    db,
    vocabRow.isEmpty ? null : parsePayload(vocabRow.first['payload']),
  );
  final articles = await db.rawQuery('SELECT payload FROM articles');
  for (final a in articles) {
    await rebuildArticleProjection(db, parsePayload(a['payload']));
  }
}

/// 词库 JSON → `words` / `word_*` 派生表。
///
/// 事实来源仍是 `vocab.payload`；这里只负责派生表，必须由调用方放在写事务里。
/// 传 `prevLib` 时走**增量**：只有新增 / 内容变化 / 删除的词条会动派生表；
/// 未变化的词条保留原 rowid，避免每次自动补全 / 评分都全量 delete + insert。
/// 不传（迁移、清空）则全量重建。
Future<void> rebuildVocabProjection(DatabaseExecutor db, Object? lib, {Object? prevLib}) async {
  final items = _itemsOf(lib);
  final incremental = lib != null && prevLib != null;
  Set<String>? writeIds;

  if (incremental) {
    final prevItems = _itemsOf(prevLib);
    final prevById = <String, String>{
      for (var i = 0; i < prevItems.length; i++) _wordIdOf(prevItems[i], i): jsonEncode(prevItems[i]),
    };
    final nextById = <String, String>{
      for (var i = 0; i < items.length; i++) _wordIdOf(items[i], i): jsonEncode(items[i]),
    };
    writeIds = <String>{};
    for (final e in nextById.entries) {
      if (prevById[e.key] != e.value) writeIds.add(e.key);
    }
    final removed = prevById.keys.where((id) => !nextById.containsKey(id)).toList();
    await _deleteWordIds(db, <String>[...writeIds, ...removed]);
  } else {
    await _clearWordProjection(db);
  }

  if (items.isEmpty) return;

  for (var i = 0; i < items.length; i++) {
    final it = items[i];
    final id = _wordIdOf(it, i);
    if (writeIds != null && !writeIds.contains(id)) continue;
    // reviewState 只认对象；数组读字段全是 null，与 Web 版行为一致。
    final review = asRecord(it['reviewState']) ?? const <String, Object?>{};
    final source = asRecord(it['source']);
    await db.rawInsert(
      'INSERT OR REPLACE INTO words ('
      'id, word, lemma, kind, lang_point_id, phonetic, part_of_speech, meaning, definition, '
      'status, note, source_article_id, source_file_name, source_sentence_id, source_sentence_text, '
      'review_ease, review_due, review_interval, review_repetitions, review_lapses, '
      'last_printed_at, priority_until, created_at, updated_at'
      ') VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      <Object?>[
        id,
        asText(it['word']) ?? '',
        asText(it['lemma']) ?? asText(it['word']) ?? '',
        asText(it['kind']) ?? 'word',
        asText(it['langPointId']),
        asText(it['phonetic']),
        asText(it['partOfSpeech']),
        asText(it['meaning']),
        asText(it['definition']),
        asText(it['status']) ?? 'unqueried',
        asText(it['note']) ?? '',
        asText(source?['articleId']),
        asText(source?['fileName']),
        asText(source?['sentenceId']),
        asText(source?['sentenceText']),
        asNum(review['ease'], 2.5),
        asText(review['due']),
        asNum(review['interval']),
        asNum(review['repetitions']),
        asNum(review['lapses']),
        asText(it['lastPrintedAt']),
        asText(it['priorityUntil']),
        asText(it['createdAt']) ?? nowIso(),
        asText(it['updatedAt']) ?? nowIso(),
      ],
    );

    const textTables = <String, String>{
      'word_usage': 'usage',
      'word_phrases': 'phrases',
      'word_idioms': 'idioms',
      'word_tags': 'tags',
      'word_grammar_marks': 'grammarMarks',
    };
    for (final e in textTables.entries) {
      final values = asList<Object?>(it[e.value]);
      for (var ordinal = 0; ordinal < values.length; ordinal++) {
        await db.rawInsert(
          'INSERT INTO ${e.key} (word_id, ordinal, text) VALUES (?, ?, ?)',
          <Object?>[id, ordinal, asText(values[ordinal]) ?? ''],
        );
      }
    }

    final examples = asList<Object?>(it['examples']);
    for (var ordinal = 0; ordinal < examples.length; ordinal++) {
      final ex = asRecord(examples[ordinal]);
      if (ex == null) continue;
      await db.rawInsert(
        'INSERT INTO word_examples '
        '(word_id, ordinal, text, translation, article_id, file_name, sentence_id, origin) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        <Object?>[
          id,
          ordinal,
          asText(ex['text']) ?? '',
          asText(ex['translation']),
          asText(ex['articleId']),
          asText(ex['fileName']),
          asText(ex['sentenceId']),
          asText(ex['origin']),
        ],
      );
    }

    final contexts = asList<Object?>(it['contexts']);
    for (var ordinal = 0; ordinal < contexts.length; ordinal++) {
      final ctx = asRecord(contexts[ordinal]);
      if (ctx == null) continue;
      await db.rawInsert(
        'INSERT INTO word_contexts '
        '(word_id, ordinal, article_id, file_name, sentence_id, sentence_text, meaning, at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        <Object?>[
          id,
          ordinal,
          asText(ctx['articleId']) ?? '',
          asText(ctx['fileName']),
          asText(ctx['sentenceId']),
          asText(ctx['sentenceText']) ?? '',
          asText(ctx['meaning']),
          asText(ctx['at']) ?? nowIso(),
        ],
      );
    }

    final confusables = asList<Object?>(it['confusables']);
    for (var ordinal = 0; ordinal < confusables.length; ordinal++) {
      final c = asRecord(confusables[ordinal]);
      if (c == null) continue;
      await db.rawInsert(
        'INSERT INTO word_confusables (word_id, ordinal, word, meaning) VALUES (?, ?, ?, ?)',
        <Object?>[id, ordinal, asText(c['word']) ?? '', asText(c['meaning'])],
      );
    }
  }
}

/// v4：早期词条的 `source.articleId` 存的是文章标题（不是 `saved:…` id）。
/// 重新切句后按标题还能唯一对上，就一次性换成真正的文章 id；
/// 结构相同的 `examples[].articleId` / `contexts[].articleId` 一起换。
///
/// 只改能唯一对上的标题；同名文章、找不到的标题保持原样，不猜。
Future<void> normalizeLegacySourceIds(DatabaseExecutor db) async {
  final byTitle = <String, String?>{};
  for (final r in await db.rawQuery('SELECT id, title FROM articles')) {
    final title = asText(r['title']);
    if (title == null || title.isEmpty) continue;
    // 同名文章不猜：置空后下面会跳过。
    if (byTitle.containsKey(title)) {
      byTitle[title] = null;
    } else {
      byTitle[title] = asText(r['id']);
    }
  }
  if (byTitle.isEmpty) return;

  final rows = await db.rawQuery('SELECT payload FROM vocab WHERE id = 1');
  if (rows.isEmpty) return;
  final lib = parsePayload(rows.first['payload']);
  final root = asRecord(lib);
  if (root == null) return;

  var changed = false;
  String? mapId(Object? v) {
    final s = asText(v);
    if (s == null || s.isEmpty) return null;
    final id = byTitle[s];
    if (id == null) return null;
    changed = true;
    return id;
  }

  /// 改原始 JSON 里的 `articleId`。
  ///
  /// **必须拿解码出来的那个 Map 原地改**：`asRecord` 返回的是复制出来的新 Map，
  /// 在副本上写字段不会回到 `lib` 里（2026-11-08 踩过，v4 看似改了实际没改）。
  void rewrite(Object? holder) {
    if (holder is! Map) return;
    final next = mapId(holder['articleId']);
    if (next != null) holder['articleId'] = next;
  }

  for (final item in asList<Object?>(root['items'])) {
    if (item is! Map) continue;
    rewrite(item['source']);
    // 注意：这里不能用 asRecord(...) 的结果，它是副本。
    for (final ex in asList<Object?>(item['examples'])) {
      rewrite(ex);
    }
    for (final ctx in asList<Object?>(item['contexts'])) {
      rewrite(ctx);
    }
  }

  if (!changed) return;
  await db.rawUpdate(
    'UPDATE vocab SET payload = ?, updated_at = ? WHERE id = 1',
    <Object?>[jsonEncode(lib), nowIso()],
  );
  await rebuildVocabProjection(db, lib);
}

List<Map<String, Object?>> _itemsOf(Object? lib) => asList<Object?>(asRecord(lib)?['items'])
    .map(asRecord)
    .whereType<Map<String, Object?>>()
    .toList();

String _wordIdOf(Map<String, Object?> it, int i) =>
    asText(it['id']) ?? '${asText(it['lemma']) ?? asText(it['word']) ?? 'word'}:$i';

Future<void> _clearWordProjection(DatabaseExecutor db) async {
  for (final t in wordChildTables) {
    await db.rawDelete('DELETE FROM $t');
  }
  await db.rawDelete('DELETE FROM words');
}

/// 按 id 删一组词条（words + 派生表）；分块避免超过 SQLite 参数上限。
Future<void> _deleteWordIds(DatabaseExecutor db, List<String> ids) async {
  if (ids.isEmpty) return;
  for (var start = 0; start < ids.length; start += 500) {
    final chunk = ids.sublist(start, start + 500 > ids.length ? ids.length : start + 500);
    final ph = List<String>.filled(chunk.length, '?').join(',');
    for (final t in wordChildTables) {
      await db.rawDelete('DELETE FROM $t WHERE word_id IN ($ph)', chunk);
    }
    await db.rawDelete('DELETE FROM words WHERE id IN ($ph)', chunk);
  }
}
