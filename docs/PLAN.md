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
| P1 | core 地基：模型 + 词形/词库/复习纯函数 | 🚧 进行中 |
| P2 | 数据层：sqflite schema（13 版迁移）+ 仓储 + 端口实现 | 待开始 |
| P3 | 精读主链路：文章导入 → 拆句 → 选词 → 词库 | 待开始 |
| P4 | 背单词：学习模式 + 复习调度 + 拼写 | 待开始 |
| P5 | 产出训练（全脂 / 脱脂 / 风味酸奶）+ D老师小课堂 | 待开始 |
| P6 | 跟读（TTS 现合成）+ AI 跑批 + 打印导出 + 备份 | 待开始 |

---

## P1 — core 地基（进行中）

Web 版 `src/core` 140 文件 19.6k 行，按「被谁依赖」排序，先做地基：

### P1.1 模型（`lib/models/`）

- [x] `activity`（已并入 `lib/core/activity/activity.dart`，20 例）
- [ ] `vocab.dart`：`VocabItem` / `VocabLibrary` / `ArticleVocabEntry` / `VocabTombstone` /
      `ReviewState` / `VocabExample` / `VocabSource` / `VocabContext` / `VocabConfusable`
      + `normalizeVocabLibrary`（外部输入守卫）
- [ ] `document.dart`：`DocumentMeta` / `Sentence` / `Paragraph` / `SavedArticle` /
      `SentenceLanguage` / `AudioSegment`
- [ ] `learning.dart`：16 个 section 的容器（`practice` / `mistakes` / `activity` / …）

### P1.2 词形与释义（`lib/core/vocab/`，对应 Web 版 `core/vocab/word.ts` 166 行）

- [ ] `word.dart`：`normalizeWord` / `lemmaOf`（不规则表 + 后缀规则）/ `canRewriteTo`
      （**只认屈折、不认派生** —— 这条防的是 2026-10-22 那个「unchallenged → challenge
      张冠李戴」的血案）/ `normalizePos` / `cleanGloss` / `stripLeadingPos` / `displayMeaning`
- [ ] 测试 `word_test.dart`：照搬 Web 版 102 行用例

### P1.3 词库增删改查（`lib/core/vocab/library.dart`，217 行）

- [ ] `createLibrary` / `editItem`（标 fieldSources=manual）/ `setStatus` / `removeItem`
      （记墓碑）/ `markPrinted` / `isPrinted` / `unprintedItems` / `prioritizeItems` /
      `isPriority` / `articleWordsOf` / `removeByLemma` / `filterItems` / `groupItems` /
      `sortItems`
- [ ] 测试 `library_test.dart`

### P1.4 复习与学习（按依赖顺序）

- [ ] `review.dart`（236 行）：SM-2 变体、`due` 排期、`relearn` 重学阶段
- [ ] `reviewStep.dart`（51 行）、`learnStep.dart`（122 行）：单步状态迁移
- [ ] `spelling.dart`（38 行）、`meaningOptions.dart`（49 行）、`sense.dart`（107 行）
- [ ] `tombstones.dart`（168 行）、`sentenceTexts.dart`（153 行）
- [ ] `drill.dart`（74 行）、`extra.dart`（78 行）、`studyView.dart`（61 行）

### P1.5 合并与迁移（数据安全的关键）

- [ ] `merge.dart`（448 行）：两份词库按 lemma 合并、墓碑防复活、篇条目按 articleId+lemma 合
- [ ] `migrations.dart`（369 行）：`schemaVersion` 升级链，**老备份必须能进**
- [ ] `backup_parse.dart`（对应 Web 版 217 行）：外部 JSON 逐段守卫，坏条目丢弃并计数

### P1.6 其余纯函数（与视图无关，能单独跑）

- [ ] `entry_kind`（✅ 已完成，6 例）
- [ ] `article_vocab.dart`（208 行）、`vocab_browse.dart`（261 行）
- [ ] `segmenter.dart`（拆句）、`align_text.dart`（270 行，句↔音频近似投影）
- [ ] `quiz.dart`（518 行）：出题（选义 / 拼写 / 听音 / 造句）
- [ ] `learning.dart`（250 行）：16 section 的归一化守卫

---

## P2 — 数据层

- [ ] `lib/data/db/schema.dart`：13 版迁移，**逐版照搬** `server/sqliteStore.ts`
      （v1 老库要回填 `articles.title/sentence_count/word_count/created_at`；
      v7 同时建 V8/V9/V11/V13 并写派生基线）
- [ ] `lib/data/db/migrations_test.dart`：用 `sqflite_common_ffi` 起真库，
      从 v1 老库一路迁到 13，断言每步回填
- [ ] 仓储：`vocab_repository.dart` / `article_repository.dart` / `learning_repository.dart`
- [ ] `lib/core/ports.dart`：端口声明（抽象类，零实现）

## P3 — 精读主链路

- [ ] 文章导入（PDF 抽文 / 粘贴 / 备份里的 `articles`）
- [ ] 精读页：段落 + 句子列表、点句选中、翻译与语言点
- [ ] 选词：点词 → 查词典（离线 `ecdict.tsv`）→ 收进词库（写 `ArticleVocabEntry`）
- [ ] 本篇词表 / 语言点列表

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
