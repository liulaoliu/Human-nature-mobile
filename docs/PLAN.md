# 重写计划

目标：把 https://github.com/liulaoliu/Human-nature （React + TS Web 版，
本地源码 `I:\Examples\Stutterer`，483 源文件 / 73.7k 行）
重构成 Flutter 安卓版，功能对齐、数据可迁移、规则不走样。

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
| P3 | 精读主链路：粘贴建文 → 拆句 → 选词 → 词库 | ✅ 完成 |
| P4 | 背单词：学习模式 + 复习调度 + 拼写 | ✅ 完成（`4b2eed4`） |
| P5 | 产出训练（全脂 / 脱脂 / 风味酸奶）+ 仿写 + 金句课 | ✅ 完成（产出训练、仿写、造句、历史、金句课全部接通） |
| P6 | 跟读（TTS 现合成）+ AI 跑批 + 打印导出 + 备份 | ✅ 完成（备份、跟读、AI 跑批接通；打印导出按用户要求不做） |
| P8 | 真网络 e2e（AI 跑批整条链路真调 DeepSeek） | ✅ 完成（`test/e2e/`，默认 skip；真机未验） |

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

## P3 — 精读主链路（✅ 完成）

> **范围收敛（2026-11-08）**：本 App **不做文件导入** —— PDF / EPUB / txt 一律不解析，
> 正文只走「粘贴原文」一条路。已删掉 `data/importers/epub_importer.dart`、
> `core/html_text.dart`、`core/pdf_text.dart` 及其测试。理由：移动端解析 PDF
> 要引入几十 MB 的原生库，而用户手边总有能复制文本的阅读器；少一条链路就少一类
> 「导进来是乱码」的故障。备份 JSON 的导入仍保留（那是数据迁移，不是正文抽取）。

已完成：

- [x] 文本清洗与拆句：`cleaner.dart`（连字/标记行/段落）、`article_build.dart`（新建 / 重切句）、
      `article_meta.dart`（指纹、日期口径）
- [x] 文章创建服务 `services/article_import_service.dart`：粘贴建文（同毫秒不撞 id）
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
- [x] 点词直查：`analysis_fill.wordAnalysisFromDict` + 取词面板的 `_dictPreview`
      （选中词立刻出音标 / 词性 / 释义，一键填进释义，不用走 AI）
- [x] 句子级 AI 面板：`views/ai_paste_sheet.dart`（复制提示词 → 粘回结果）接
      查词 / 翻译 / 结构 / 搭配四条
- [x] 整篇语言点面板：`ReaderViewModel.applyLanguageText`（`parseLanguage` +
      `applyLanguage`，手动条目不被 AI 覆盖），阅读页顶栏入口



## P4 — 背单词（✅ 完成）

已完成：

- [x] 候选池 `core/study_pool.dart`：范围（全部 / 本篇 / 没掌握 / 忘过的）× 牌组
      （单词 / 搭配）筛选、组大小生效值（手动优先，本篇 = 整篇，否则 20）、到期 / 新词计数
- [x] 学习模式 `core/study_session.dart` + `vocab/learn_step.dart`：首次选中文释义判
      「模糊 / 认识」，`meaningPasses` 计数与评级**一次写库**（分两次写会互相覆盖）；
      「不认识，看答案」只停留不写库，等过场后再判
- [x] 复习模式：`buildReviewQueue` 取到期、`reviewItem` 走 SM-2 排期、`priorityUntil`
      优先重排（`vocab/review.dart`）
- [x] 拼写模式 `vocab/spelling.dart`：卡面拼写对了算认识、拼错判「不认识」+ 打标签 + 重学；
      组末拼写是**验收不是加练**（拼错不重排，要求照着重打一遍）
- [x] 收尾重练：一轮只发起一次，重练会开新账本（`vocab/extra.dart`）
- [x] 记账 `services/study_ledger.dart`：今天学过哪些词（逻辑日 4 点换日）+ 背词活动；
      `LearningData` 里的记录是不可变的，换新对象重建而不是原地改
- [x] 页面：`viewmodels/study_view_model.dart`（池子 / 会话 / 落盘，词库冲突时重读后
      只重放自己动过的词）、`views/study_page.dart`（设置卡 / 四选一释义 / 三档评分 /
      组末拼写 / 小结）；首页「背单词」入口接通
