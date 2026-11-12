# 待办（2026-11-09 晚）

> 这份是给自己第二天开工用的清单。按「先做什么收益最大」排序，
> 每条都写了为什么值得做、大概多久。

## ~~明天第一件：AI 跑批（P6 最后一件）~~ ✅ 已完成（2026-11-10）

> **实际落地**：方向从 TODO 原写的「批改 writingHistory」改成**批量查词** ——
> 词库里缺释义的词 → `buildBatchLookupPrompt` → API → `parseAnalysis` →
> `applyWordAnalysis` → `VocabRepository.save`，这条链路的提示词/解析器/落库
> 全是现成且已测的，能真闭环；「批改历史」没有对应批量落库路径。
> - `lib/core/ai_config.dart` + `lib/core/ai_jobs.dart`（守卫 / 挑待查词 / 分块 / 稳定 id）
> - `lib/services/ai_client.dart`（`http` 直连、错误分相）
> - `lib/viewmodels/ai_batch_view_model.dart`（跑批 / 暂停 / 续跑 / 失败留待办 / 落库）
> - `lib/views/ai_batch_page.dart`（key 本机存 + 测试连接 + 进度 + 任务清单）
> - 首页第九张卡；`http` 只在 services，core 完全不认识它；测试全部假 HTTP 离线跑
> - **key 只存 `shared_preferences`（`ai:config`），不进 git / 备份 JSON**

**估算：2–3 轮，约 2–4 小时**

要做的东西（历史草案，留作对照）：
- **先加依赖**：`http: ^1.6.0`（`I:\.pub-cache\hosted\pub.flutter-io.cn\http-1.6.0` 已缓存，
  离线可装）。注意 `lib/core/` 不能 import 它（R1 只禁 flutter/sqflite/shared_preferences，
  但纯 Dart 的 http 也不该进 core —— 放 `lib/services/`）。
- `lib/core/ai_config.dart`：`AiConfig{baseUrl, apiKey, model, temperature}` + `normalizeAiConfig` 守卫
  + `aiConfigToJson`。baseUrl 默认 `https://api.deepseek.com`，model 默认 `deepseek-chat`。
- `lib/services/ai_client.dart`：`AiClient`（`http` 直连，`POST /chat/completions`）。
  错误要分相：网络不通 / 401 key 错 / 429 限流 / 5xx 服务端 / JSON 解析失败。
- `lib/viewmodels/ai_batch_view_model.dart`：读 `writingHistory` 里没批改的记录 →
  逐条 `buildWritingFeedbackPrompt` → 调 API → `parseWritingFeedback` → 落库。
  要能暂停/继续、显示「第 N/M 条」、失败的单独列出来。
- `lib/views/ai_batch_page.dart`：key 输入（`obscureText`）+ 测试连接按钮 +
  选择范围（未批改 / 全部 / 指定文章）+ 跑批进度 + 结果列表。
- 首页第九张卡。
- **key 存放**：`PrefsStore` 新增 `aiConfigKey`，存 `shared_preferences`。
  **绝不要**写进 `local.properties` 或任何会被 git 跟踪的文件。

测试要点（全部可离线跑，用假 HTTP）：
- `AiClient` 的错误分支（401/429/超时/坏 JSON）
- 跑批中途失败的续跑
- `normalizeAiConfig` 对坏数据的兜底

## ~~第二件：补 19 个页面的 smoke 测试~~ ✅ 已完成（2026-11-10）

实际落地（2026-11-10）：
- `test/views/` 从 3 个测试补到 **23 个 `*_test.dart`，覆盖 `lib/views/` 全部 23 个 .dart**。
  新建 20 个同名 smoke 测试 + 1 个公共装配 `smoke_harness.dart`（非 `*_test.dart`，
  不被收集）；既有 `production_run_test.dart` / `production_setup_test.dart` /
  `writing_panel_test.dart` 原封不动。
- 公共装配把 `test/widget_test.dart` 的套路收在一处：10 个 VM 用
  `ChangeNotifierProvider<X>.value` 注入且刻意不 dispose、真 SQLite 走
  `tester.runAsync` + `inMemoryDatabasePath` + `ensureSchema`、`pump()` 不用
  `pumpAndSettle`、收尾 6 轮 `runAsync(100ms)+pump(500ms)` 消 pending Timer、
  `useTallScreen` 设 1080×3000；`AiBatchViewModel` 用假回调离线跑。
- 每条用例都断言该页特有文案 / 控件（标题、Tab、hint、按钮、空态），不是只
  `find.byType(page)`。子视图用 `Scaffold(body: SafeArea(child: <view>))` 包，
  整页直接作 `MaterialApp(home:)` 不套第二层 Scaffold。
- `flutter test test/views -j 4` → **28 例全绿**（20 新 + 8 既有）；
  `flutter analyze test/views` → No issues found!。全量 `flutter test -j 4`
  从 1,722 → **1,742 passed**，五门禁全绿。
- 由后台子代理批量产出，只写 `test/views/*`，未改 `lib/`、未提交、未碰
  `assets/GinShinImapct.webp`；复核抽查 `smoke_harness.dart` /
  `drill_sentence_page_test.dart` / `ai_batch_page_test.dart` 中文与断言均正常。

原方案（历史草案，留作对照）：

**估算：1 轮，约 1 小时**

二次打分里测试维只有 76 分，全库最低。22 个页面只有 3 个有测试。

每个页面一条用例就够（约 10 行）：
```dart
testWidgets('XXX 页能打开，关键文案在', (tester) async {
  // 复用 test/widget_test.dart 里的套路：
  // - useTallScreen(tester)
  // - ViewModel 用 ChangeNotifierProvider.value 注入，不 dispose
  // - pump 两下断言关键文案
});
```

有现成的 `test/views/production_run_test.dart`、`production_setup_test.dart`、
`writing_panel_test.dart` 可以照抄。

为什么值得做：上一轮 review 在 `writing_panel.dart` 抓到的「词块输入框吞分隔符」
就是零测试区域的 bug —— 用户根本打不出第二个词块，只能粘贴。同样的问题还在
另外 19 个页面里。

## ~~第三件：三份 `_appendRecord` 三合一~~ ✅ 已完成（2026-11-10）

