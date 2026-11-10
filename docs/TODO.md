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

## 第二件：补 19 个页面的 smoke 测试

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

## 第四件：`_ErrorBar` / `_NoticeBar` 提到 `lib/widgets/`

**估算：一小时**

`_ErrorBar` 在 9 个文件、`_NoticeBar` 在 6 个文件各写一遍：
```
lib/views/articles_page.dart      lib/views/backup_page.dart
lib/views/drill_sentence_page.dart lib/views/golden_page.dart
lib/views/production_page.dart    lib/views/shadowing_page.dart
lib/views/study_page.dart         lib/views/vocab_browse_page.dart
lib/views/writing_page.dart
```
`_NoticeBar` 少 articles / study / vocab_browse 三个。

新建 `lib/widgets/status_bar.dart`，导出 `StatusBar.error(message)` /
`StatusBar.notice(message, onClose)`。`lib/widgets/` 就是为这种共享 UI 存在的，
不违反分层约束。

样式已经开始漂移了（`_NoticeBar` 有的带 close 按钮有的不带），越早收越好。

## 第五件：`core/writing.dart` 拆文件

**估算：一小时**

774 行、35 个顶层符号、被 13 处 import（全库扇入第一）。

按 `golden.dart` / `golden_parse.dart` / `golden_exam.dart` 已经走过的路拆：
- `writing_types.dart`：`ImitationTask` / `WritingFeedback` / `WritingIssue` /
  `WritingScore` / `WritingRecommendation` / `RubricItem` 等数据结构
- `writing_prompt.dart`：`buildImitationTaskPrompt` / `buildWritingFeedbackPrompt`
- `writing_parse.dart`：`parseWritingFeedback` / `parseWritingFeedbackDetailed`
- `writing.dart` 只留 re-export（保证现有 import 不用改）

## 第六件：给 `core/quiz.dart` 定性

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
  `ListView` 不挂载它。用 `useTallScreen(tester)` 调到 1080×2600。