- [x] 词库浏览 `views/vocab_browse_page.dart` + `viewmodels/vocab_browse_view_model.dart`：
      范围（全部 / 本篇 / 选篇）× 类型（全部 / 单词 / 语言点）× 状态（复习 / 未学习 /
      忘记 / 已掌握）× 入库日 × 搜索，三种排序（最近 / 字母 / 到期）；
      口径全在 `core/vocab_browse.dart`，界面不拼第二份布尔（13 例）
- [x] 词库筛选收进抽屉面板（`views/vocab_filter_sheet.dart`）：平时只留一行摘要，
      点 AppBar 的筛子图标滑出面板，四组条件按块竖排、不用 chip/button；
      默认**本篇 / 单词 / 复习**；日期改成可搜索的下拉（`DropdownMenu` + `enableFilter`）；
      条件落 `shared_preferences` 的 `vocab:browse`（`core/vocab_browse_prefs.dart`，
      坏项各自回默认），换页/重启都记得

- [x] 浅色主题 + 设置两级（`lib/theme/app_skin.dart` + `app_theme.dart`）：
      明暗（`core/theme_prefs.dart` 的 `AppThemeMode`，键 `theme:mode`）与配色
      （`AppSkin`）是两件正交的事；`SkinColors extends ThemeExtension` 承载语义色令牌，
      `SkinColors.of` 在未注册时按明暗回落经典蓝（裸 `MaterialApp` 的测试不崩）；
      设置页拆成目录（`views/settings_page.dart`）→ 背诵设置（`study_settings_page.dart`）
      / 皮肤（`theme_page.dart`，深色 / 浅色 / 跟随系统）。加新皮肤只改三处

- [x] 背词设置持久化 `core/study_prefs.dart` + `data/prefs_store.dart` +
      `viewmodels/study_settings.dart`：范围 / 牌组 / 每组词数 / 每日新词上限都会记住，
      跨结算点（04:00）自动归零，脏值回默认；设置写失败只回默认、不打断正在进行的这一轮
- [x] 每日新词额度：`buildLearnQueue(newLimit, newToday)` 已接上，`GradeOutcome.firstNew`
      保证同一天重复判同一个词只扣一次；装不下时给「今天的新词额度用完了（N/M）」

## P5 — 产出训练（即「D老师奶牛工棚」）+ 仿写 + 金句课

- [x] 奶牛工棚：全脂 / 脱脂 / 风味酸奶三种吃法（`lib/views/production_page.dart`
      + `production_setup.dart` / `production_run.dart` / `production_history_view.dart`）
- [x] 练习页三段式布局：上方进度/题号**吸顶**、下方批改/重写/跳过**吸底**，
      中间只有题干 / 作答 / 批改跟正文滚；主路是**一键叫 AI 出题 / 批改**
      （复用 `ai:config` 那份 key，见 `ProductionViewModel.generateWithAi` 与
      `ProductionSession.gradeWithAi`），手动粘贴（复制提示词 / 手动批改）留作兜底
      （对齐 Web `useProductionAi.ts` 的 `callAi` + `manualGrade()`，跑完仍从粘回面板进
      `applyFeedback`，不写第二套解析）；`test/views/production_run_test.dart` 验归属
- [x] 拆句配对（`productionPrompts` 的 `pairYogurtTexts` / `buildYogurtPromptsFromPairs`），
      出题页有「拆句预览」，重新拆句后按原文找回同一题
- [x] 草稿按「文章 + 吃法」各存一组（Web 版踩过的坑：只按 articleId 存会互相覆盖）
- [x] 仿写：范句 → 出题 → 作答 → 批改 → 落库
      （`lib/viewmodels/writing_view_model.dart` + `lib/views/writing_page.dart`
      / `writing_panel.dart` / `writing_history_view.dart`；草稿键 `writing:draft`）
- [x] 仿写 · 历史：按来源（普通仿写 / 奶牛工棚 / 拷打造句）+ 本篇/全库筛选、
      计数、点开载入回看、清空当前范围（金句课记录不在这个面板里清）
- [x] 仿写 · 造句：一轮背完 → 每个考到的词/词块各一道题，按题各存一份作答与批改
      （`core/drill_sentence_draft.dart` + `lib/viewmodels/drill_sentence_view_model.dart`
      + `lib/views/drill_sentence_page.dart` / `drill_sentence_feedback.dart`）；
      入口挂背单词结算页，上方进度/题号吸顶、下方批改/重写吸底