> **实际落地**：新建 `lib/services/writing_ledger.dart`，导出
> `Future<WritingAppendResult> appendWritingRecord({required LearningRepository repo,
> required List<WritingRecord> current, required WritingRecord record,
> required bool countActivity})`。`WritingAppendResult{ok, history, appended, error}`：
> 成功回追加后的完整历史（调用方整体替换 `_history`），失败原样返回 `current`
> 并带中文 `error`，调用方不用回滚。服务内部统一「整段重写 `writingHistory`
> + 可选记 `activity`」，去重（`hasSameWritingAttempt`）与 `counted = countActivity && appended`
> 只在服务里算一次。
> - writing / drill 传 `countActivity: true`；production 传 `productionTaskOf(record)?.skipped != true`
> - `test/services/writing_ledger_test.dart` 5 例（真追加 +1 / 重复不刷历史也不重复记账 /
>   `countActivity:false` 不记活动 / repo 抛错返回 `ok:false` / 不动原列表）
> - 三份 ViewModel 都删掉重复的 `addActivity`/`dayKeyLocal`/`ActivityCat` import，
>   成功时统一 `notifyListeners()`（drill 原来缺）
> - **顺带修掉一个真 bug**：drill 原来重复粘回同一份批改会重复给今天「写」活动 +1，
>   统一后改成只在真追加时记；writing / production 语义不变
> - 相关 4 个测试套件 75 例全过

原方案（历史草案，留作对照）：

**估算：半小时**

位置：
- `lib/viewmodels/writing_view_model.dart:277`
- `lib/viewmodels/production_view_model.dart:400`
- `lib/viewmodels/drill_sentence_view_model.dart:310`

三份几乎逐行相同，差异只有：
- production 多一句 `productionTaskOf(record)?.skipped != true`
- drill 少了 `counted` 变量（它总是记 activity）

抽成 `lib/services/writing_ledger.dart`（最终签名见上，返回 richer result）。

注意 drill 那份**永远记 activity**，所以传 `countActivity: true`；
production 传 `productionTaskOf(record)?.skipped != true`；
writing 传「真的追加了才记」。

## ~~第四件：`_ErrorBar` / `_NoticeBar` 提到 `lib/widgets/`~~ ✅ 已完成（2026-11-10）

**估算：一小时**

实际落地：
- 新建 `lib/widgets/status_bar.dart`：`StatusBar.error(message)`（红底、不可关）/
  `StatusBar.notice(message, onClose)`（次要色底、点叉关掉）。10 个页面统一加
  `import '../widgets/status_bar.dart';`，共替换 18 处调用、删掉 17 份私有类
  （`_ErrorBar` 10 份、`_NoticeBar` 7 份；此前手工数成 9 + 6，实际多一份）。
- 样式收口成一种：提示条右内边距统一 `8`、关闭图标统一 `Icons.close, size: 18`、
  `tooltip: '知道了'` 保留；错误条统一 `symmetric(16, 10)`。原来 backup / drill /
  golden / production / shadowing / writing 用 `fromLTRB(16,6,6,6)`、
  ai_batch 用 `8`，关闭图标还有的默认大小、有的 18，现已不再漂移。
- 新增 `test/widgets/status_bar_test.dart` 2 例（error 红底且无 IconButton /
  notice 可关且点叉触发 onClose），全过。
- 批量替换走 Python 脚本（含中文的 Dart 不能用 pwsh `.Replace` 写，会坏 UTF-8），
  脚本用完即删，不留在仓库。

原方案（历史草案，留作对照）：新建 `lib/widgets/status_bar.dart`，导出
`StatusBar.error(message)` / `StatusBar.notice(message, onClose)`。`lib/widgets/`
就是为这种共享 UI 存在的，不违反分层约束。

## ~~第五件：`core/writing.dart` 拆文件~~ ✅ 已完成（2026-11-10）

**估算：一小时**。774 行、35 个顶层符号、被 13 处 import（全库扇入第一）。

实际落地（按 `golden.dart` / `golden_parse.dart` / `golden_exam.dart` 已经走过的路）：
- `writing_types.dart`：全部数据结构（`ImitationTask` / `WritingFeedback` /
  `WritingIssue` / `WritingScore` / `WritingRecommendation` / `RubricItem` 等）+ 私有
  `_recKindLabel` + `isWritingFeedbackV2`，只依赖 `writing_error_rules.dart`。
- `writing_prompt.dart`：`buildImitationTaskPrompt` / `buildWritingFeedbackPrompt` 与
  `AvailablePoint` / `PreviousIssue` / `WritingFeedbackPromptOptions`；纯字符串拼装，
  连 `dart:convert` 都不用。
- `writing_parse.dart`：`parseImitationTask` / `parseWritingFeedback` /
  `parseWritingFeedbackDetailed` + 5 个私有助手（`_fence`/`_stripFence`/`_asString`/
  `_asStringArray`/`_asInt`，两个 parse 共用，故放这里）+ 解析结果类。
- `writing.dart` 改成 re-export 伞：保留原有 3 条 re-export
  （`writing_error_rules.dart` / `writing_json.dart` / `writing_record.dart`），
  新增 3 条指向上面新模块。**全库 20 处 `import 'writing.dart'` 一行没改**，
  `flutter analyze lib` 全绿（含 `writing_json.dart` 反向 import 伞的环）。
- 门禁要求每个 `lib/core/x.dart` 配 `test/core/x_test.dart` → 三份薄测试各 3 例
  （单独 import 对应新模块，验证边界），原 `test/core/writing_test.dart`（331 行）
  原封不动保留、继续从伞测公共 API。9 个新例全过。

原方案（历史草案，留作对照）：按 `golden.dart` / `golden_parse.dart` /
`golden_exam.dart` 已经走过的路拆：
- `writing_types.dart`：`ImitationTask` / `WritingFeedback` / `WritingIssue` /
  `WritingScore` / `WritingRecommendation` / `RubricItem` 等数据结构
- `writing_prompt.dart`：`buildImitationTaskPrompt` / `buildWritingFeedbackPrompt`
- `writing_parse.dart`：`parseWritingFeedback` / `parseWritingFeedbackDetailed`
- `writing.dart` 只留 re-export（保证现有 import 不用改）

## ~~第六件：给 `core/quiz.dart` 定性~~ ✅ 已完成（2026-11-10）

**选了原方案的路 2（文档定性），不接考试 UI。** 落地：

- `lib/core/quiz.dart` 文件头补「状态说明」：写明 6 个函数是「整卷 / 题型考试」的
  预留实现、不是死代码；全库只有 `drill_sentence.dart` 用 `QuizQuestion` / `QuizKind`
  两个类型；正确性由 `test/core/quiz_test.dart` 约 100 例守着；等 P7 直接拿去接
  ViewModel + 页面，不用重写。
- `docs/PLAN.md` 新增 `## P7 — 整卷 / 题型考试（未排期，先登记）`，把 6 个函数、
  `DrillSentenceOptions.questions` / `testedChunk` 的缺口一起登记。
- **刻意不标 `@visibleForTesting`**：那注解语义是「public 仅为测试」，会误导 ——
  这些是给产品功能预留的，不是测试专用，且对 lib 内零调用没有实际约束。
- 理由：P6 已完成、产品没有考试入口；硬接 UI + ViewModel + 落库远超「十几分钟定性」，
  且 HY4 时段的 review 早已判定「等考试链路」。定性写进仓库，不再悬着。

原方案（历史草案，留作对照）：

**估算：十几分钟**

