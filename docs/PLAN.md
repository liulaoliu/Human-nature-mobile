# 重写计划

目标：把 `I:\Examples\Stutterer`（React + TS Web 版，483 源文件 / 73.7k 行）
重写成 Flutter 安卓版，功能对齐、数据可迁移、规则不走样。

原则三条：

1. **core 先移植，视图后重设计**。`src/core` 23k 行纯逻辑是唯一能「照搬」的部分，
   它决定 App 行为对不对；视图层必须按手机重想，不翻译 React 组件树。
2. **每一步都可验证**。每个模块都先写测试（用例从 Web 版同名测试逐条翻），
   跑完四条门禁再 commit。
3. **数据可迁移**。PC 导出的 `economist-backup-*.json` 必须能原样导入，
   所以 sqflite schema 要照搬 Web 版 13 版迁移史。

## 进度总览

| 阶段 | 内容 | 状态 |
|---|---|---|
| P0 | 建仓 + 门禁 + 文档骨架 | ✅ 完成（`81ead6e`） |
| P1 | core 地基：模型 + 词形/词库/复习纯函数 | ✅ 完成（44 个 core 文件 / 647 例） |
| P2 | 数据层：sqflite schema（13 版迁移）+ 仓储 + 端口实现 | ✅ 完成（`101fd6e` `1c944e3`） |
| P3 | 精读主链路：文章导入 → 拆句 → 选词 → 词库 | 🚧 进行中 |
| P4 | 背单词：学习模式 + 复习调度 + 拼写 | 待开始 |
| P5 | 产出训练（全脂 / 脱脂 / 风味酸奶）+ D老师小课堂 | 待开始 |
| P6 | 跟读（TTS 现合成）+ AI 跑批 + 打印导出 + 备份 | 待开始 |

---

## P1 — core 地基（✅ 完成）

Web 版 `src/core` 140 文件 19.6k 行，按「被谁依赖」排序，先做地基：

### P1.1 模型（`lib/models/`）

- [x] `activity`（已并入 `lib/core/activity/activity.dart`，20 例）
- [x] `vocab.dart`：`VocabItem` / `VocabLibrary` / `ArticleVocabEntry` / `VocabTombstone` /
      `ReviewState` / `VocabExample` / `VocabSource` / `VocabContext` / `VocabConfusable`
      + `normalizeVocabLibrary`（外部输入守卫）
- [x] `document.dart`：`Sentence` / `Paragraph` / `SavedArticle` /
      `SentenceLanguage` / `AudioSegment` / `ArticleOrigin`
- [x] `learning.dart`：16 个 section 的容器（`practice` / `mistakes` / `activity` / …）

### P1.2 词形与释义（`lib/core/vocab/`，对应 Web 版 `core/vocab/word.ts` 166 行）

- [x] `word.dart`：`normalizeWord` / `lemmaOf`（不规则表 + 后缀规则）/ `canRewriteTo`
      （**只认屈折、不认派生** —— 这条防的是 2026-10-22 那个「unchallenged → challenge
      张冠李戴」的血案）/ `normalizePos` / `cleanGloss` / `stripLeadingPos` / `displayMeaning`
- [x] 测试 `word_test.dart`

### P1.3 词库增删改查（`lib/core/vocab/library.dart`）

- [x] `createLibrary` / `editItem`（标 fieldSources=manual）/ `setStatus` / `removeItem`
      （记墓碑）/ `markPrinted` / `isPrinted` / `unprintedItems` / `prioritizeItems` /
      `isPriority` / `articleWordsOf` / `removeByLemma` / `filterItems` / `groupItems` /
      `sortItems`
- [x] 测试 `library_test.dart`

### P1.4 复习与学习（按依赖顺序）

- [x] `review.dart`：SM-2 变体、`due` 排期、`relearn` 重学阶段
- [x] `review_step.dart`、`learn_step.dart`：单步状态迁移
- [x] `spelling.dart`、`meaning_options.dart`、`sense.dart`
- [x] `tombstones.dart`、`sentence_texts.dart`
- [x] `drill.dart`、`extra.dart`、`study_view.dart`

### P1.5 合并与迁移（数据安全的关键）

- [x] `merge.dart`：两份词库按 lemma 合并、墓碑防复活、篇条目按 articleId+lemma 合
- [x] `migrations.dart`：`schemaVersion` 升级链，**老备份必须能进**
- [x] `backup_parse.dart`：外部 JSON 逐段守卫，坏条目丢弃并计数（16 例）

### P1.6 其余纯函数（与视图无关，能单独跑）

- [x] `entry_kind`（6 例）
- [x] `article_vocab.dart`、`vocab_browse.dart`（17 例）
- [x] `segmenter.dart`（拆句）、`align_text.dart`（句↔音频近似投影，31 例）
- [x] `quiz.dart`（19 种题型）+ `quiz_parts.dart`（100 例）
- [x] `learning.dart`（16 section 的归一化守卫，14 例）
- [x] 另补：`article_meaning` / `print_plan` / `word_select` / `goals` / `vocab_stats` /
      `practice` / `mistakes` / `kind_stats` / `answer_events` / `article_origin` /
      `vocab_json` / `article_json` / `lang_points` / `library_validate` / `text_norm`

---

## P2 — 数据层（✅ 完成）

