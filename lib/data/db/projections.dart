/// 派生投影：把行级事实（`vocab_items` / `vocab_extras`）摊到可查询的关系表里。
///
/// 为什么单独一层：事实来源是**行级表**（v15 起）；`words` / `word_*` 是「同一次
/// 事务里重建的副本」，`vocab.payload` 只是导出缓存。重建逻辑全是 db 语句，
/// 混在 [ensureSchema] 里很难看出「哪些是事实、哪些是投影」。
///
/// 这里只接 [DatabaseExecutor]、不持有连接、不管事务 —— 事务由调用方包。
/// 对应 Web 版 `server/sqliteProjection.ts` + `server/sqliteVocab.ts`。
library;

import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'payload_codec.dart';
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

/// 词条里「一个字符串数组落一张小表」的那几张（字段名 → 表名）。
const Map<String, String> _wordTextTables = <String, String>{
  'word_usage': 'usage',
  'word_phrases': 'phrases',
  'word_idioms': 'idioms',
  'word_tags': 'tags',
  'word_grammar_marks': 'grammarMarks',
};

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
  // 词库那一行 gzip 之后真机 2.14MB，超过 CursorWindow 的 2MB 单行上限：
  // 一次 `SELECT payload` 会抛 Row too big to fit into CursorWindow，
  // 所以走分块读。文章 payload 是几十 KB 的小 JSON，整取即可。
  final vocab = await readBigPayload(
    db,
    table: 'vocab',
    keyColumn: 'id',
    key: 1,
  );
  await rebuildVocabProjection(db, parsePayload(payloadJsonText(vocab)));
  final articles = await db.rawQuery('SELECT payload FROM articles');
  for (final a in articles) {
    await rebuildArticleProjection(db, parsePayload(a['payload']));
  }
}