6 个顶层函数在 `lib` 里零调用：
`buildQuizQuestions` / `countQuestions` / `makeQuestion` / `isCorrect` /
`isArticleKind` / `makeDictationQuestion`。

565 行 + 19 种题型 + 100 例测试，当前产品里没有任何入口能触发它
（背单词走的是 `study_view.dart` 的释义四选一）。

两条路选一：
1. 接上「整卷 / 题型考试」入口（这也是 `drillSentence` 的
   `DrillSentenceOptions.questions` 一直没数据的原因 —— `testedChunk` 恒 null）
2. 标 `@visibleForTesting` + 在 `docs/PLAN.md` 记成「等考试功能再启用」

别让它悬着。

---

## 第七件：本轮 review 记下但**没修**的（2026-11-10 晚）

> 六件已清完；下面这些是「知道有问题、故意没动」的，按值不值得做排序，不是按难易。
> **7.1 与 7.3–7.6 已于 2026-11-10 晚处理（见各小节顶部的 ✅ 注），只剩 7.2 待办。**

### 7.1 端到端从没验证过（✅ 已补真网络 e2e，只剩真机）

> ✅ 2026-11-10 晚：新增 `test/e2e/ai_batch_e2e_test.dart`，真调 DeepSeek 走完
> 「挑缺释义的词 → 请求 → `parseAnalysis` → `applyWordAnalysis` → 写 SQLite → 读回来」，
> 断言释义 / 音标非空、`status == queried`、`fieldSources[meaning] == ai`。
> **默认 skip**，设 `DLAOSHI_E2E_KEY` 才跑（key 只从环境变量读）。
> 实测：30 词一块 9.8s 回 5,513 字符、30/30 解析正确、`max_tokens: 4096` 够用；
> 错误分相全对（401 / 400 / DNS / ftp 守卫）。见 `docs/TESTING.md` §五。
> **仍未做**：安卓真机上跑同一条（device 网络栈 / 代理 / 证书）。这步只能你在手机上做。

全部 **1,749 例测试都是离线假数据**：假 HTTP 客户端、内存 SQLite、假 TTS/录音端口。
AI 跑批是这次重写里**第一次碰网络请求和用户凭据**，却从来没真正向 DeepSeek 发过
一个请求。`AiClient` 的请求体、header、超时、错误分相都只在 `MockClient` 里验证过。

- 一条真请求的成本：填 key → 点「测试连接」→ 看回包。**这事儿必须人拿自己的 key
  在真机上做，我不该代填**。
- 值得顺手确认的：真模型回的表格式是否被 `parseLookupTable` 吃得干净（现在只测了
  我按 Web 版格式手写的样例表）、429 限流文案是否真会出现、`max_tokens: 4096`
  够不够 30 个词一次查完。
- 如果走一遍发现解析挂，优先修 `lib/core/analyzer_parse.dart` 的表格兜底，别改提示词。

### 7.2 smoke 测试只验「能渲染」（20 个页面）

第二批补的 20 条用例基本是「打开页面 → 断言标题/空态文案在」，**不验证交互**。
本轮只给 AI 跑批页补了 1 条真交互（改 key → 点测试 → 断言假回调收到新 key），
其余 19 页仍是纯渲染。

- 价值最高的三条：`reader_page`（最重）、`study_page`（会话状态机）、
  `backup_page`（导入是破坏性操作）。
- 写法照 `test/views/ai_batch_page_test.dart` 第 2 例：真点控件 + 假回调断言参数，
  不是 `expect(find.text(...), findsOneWidget)`。
- 上一轮在零测试区抓到过真 bug（`writing_panel` 词块输入框吞分隔符），同类问题
  现在还可能在。

### 7.3 性能 / 运行时表现完全没覆盖（已处理已知的两处热点）

> ✅ 2026-11-10 晚修：`VocabBrowseViewModel` 的筛选结果与排序列表按条件缓存
> （只改排序不重扫整库），`ProductionHistoryView` 的四趟派生统计按「历史列表引用 +
> 吃法筛选」记忆化。配了 7 例缓存行为测试（含两千条词一帧只扫一次）与 1 条
> 有记录的页面用例。**「有没有 baseline」这一层仍然没做**，下面列的量测项依旧有效。

1,749 例测的是逻辑正确性，**不反映 App 跑起来顺不顺**。完全没测过的：

- 冷启动时间、首页九张卡的构建耗时；
- 词库几千条时 `/词库` 页的滚动与搜索；
- 长文章（几千词）进精读页的内存峰值；
- AI 跑批 30 词一块时的 http 内存占用（响应体整段解码）。

没有性能基线，任何一次「是不是变慢了」都只能靠感觉。真要做，先在真机上量
冷启动 + 词库滚动两项，别铺开做全套。

### 7.4 两个 `/100` 口径不同（已注明，未统一权重）

> ✅ 2026-11-10 晚：两份报告都把精确分改成了区间读法（整库 **96 ± 2** / PR **≈ 74–80**），
> 并在顶部写了口径声明。**两套权重本身仍未统一**，只是不再假装可比。

整库 Dashboard 97 分与 PR Review 77 分**不可比**：同一批问题在整库报告折 −13、
在 PR 报告折 −23。PR 报告 Scope 自己写了 sampled 却给精确到个位的分数，我在
顶部补了口径声明，但**没有真正统一两套权重**。

- 要么把两者都改成「区间」（如 95–97），要么分成两个明确不同的指标名。
- 现在保持原样，因为分数只是给人看的参考，不是 CI 门禁。

### 7.5 「1,749 例」里含金量没分层（已定规矩，存量不追溯）

> ✅ 2026-11-10 晚：`docs/TESTING.md` §二补了 `[Web]` / `[Dart]` 前缀约定，
> 给了四个真实例子。存量 1,700+ 例不改，新写的必须带、动到的顺手带。

没区分「从 Web 版测试逐条翻过来的」与「为 Dart 边界真写的」。前者保证行为一致，
后者才抓新引入的问题（如 `clozeParts` 丢分隔符、`countWritesOnDay` 的 UTC 时区）。
现在只有一个总数。

- 想分层得给每个测试加标记，成本大于收益，暂时不做。
- 折中：新增测试时在用例名里写清「Dart 边界」还是「对齐 Web」。

### 7.6 剩下两条 🟢（一条已修，一条攒着）

> ✅ 2026-11-10 晚：`smokeFinish` 改成「连续两轮没有排帧 / 瞬态回调就返回」，
> 上限 12 轮兜底，参数提成四个具名常量。

- ~~`test/views/smoke_harness.dart` 的 `smokeFinish` 固定 6 轮~~
- `lib/core/quiz.dart` 518 行 / 6 个顶层函数零消费者，已定性为「P7 考试链路预留」，
  写在 `docs/PLAN.md` 的 P7 段。等真要考试功能时再动。

---

## 第八件：真机用起来的问题（2026-11-10 深夜，用户报，明天 overhaul）