- [x] 金句课（Web 侧叫「D老师小课堂」，`golden*` 那一套，1,900+ 行）
  - [x] core 地基：`lib/core/golden_types.dart`（强类型内容模型）/ `golden.dart`
        （目标匹配、本地课程、脉络、去重）/ `golden_exam.dart`（仿写考试题、提示词、
        守卫）/ `golden_parse.dart`（`normalizeGoldenLesson` / `normalizeGoldenExtraPoints` /
        `mergeGoldenIntoArticle` / `pruneGoldenLesson`）；外部输入一律先过守卫
  - [x] 同名测试 4 套共 38 例（`test/core/golden_test.dart` 10 / `golden_types_test.dart` 8
        / `golden_exam_test.dart` 8 / `golden_parse_test.dart` 12），翻自 Web
        `golden.test.ts` / `goldenExam.test.ts` / `goldenParse.test.ts`
  - [x] 派生模块第一组：`lib/core/golden_progress.dart`（掌握口径：三步首次全对 + 看过小结；
        首次答错后重试不改回；重练不降级；待回顾队列按课文顺序；坏记录逐条丢弃；
        `mergeGoldenDrills` 取各步最大次数并合并首次对错；`summarizeGolden` 默认按句独立）/
        `golden_lang_point.dart`（只收 phrases + idioms，`usage` 是中文说明不进选块；
        同英文按大小写/空白去重、保留首次出现的原始空白；`lp:<sentenceId>:<slug>` 稳定 id）/
        `golden_markdown.dart`（默认不带进度勾，`includeProgress` 才打 ✅；反引号转义、
        去回车；段落角色翻成开头段 / 主体段 / 结尾段）
  - [x] 同名测试 3 套共 22 例（`golden_progress_test.dart` 11 / `golden_lang_point_test.dart` 7
        / `golden_markdown_test.dart` 4），翻自 Web `goldenProgress.test.ts` /
        `goldenLangPoint.test.ts` / `goldenMarkdown.test.ts`
  - [x] 派生模块第二组：`lib/core/print_html.dart`（A4 外壳，`escapeHtml` 先转 `&` 再转
        `<`/`>`/`"`，调用方 css 追加在基础样式之后）/ `golden_bank.dart`（摊平全库金句 +
        掌握状态 + 待回顾；按状态 / 学习点类型 / 关键词筛；导出 Markdown、Anki CSV、
        两栏 A4 讲义；`buildGoldenBank` 的 `now` 先 `toLocal()` 再取日期键，
        否则和 `goldenReviewDue` 的本地口径对不上）/ `text_diff.dart`（`compareToReference`
        的 LCS 重合度与 exact/near/fair/loose 分档、`diffWords` 的逐词对照）/
        `golden_drill.dart`（挖空按语言点整块、`splitWords` 才一词一空、同一目标重复出现
        共用一个空；细碎轮后缀逐步变长；整句渐进一个词 → 全部目标词 → 分句/整句，
        长句按标点切分句；拼句用句子文本做种子，刷新不跳；逆向默写 exact/near 才算首次掌握）
  - [x] 同名测试 4 套共 35 例（`print_html_test.dart` 6 / `golden_bank_test.dart` 6 /
        `text_diff_test.dart` 11 / `golden_drill_test.dart` 12），翻自 Web
        `backTranslate.test.ts` / `goldenDrill.test.ts` 与金句本行为
  - [x] 派生模块第三组：`lib/core/golden_ai.dart`（提示词只让 AI 挑句 + 加注释、不许改写
        原句；解析宽容围栏 / 前后废话 / 非法转义，但内容仍过 `normalizeGoldenLesson`；
        `mergeGoldenLessons` 把 AI 与本地推导取并集 —— AI 注释优先、本地语言点不被覆盖，
        用户手选的金句默认保留，`preferAI` 才用 AI 的选择；AI 全失败也能用本地课程练）
  - [x] 同名测试 1 套 13 例（`golden_ai_test.dart`），翻自 Web `goldenAi.ts` 行为
  - [x] 金句课 ViewModel / 页面：`lib/viewmodels/golden_view_model.dart`（跨句读取、落库、会话位置）
        + `golden_lesson_editor.dart`（改选句 / 设置 / 语言点、写回文章）+ `golden_drill_session.dart`
        （一句的逐轮练习）；`lib/views/golden_page.dart` 四页壳 + `golden_plan_view.dart`
        （挑句，主按钮吸底）/ `golden_drill_view.dart`（填空 → 拼句 → 小结，进度吸顶、动作吸底）
        / `golden_bank_view.dart`（全库金句本，搜索 + 状态 + 类型筛）/ `golden_history_view.dart`
        （掌握情况 + 练习记录 + 导出 Markdown）。首页第六张卡「金句课」已接通
  - [x] `SavedArticle.golden` 仍存原始 JSON，但读写都过 `golden_article.dart` 的
        `goldenLessonOf` / `withGoldenLesson` / `pruneGoldenOf` 守卫（models 不能反向 import core）

