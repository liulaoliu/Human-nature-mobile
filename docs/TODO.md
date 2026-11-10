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