> 用户原话：「处理完手头问题之后，不用打包，今天就到这，下面问题写todo，
> 应该会连带明天我发现的问题，一并 overhaul。」
> 顺序按他给的编号，不改。**这批是「用起来」的问题，前七件是「写得对不对」的问题**，
> 口径不一样：这里的每一条都得先在真机上复现，再谈改。

### 8.1 切换界面的按键都卡 1 秒左右 ✅ 已定位并修（2026-11-11）

**实测数字**（真备份 `economist-backup-2026-11-10.json`：10,892 词 / 13,554 篇次关联 /
50 篇，词库 JSON 20.9MB）。桌面与模拟器各跑一遍：

| 步骤 | 桌面 | 模拟器（Pixel_4） |
|---|---|---|
| 读 33.1MB 备份文件 | 266 ms | 1,033 ms |
| `jsonDecode` | 567 ms | 1,053 ms |
| `parseBackupPayload` | 947 ms | 1,988 ms |
| **`vocab.load()`（进页面就走这条）** | **1,501 ms** | 冷 6 ms / 暖 5 ms（修后） |
| `vocab.meta()` | 1 ms | 3 ms |
| **`vocab.save()` 增量（改 1 条）** | **3,157 ms** | **2,486 ms** |
| `vocab.save()` 首次灌库 | 12,737 ms | 124,756 ms |
| `articles.save()` × 50 | 4,588 ms | 52,203 ms |
| `articles.list()` | 4 ms | 4 ms |

**根因**：不是渲染，是 `VocabRepository.load()` 每次都要
「gzip 解压 20.9MB → `parsePayload` → `migrateLibrary`」≈1.5 秒，
而**每个页面 `initState` 的 `bootstrap()` 都读一次** → 进哪页都卡。

**已修**（`lib/data/repositories/vocab_repository.dart`）：`load()` 先只查
`meta()`（`SELECT item_count, updated_at`，1ms），版本号没变直接返回上次解析的对象，
连 gzip 都不解。写入路径（`save` / `migrate` / `clear`）成功后顺手更新缓存。
`load()` 1501ms → **1ms**。

顺带把 `save()` 里的「内容没变」判定从「重新解压 20MB 再比」改成比缓存里的明文
（832ms → 472ms），冲突检测也从 `_selectPrev()`（解 20MB）改成 `_selectPrevMeta()`。

### 8.2 速读哪去了？—— ✅ 已接通（2026-11-11）

`lib/core/reader_view.dart` 的 `ReaderViewFlagsInput` 里有 `speedReadOpen` 字段，
**但全库没有对应页面、没有入口** —— 不是藏起来了，是**根本没移植**。

用户原话（m23127）：「速读肯定要做的，留着。」

**已落地的四层**：

| 层 | 文件 | 测试 |
|---|---|---|
| 纯逻辑 | `lib/core/speed_read.dart`（目标时长 / 挖空 / 判分 / 结算） | `test/core/speed_read_test.dart` 20 例 |
| 正文签名 | `lib/core/doc_signature.dart`（`标识@djb2` 当游标键） | `test/core/doc_signature_test.dart` 9 例 |
| 偏好解析 | `lib/core/speed_read_prefs.dart` | `test/core/speed_read_prefs_test.dart` 13 例 |
| 状态编排 | `lib/viewmodels/speed_read_view_model.dart` | `test/viewmodels/speed_read_view_model_test.dart` 16 例 |
| 界面 | `lib/views/speed_read_page.dart` + 首页第四张卡 | `test/views/speed_read_page_test.dart` 6 例 |

和 Web 版的口径差异（有意为之）：

- **Web 的速读是「整篇连续滚 + 按词高亮」，这里是「一句一屏 + 计时」**。理由：手机上
  连续滚 + 逐词高亮要每帧重建文本，8 英寸屏还容易跟丢；一句一屏更好控制，也才谈得上
  「超时就地拷打」。
- 译文与语言点**只在揭晓阶段出现**（复用 `lib/views/sentence_extras.dart`），
  读的时候给出来就等于开卷。揭晓阶段整屏**停住**（`elapsedMs` 定格在 `_readMs`），
  顺手给出「搭配」与「本句速度 N 词/分」，用户看完自己点「下一句」。
- **底部只有「上一句 / 下一句」两个常驻按钮，没有「读完了」「拷打」「跳过」**
  （2026-11-11 按用户 m23913 改）：按钮文字不随阶段变，「下一句」按当前阶段干活 ——
  读的阶段按它 = 读完（**超时且开了自动拷打会直接进拷打**，用户 m23919 明确要求），
  揭晓阶段按它 = 继续，拷打阶段按它 = 不做拷打直接翻句（所以「跳过」不需要了）。
  现在按什么会发生什么，用底部一行小字提示（`_hintOf`）。
- **可以回上一句**（「上一句」→ `vm.go(-1)`，第一句禁用）。
  回退只移动游标、不记成绩 —— 只有 `advance()` 走到 `_finish()` 才落一行 `SpeedRow`。
- 挖空目标优先级与 Web 一致：语言点 phrases → 本句生词 → 最长实词（`pickTargetBlank`）。
- 游标按 `文章 id + 正文签名` 存，正文改过老游标自动作废。

**还没做**：阅读页里没放入口（首页第四张卡是唯一入口）；`ReaderViewFlagsInput.speedReadOpen`
仍是没人读的死字段。要不要把速读塞进阅读页，等用户看过这一版再定。

### 8.3 跟读录音后不能播放 + 朗读引擎怎么选 ✅ 已接通（2026-11-12）

两件事都做了：

1. **录完能回放**：加了 `audioplayers: ^6.8.1`（只放 `lib/services/`）。
   - `lib/core/ports.dart`：`RecorderPort` 的 `stop()` 改成**不删临时文件**，
     新增 `String? get lastPath` + `clearTake()`；再加一个 `PlaybackPort`
     （`play` / `stop` / `isPlaying` / `progress` / `dispose`）。
   - `lib/services/audio_playback.dart`：`AudioPlayback` 用懒创建的 `AudioPlayer`
     （理由同 `DeviceRecorder`：构造就碰平台通道，widget 测试会 `MissingPluginException`）。
   - 临时文件的生命周期：**只活到下一次换句 / 退出页面 / 下次开录**，
     由 `ShadowingViewModel.clearTake()` 删；音频绝不上传、不进任何存储。
   - 跟读页在判语卡片里加「听自己读的」（`_VerdictCard`，`vm.hasTake && !vm.recording`
     才出现；播放中变「停下」）。