/// 词库 JSON → `words` / `word_*` 派生表。
///
/// 事实来源是**行级表**（v15 起 `vocab_items` / `vocab_extras`）；这里只负责
/// 派生表，必须由调用方放在写事务里。传 `prevLib` 时走**增量**：只有新增 /
/// 内容变化 / 删除的词条会动派生表；未变化的词条保留原 rowid，避免每次自动补全
/// / 评分都全量 delete + insert。不传（迁移、清空）则全量重建。
///
/// [changedIndexes] 是「已知变了的词条下标」（行级写路径算出来的），传了就不必
/// 再算 [_fingerprint] —— 一万词各算一次实测 439ms，而评分一次只有 1 条变。
Future<void> rebuildVocabProjection(
  DatabaseExecutor db,
  Object? lib, {
  Object? prevLib,
  Set<int>? changedIndexes,
}) async {
  final items = _itemsOf(lib);
  final incremental = lib != null && prevLib != null;
  Set<String>? writeIds;

  if (incremental && changedIndexes != null) {
    // 调用方已经知道哪些下标变了：只按下标取 word id，末尾多出来的算删除。
    final prevItems = _itemsOf(prevLib);
    writeIds = <String>{
      for (final i in changedIndexes)
        if (i >= 0 && i < items.length) _wordIdOf(items[i], i),
    };
    final removed = <String>[
      for (var i = items.length; i < prevItems.length; i++) _wordIdOf(prevItems[i], i),
    ];
    await _deleteWordIds(db, <String>[...writeIds, ...removed]);
  } else if (incremental) {
    // 比对用**投影指纹**，不是整条 jsonEncode：一万词各编一遍要 470ms，
    // 而其中 `fieldSources` / `confusablesSource` 这些字段根本不落派生表。
    // 详见 [_fingerprint]。
    final prevItems = _itemsOf(prevLib);
    final prevById = <String, String>{
      for (var i = 0; i < prevItems.length; i++) _wordIdOf(prevItems[i], i): _fingerprint(prevItems[i]),
    };
    final nextById = <String, String>{
      for (var i = 0; i < items.length; i++) _wordIdOf(items[i], i): _fingerprint(items[i]),
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

  // 攒成一个 batch 再提交：逐条 `await db.rawInsert` 每一句都要过一次平台通道，
  // 1 万词 ≈ 6 万次往返（真机实测首次投影 9.2s，几乎全花在这儿）。
  // 只在这一段用 batch：上面的 `_deleteWordIds` / `_clearWordProjection`
  // 必须先把旧行删干净，塞进同一个 batch 会让「先删后插」的次序不再是显而易见的事实。
  final batch = db.batch();
  for (var i = 0; i < items.length; i++) {
    final it = items[i];
    if (writeIds != null && !writeIds.contains(_wordIdOf(it, i))) continue;
    _addWordRows(batch, it, i);
  }
  await batch.commit(noResult: true);
}

/// 只重写**一个**词条的派生表（行级写路径的热路径）。
///
/// 与 [rebuildVocabProjection] 的区别只有「范围」：那边一万词一条条比指纹再
/// 攒 batch，这边调用方已经知道是第几个词条变了（`save()` 里比 `doc` 字符串
/// 得到），直接删了这一条再插回去即可 —— 单条实测 0.6ms 量级。
///
/// [index] 必须与 `lib['items']` 里的下标一致：[_wordIdOf] 在没有 `id` 时用
/// 下标拼兜底 id，传错了会把词条写到别的行上。
Future<void> writeVocabItemProjection(
  DatabaseExecutor db,
  Object? item,
  int index,
) async {
  final it = asRecord(item);
  if (it == null) return;
  final id = _wordIdOf(it, index);
  await _deleteWordIds(db, <String>[id]);
  final batch = db.batch();
  _addWordRows(batch, it, index, id: id);
  await batch.commit(noResult: true);
}

/// 把一个词条写进 `words` + 八张 `word_*`（攒进 [batch]，不提交）。
///
/// 抽出来是因为两条写路径（全量重建 / 单条重写）必须写**完全一致**的一组列，
/// 各写一遍迟早会漂（33.9 的教训：派生表和事实形状对不上时最难查）。
void _addWordRows(
  Batch batch,
  Map<String, Object?> it,
  int index, {
  String? id,
}) {
  final wordId = id ?? _wordIdOf(it, index);
  // reviewState 只认对象；数组读字段全是 null，与 Web 版行为一致。
  final review = asRecord(it['reviewState']) ?? const <String, Object?>{};
  final source = asRecord(it['source']);
  batch.rawInsert(
    'INSERT OR REPLACE INTO words ('
    'id, word, lemma, kind, lang_point_id, phonetic, part_of_speech, meaning, definition, '
    'status, note, source_article_id, source_file_name, source_sentence_id, source_sentence_text, '
    'review_ease, review_due, review_interval, review_repetitions, review_lapses, '
    'last_printed_at, priority_until, created_at, updated_at'
    ') VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
    <Object?>[
      wordId,
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

  for (final e in _wordTextTables.entries) {
    final values = asList<Object?>(it[e.value]);
    for (var ordinal = 0; ordinal < values.length; ordinal++) {
      batch.rawInsert(
        'INSERT INTO ${e.key} (word_id, ordinal, text) VALUES (?, ?, ?)',
        <Object?>[wordId, ordinal, asText(values[ordinal]) ?? ''],
      );
    }
  }

  final examples = asList<Object?>(it['examples']);
  for (var ordinal = 0; ordinal < examples.length; ordinal++) {
    final ex = asRecord(examples[ordinal]);
    if (ex == null) continue;
    batch.rawInsert(
      'INSERT INTO word_examples '
      '(word_id, ordinal, text, translation, article_id, file_name, sentence_id, origin) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      <Object?>[
        wordId,
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
    batch.rawInsert(
      'INSERT INTO word_contexts '
      '(word_id, ordinal, article_id, file_name, sentence_id, sentence_text, meaning, at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      <Object?>[
        wordId,
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
    batch.rawInsert(
      'INSERT INTO word_confusables (word_id, ordinal, word, meaning) VALUES (?, ?, ?, ?)',
      <Object?>[wordId, ordinal, asText(c['word']) ?? '', asText(c['meaning'])],
    );
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

  // 同样避开 CursorWindow：整库 payload 一行就超 2MB。
  final raw = await readBigPayload(
    db,
    table: 'vocab',
    keyColumn: 'id',
    key: 1,
  );
  if (raw == null) return;
  final lib = parsePayload(payloadJsonText(raw));
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
    // 与 [VocabRepository.save] 一致写成 gzip BLOB：这一列读路径两种都认，
    // 但明文写回去会让下一次真机读又多 16MB 的窗口压力。
    <Object?>[packPayloadJson(jsonEncode(lib)), nowIso()],
  );
  await rebuildVocabProjection(db, lib);
}

/// v14：把 `articleEntries[].articleId` 从「书名」订正回真正的文章 id。
///
/// 背景（2026-11-19，用户报）：早期写路径优先拿 `MarkInput.fileName` 当按篇键，
/// 而精读 / 速读把 `article.book` 传成 fileName —— 带书名的文章（EPUB 导入）
/// 标完词只进了书名的桶，「本篇」一条都不显示。写路径已经在
/// `lib/core/vocab/analysis.dart` 里改成只认 `article.id`，这里负责把已经
/// 写错的老数据搬回去。
///
/// 只搬**能唯一对上**的：书名 → 该书名下唯一那篇文章的 id。同名多篇、
/// 找不到的保持原样（不猜，也不能把两篇并成一篇）。
Future<void> normalizeArticleEntryIds(DatabaseExecutor db) async {
  // `articles.book` 是后加列：跳版本的老库（比如直接从 v6 起来）可能还没有。
  final cols = <String>{
    for (final r in await db.rawQuery('PRAGMA table_info(articles)'))
      asText(r['name']) ?? '',
  };
  if (!cols.contains('book')) return;

  final byBook = <String, String?>{};
  for (final r in await db.rawQuery('SELECT id, book FROM articles')) {
    final book = asText(r['book']);
    if (book == null || book.isEmpty) continue;
    if (byBook.containsKey(book)) {
      byBook[book] = null; // 同名多篇：置空后跳过。
    } else {
      byBook[book] = asText(r['id']);
    }
  }
  if (byBook.isEmpty) return;

  final raw = await readBigPayload(
    db,
    table: 'vocab',
    keyColumn: 'id',
    key: 1,
  );
  if (raw == null) return;
  final lib = parsePayload(payloadJsonText(raw));
  final root = asRecord(lib);
  if (root == null) return;

  var changed = false;
  for (final entry in asList<Object?>(root['articleEntries'])) {
    if (entry is! Map) continue;
    // 必须拿解码出来的那个 Map 原地改（同 v4 的教训）。
    final key = asText(entry['articleId']);
    if (key == null || key.isEmpty) continue;
    final id = byBook[key];
    if (id == null || id == key) continue;
    entry['articleId'] = id;
    changed = true;
  }

  if (!changed) return;
  await db.rawUpdate(
    'UPDATE vocab SET payload = ?, updated_at = ? WHERE id = 1',
    <Object?>[packPayloadJson(jsonEncode(lib)), nowIso()],
  );
  await rebuildVocabProjection(db, lib);
}

List<Map<String, Object?>> _itemsOf(Object? lib) => asList<Object?>(asRecord(lib)?['items'])
    .map(asRecord)
    .whereType<Map<String, Object?>>()
    .toList();

String _wordIdOf(Map<String, Object?> it, int i) =>
    asText(it['id']) ?? '${asText(it['lemma']) ?? asText(it['word']) ?? 'word'}:$i';

/// 词条 → **投影指纹**：判断「这条要不要重写派生表」的比对口径。
///
/// 为什么不用 `jsonEncode(it)`：一万词各编一遍 470ms，而整条 JSON 里还有
/// `fieldSources`、`confusablesSource` 这些根本不落派生表的字段 —— 它们变了
/// 不该触发重写。指纹只收**下面那几条 INSERT 真正读到的字段**。
///
/// 规矩：指纹相同 ⇒ 落库结果相同（所以口径必须跟着写入语句一起改，别只改一边）。
/// 每段写成 `${长度}:${内容}`，null 写成 `~`：既能区分 null / 空串
/// （落到 SQL 里一个是 NULL、一个是 `''`），也不会让「A 的尾巴 + B 的头」
/// 拼出跟别的词条一样的串。
String _fingerprint(Map<String, Object?> it) {
  final b = StringBuffer();
  void add(Object? v) {
    if (v == null) {
      b.write('~');
      return;
    }
    final s = v is String ? v : '$v';
    b.write(s.length);
    b.write(':');
    b.write(s);
  }

  // 与 words 那一条 INSERT 的 ? 一一对应（id 是键，不重复算）。
  final review = asRecord(it['reviewState']) ?? const <String, Object?>{};
  final source = asRecord(it['source']);
  add(asText(it['word']) ?? '');
  add(asText(it['lemma']) ?? asText(it['word']) ?? '');
  add(asText(it['kind']) ?? 'word');
  add(asText(it['langPointId']));
  add(asText(it['phonetic']));
  add(asText(it['partOfSpeech']));
  add(asText(it['meaning']));
  add(asText(it['definition']));
  add(asText(it['status']) ?? 'unqueried');
  add(asText(it['note']) ?? '');
  add(asText(source?['articleId']));
  add(asText(source?['fileName']));
  add(asText(source?['sentenceId']));
  add(asText(source?['sentenceText']));
  add(asNum(review['ease'], 2.5));
  add(asText(review['due']));
  add(asNum(review['interval']));
  add(asNum(review['repetitions']));
  add(asNum(review['lapses']));
  add(asText(it['lastPrintedAt']));
  add(asText(it['priorityUntil']));
  add(asText(it['createdAt']));
  add(asText(it['updatedAt']));

  // 五个「一个字符串数组落一张小表」的字段：顺序即 ordinal，长度也要算进去
  // （否则 ['a','b'] 与 ['a','b',''] 只差一个空尾项时会被误判成没变）。
  for (final field in _wordTextTables.values) {
    final values = asList<Object?>(it[field]);
    add(values.length);
    for (final v in values) {
      add(asText(v) ?? '');
    }
  }

  // examples / contexts / confusables：坏形状的那一项不落库，但它的**位置**仍然
  // 决定了后面几项的 ordinal，所以 null 项也要占一个记号。
  void addItems(String field, void Function(Map<String, Object?> it) addOne) {
    final values = asList<Object?>(it[field]);
    add(values.length);
    for (final raw in values) {
      final rec = asRecord(raw);
      if (rec == null) {
        b.write('x');
        continue;
      }
      addOne(rec);
    }
  }

  addItems('examples', (ex) {
    add(asText(ex['text']) ?? '');
    add(asText(ex['translation']));
    add(asText(ex['articleId']));
    add(asText(ex['fileName']));
    add(asText(ex['sentenceId']));
    add(asText(ex['origin']));
  });
  addItems('contexts', (ctx) {
    add(asText(ctx['articleId']) ?? '');
    add(asText(ctx['fileName']));
    add(asText(ctx['sentenceId']));
    add(asText(ctx['sentenceText']) ?? '');
    add(asText(ctx['meaning']));
    add(asText(ctx['at']));
  });
  addItems('confusables', (c) {
    add(asText(c['word']) ?? '');
    add(asText(c['meaning']));
  });
  return b.toString();
}

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