## P6 — 跟读与外围

- [x] 跟读：`flutter_tts` 现合成（不存音频）、`record` 录音算完即删
  - [x] core 地基：`recording.dart`（录音上限 / 说话阈值 / 六个常量）、`tts_timing.dart`（逐词时间对齐）、
        `shadowing_state.dart`（校准与改文的旧数据守卫）、`shadowing_prefs.dart`（显示模式 / 麦克风 /
        静音时长 / 回放放大，读不到一律回默认）＋ 同名测试 4 套共 32 例
  - [x] `shadowing_take.dart`（`TakeTracker` 底噪只往低走、没开过口永远不收；`judgeTake` 三种判词）＋ 13 例
  - [x] `core/ports.dart` 加 `SpeechPort` / `RecorderPort` 两个端口（平台能力藏在接口后，测试喂假实现）
  - [x] `services/shadowing_speech.dart`（`flutter_tts` 合成，`AudioRecorder` 懒创建）、
        `services/shadowing_recorder.dart`（`record` 录到临时文件，`stop` / `discard` 返回前删掉）
  - [x] `viewmodels/shadowing_view_model.dart`（听 / 录 / 判 / 偏好 / 切句，19 例）
  - [x] 跟读页 `views/shadowing_page.dart`（吸顶进度、中间滚原文、吸底听 / 读），首页第八张卡接通
- [x] AI 跑批：客户端直连（key 存本机）
  - [x] `core/ai_config.dart`（`AiConfig` / `normalizeAiConfig` / 脱敏回显 / 默认 `https://api.deepseek.com`）、
        `core/ai_jobs.dart`（照 Web `pickNeedInfo` 挑缺释义的词、30 个一块、FNV-1a 稳定 id）
  - [x] `services/ai_client.dart`（`http` 直连 `POST /chat/completions`，401 / 429 / 5xx / 坏 JSON 分相）+ 15 例假 HTTP 测试
  - [x] `viewmodels/ai_batch_view_model.dart`（跑批 / 暂停 / 续跑 / 失败留待办 / 解析后整库回填）+ 9 例
  - [x] `views/ai_batch_page.dart`（key 只存 `shared_preferences` 的 `ai:config`、测试连接、进度、任务清单、吸底动作条），
        首页第九张卡接通；`http` 只在 services，core 完全不认识它
- [~] 打印 / 导出（Anki CSV、词表、错词表）—— **不做**：用户 2026-11-09 明确说不想要
      （导出已经在写的地方留着：金句本 / 本课的 Markdown 复制、`print_html.dart` 的 A4 外壳，
      不新做 Anki CSV 与词表打印）
- [x] 备份：导出 + 覆盖导入 + 合并导入（带指纹去重）
  - [x] core：`merge_backup.dart`（词库互补、按天累加、记录去重）、`import_ledger.dart`（FNV-1a 指纹与账本）、
        `backup_export.dart`（整库 JSON 打包，历史键名 `stats` / `studyStats` 与导入侧对齐）
  - [x] `services/backup_service.dart`（导出 / 覆盖导入 / 合并导入；没写学习记录的备份不清空现有统计；
        指纹在落盘成功之后才记）+ `viewmodels/backup_view_model.dart`（只收文本、只吐结果，平台能力留给页面）
  - [x] 备份页：导出并分享（`share_plus`）、合并导入 / 覆盖导入（`file_picker` + `withData`），
        首页第七张卡接通