2. **朗读引擎可在 App 里选**：`flutter_tts` 的 `getEngines` / `setEngine` 都接上了。
   - `lib/core/tts_engine.dart`：`SpeechEngine{name, label}` + `parseSpeechEngines` /
     `readTtsEngine` / `resolveTtsEngine`（**存下来的包名已卸载 → 退回系统默认**，
     免得拿着装不上的名字反复抛）。
   - `lib/core/ports.dart` 另加 `SpeechEnginePort`（与 `SpeechPort` 分开：
     语速谁都能设，枚举引擎只有系统 TTS 有）。
   - `lib/services/speech_engine_picker.dart`：`SpeechEnginePicker extends ChangeNotifier`
     收「列表 / 选中 / 落盘」。**为什么单独一个类**：跟读 ViewModel 已经四十几件事，
     再塞引擎枚举就撞 40 方法门禁（实测 45 > 40）。
   - 设置页多「朗读」卡：引擎下拉（null = 系统默认）+ 语速滑杆。
   - 键：引擎 `tts:engine`（`PrefsStore.loadTtsEngine/saveTtsEngine`，传 null 就删键）；
     语速沿用 `shadowing.ui.speechRate`。

**踩过的坑**：`flutter_tts` 里 `getEngines` 是 **getter**（`await _tts.getEngines`），
写成 `getEngines()` 报 `invocation_of_non_function_expression`；换引擎会把语言重置，
所以 `_ensureReady()` 里必须**先 `setEngine` 再 `setLanguage('en-US')`**；
`SpeechEnginePort` 与 `SpeechPort` 不相干，`is` 之后直接调跨接口成员不通过，
要显式 `speech as SpeechEnginePort`。

**还没做**：跟读页没有「逐词高亮」（`core/tts_timing.dart` 已备好纯函数，没人用）。

### 8.4 主界面上点任何模块也卡 1 秒 ✅ 同 8.1，已一并修掉

与 8.1 同源：首页点卡片 → `Navigator.push` → 目标页 `initState` 的 `bootstrap()`
同步卡住首帧。`vocab.load()` 加缓存后，模拟器实测：

- 背单词页首帧：冷 2,797 ms → **热 553 ms**（冷启动那次仍要解析一遍，躲不掉）
- 词库页首帧：1,085 ms → 缓存后 `bootstrap()` 44 ms

还剩的冷启动那一次（解析 20.9MB）：如果要再压，方向是把 `parsePayload` 挪
Isolate（`compute`）+ 首帧先出骨架屏。**没做**，因为只在「App 冷启动后第一次进页面」
出现一次，不是用户抱怨的「每次点都卡」。

### 8.5 背单词界面点「下一个」也卡 1 秒 ✅ 已修（2026-11-11）

**实测**：评分走 `grade()` → `_persist()` → `vocab.save()`，模拟器上一次 **2,486 ms**
（`encodeVocabLibrary` 序列化 20.9MB + gzip + `rebuildVocabProjection`）。
而且 `grade()` 里是 `await` 完落盘才 `notifyListeners()`，所以界面就卡在 await 上。

**已修两处**（`lib/viewmodels/study_view_model.dart`）：

1. **先回界面再落盘**：`grade()` / `learnStep()` / `checkSpelling()` 改成先在内存改
   session 并 `notifyListeners()`，写盘在背后跑，写完再通知一次刷错误提示。
2. **合并写**：`_persist` 从「串行排队」改成「只保留最新一份」——
   写盘期间又评分了，就等这次写完再拿最新的写一次（中间态已被后一次包含）。
   连点 5 次不再排 5 个 2.5 秒的队。配 `flushWrites()`，切后台时
   （`StudyPage` 的 `didChangeAppLifecycleState`）把最后一次补上。

**注意**：单次写盘本身仍是 2.5 秒（16MB 序列化躲不掉），只是不再挡界面、
也不再累积。要真正压下来得走「单条更新」或「序列化挪 Isolate」，**没做**。

### 8.6 开发用的真数据样本 ✅ 已接通（2026-11-11）

用户原话（m23659）：「我建议你把我准备的json数据包直接在开发过程中用上
（也就是放到app中），能省很多事，还方便发现问题。」

- `pubspec.yaml` 的 `assets:` 加了 `assets/data/`；
- `lib/views/backup_page.dart` 里 `sampleBackupAsset` 常量指向那份 JSON，
  `kDebugMode` 时备份页多一张「开发用 → 导入内置样本」卡片，走覆盖导入；
- 样本**不进 git**（`.gitignore` 忽略 `assets/data/*`，只留 `assets/data/README.md`）。

**待办**：样本目前仍会打进 release 包（`assets:` 是全局的，多 33MB）。
要瘦身就上 debug-only 的 Android flavor，把 `assets/data/` 只挂到 debug variant。

### 8.7 精读词表改右侧抽屉 + 单词一键复制 ✅ 已接通（2026-11-11）

用户原话（m23913）：「精读中，单词表改成侧边栏，从右侧滑入即可，单词表中任意单词，
加个按键，点击复制。」

- `lib/views/reader_page.dart` 的 `_VocabSheet`（底部 sheet）换成 `_VocabDrawer`
  （`Scaffold.endDrawer` + `endDrawerEnableOpenDragGesture: true`），宽度取屏宽 86%；
  AppBar 的「本篇词表」按钮走 `_scaffoldKey.currentState?.openEndDrawer()`，
  右边缘左滑也能拉出来。
- 每行右侧加复制按钮：`Clipboard.setData(ClipboardData(text: view.item.word))`，
  复制的是**单词本身**（不带释义）。**反馈用「图标变对勾 1.2 秒」而不是 SnackBar**
  —— 真机上抽屉盖住了页面底部，SnackBar 弹在抽屉下面，用户根本看不见（截图验证过）。
- 抽屉里原来那个序号 `CircleAvatar` 去掉（右侧要放按钮，一行塞不下三样）。
- 测试：`test/views/reader_vocab_drawer_test.dart` 2 例（点按钮滑出抽屉 / 复制按钮真写进
  剪贴板并变成对勾 —— 用 `setMockMethodCallHandler(SystemChannels.platform)` 拦
  `Clipboard.setData`）。

### 怎么推进这批

1. ~~先只做**量测**（8.1 / 8.4 / 8.5 一起量）~~ ✅ 2026-11-11 已量完，数字见上；
2. 8.2 与 8.3 是功能缺口，不是性能问题，单独排；
3. 每条改完都要能在真机上指着说「现在不卡了 / 现在能放了」，
   不能只看测试绿。

---

## 第九件：选词模式与自动标词（2026-11-11 深夜，用户报）

用户原话（m24894）：「这个取词效果太粗糙了，我建议是仿照 web 版本，有选词模式，
开了选词模式可以点词选词；另外注意，在速读模块，选词模式也要有并且要复用……
另外自动选词功能没有重现吗？web 版本侧边栏有一键处理 + 补充离线例句，
如果你感觉不需要，可以把现有的粗糙的选词模式删除或者部分删除……
然后实现 web 端选词模式到精读和速读的基本框架，但是不实现功能，
包括一键处理 + 补充离线例句，完成框架，加到 todo 里，以后如果有需要，知道怎么完善。」