- [x] `lib/data/db/schema.dart`：13 版迁移，**逐版照搬** `server/sqliteStore.ts`
      （v1 老库要回填 `articles.title/sentence_count/word_count/created_at`；
      v7 同时建 V8/V9/V11/V13 并写派生基线）
- [x] `lib/data/db/migrations_test.dart`：用 `sqflite_common_ffi` 起真库，
      从 v1 老库一路迁到 13，断言每步回填（20 例）
- [x] 仓储：`vocab_repository.dart`（17 例）/ `article_repository.dart`（21 例）/
      `learning_repository.dart`（22 例）
- [x] 支撑层：`db/sql_util.dart` / `db/projections.dart`（派生表重建）/
      `db/learning_{json,read,write}.dart` / `core/vocab/vocab_json.dart` /
      `core/article_json.dart`
- [ ] `lib/core/ports.dart`：端口声明（抽象类，零实现）——**推迟**：仓储已直接实现具体类
      并由 `main.dart` 注入，端口抽象等到 P3 真有第二个实现（测试假实现）再抽，
      避免先造一层没人实现的接口。

## P3 — 精读主链路（🚧 进行中）

已完成：

- [x] 文本清洗与拆句：`cleaner.dart`（连字/标记行/段落）、`article_build.dart`（新建 / 重切句）、
      `article_meta.dart`（指纹、日期口径）
- [x] 文章导入服务 `services/article_import_service.dart`：粘贴 / 多文本 / EPUB 分章 /
      原文库按 `sourceKey` 去重
- [x] EPUB 解包 `data/importers/epub_importer.dart`（container.xml → OPF → spine），
      纯函数部分 `html_text.dart`（抽文 + `parseOpf`）、`pdf_text.dart`（页码范围、文本项拼行）
- [x] 离线词典：`core/ecdict.dart`（解析 / 词形 / 分级 / 复合词词性）+ `data/dictionary_loader.dart`
      （`assets/ecdict/` 三份 TSV，自带冒烟测试）
- [x] 文章 slug 索引 `article_index.dart`（稳定别名、冲突消歧）
- [x] 语言点抽取与收藏 `language.dart` / `lang_points.dart`；AI 结果解析 `parseLanguage`
- [x] 词库写入侧 `core/vocab/analysis.dart`：`markWord` / `applyWordAnalysis` /
      `applyConfusables` / `applyLemmaMap` / `applyPosAnalysis`
- [x] 精读页：`viewmodels/reader_view_model.dart`（列表 / 打开 / 标词落盘 / 删除）、
      `views/articles_page.dart`（列表 + 粘贴新建）、`views/reader_page.dart`
      （逐句正文、点句取词、本篇词表）
- [x] 装配：`data/db/app_database.dart` + `main.dart` 的 `MultiProvider`；首页「精读」接通

待做：

- [ ] 文件导入 UI（选 PDF / EPUB）：服务层已就绪，缺 `file_picker` 接线与 PDF 文本层抽取
      （需引入 pdf 解析包）
- [ ] 查词：点词后走离线词典 `/ 手动输入释义 → `applyWordAnalysis` 回填（当前只有手填释义）
- [ ] 翻译 / 语言点 AI 面板：`parseLanguage` 已就绪，缺「拼 prompt → 粘回结果」的界面


## P4 — 背单词

- [ ] 学习模式（首次选义判「模糊/认识」，`meaningPasses` 计数）
- [ ] 复习模式（SM-2 排期、到期队列、优先重排 `priorityUntil`）
- [ ] 拼写模式（`spelling.dart` 判错 + 重学）
- [ ] 词库浏览（筛选 / 分组 / 排序）

## P5 — 产出训练 + 小课堂

- [ ] 奶牛工棚：全脂 / 脱脂 / 风味酸奶三种吃法
- [ ] 拆句配对（`productionPrompts` 的 `pairYogurtTexts` / `buildYogurtPromptsFromPairs`）
- [ ] 草稿按「文章 + 吃法」各存一组（Web 版踩过的坑：只按 articleId 存会互相覆盖）
- [ ] 小课堂：金句课 / 仿写 / 造句 / 历史

## P6 — 跟读与外围

- [ ] 跟读：`flutter_tts` 现合成（不存音频）、`record` 录音算完即删
- [ ] AI 跑批：客户端直连（key 存本机）
- [ ] 打印 / 导出（Anki CSV、词表、错词表）
- [ ] 备份：导出 + 覆盖导入 + 合并导入（带指纹去重）

---

## 每个模块的固定套路

1. 打开 Web 版同名源文件 + 同名测试；
2. 写 `lib/core/xxx.dart`（先写函数签名，注释照抄「为什么」）；
3. 写 `test/core/xxx_test.dart`，用例名照抄中文，逐条断言；
4. `flutter test test/core/xxx_test.dart` → 红了改实现（不是改断言）；
5. 四条门禁全绿 → `git commit`（`feat:` / `fix:` + 中文简述）。

## 不许做的事

- 不许「先搭 UI 再补 core」——视图层没有 core 就是一堆假按钮。
- 不许把 Web 版的 `localStorage` 用法翻成 `SharedPreferences` 塞大对象
  （词库、学习记录一律进 sqflite）。
- 不许跳过 `backupParse` 这类守卫直接 `jsonDecode` 后强转。
- 不许为了「跑起来」把测试删掉或改断言。