- [x] 速读：一句一屏计时读，超时就地拷打（2026-11-11 补做，用户 m23127 要求）
  - [x] core：`speed_read.dart`（目标时长 `targetMs` / 挖空 `pickTargetBlank` / 四选一 `pickDrill` /
        判分 `checkDrill` / 结算 `summarize`）、`doc_signature.dart`（`标识@djb2` 当游标键）、
        `speed_read_prefs.dart`（语速 / 自动拷打 / 游标三个键的宽松解析）＋ 同名测试 42 例
  - [x] `data/prefs_store.dart` 加 `loadSpeedWpm` / `saveSpeedWpm` / `loadSpeedAutoDrill` /
        `saveSpeedAutoDrill` / `loadSpeedCursor` / `saveSpeedCursor`（游标按篇分开）
  - [x] `viewmodels/speed_read_view_model.dart`（阶段机 read → reveal → drill → drillAnswer、
        计时由界面 `tick` 驱动但读秒现算、翻句不记成绩、读完游标归零）＋ 16 例
  - [x] `views/speed_read_page.dart`（顶栏吸顶 / 底栏吸底 / 正文自己滚；译文与语言点只在揭晓阶段出现，
        复用 `sentence_extras.dart`），首页第四张卡接通＋ 4 例页面测试
  - [x] 语速与「超时就拷打」搬进设置页（`views/speed_settings_page.dart`，入口
        `settings-entry-speed`）：速读页只留选篇与正文，语速是一次定好、长期有效的偏好，
        摊在选篇页顶部既占地方又容易误触；VM 与落盘键（`reader:speedWpm` /
        `reader:speedAutoDrill`）不变，改完即生效

## P7 — 整卷 / 题型考试（✅ 最小可用已完成，2026-11-14）

- [x] 启用 `core/quiz.dart` 的 19 种题型：新增 `viewmodels/quiz_prep.dart`（组卷 / 判分 / 交卷落库）、
      `viewmodels/quiz_view_model.dart`（会话状态机）、`views/quiz_page.dart`（设置 → 作答 → 报告），
      首页第 9 张「考试」卡 + `main.dart` Provider 已接。
- [x] 词级卷：自选 `QuizScope` × 13 种词级题型 × 题量（5/10/20/30/不限）；
      文章卷：自选 6 种文章级题型，**显式传 kinds**（Web 默认含 `phraseBlank` 不含 `grammar`）。
- [x] 交卷写一条 `practice_records`（`PracticeKind.quiz`）；有 `articleId` 时累计 `kindStats`；
      活动热力图按 `quizActivityCat` 计入（文章题算「读」、听音算「听」、其余算「词」）。
- [x] 判分复用 `DrillPrep.record`，并修正文章题守卫：文章题**不写 SRS、不进错题本**，
      `articleId` 可显式传入（不再只能取全局当前篇）。
- [x] 一轮只记一次成绩：`retryWrong` 不重置 `recorded`；`restart` 才重新记。
- [x] P7.1（✅ 已完成，2026-11-14）：会话恢复（`core/quiz_session.dart` 存 `quiz:session`，
      设置页给「继续上次考试」）、考试历史 / 逐题明细（`core/quiz_history.dart`，存 prefs，
      **不加 v14 迁移**）、考试设置持久化（`core/quiz_settings.dart` → `quiz:settings`）、
      自动下一题 / 答完朗读 / 反复鞭打（最多 3 轮）、听写入口（`quiz_prep._dictation` 按正文句序挖
      词库里的词）、词级 + 文章级混合一张卷（`QuizMode.mixed` 各出一半）。
- [ ] 顺带：`DrillSentenceOptions.questions` 与 `testedChunk` 仍未喂数据 —— 独立小项。
      **2026-11-14 复查结论：不是漏接线，是口径对不上。** P7 的 `QuizQuestion` 链路
      已经有了，但背单词这一轮考的是「拼写 / 选义 / 写搭配」，搭配那一步是
      「写出任意一条用法就算过」（`StudyDrill.submitUsage`），不存在「这一题考的是
      哪一条词块」。要接上必须先改产品口径：让搭配题指定一条词块来考。

## P8 — 真网络 e2e（✅ 已接通，2026-11-10 晚）

- [x] `test/e2e/ai_batch_e2e_test.dart`：真调 DeepSeek → `parseAnalysis` →
      `applyWordAnalysis` → 写 SQLite → 读回来验释义 / 音标 / `status` / 来源标记。
      **默认 skip**，只有设了 `DLAOSHI_E2E_KEY` 环境变量才跑（key 不进仓库）。
- [x] 实测（DeepSeek 官方 `deepseek-chat`）：30 词一块 9.8s 回 5,513 字符、
      30/30 解析正确、`max_tokens: 4096` 够用；5 词整条链路 4s 跑通。
- [x] 错误分相实测：坏 key → `unauthorized`、空 key → 不发请求、不存在的模型 →
      `badResponse`（HTTP 400）、域名不通 → `network`、`ftp://` → 客户端守卫拦住。
- [ ] 仍未做：真机（安卓）上跑同样一条，验证 device 网络栈 / 代理 / 证书；
      以及把 e2e 挂进日常流程的成本（每次跑烧额度，不建议进 CI）。

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