### 9.1 选词模式（精读 + 速读共用开关）✅ 已接通（2026-11-12）

用户要的「开选词模式点词选中、精读与速读共用同一个开关」已落地（提交 `95bb21f`）：

| 层 | 文件 | 测试 |
|---|---|---|
| 选中的词与词组 | `lib/core/word_pick.dart`（`PickTarget` / `PickState` / 同句连续才合成词组 / `PickEntry` 带 `count` 与 `kind`） | `test/core/word_pick_test.dart` 19 例 |
| 开关状态 | `lib/viewmodels/pick_mode_view_model.dart`（**独立 VM**，两页读同一份；含 `multi` 多选开关） | `test/viewmodels/pick_mode_view_model_test.dart` 15 例 |
| 收词落库 | `lib/services/vocab_mark.dart`（`addWordsToArticle` 收 `List<PickEntry>`，透传 `kind` 与 `sentenceId`，冲突重放一次） | `test/services/vocab_mark_test.dart` 7 例 |
| 逐词可点 | `lib/views/pickable_sentence.dart`（`GestureDetector` 逐词，不用 `TextSpan(recognizer:)` —— 那个要手动 dispose） | 页面用例覆盖 |
| 精读正文 | `lib/views/reader_body.dart`（`ReaderBody` + `PickBar`，底栏有「多选」chip） | `test/views/pick_mode_test.dart` 4 例 |
| 会话统计 | `PickSession` 写 `LearningSection.sessions`，截最近 500 条 | — |

**多选开关（2026-11-12 加）**：底栏「多选」默认关 —— 一次只收一个词，点第二个顶掉第一个；
打开后连点相邻词才拼成词组（`PickEntry.kind == VocabItemKind.phrase`），底栏文案变成
「已选 N 个词 · M 条（K 条词组）」。切回单选只留最后点的那一个。
**词组现在会真的进本篇**（`_collectToArticle` 不再拦 `phrase`，只拦 `idiom` / `usage`
和多词但没标类型的），但 `articleEntryViews(includeLang: false)` 仍把它挡在正文编号外。

**没做**（框架留在这儿）：手机没有鼠标框选，所以只有「点词」这一种选法，
没有 Web 那种拖动选一段（Web 用 Ctrl 点离散选 + 拖动整段）。

### 9.2 自动标词（`autoVocab`）✅ 已接通（2026-11-12）

Web 的 `src/reader/panels/ReaderToolbar.tsx:287` 有个 `tb-autovocab` 按钮：
「按所选词汇标准，让 AI 从全文挑出要查的词（结果进『待选』）」。

App 侧落地（精读页 AppBar 的 ✨ 按钮）：

| 层 | 文件 | 测试 |
|---|---|---|
| 结果解析与去噪 | `lib/core/auto_vocab.dart`（`parseAutoVocabWords` / `autoVocabCandidates` / `autoVocabLevelLabel`） | `test/core/auto_vocab_test.dart` 16 例 |
| 界面流程 | `lib/views/auto_vocab_sheet.dart`（选水平 → `AiPasteSheet` → 勾选清单 → `markCurrentWord` 逐个收） | `test/views/auto_vocab_sheet_test.dart` 1 例 |
| 提示词 | 现成的 `lib/core/analyzer_prompt.dart:162 buildAutoVocabPrompt` | `test/core/analyzer_prompt_test.dart` 已有 |

**AI 不听话的几种写法都在 `parseAutoVocabWords` 里吃掉**：行首编号 / 项目符号 / ①、
`word —— 释义`、`word（释义）`、`word: 释义`、直接跟中文、一行多个词、引号包着、
太短的词（`of` / `is`）、短语（带空格的一律丢 —— 短语该走「语言点」不进生词本）。
连字符词（`well-being`）整词保留，不从中间切。

界面与 Web 的差别：Web 用侧栏「待选」页签人工增删，手机上换成一张**默认全选**的
勾选清单（从全选往下减比从全零往上加省事），勾完一次收进本篇。

### 9.3 一键处理 + 补充离线例句 —— ✅ 框架已搭（2026-11-12），动作未实现

用户明确说：手机端数据本来就从 Web 拿，这两个功能可以先不做，
但**框架要在**，以后想补时知道往哪补。

App 侧：`lib/core/dict_tools.dart`（`dictToolSteps` 五步清单 + `dictStepEnabled` +
`dictToolsBlocker`）+ 词库页 AppBar 的 ⚡ 按钮 → `_DictToolsSheet`（五个 ListTile
全标「未实现」、底部 `FilledButton` 的 `onPressed: null` **禁用不隐藏**）。
测试：`test/core/dict_tools_test.dart` 10 例 + `test/views/vocab_browse_page_test.dart` 第 2 例。

**`dictStepEnabled` 现在恒 false** —— 动作没写，光有数据也不算能跑。以后接上某一步，
把它从「恒 false」改成真判定，界面不用改。每步要调的现成函数写在
`lib/core/dict_tools.dart` 的 doc 注释里（挑词 / 补齐 / 例句 / 校正 / 混淆各一行）。

### 9.3 一键处理 + 补充离线例句 —— **只搭框架，不实现**

Web 口径（`src/reader/panels/SidePickDictTools.tsx` + `src/reader/hooks/useDictTools.ts`）：
`⚡ 一键处理（挑词 / 补齐 / 例句 / 校正 / 混淆）`，依次跑
「挑词 → 补齐生词本 → 补例句 → 校正原形 → 补混淆项」，每步都能单独跑。

Dart 侧现成积木：
- 挑词：`buildAutoVocabPrompt`（同上）；
- 补齐：`buildBatchLookupPrompt` + `parseLookupTable` + `applyWordAnalysis`（AI 跑批已在用，见第六件的 `lib/core/ai_jobs.dart`）；
- 补例句：`buildExamplePrompt`（`analyzer_prompt.dart:84`）；
- 校正原形：`buildLemmaPrompt`（`:210`）+ `normalizeLemma`；
- 补混淆项：`buildConfusablePrompt`（`:178`）。

要搭的框架：给词库页/精读侧栏留一个「⚡ 一键处理」入口，点了先弹一个
「还没做，这几步以后接」的说明 + 五步清单（**按钮禁用**，不是隐藏），
把上面的函数名写在注释里，方便以后照单接。

### 9.4 按篇 / 按需懒加载（用户 m25095 / m25098）

用户觉得「一次性把全部语言点和生词读进内存太过分」。实测（2026-11-11，真备份）：
10,892 条的词条 JSON 是 6.1 MB（contexts 1.8 / examples 1.6 / 释义 0.2），
**只用精简字段约 1.11 MB**；`VocabRepository.load()` 命中内存缓存是 0 ms。

结论：现在不是瓶颈，收益有限。真要按篇加载有两条路：
- 轻：`ReaderViewModel` 只按需 `articleEntryViews(...)`（已在这么做），
  但整库仍在内存 —— 这只省渲染，不省内存；
- 重：给 `rebuildVocabProjection` 加一张 `article_entries(article_id, lemma, item_id, added_at)`
  投影表，按篇查词条不走 payload 解析。**这会多一套 SSOT 口径**，
  且 `isFresh` / 到期判定也得下推 SQL，容易和 `core/vocab/review.dart` 分叉，
  要动先写决策。

### 9.5 回顾的小结页 ✅ 已接通（2026-11-12）

背单词现在有三个入口（学习 / 复习 / 回顾），小结页多了一张「接下来」卡
（提交 `b17506d`）：

| 情况 | 给什么 |
|---|---|
| 本篇还有生词 | 「继续学这 N 个」 |
| 生词学完了、有到期的 | 「去复习这 N 个」 |
| 都没有 | 老实说没有，指回去换一篇 / 再收几个词 |

**不自动跳**：跳走会把「认识 / 模糊 / 忘记」的结算数字盖掉。
判断在 `lib/core/study_next_step.dart`（`roundNextStep`，纯函数，5 例单测），
界面只负责画 —— 同一个判断写两遍会分叉。

---

### 9.6 词库筛选改成抽屉面板 ✅ 已接通（2026-11-12）

用户原话（m27346）：「选项不应用 button，建议换成一个日常关闭的面板，点击打开」，
四组条件 + 分块 + 全部持久化。

| 层 | 文件 | 测试 |
|---|---|---|
| 偏好形状与守卫 | `lib/core/vocab_browse_prefs.dart`（默认**本篇 / 单词 / 复习**，坏项各自回默认） | `test/core/vocab_browse_prefs_test.dart` 11 例 |
| 落盘 | `lib/data/prefs_store.dart` 的 `loadVocabBrowsePrefs` / `saveVocabBrowsePrefs`（键 `vocab:browse`） | `test/data/prefs_store_test.dart` |
| 面板 | `lib/views/vocab_filter_sheet.dart`（四块竖排 + `_ChoiceTile` 单选行 + 日期 `DropdownMenu(enableFilter: true)`） | `test/views/vocab_browse_page_test.dart` 2 例 |
| 页面 | `lib/views/vocab_browse_page.dart`：AppBar 筛子图标 + 一行摘要 `_FilterBar` | 同上 |

`VocabBrowseViewModel` 构造收 `PrefsStore?`，每个 setter 后 `_persist()`
（`unawaited`，写偏好失败不卡界面）。**`loadVocabBrowsePrefs` 读不到时回 `null`
而不是回一份默认对象** —— 默认值只由 core 的构造函数负责，两处默认必然漂移。

---

## 第十件：浅色主题（2026-11-12 晚，用户 m27710）✅ 已接通

用户原话：「加一套浅色主题……设置页面上的设置点进去的出现两个 sector，
一个点进去是现在的背诵设置，另外一个皮肤 sector，点进去有深色、浅色、跟随系统；
注意加主题这个工作量不小，要考虑到未来主题的扩展性，可以参考 patrol helper」。

| 层 | 文件 | 说明 |
|---|---|---|
| 偏好守卫 | `lib/core/theme_prefs.dart` | `enum AppThemeMode { system, light, dark }` + 键 `theme:mode`；**存枚举名不存序号**（以后往枚举中间插值不会让老用户的选择错位）；测试 8 例 |
| 配色令牌 | `lib/theme/app_skin.dart` | `enum AppSkin { classic('经典蓝') }` + `SkinColors extends ThemeExtension<SkinColors>`（`success` / `successSurface` / `heat1..3` 五个令牌，浅深各一份）；`SkinColors.of(context)` 在未注册时按明暗回落 classic，裸 `MaterialApp` 的组件测试不崩 |
| 主题装配 | `lib/theme/app_theme.dart` | `AppTheme.light({skin})` / `AppTheme.dark({skin})` + 顶层 `themeModeOf(AppThemeMode) → ThemeMode`（**core 不许 import flutter，所以映射放这层**） |
| 状态 | `lib/viewmodels/theme_view_model.dart` | `ThemeViewModel extends ChangeNotifier`，先改内存 + notify 再落盘；测试 7 例 |
| 落盘 | `lib/data/prefs_store.dart` | `loadThemeMode()` / `saveThemeMode()`（键 `theme:mode`） |
| 接线 | `lib/main.dart` | `Consumer<ThemeViewModel>` 包 `MaterialApp`，`theme:` + `darkTheme:` + `themeMode:` 三件套；`ChangeNotifierProvider<ThemeViewModel>` 放在所有 VM 之前 |
| 设置页 | `lib/views/settings_page.dart`（目录，三个 `_EntryCard`）+ `lib/views/study_settings_page.dart`（原背诵设置整段搬过去）+ `lib/views/speed_settings_page.dart`（语速、超时拷打）+ `lib/views/theme_page.dart`（明暗三选一 + 配色卡） | `test/views/theme_page_test.dart` 4 例 |

**加一套新皮肤只改三处**：`AppSkin` 枚举加一支（带 `label` 与两个 seed getter）、
`SkinColors` 加一对 `xxxLight` / `xxxDark` 常量、`SkinColors.resolve` 与
`AppSkin.lightSeed/darkSeed` 的 switch 各加一支。界面代码一行不用动。

**顺手清掉的硬编码色**：`views/study_card_view.dart` 的 `heatColor(scheme, skin, heat)`
三档热度色改成 `skin.heat1/2/3`、答对底色改 `skin.successSurface`；
`views/ai_batch_page.dart` 两处 `Colors.green` 改 `SkinColors.of(context).success`。
全库现在没有写死的颜色字面量。

**坑**：Flutter 3.44 里 `RadioListTile` 的 `groupValue` / `onChanged` 已废弃，
必须用 `RadioGroup<T>` 祖先包一层、`RadioListTile` 只留 `value`；
页面 pop 之后测试要 `pump(600ms)` 再 `pump()`，退场动画没走完就点会命中正在淡出的那层。

### 10.1 速读设置搬进设置页（同日补，用户 m27987）

用户原话：「速读的语速设置也放在设置页，设置页加 sector 速读设置，点进去有语速设置。
速读页的语速设置完全移过去，不放在速度界面。」

- 新建 `lib/views/speed_settings_page.dart`：语速 `Slider`（`minWpm` 50 – `maxWpm` 400，
  默认 `defaultWpm` 120）+ 「超时就拷打」`SwitchListTile` + 两句说明（达标时长按
  「词数 ÷ 语速 + 1.5 秒」算；改完即生效、记在本机）。
- `lib/views/speed_read_page.dart` 里整块删掉 `_SettingsCard`（原来是选篇页顶部那张卡），
  选篇页现在只剩「挑一篇来读」+ 文章列表。**VM 与落盘键不动**：仍是
  `SpeedReadViewModel.setWpm/setAutoDrill` → `reader:speedWpm` / `reader:speedAutoDrill`。
- 设置页目录多一张 `_EntryCard(icon: Icons.speed_outlined, title: '速读设置', page: SpeedSettingsPage(), key: ValueKey('settings-entry-speed'))`，
  现在三个入口：背诵设置 / 速读设置 / 皮肤。
- 测试：`test/views/speed_read_page_test.dart` 第 1 例从「空态与语速设置」改成
  「空态（语速设置已搬去设置页）」，并断言 `find.text('超时就拷打')` 与
  `find.byType(Slider)` **都是 `findsNothing`**（防止哪天又摊回来）；
  `test/views/theme_page_test.dart` 第 1 例扩到三个入口，点 `settings-entry-speed` 后断言
  `SpeedSettingsPage` + 「语速」+「超时就拷打」。

---

## 已知的坑（别再踩）

- **release APK 默认只打 arm64**，模拟器是 x86_64，直接装会崩：
  `Could not find 'libflutter.so'. Looked for: [x86_64, x86], but only found: [arm64-v8a].`
  本地调试用 `flutter build apk --target-platform android-x64`。
- **`flutter build` 会把 Gradle 输出全缓存到结束才打印**，日志长时间不动不代表卡死。
  看真实进度用 `sh scripts/watch_build.sh`（盯 `.tmp` 下载中文件 / build 产物 / APK）。
- **本机到镜像的 TCP 连接会「假活」**（连接在、数据不来）。已在
  `android/gradle.properties` 压短超时，坏连接会快速重连。
- **含中文的 Dart 文件只能用 `write`/`edit` 工具改**。pwsh 的
  `.Replace()` + `WriteAllText` 会把 UTF-8 写成 GBK，之后 read 直接报
  `invalid UTF-8 text`。
- **测试里 ViewModel 要用 `.value` 注入且不 dispose**。目标页 `initState` 的
  `bootstrap()` 读真 SQLite 的 Future 会在拆树 dispose 之后才回来，报
  `A XXXViewModel was used after being disposed.`
- **`AudioRecorder()` 构造函数就会碰平台通道**，widget 测试里没插件实现会抛
  `MissingPluginException`。已改成懒创建。
- **默认测试窗口只有 800×600**，首页 8 张卡放不下，最后一张在视口外
  `ListView` 不挂载它。用 `useTallScreen(tester)` 调到 **1080×3000**（九张卡 +
  底部文案，2600 已不够）。
- **`INTERNET` 权限必须自己写进 `android/app/src/main/AndroidManifest.xml`**。
  Flutter 模板只在 `src/debug/` 与 `src/profile/` 里给这一条（工具链热重载要用），
  release 只合 `main`，漏了的话装到手机上**任何**网络请求都报
  `Failed host lookup: 'api.deepseek.com'`——看着像 DNS / 网络不通，其实是没权限。
  2026-11-10 踩过一次（AI 跑批上真机）。核对办法：
  `aapt2 dump badging app-release.apk | findstr INTERNET`。
- **重打 release 前先停 Gradle 守护进程**。`:app:packageRelease` 会报
  `java.io.IOException: Unable to delete directory '...\build\app\outputs\apk\release' /
  Failed to delete some children`，`Remove-Item` / `Rename-Item` 全部「文件正由另一进程使用」；
  锁定者是 `I:\tools\jdk17\bin\java.exe`（Gradle daemon）。`Stop-Process -Id <pid> -Force`
  之后 APK 立刻可删，不用重启机器。
- **`Get-Content` 打印中文 Dart / XML 会是乱码**（pwsh 默认按 GBK 解码），
  文件本身没坏——判断有没有坏用 `aapt2 dump badging` 或 `flutter analyze`，别看终端回显。
- **性能基准用 `test/bench/vocab_bench.dart`，文件名故意不带 `_test`**：
  `flutter test` 全量只收 `*_test.dart`，这份得手动跑
  （`flutter test test/bench/vocab_bench.dart`），否则每次全量都要多花 13 秒。
  没有真备份时它会造 10,000 词合成数据，只看趋势；有真备份
  （`assets/data/economist-backup-2026-11-10.json`）才反映真实数据形状。
  **冷读要用新 `VocabRepository` 实例**——同一个实例刚 save 过，缓存已填好，
  拿它测「冷」只会量到 1ms 的缓存命中（2026-11-11 踩过）。
- **真数据样本 `assets/data/economist-backup-2026-11-10.json`（33MB）已打进 App**：
  `pubspec.yaml` 的 `assets:` 收了 `assets/data/`，debug 包的「备份 → 开发用 → 导入内置样本」
  一键灌库（`kDebugMode` 守卫，正式包不显示这个按钮）。
  - **样本不进 git**（用户 2026-11-11 定）：`.gitignore` 忽略 `assets/data/*`，
    只留 `assets/data/README.md` 说明怎么放文件。新克隆的仓库没有样本，
    `test/views/backup_page_test.dart` 那条用例会自动 skip。
  - **别在 widget 测试里 `rootBundle.loadString` 它**：33MB 的 asset 读在测试的假异步里
    永远不完成，整条用例卡到 10 分钟超时（2026-11-11 踩过）。
    验「文件在、pubspec 登记了」用 `dart:io` 的 `File` 直接查。
  - 它仍会打进 release 包（`assets:` 是全局的），release 体积多 33MB。
    真要瘦身就把样本挪到 debug-only 的 flavor，见下面第 9 条。
- **热重载（HMR）要用 `tool/hmr_daemon.dart` 代理**（2026-11-12 加的）。
  `flutter run` 只认 **stdin** 上的 `r` / `R`；Windows 没有 POSIX `SIGUSR1`
  （`--pid-file` 那套只在 Unix 有效），而后台任务拿不到交互式 stdin。
  用法：后台起 `dart run tool/hmr_daemon.dart emulator-5554`，
  然后写触发文件 `echo r > .hmr-trigger`（热重载）/ `R`（热重启）/ `q`（退出），
  日志在 `build/hmr.log`（**用 `Get-Content -Encoding utf8` 读，否则中文乱**）。
  - 只对 Dart 代码改动有效。**改 `pubspec.yaml`（新依赖）、`AndroidManifest.xml`、
    assets 不会热重载**，必须重起 `flutter run`。
  - daemon 的判断依据是日志里出现 `Flutter run key commands`：没到这句之前的
    `r` 会被丢掉并记「还没就绪」。首轮冷编译（Gradle `assembleDebug`）要 1–2 分钟。
  - 别用 `File.openWrite()` 写日志再 `flush()` —— 会抛
    `Bad state: StreamSink is bound to a stream`（`_IOSinkImpl.write` 之后
    transformer 又往同一个 sink 塞）。用 `openSync` + `writeFromSync` 写原始字节，
    顺手也就不经过系统代码页转码，中文不乱。
