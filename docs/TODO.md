# 待办（2026-11-14 更新）

> 上半部分是**换电脑接手单 + 当前未完成事项**；下半部分是历史清单（已完成/已废弃的
> 决策留档，别当成现状）。排序按「先做什么收益最大」。

## 🔴 当前优先：Kokoro 实际文章读音怪（2026-11-16，用户）

**用户反馈**：

- 设置页「试听一句」正常；**直接点文章句子（没用离线生成）**读音很怪，
  「一个句子里有些词特别标准，有些错得离谱」，听起来「有点像在读德语」。
- 不是缓存问题：强杀 App、清掉 `tts_audio` 后直接点句仍然复现。
- 也不是退回系统朗读：已加 `ReaderPage` 兜底 SnackBar，点句没有弹出，
  `KokoroSpeech.speak` 正常返回；DB 里的 `article_sentences.text` 和界面一致。
- 之前 Kitten 也有「读不准」，但 Kokoro 错得更明显；Kitten 可能是模型本身，
  这次更像 **音素 → tokenizer** 的问题。

**关键发现（下一步从这里接）**：

1. 文章使用 `phonemize`（Dart，`en-us`）生成 IPA，再交给 Kokoro。
2. `assets/tts/kokoro/tokenizer.json` 的 vocab 里**没有**这些 IPA 字符：
   - `ɝ`（U+025D，bird / perfect / first 的元音）
   - `ɫ`（U+026B，global / clear / school 的暗 l）
   - `ê`（U+00EA，`raison d’être` 这种法语借词）
3. tokenizer 的 normalizer 会把不在 vocab 的字符**直接删掉**：
   - `perfect` → `pɝfɪkt` → `pfɪkt`（“pfikt”）
   - `global` → `ɡɫoʊbəɫ` → `ɡoʊbə`（“goh-buh”）
   - 文章里 `ɫ` / `ɝ` 很多，所以大片词听起来像外语；预览句只有 `ɝ`，不明显。
4. 之前的 `chunkText` 还会按 200 **字符**硬切，可能把单词劈成两半，造成
   “同一句里个别词特别怪”。已改成按词拼块（`KokoroEngine.kt`）。
5. 文本侧已加 `normalizeTtsText`（弯引号、破折号、G20、20’s、IMF、%、$ 等），
   但 **IPA 归一化还没做**。

**建议修法（按顺序）**：

- [ ] 在 `KokoroEngine` 把 IPA 送进 tokenizer 前做映射：
  `ɝ → ɜː`、`ɫ → l`、`ê → e`；再统一去掉 tokenizer 不认识的字符。
  （`ɜ`、`ː`、`l` 都在 vocab 里；先按这个映射试听，必要时改 `ɝ → ɜr`。）
- [ ] 加一行 native 日志：打印原始 IPA、映射后 IPA、被丢弃字符的集合，
      `adb logcat -s KokoroPhoneme`，确认没有别的漏网符号。
- [ ] 用 **同一句** 做 A/B：
  `Reading makes perfect.`（含 `ɝ`）和
  `The global economy has many ailments and few easy remedies.`（含 `ɫ`）。
  生成 WAV 后真机耳朵听；再跑 `ffmpeg -v error -i x.wav -f null -`
  （WAV 应该零报错；AAC 已弃用）。
- [ ] 确认短预览仍正常、文章句子不再“德语化”。
- [ ] 如仍不对，再试 **native `Phonemizer`**（`phonemize: false`）对比；
      注意它 `expandDigits` 是逐位读数字（2016 → “two zero one six”），
      需要先把数字展开成英文再交给它。

**当前工作区（未提交，接着改前先 `git status`）**：

- `lib/core/tts_text.dart` + test：文本归一化（弯引号 / G20 / 20’s / 缩写 / 单位）。
- `lib/services/kokoro_speech.dart`：`language: 'en-us'`、发音前归一化、WAV 缓存播放。
- `packages/neural_tts/android/.../KokoroEngine.kt`：`chunkText` 按词切；
  `synthesizeToFile` 已改 **WAV**（AAC 编码器在 vivo 上坏帧，见 §10 第二十六件）。
- `lib/views/reader_page.dart`：Kokoro 退回系统朗读时弹 SnackBar（用于取证）。
- 测试：`test/core/tts_text_test.dart`、`tts_audio_cache_test.dart` 等已过；
  全量 `flutter test` 最近一次 2587 passed / 1 skipped（改动后需重跑）。

**验收命令**：

```bash
flutter analyze
dart run tool/check_god_class.dart
dart run tool/check_layers.dart
dart run tool/check_core_tests.dart
flutter test
```

**注意**：手机是 release/debug 混装过，装 APK 前先唤醒；`adb install -r` 成功后再测。
测完把 WAV + IPA 映射 + 文本归一化合成一个 `fix:` commit，别和上一笔
`feat: 预生成朗读缓存` 混在一起。

---
## 换电脑接手单（2026-11-14）

**先读这三份**：`AGENTS.md`（硬约定 + 门禁 + 热重载边界）、`docs/ARCHITECTURE.md`（分层与依赖方向）、`docs/TESTING.md`（测试分层）。

### 代码在哪

- 仓库 `git@github.com:liulaoliu/Human-nature-mobile.git`（SSH；新机器要先配好 key，否则报 `could not read Username for 'https://github.com'`）
- 分支 `master`，工作区干净。**一切以 `origin/master` 为准**：写这份接手单时是
  `fa770e5`，之后可能还有纯文档提交（每改一次这份文档 hash 就往前走一格，别照抄）。
  `1e46eff` 之后的 `754b8b2` / `dc3b5af` / `fa770e5` 三个提交只改了这份接手单：
  补一键处理 / P7 交付记录、记下背单词流程对齐与卡面拼写两条待办
- Flutter 安卓版就在本仓库根目录；Web 版原项目在 `I:\Examples\Stutterer`（**只读参考，别在里面改**）

### 新机器上把环境起起来

1. 本项目用的 Flutter SDK 在 `I:\tools\flutter` —— 新机器换成你自己的路径，下文 `flutter` / `dart` 都指它
2. `flutter pub get`；`flutter analyze` 应该干净
3. 模拟器：`adb devices` 要看得到设备（本机 AVD 叫 `Pixel_4`，`emulator.exe -avd Pixel_4 -no-snapshot-load -no-boot-anim`）
4. 热重载：`dart run tool/hmr_daemon.dart emulator-5554` 后台跑，等 `build/hmr.log` 出现「已就绪」；之后写 `.hmr-trigger` 发 `r`（热重载）/ `R`（热重启）
5. 换机器后第一次直接整编一次，别指望旧 daemon 还在

### 提交前必须过的五门禁

```bash
dart analyze lib test tool
flutter test -j 4
dart run tool/check_god_class.dart
dart run tool/check_layers.dart
dart run tool/check_core_tests.dart
```

当前基线（2026-11-15 晚）：**2540 passed / 1 skipped**；251 个源文件过上帝类与分层；133 个 core 文件都有同名测试。
（pwsh 里 flutter/dart 的 stderr 会让命令报 `[exit code: 1]`，看 `All tests passed!` / `No issues found!` / `✅` 判成功。）

### 已经做完的，不用重做

P0–P6 全部 + 金句课 + 速读 + 选词多选 + 跟读复读 + 产出训练三种吃法 + AI 跑批搬进设置与阅读页（`2c2119e`）+ 拷打七档全开与「先看一遍」（`722639b`）+ 语法专项预选 grammar 档（`d15a936`）。

2026-11-14 这一轮又收了三块：

- **跟读逐词高亮**（`3063ca7`）：`SpeechProgressPort` + `core/tts_timing.dart` 的 `spokenWordIndex`，页面按词上色；老系统整句一条区间时不猜、不亮。
- **一键处理五步**（`e119b62`）：挑词 / 补齐生词本 / 补离线例句 / 校正原形 / 补混淆项，全部离线（ECDICT + Tatoeba），可单步也可一键连跑；词典启动后后台 isolate 解析。详见 9.3。
- **P7 整卷考试**（`1e46eff`）：词级卷 / 文章卷，自选题型 × 范围 × 题量；交卷写 `practice`、按题型累计、活动热力图；文章题不写 SRS / 错题本。首页第 9 张卡。
- **P7.1 考试会话**（2026-11-14）：会话恢复 / 考试历史与逐题明细 / 设置持久化 / 自动下一题·答完朗读·反复鞭打 / 听写 / 混合卷；见 `docs/PLAN.md` P7 段。
- **背单词学习 / 复习流程对齐 Web**：学习新词第一屏四选一中文释义（选错红绿高亮），复习三档评分后一律摊开释义并停住给「下一词 / 记错了」出口。详见下面「背单词学习 / 复习流程对齐」。
- **朗读三档**（2026-11-15，见第二十件 / 第二十六件）：系统 TTS 兜底 + Kokoro 离线（模型打进 APK，约 88MB；2026-11-16 顶替已删的 Kitten）+ Edge 在线（断网自动退回系统），设置页可选档位 / 音色 / 试听。

### 接下来可以做的（按收益排序，都不急）

1. ~~**背单词学习 / 复习流程对齐 Web**~~ ✅ **已完成**（2026-11-14，见下面「背单词学习 / 复习流程对齐」一节）：学习新词第一屏四选一中文释义；复习三档评分后一律摊开释义并停住，给「下一词 / 记错了」出口。
2. ~~**背单词「卡面拼写」接线**~~ ✅ **已完成**（2026-11-14，见下面「卡面拼写接线清单」）：设置开关打开后卡面正面出输入框，拼对解锁评分，拼错当场判「不认识」并给确认卡。详见下面「卡面拼写接线清单」。
3. ~~**安卓真机跑 AI 真请求**~~ ✅ **已完成（2026-11-15，安卓模拟器 Pixel_4_B）**：
   假 key 815→756 ms 拿到 401（网络栈全通），**真 key 869 ms 拿回模型正文 `通了`**，
   见下面「第二十三件」。`test/e2e` 那套桌面 e2e 仍未在安卓上跑（它读宿主环境变量，
   集成测试读 `--dart-define`，两条通道刻意分开）。
4. ~~**P7.1**~~ ✅ **已完成**（2026-11-14，见 `docs/PLAN.md` P7 段）：会话恢复（`core/quiz_session.dart` 存 `quiz:session`，设置页「继续上次考试」）、考试历史 / 逐题明细（`core/quiz_history.dart` 存 prefs，**不加 v14 迁移**）、考试设置持久化（`core/quiz_settings.dart` → `quiz:settings`）、自动下一题 / 答完朗读 / 反复鞭打（最多 3 轮）、听写入口（`quiz_prep._dictation` 按正文句序挖词库里的词）、词级 + 文章级混合卷（`QuizMode.mixed` 各出一半）。
5. ~~**一键处理真机验收**~~ ✅ **已完成（2026-11-15，安卓模拟器 Pixel_4_B）**：三项都在真机跑出了数字，见下面「一键处理真机验收（2026-11-15）」。结论：**不需要把 Tatoeba 导入 sqflite**。
6. ~~**写路径性能**~~ ✅ **已完成**（2026-11-15，任务书 `docs/PERF-TODO.md` 三处改动全部落地）。
   实测：`save 首次` 9244 → **2721 ms**（3.4 倍），`save 增量` 1536 → **1234 ms**。
   改的是 `projections.dart`（派生表改 batch 批量写 + 增量 diff 用投影指纹替代逐条 `jsonEncode`）
   与 `vocab_repository.dart`（gzip level 6 → 1）。现状数字与「剩下 2.7 秒在哪」见
   `docs/PERF-TODO.md` 第 2.1 节。真机冷启动 / 滚动帧率**用户明确不做**。

### 背单词学习 / 复习流程对齐（用户 2026-11-14 报）✅ **已完成（2026-11-14）**

> **落地摘要**：`review_step.dart` 的 `planReviewGrade` 改成「任何档都只摊卡、不写库、不推进」，
> 出口拆到新的 `planReviewExit(grade, choice)`（`ReviewExitChoice.next` / `missed`）；
> `study_session.dart` / `study_view_model.dart` 的 `grade()` / `learn()` 加了 `advance` 参数
> （默认 `true` 保住旧语义，`false` 时只写库不推指针）；
> `StudyCardFlow` 新增 `learnPhase` / `learnGraded` / `learnPick` / `learnWrong` / `learnContinued`
> / `reviewPending`，`drillReasonNow` 的 `learnPhase` 不再写死 false；
> `study_actions.dart` 重写成五态（学习判完 →「继续（看单词卡）」；复习摊卡 →「下一词 / 记错了」）；
> `study_page.dart` 在 `view.meaningGate` 之前插入 `learnPhase || (learnGraded && !learnContinued)` 走 `_MeaningBody`。
> 测试：`test/core/vocab/review_step_test.dart` 重写 13 例、新建 `test/viewmodels/study_card_flow_test.dart` 13 例、
> `test/views/study_page_test.dart` 加 2 例（共 5 例）。全量 **2391 passed / 1 skipped**，五门禁全绿。
> **口径**：按用户口径实现，**刻意偏离本地 Web**（Web 的 `planReviewGrade('good')` 仍是「直接推进不摊卡」），Web 侧未改。

**用户明确要求（原话要点，不要改口径）：**

1. **学习新单词阶段**：先显示**四个中文释义**让用户选；根据对 / 错处理 ——
   选对进入下一词；选错**红色高亮错误项、绿色高亮正确项**，再进入下一次。
   具体节奏参考 Web。
2. **非学习新单词阶段（复习 / 回顾）**：先显示**单词英文**；用户选「认识 / 模糊 / 忘记了」后，
   **显示单词释义并暂停在该页面**，再给出口：
   - 认识 → 「下一词」「记错了」
   - 模糊 → 「下一词」「记错了」
   - 忘记了 → 「下一词」

**App 现状（为什么没对齐）：**

- 学习新词没有「四选一」这一步：`lib/core/vocab/study_view.dart` 的 `meaningRequired` 只在
  `needsMeaningCheck`（打过「不认识」/ 重学 / 重练）时成立；普通 fresh 词直接进单词卡。
  Web 的 `useStudyLearnStep.ts` 是 `mode === 'learn' && isFresh(card)` 就进 `learnPhase`。
- `StudySession.learn` / `StudyCardFlow.pickMeaning` 其实已经有，但 `study_page.dart` 的
  `_SessionBody` 只在 `view.meaningGate` 时进 `_MeaningBody`，没有 Web 的 `learnPhase`。
- 复习 / 回顾：`StudyCardFlow.chooseGrade` 里 `good` 直接推进、`hard` 进 fuzzy、
  `again` 只进 graded；不是所有评分都摊释义。
- 用户点「认识 / 忘记了」看不到释义：`chooseGrade(good)` 直接推进；`again` 只置
  `_reviewGraded`，卡面 `revealed` 仍为 false；`StudyCardPanel` 的释义区只在
  `flow.revealed` 时显示。所以只能再点「看一下释义」。

**实现要点：**

- 学习新词：`StudyCardFlow` 增加 `learnPhase`（`mode == learn && isFresh(card) && !relearning &&
  canQuizMeaning`），开轮后第一屏直接显示 `_MeaningBody`，不是 `_CardBody`。
  判定复用 `LearnStep`：
  - 选对：按 `gradeLearnStep` 给 hard / good + `learnPass`，再按 Web 节奏进单词卡 / 下一词；
  - 选错 / 看答案：正确项浅绿、错误项浅红，停住等「继续」/ 自动过场，落库 again 且
    `meaningPasses = 0`。
- 非学习阶段：**任何评分都先摊开释义并停住**，出口按上面的矩阵：
  - good → 下一词 / 记错了；hard → 下一词 / 记错了；again → 下一词。
  - 「认识后点记错了」意味着 **good 不能立刻落库**：先摊卡等出口，选「记错了」时
    直接按 again 写一次，避免 good + again 双写、统计算两次。
- 释义展示：评分后必须 `revealed = true`，不能要求用户再点「看一下释义」。
- 参考 Web：`useStudyLearnStep.ts`、`useStudyReviewStep.ts`、`core/vocab/reviewStep.ts`、
  `StudyActions.tsx`、`StudyCardView.tsx`。
- **口径备注**：本地 Web 当前 `planReviewGrade('good')` 是「commit good + 直接推进 + 不摊卡」，
  与用户第 2 条「认识也要摊卡并给下一词 / 记错了」不一致。实施前先确认以用户这份为准；
  若以用户为准，Web 侧也要同步改（或明确 App 是刻意偏离）。
- 测试：学习新词四选一（选对 / 选错 / 看答案）、复习三档出口矩阵、评分后释义必显、
  「认识 → 记错了」不双写、重学卡 / 组末拼写不回归。

### 卡面拼写接线清单（Web 口径）✅ **已完成（2026-11-14）**

> **落地摘要**：新建 `lib/viewmodels/study_spelling_front.dart` 的 `StudySpellingFront`
> （前置条件 / 检查 / 拼错卡 / 换卡重置四组状态，`SpellMissCard` 值对象），
> 从 `StudyCardFlow` 拆出来是因为塞在一起会让它越过 40 个方法的门禁；
> `StudyCardPanel` 加 `spelling` / `onSpellInput` / `onCheckSpelling` 参数，
> 正面只渲染「释义 + 词性 + 输入框」（不显英文、不显音标、不自动朗读，整卡也不可点翻面）；
> 新增 `SpellMissPanel`（原文 + 你写的 + 「已判不认识」+ 「知道了，下一个」）；
> `StudyActions` 加「检查（回车）」与「知道了，下一个」两态（插在学习四选一之前）；
> `study_session.dart` / `study_view_model.dart` 的 `checkSpelling` 加 `advance` 参数
> （`false` 时拼对只解锁评分、不写库不推进 —— 卡面拼写只是门槛）。
> 测试：新建 `test/viewmodels/study_spelling_front_test.dart` 8 例、
> `test/views/study_page_test.dart` 加 1 例（共 6 例）。
> **修掉的 bug**：拼错卡的「你写的是」原来读实时 `_input`，用户检查后再打字会改掉判卷结果 →
> 改成检查那一刻定格到 `_typed`。

设置入口：`lib/views/study_settings_page.dart` 的「卡面拼写」（`StudyPrefs.spelling`）。
core 已有：`lib/core/vocab/spelling.dart` + `StudySession.checkSpelling`。
缺的是 UI 接线 —— 现在 `StudyActions` 没有 `spellingFront` 分支，`StudyCardPanel` 没有正面输入框，
`checkSpelling` 只在组末拼写里被调用。

要做的：

- `StudyCardFlow` 加 `spellingFront`（`prefs.spelling && !已检查 && !正在重学`）与检查后的
  `checked` / 输入状态；换卡、开新一轮、切换拼写开关时清掉。
- `StudyCardPanel` 在 `spellingFront` 时渲染：**中文释义 + 词性 + 输入框**（不显示英文单词、
  不显示音标、不自动朗读），回车 / 「检查」触发判卷。
- `StudyActions` 补拼写前置态：只给「检查」；拼对后进入正常评分（认识 / 模糊 / 忘记）；
  拼错后显示拼错卡（原文 + 你写的内容 + 「已判不认识」），确认后再下一张。
- 拼错走 `markSpellingMiss`（again + 重学 + 「不认识」标签 + 本轮队尾重排），**不给第二次输入**。
- 重学卡（`relearn > 0`）跳过卡面拼写，先看词看释义，避免「从头重学」变成又考一次。
- 组末拼写不受影响：它是本组验收，拼错不重排。
- 测试：core 的 `spelling_test` 已够；补 `study_card_flow_test`（前置/检查/拼错/换卡重置）与
  `study_page_test`（打开设置后卡片出输入框、拼对解锁评分、拼错出确认卡）。
- 参考 Web：`StudyCardView.tsx` 的 `spellingFront` 分支 + `useStudySpelling.ts`。

### 交接时没结论的两件事

- 用户发过两张指向「最近的产出」的 **Web 版**截图，后来又说「哪两张图？」不认它们 —— `I:\Examples\Stutterer` 一个字没动（工作区干净，`e5461be`）。要动先问。
- 打印 / 导出**不做**（用户 m16220 明确否掉），别自己加回来。

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

> ✅ 2026-11-14：P7 已接（`1e46eff`），`quiz.dart` 现在有 `QuizPrep` / `QuizViewModel` /
> `QuizPage` + 交卷落库。这一条的「只定性、不接 UI」已经过期，保留作历史。
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

### 7.1 端到端从没验证过（✅ 已补真网络 e2e；✅ 2026-11-15 模拟器上真 key 也打通了）

> ✅ 2026-11-10 晚：新增 `test/e2e/ai_batch_e2e_test.dart`，真调 DeepSeek 走完
> 「挑缺释义的词 → 请求 → `parseAnalysis` → `applyWordAnalysis` → 写 SQLite → 读回来」，
> 断言释义 / 音标非空、`status == queried`、`fieldSources[meaning] == ai`。
> **默认 skip**，设 `DLAOSHI_E2E_KEY` 才跑（key 只从环境变量读）。
> 实测：30 词一块 9.8s 回 5,513 字符、30/30 解析正确、`max_tokens: 4096` 够用；
> 错误分相全对（401 / 400 / DNS / ftp 守卫）。见 `docs/TESTING.md` §五。
> ✅ 2026-11-15：安卓模拟器（Pixel_4_B）上用**真 key** 发了一次真请求，
> **869 ms 拿回模型正文**；同一台机器上假 key 756 ms 得 401（网络栈全通）。
> 见下面「第二十三件」。仍未做的是「真模型回的表格是否被 `parseLookupTable`
> 吃得干净」—— 那句请求只回两个字，验的是能打通，不是解析表格式。

全部 **2,371 例测试都是离线假数据**：假 HTTP 客户端、内存 SQLite、假 TTS/录音端口。
AI 跑批是这次重写里**第一次碰网络请求和用户凭据**，却从来没真正向 DeepSeek 发过
一个请求。`AiClient` 的请求体、header、超时、错误分相都只在 `MockClient` 里验证过。

- 一条真请求的成本：填 key → 点「测试连接」→ 看回包。**这事儿必须人拿自己的 key
  在真机上做，我不该代填**。
- 值得顺手确认的：真模型回的表格式是否被 `parseLookupTable` 吃得干净（现在只测了
  我按 Web 版格式手写的样例表）、429 限流文案是否真会出现、`max_tokens: 4096`
  够不够 30 个词一次查完。
- 如果走一遍发现解析挂，优先修 `lib/core/analyzer_parse.dart` 的表格兜底，别改提示词。

### 7.2 smoke 测试只验「能渲染」（20 个页面）

> ✅ 2026-11-15 补完价值最高的三条：`reader_page` / `study_page` / `backup_page`
> 各一条真交互。**顺带抓到并修了一个真 bug**（见下）。其余页面仍是纯渲染，
> 但不在这三条之列，按需再补。

第二批补的 20 条用例基本是「打开页面 → 断言标题/空态文案在」，**不验证交互**。
本轮只给 AI 跑批页补了 1 条真交互（改 key → 点测试 → 断言假回调收到新 key），
其余 19 页仍是纯渲染。

- 价值最高的三条：`reader_page`（最重）、`study_page`（会话状态机）、
  `backup_page`（导入是破坏性操作）。
- 写法照 `test/views/ai_batch_page_test.dart` 第 2 例：真点控件 + 假回调断言参数，
  不是 `expect(find.text(...), findsOneWidget)`。
- 上一轮在零测试区抓到过真 bug（`writing_panel` 词块输入框吞分隔符），同类问题
  现在还可能在。

**补的三条（2026-11-15）**

| 页面 | 用例 | 验的是什么 |
|---|---|---|
| `reader_page` | 关掉选词模式：这一轮真的记进 `learning.sessions` | 顶栏按钮 → `takeSession()` → `LearningRepository.writeSection` 整条链，断言落盘里 `picked == 1` |
| `study_page` | 复习评分真的落盘 | 点「认识」再点「下一词」→ 重读词库断言 `repetitions 1→2`、`interval 1→6` |
| `backup_page` | 合并导入：选的 JSON 真的合进库里 | 假 `FilePicker`（必须 `extends FilePicker`，`platform` 的 setter 要过 `PlatformInterface.verifyToken`）注入字节 → 真点「合并导入」→ 断言词库里出现 `zephyr`、界面出现「上一次导入」 |

- `study` 那条不能只点「认识」：按 `core/vocab/review_step.dart` 的口径三键**不写库**，
  必须再点「下一词」才 `grade`。
- 断言落盘时别写 `await tester.runAsync(() => vm.flushWrites())` —— **必然死锁**：
  写链是在假时钟里由 `tap` 启动的，每个 `await` 续体要 `pump()` 才走一步，
  而 `runAsync` 在真时钟里等 `_idle`，两边互等（第一次跑超 300s 无输出就是这个）。
  正确姿势是真/假时钟交替推进：`for (25 轮) { runAsync(delay 20ms); pump(); }`。
- **抓到的真 bug**：`PickModeViewModel.setEnabled(false)` 会把 `_startedAt` 置 null，
  而页面顺序是 `toggleEnabled()` 紧接着 `takeSession()` —— 于是 `takeSession()`
  直接返回 null，**关掉选词模式的会话从来没记下来过**（速读页同款代码，一样）。
  同时 `picked` 取的是 `_state.length`，而 `setEnabled(false)` 已经清空了选中，
  所以即使记下来也恒为 0。改成 `_picked` 只增不减（口径同 Web `useVocabMode`
  的 `sessionPickedRef`）、关开关时不清 `_startedAt`。补了 4 条 VM 用例。

### 7.3 性能 / 运行时表现完全没覆盖（已处理已知的两处热点）

> ✅ 2026-11-10 晚修：`VocabBrowseViewModel` 的筛选结果与排序列表按条件缓存
> （只改排序不重扫整库），`ProductionHistoryView` 的四趟派生统计按「历史列表引用 +
> 吃法筛选」记忆化。配了 7 例缓存行为测试（含两千条词一帧只扫一次）与 1 条
> 有记录的页面用例。**「有没有 baseline」这一层仍然没做**，下面列的量测项依旧有效。

2,371 例测的是逻辑正确性，**不反映 App 跑起来顺不顺**。完全没测过的：

- 冷启动时间、首页九张卡的构建耗时；
- 词库几千条时 `/词库` 页的滚动与搜索；
- 长文章（几千词）进精读页的内存峰值；
- AI 跑批 30 词一块时的 http 内存占用（响应体整段解码）。

没有性能基线，任何一次「是不是变慢了」都只能靠感觉。真要做，先在真机上量
冷启动 + 词库滚动两项，别铺开做全套。

**已验证一层（2026-11-14，桌面 host，非真机）**
`flutter test test/bench/vocab_bench.dart`，真备份 10,892 词 / 13,552 篇次关联：

| 项 | 耗时 |
|---|---|
| 读备份文件 33.1MB | 297 ms |
| jsonDecode | 531 ms |
| parseBackupPayload（10,892 词） | 923 ms |
| save 首次（全量投影） | **9,390 ms** |
| load 冷（新实例，解 gzip） | 1,174 ms |
| load 暖（走缓存） | 0 ms |
| meta（版本号） | 0 ms |
| save 增量（改 1 条） | **1,795 ms** |

结论：**读路径已经有缓存兜住（暖读 0ms），写路径仍是瓶颈** ——
首次 save 9.4s、增量 save 1.8s，都是整库投影 + 全量重写 gzip。
「评分落盘慢」这条还没真正治，只是被「先回界面、写盘合并」挡住了体感。
真要优化得换存储形态（按词增量写表），不是调参能解决的。
真机（冷启动 / 滚动帧率）仍未量，用户 2026-11-14 明确不做真机验收。

### 7.4 两个 `/100` 口径不同（已注明，未统一权重）

> ✅ 2026-11-10 晚：两份报告都把精确分改成了区间读法（整库 **96 ± 2** / PR **≈ 74–80**），
> 并在顶部写了口径声明。**两套权重本身仍未统一**，只是不再假装可比。

整库 Dashboard 97 分与 PR Review 77 分**不可比**：同一批问题在整库报告折 −13、
在 PR 报告折 −23。PR 报告 Scope 自己写了 sampled 却给精确到个位的分数，我在
顶部补了口径声明，但**没有真正统一两套权重**。

- 要么把两者都改成「区间」（如 95–97），要么分成两个明确不同的指标名。
- 现在保持原样，因为分数只是给人看的参考，不是 CI 门禁。

### 7.5 「测试例」里含金量没分层（已定规矩，存量不追溯）

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
- ~~`lib/core/quiz.dart` 518 行 / 6 个顶层函数零消费者~~ ✅ 2026-11-14：P7 已接
  （`quiz_prep.dart` / `quiz_view_model.dart` / `quiz_page.dart`），不再是零消费者。

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

**现状（2026-11-14 更新）**：入口不止首页第四张卡 —— 精读工作流的「通读」一步也直接进速读页
（`lib/views/intensive_page.dart:55`）。`ReaderViewFlagsInput.speedReadOpen` 不是死字段：
`lib/core/reader_view.dart:139` 会读它（并进 `examActive`），只是生产代码里没人置 true，
只有 `test/core/reader_view_test.dart:23,59` 传。准确说是「读得到、没人开」，不是「没人读」。
要不要把速读塞进阅读页，等用户看过这一版再定。

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

**2026-11-14 补上逐词高亮**：`core/tts_timing.dart` 新增 `spokenWordIndex`
（字符区间 → 词下标；整句一条区间时返回 null，不猜）；`core/ports.dart` 加
`SpeechProgressPort`，`SystemSpeech` 把 `setProgressHandler` 接出来；
`ShadowingViewModel.highlightWord` 跟着朗读进度走，读完 / 停 / 换句清空；
跟读页 `Text.rich` 只给当前词加底色。`alignTimings`（毫秒）留给将来带时间戳的音频，
真机 TTS 没有毫秒数据。

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

**已解决（2026-11-14）**：`scripts/build_release.bat` 在构建前后把
`assets/data/economist-backup-2026-11-10.json` 挪进 `%TEMP%` 再挪回来，
release 包不再带这份 34.8MB 的开发样本（成功 / 失败两条退出路径都会还原）。
`pubspec.yaml` 保持 `assets/data/` 登记不变（debug 的「导入内置样本」还要用），
所以**别直接用 `flutter build apk --release`**，走脚本。

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

### 9.3 一键处理 + 补充离线例句 —— ✅ 已实现（2026-11-14）

词库页 AppBar 的 ⚡ → `DictToolsSheet`：五步**都能单独跑，也能一键连跑**。
全程离线（ECDICT + Tatoeba），不调 AI、不联网。

顺序与 Web 版 `src/reader/hooks/useDictTools.ts` 一致：
**挑词 → 补齐生词本 → 补离线例句 → 校正原形 → 补混淆项**。
例句必须排在校正之前 —— 校正后词形变了，例句表按旧词形对不上。

| 层 | 文件 | 做什么 |
|---|---|---|
| core | `lib/core/dict_tools.dart` | 五步清单 + `dictStepEnabled`（真判定：词典 / 例句库 / 本篇） |
| core | `lib/core/vocab/dict_enrich.dart` | `enrichWithDict`：只补空字段、尊重 `manual` 来源、复合词按后缀给词性、幂等返回同一引用 |
| core | `lib/core/tatoeba.dart` | 解析 `word ⇥ en ⇥ zh`、按词形/原形查、`examplesForWords` 只抽目标词 |
| data | `lib/data/tatoeba_loader.dart` | 读 6.5MB asset，后台 isolate 只抽生词本需要的词 |
| data | `lib/data/dictionary_loader.dart` | 启动后后台 isolate（`compute`）解析 9MB 词典，阅读页与一键处理共用 |
| services | `lib/services/dict_tools_service.dart` | 读库 → 纯函数变换 → 写库；`VocabConflict` 重读后**重放同一次变换**（最多 3 次） |
| viewmodels | `lib/viewmodels/dict_tools_view_model.dart` | 忙碌守卫、词典加载状态、逐步结果、挑词水平 |
| views | `lib/views/dict_tools_sheet.dart` | 五步清单 + 每步「跑」+ 底部一键跑 + 每步成功/跳过/失败 |

与 Web 版的两处故意不同：

1. **挑词直接收进「本篇」**：Web 是塞进侧栏「待选」再人工勾选；手机上没有侧栏，
   直接按当前篇的句子建词条（带来源句原文），提示里报「挑出 N 个，新收 M 个」。
2. **没有 M-W 释义源**：App 只打包 ECDICT，`enrichWithDict` 的 M-W 可选参数未接；
   例句只来自 Tatoeba。

测试：`dict_enrich_test` 9 例、`tatoeba_test` 5 例、`tatoeba_loader_test` 3 例 +
真 asset 冒烟 1 例、`dict_tools_service_test` 9 例、`dict_tools_view_model_test` 8 例、
`dict_tools_test` 10 例、词库页「一键处理」1 例（真点一步，断言结果文案）。

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

## 第十一件：全局「当前文章」（2026-11-12 深夜，用户 m28242 / m28318）✅ 已接通

用户原话（m28242）：「目前看貌似没有全局的『某一篇文章的状态和持久化』……在精读页面的
『精读』两个字边上，显示被读者选中的文章的标题，这个被读者选中的文章，就是『本篇』
数据的来源，他全局存在，持久化放在 sharePref 中，并且放在内存中，方便其他模块读取」；
（m28318）「选篇是个动作，不是个选择器……在精读点进某一篇之后，这一篇文章就是就被定位
全局可知的『当前篇』」「我的心智模型是 web 版本，主页面的文章决定生词本、小课堂、
精读页面、奶牛工棚等用哪篇文章的数据」「别的模块能临时换也可以，但目前来看好像不需要」。

改造前的问题是 **7 个模块各有一份「本篇」**：背单词靠精读页帧后回调推（不打开精读页就
永远没有本篇）、产出训练与小课堂的 `setArticleContext` 是零调用方的**死接口**、
速读 / 跟读 / 金句课 / AI 跑批各记各的。

| 层 | 文件 | 说明 |
|---|---|---|
| 判定 | `lib/core/current_article.dart` | 键 `reader:currentArticle`；`parseCurrentArticleId` / `resolveCurrentArticleId`（找不到那篇 / 列表为空 → null，**不自动选第一篇**）；测试 9 例 |
| 状态 | `lib/viewmodels/current_article_view_model.dart` | **唯一写入方是精读页**；`bootstrap()` 先 `list()` 再校验 id（反过来会把「文章被删了」误判成「没选过」）；`select()` 先改内存 notify 再落盘；测试 8 例 |
| 落盘 | `lib/data/prefs_store.dart` | `loadCurrentArticleId()`（只读不校验，校验归 VM）/ `saveCurrentArticleId()`（null 即删键） |
| 选择器 | `lib/views/article_picker.dart` | `articleSearchMatches(rows, query)` 纯函数 + `ArticlePickerSheet` + `ArticleSearchField`；**不用 `DropdownMenu(enableFilter)`**：菜单高度受 `menuHeight` 限，文章多了只能在小窗里滚 |
| 入口页 | `lib/views/articles_page.dart` | AppBar 标题「精读 · <当前那篇>」；搜索栏**默认收着**；选文章 / 粘贴新建后立刻成为全局；删篇后 `cur.refresh()` 回落 null |
| 推送 | `lib/views/article_context_sync.dart` | 挂在 `MaterialApp` 之上、所有 Provider 之内；`addListener` 而不是 `context.watch`（要在状态变化后做 IO 读正文词集合）；`_dirty` 循环让「连点两篇」排队重跑，最后一篇赢；推给 `StudyViewModel` / `ProductionViewModel` / `WritingViewModel`；测试 3 例 |
| 接线 | `lib/main.dart` | `ChangeNotifierProvider<CurrentArticleViewModel>` 在 `ThemeViewModel` 之后、`ReaderViewModel` 之前；`home: const ArticleContextSync(child: HomePage())` |

**删掉的东西**：`reader_page.dart` 的 `_syncStudyArticle`（改由 `ArticleContextSync` 负责，
与当前页面无关）、`reader_page.dart` 的 `_BottomBar`（用户 m28601：「本篇已收 xx 个 的提示
不要，没啥用」）、`vocab_browse_prefs` 里的 `articleId` / `pickedArticleIds`、
`VocabBrowseViewModel.setCurrentArticle` / `togglePicked`。

**词库筛选面板跟着改**：「本篇」不再有自己的「哪一篇」选择器，直接用全局当前文章；
「选篇」从多选勾选降级成**单选可搜下拉**（复用 `article_picker.dart`），
落盘点仍是 `vocab:browse` 的 `pickedArticleId` —— 它只管浏览视角，**不回写全局**。

**注意两处「没绑文章」的口径不一样**：`StudyViewModel.articleId` 是 `String?`（null 就是没绑）；
`ProductionViewModel.articleId` / `WritingViewModel.articleId` 用 `'manual'` 当哨兵值
（它们允许手工出题 / 手工仿写）。写断言时别混。

### 11.1 其余四个模块接上全局当前篇 ✅ 已接通（2026-11-13）

用户原话（2026-11-12 23:46）：「速读 / 跟读 / 金句课 / AI 跑批等都要用全局的当前篇，
页内页可以换，但今天就这样。明天再说」。

要求：**默认取全局当前篇，页内仍可临时换**（不写回全局，和词库「选篇」同一个口径）。

落地（四个 ViewModel 构造各加 `CurrentArticleViewModel? currentArticle`，
`lib/main.dart` 与 `test/views/smoke_harness.dart` 都传进去）：

| 模块 | 改法 |
|---|---|
| 速读 `lib/viewmodels/speed_read_view_model.dart` | `bootstrap()` 读完列表与偏好后记 `autoOpen = _current?.articleId`，**`finally` 之后**才 `await openArticle(autoOpen)`（放 try 里会带着 `_busy` 重入） |
| 跟读 `lib/viewmodels/shadowing_view_model.dart` | 同上。**刻意不加 `currentArticleId` getter** —— 本类方法数已到 40 上限，直接读 `_current?.articleId` |
| 金句课 `lib/viewmodels/golden_view_model.dart` | `bootstrap()` 在 `_guard(...)` 之后：`if (_error == null && editor.article == null && _library.any((a) => a.id == global)) await openArticle(global)`（**必须先确认列表里真有这篇**，否则 `openArticle` 读回 null） |
| AI 跑批 `lib/viewmodels/ai_batch_view_model.dart` | `_loadArticles()` 里 `_articleId == null` → 取全局；**删掉了 `list.first.id` 兜底**（全局没选就空着，界面显示「精读页还没选文章」，不能悄悄拿别的篇去跑额度） |

**与 TODO 原写法的一处偏离**：原写「`openArticle(null)` 语义统一成『回落到全局当前篇』」，
实现时**判定不改** —— `openArticle(null)` 是「换一篇」按钮按下去的语义，用户要的是
**回到列表自己挑**；改成回落到全局会让「换一篇」点不动。全局当前篇只在 `bootstrap()`
第一次进来时生效。注释已写进两个 VM。

测试：速读 +3 / 跟读 +3 / 金句课 +3 / AI 跑批 +3（都叫 `group('跟随全局当前篇')`），
覆盖「全局选了哪篇首次进入就落在那一篇」「全局没选不自动打开、不退回第一篇」
「页内换篇不改全局」。
`ai_batch_view_model_test.dart` 的 `openBoth()` helper 要用
`OpenDatabaseOptions(singleInstance: false)` —— 内存库默认按路径复用，不这么写上一组
用例造的文章会漏过来（`hasLength(1)` 实际拿到 2 篇）。

### 11.2 首页「精读」标题右边也显示当前篇 ✅ 已接通（2026-11-13）

用户原话（2026-11-12 23:54）：「首页精读两个字右边也加上"本篇"的标题，
Null 的话就写"还没有"之类的东西」。

做法：`lib/views/home_page.dart` 里 `context.watch<CurrentArticleViewModel?>()`（可空 ——
纯组件测试不注入也不炸），「精读」那张 `_EntryCard` 的 `note` 写
`(current?.articleId == null) ? '还没有选文章' : current!.title`。
`note` 本来就会渲染成紧跟标题的灰小字（`bodySmall` + `onSurfaceVariant` + `Flexible` +
`TextOverflow.ellipsis`），长标题不会挤走右边箭头，所以**没有新加组件**。
`CurrentArticleViewModel.title` 的兜底值仍是「还没选文章」（列表页在用），首页自己判空。

测试：`test/views/home_page_test.dart` 补第二条用例「精读那行右边跟着全局当前篇换」——
先断言「还没有选文章」，`smokeCurrent.bootstrap()` + `select(id)` 之后出现标题；
**`select` 之前必须先 `bootstrap()`**，否则 `_list` 是空的、`title` 取不到（`article` 查不到就回落兜底文案）。

---

## 第十二件：奶牛工棚接 AI 直连（2026-11-13，用户 m29402 / m29598）✅ 已接通

用户原话（m29402）：「产出训练是否就是 web 端的 D 老师奶牛工棚？改名，并且内部出题批改都接入 AI，
不能只有用户手动粘贴提示词和复制 AI 结果的流程」；随后 m29598 确认「按你的发现和推荐完成」。

**改名**：「产出训练」→「**D老师奶牛工棚**」（首页卡片、`ProductionPage` 标题、设置页「关于」一行）。
Web 侧的叫法在 `I:\Examples\Stutterer\src\reader\panels\ProductionPanel.tsx`。

**AI 直连（对齐 Web `useProductionAi.ts` 的 `callAi`，一键跑为主、手动粘贴留兜底）**：

| 层 | 文件 | 说明 |
|---|---|---|
| 会话 | `lib/viewmodels/production_session.dart` | `typedef ProductionAiRun = Future<AiReply> Function(String prompt);` + 构造参数 `aiRun`；`gradeWithAi()`（`buildFeedbackPrompt()` → 直连 → 回复交给 `applyFeedback`，与粘回**同一条解析路径**）；`aiBusy` / `canGradeWithAi` |
| 出题 | `lib/viewmodels/production_view_model.dart` | `generateWithAi()`：按吃法分叉（风味酸奶不用 AI，直接 `buildYogurt()`；带词块先 `buildTargets()`）→ 直连 → `applyPack()`；`_makeAiRun(complete, store)` 每次现读 `store.loadAiConfig()`，改完 key 立即生效 |
| 界面 | `lib/views/production_run.dart` | 主按钮「AI 批改这一稿 / AI 再批一次」（`aiBusy` 时转圈禁用）；「手动批改」（粘回面板）与「复制提示词」降为兜底 |
| 界面 | `lib/views/production_setup.dart` | 主按钮「AI 出题」；「选目标块 / 自己粘结果」在第二行；风味酸奶仍是「拆句预览 / 开始逐句拷打」 |
| 装配 | `lib/main.dart` | `final aiClient = AiClient();` 提到 `MultiProvider` 之前，产出训练与 AI 跑批**共用一份**；`onDispose: aiClient.close` 只在 `AiBatchViewModel` 侧 |

**为什么 AI 方法不放在 `ProductionViewModel`**：上帝类门禁按方法数算（上限 40），
`ProductionViewModel` 当时已经 33 个；`ProductionSession` 有余量，且「一道题的作答 → 批改」
本来就是它的事。加了 `generateWithAi()` 之后 VM 是 36 个方法。

测试：`test/viewmodels/production_view_model_test.dart` 加 `group('AI 直连（出题 / 批改）')` 8 例
（没客户端不发请求 / 出题成功 / 出题坏回复 / 出题网络失败 / 批改成功落库 / 没作答不发请求 /
批改坏回复不落库）。**`complete` 的签名是 `(AiConfig, String) → Future<AiReply>`**，
测试里用闭包记 `prompts` 再回放，不需要真 HTTP。


---

## 第十三件：首页「拷打」入口（2026-11-13，用户 m29402 / m29598）✅ 七档已全接通

用户原话（m29402）：「这个精读中有一些「拷打」功能，他们是否集成到 app 了？……那应该在首页加拷打，
也就是按文章对用户进行拷打，也接入全局的「某篇」文章的数据即可」；m29598 定下顺序：
「先做 3 种（记忆 / 词块 / 错题包围战），把 quiz.dart 真正通电；剩下 4 种跟上」。

**关键背景**：`lib/core/quiz.dart`（577 行）早在 P4 就移植完了 —— 18 种题型、`makeQuestion`、
`buildQuizQuestions`、`isCorrect` 全在、全有测试，但**全库唯一消费者是 `drill_sentence.dart`
（只借它挑造句素材）**，从没拼过卷子。这一件就是把这条链路真正接上。

| 层 | 文件 | 说明 |
|---|---|---|
| 规则 | `lib/core/quiz_pool.dart` | `enum QuizScope{all,article,unmastered,due,lapses}` + `quizStudyableItems()`（走 `isStudyable`，无释义的不出题）+ `QuizPoolContext{articleIdentity, docLemmas}` + `quizPool()`（本篇 = `source.fileName`/`source.articleId` 对得上**或**正文里出现过）+ `buildQuizSet()`（unique：每词只出一题，题型轮一遍取第一个出得来的）+ `limitQuizSet()` |
| 规则 | `lib/core/quiz_drill.dart` | `enum QuizDrillKind{memory,chunk,deep,mark,grammar,listen,siege}` + `quizDrillKinds`（照 Web `useIntensiveActions.ts:37-44`）+ **`quizDrillReady = QuizDrillKind.values`（七档全开，2026-11-14）** + `quizDrillImplemented()` / `quizDrillNeedsWarmup()`（只 memory/chunk）/ `quizDrillEmptyHint()`（七档各自空池子原因）+ 题量档位 `[5,10,15,20,30]`/默认 10 + `parseDrillLimits`/`drillLimitsToJson`（键 `reader:drillLimits`，兼容平铺与旧嵌套两种形状） |
| 状态 | `lib/viewmodels/drill_view_model.dart` | `bootstrap` / `setKind` / `setLimit` / **`launch`（界面入口：memory/chunk 先出卷停在预习页，其余直接开跑）** / `beginWarmup` / `cancelWarmup` / `setWarmupLimit` / `start`（保留「调了就开跑」原语义，状态机测试用）/ `speakQuestion`（TTS 朗读句子）/ `setInput` / `submit` / `next` / `retryWrong` / `reset`；判分立刻可见，写库背后合并；答对 `reviewItem(good)`、答错 `again` + 进错题本 + 写一条答题事件 |
| 数据 | `lib/viewmodels/drill_prep.dart` | `DrillPrep`（2026-11-14 从 VM 拆出）：`bootstrap` / `buildQuestions`（grammar 走文章级出题器）/ `record`（SRS + 错题 + 答题事件）/ `flushWrites`；错误走 `onError` 回调交 VM 显示。拆类理由：VM 加完预习态实测 48 方法 > 40 门禁 |
| 界面 | `lib/views/drill_page.dart` | 四态：**预习（记忆/词块先看一遍，2026-11-14 新增）** / 选档（七档全可点，无「待开」）/ 答题（进度吸顶 + 题干 + 选项或输入框 + 判分卡 + 吸底「下一题」；**输入框自动聚焦**）/ 结算（对错数 + 错题重做 + 再打一轮） |
| 预习 | `lib/views/drill_warmup_view.dart` | 照 Web `DrillWarmup.tsx`：卡片列 word/音标/释义/词块/例句 + 取消 / 换题量 / 「看完了，开始拷打」吸底 |
| 文章题 | `lib/core/article_quiz.dart` | 移植 Web `articleQuiz.ts`：translate/translate2/functionWord/ordering/phraseBlank/grammar 六种文章级题型，`buildArticleQuestions()` |
| 装配 | `lib/main.dart` | `ChangeNotifierProvider<DrillViewModel>`（`currentArticle` 注入 + **`speech: SystemSpeech()`**，听音填空播放句子用） |

**「没绑文章就退回全库」**：首页点「拷打」时用户可能还没在精读页选文章。这时
`_poolContext()` 拿到的 `articleIdentity` 是空串，`start()` 会把范围降级成 `QuizScope.all`
——首页点进来就能考，不用先去精读页挑一篇；绑了文章才收窄到本篇。这一条和词库的
「本篇空着就空着」不同，理由是拷打是「练手」，不是「查这一篇的数据」。

测试：`test/core/quiz_pool_test.dart` 19 例、`test/core/quiz_drill_test.dart` 25 例、
`test/core/quiz_warmup_test.dart` 8 例、`test/core/article_quiz_test.dart` 10 例、
`test/viewmodels/drill_view_model_test.dart` 34 例、`test/views/drill_page_test.dart` 10 例。

**踩过的坑**：
- `start(limit:)` 传进来的数是**这一轮的确切题数**，不能再过 `normalizeDrillLimit`（那个只认
  `[5,10,15,20,30]`），否则测试里 `start(limit: 3)` 会被抬成 10、实际出 4 题。
- `quiz_pool.dart` 里 `shuffleQuiz` 已由 `quiz.dart` re-export，再 `import 'quiz_parts.dart'
  show shuffleQuiz;` 会被 analyze 报 `unnecessary_import`。
- `quizStudyableItems` 要 `import 'article_vocab.dart' show kindOfItem;`（`kindOfItem` 在那里，
  不在 `entry_kind.dart`）。

**剩下四档已全部接通（2026-11-14，见第十八件）**：英英释义（deep）、语法标记（mark）、
语法·结构（grammar，走 `article_quiz.dart` 文章级出题器）、听力（listen，TTS 朗读整句 +
「播放句子」按钮）。`quizDrillReady` 已等于 `QuizDrillKind.values`，界面不再有「待开」。

---

## 第十四件：精读工作流（2026-11-13，用户 m30502 / m30484）✅ 已接通

用户原话（m30502）：「仿写那个功能那么小，放首页没必要，而且 web 端的精读功能（/intensive 路由
的那个）没重构，得对齐，对齐后完全可以放那里，web 端的那个精读功能里边也确实有仿写入口」；
m30484：「app 端的金句课点进去就是 web 端的「D老师小课堂」，那 app 端名字是不是起错了」→ 是。

**这一件同时做两件事**：
1. **改名对齐 Web**：app 的「小课堂」→「**仿写**」（`lib/views/writing_page.dart:51`），
   「金句课」→「**D老师小课堂**」（`lib/views/golden_page.dart:54` 本来就是这个名字，
   只是首页卡片叫错了）。Web 的 `src/reader/labels.ts` 里
   `GOLDEN_LESSON_NAME = 'D老师小课堂'`、`AI_BATCH_NAME = 'D指导指导指导'`。
2. **移植 `/intensive` 那个「精读工作流」**：仿写成为其中第 6 步，不再占首页一张卡。

| 层 | 文件 | 说明 |
|---|---|---|
| 规则 | `lib/core/intensive.dart` | `enum IntensiveStageKey{skim,vocab,chunks,comprehend,recall,produce,grammar}` + `IntensiveStageStatus{todo,doing,done}` + `IntensiveStage{key,label,emoji,status,progress,detail,action,enabled}` + `IntensivePlan{stages,level,levelLabel,levelDesc,progress,nextKey,nextLabel,nextHint}`；`buildIntensivePlan(IntensiveInput)` 逐行照 Web `src/core/intensive.ts`（七阶段、四级判据、`next` 取第一个未 done）；`intensiveWordsOf()` / `hasVocabChunks()` / `isStableItem()`（`repetitions>=2 && interval>=6 && lapses==0`，照 `mastery.ts:134`） |
| 状态 | `lib/viewmodels/intensive_view_model.dart` | `bootstrap()` 读词库 + 学习记录（`skimmed`/`practice`/`writingHistory`）+ 全局当前篇那篇文章；`plan` getter 现算；`openArticle(id)` 页内换篇**不回写全局**；`toggleSkimmed()` 先改内存 notify 再落 `LearningSection.skimmed` |
| 界面 | `lib/views/intensive_page.dart` | 顶部「🎯 精读工作流 + 等级徽章 + 总进度」→「下一步」卡（只给一个按钮）→「已通读」开关 → 七张阶段卡（emoji + 状态徽章 + 进度条 + 跳转按钮）；`_go()` 把阶段映射到真页面：skim→速读 / vocab·chunks→AI 跑批 / comprehend→阅读页 / recall→背单词 / produce→**仿写** / grammar→拷打 |
| 入口 | `lib/views/home_page.dart` | 「精读」卡片右边的 `ValueKey('home-intensive')` 按钮（`Icons.route_outlined`）进工作流；首页从十条收成**九条**（删掉「仿写」卡） |
| 装配 | `lib/main.dart` | `ChangeNotifierProvider<IntensiveViewModel>`（`currentArticle` 注入） |

**关键决策**：
- **仿写不占首页**：它是七步里的一步，首页放它会让人以为它跟精读无关。
- **`openArticle(id)` 不回写全局**：和词库「选篇」同口径 —— 页内临时看看别的篇，不动全局锚点。
- **阶段按钮直接跳真页面**，不复制一套流程：`produce` 跳到 `WritingPage` 就是「去仿写」，
  与 Web `ACTION.produce = '去仿写'` 一致。

测试：`test/core/intensive_test.dart` 14 例、`test/viewmodels/intensive_view_model_test.dart` 7 例、
`test/views/intensive_page_test.dart` 5 例（14.1 之后分别是 12 例与 7 例）。

### 14.1 补齐 Web `IntensivePanel` 的三块（2026-11-13 晚）✅ 已接通

| 层 | 文件 | 说明 |
|---|---|---|
| 规则 | `lib/core/output_board.dart` | 逐行照 Web `src/core/output.ts`：`OutputInput` / `OutputWords` / `OutputWrites{count,avgScore?}` / `OutputRetells` / `OutputRow{key,label,value,level,detail,good}` / `OutputBoard{score,grade,rows,next}`；权重 `0.24*chunkAcc + 0.10*grammarAcc + 0.20*write + 0.16*retell + 0.14*chunkCover + 0.10*memory + 0.06*streak`；`gradeOf` 四档；`outputChunkKinds` / `outputGrammarKinds` 常量 + `sumKindStats()` |
| 状态 | `lib/viewmodels/intensive_view_model.dart` | `bootstrap()` 多读 `retells` / `kindStats` / `activity`；新 getter `outputBoard`（现算）/ `retells`（本篇）/ `writes`（本篇）；新方法 `saveRetell(text)`（照 Web `useLearningActions.saveRetell`：trim 空或没文章返回 false、`words` 按空白切、新的在前留 200 条、记一次 `write` 活动）与 `deleteRetell(at)` |
| 界面 | `lib/views/intensive_extras.dart`（新建） | `IntensiveOutputCard`（七行指标 + 色阶 + `board.next`）、`IntensiveRetellCard`（输入框 + 「记下来」+ 最近 3 条带删除）、`IntensiveHistoryCard`（本篇仿写记录前 5 条，`writingRecordLabel` + 分数/待批改）；在 `intensive_page.dart` 里插在「七阶段」之后 |

**为什么拆 `intensive_extras.dart`**：`intensive_page.dart` 已有头卡 + 下一步卡 + 通读开关 + 七张阶段卡，
再塞三块会顶到 800 行门禁；三块彼此独立、只吃 VM 数据，拆出来一行 import 就能用。

测试：`test/core/output_board_test.dart` 13 例、`test/viewmodels/intensive_view_model_test.dart`
**12 例**（新增「产出看板」组 5 例）、`test/views/intensive_page_test.dart` **7 例**（新增看板七行 + 复述落库 2 例）。

**踩坑**：
- `output_board.dart` 只 import `kind_stats.dart`，**不要 import flutter**（core 层门禁 R1）。
- 复述词数按 `split(RegExp(r'\s+'))` 数 —— `'This article is about slowing growth.'` 是 **6** 词不是 7。
- 看板配色用 `scheme.primary` / `outlineVariant`，**别硬编码绿**（浅色主题下会刺眼，且主题门禁查不到）。

**现状（2026-11-14 更新）**：精读工作流的「语法专项」一步已经直接进拷打页，并预选 grammar 档
（`lib/views/intensive_page.dart:61` 传 `DrillPage(initialKind: QuizDrillKind.grammar)`）。
首页「拷打」卡仍是通用入口（落在上次选的档）。Web 那种「七种入口一字排开」的 launcher
没有照搬 —— App 用选档页代替，一次只让用户看一屏。

**踩过的坑**：
- `IntensiveWords` 的 `chunksAsked` 构造参数必须赋给**公开**字段 `chunksAskedRaw`，写成私有
  `_chunksAsked` 会被 analyze 报 `prefer_initializing_formals`。
- `StatusBar` 在 `lib/widgets/status_bar.dart`，不是 `lib/views/`。
- 页面测试里 `smokeCurrent` 是 `smokeApp` 里赋值的 `late` 变量，**必须先 `smokePump` 再用**；
  而且选完文章要**再 `bootstrap()` 一次**（页面 `initState` 那次读的是「还没选文章」）。
- `studied` 的判据是 `hasReviewHistory`（有 `due` 也算学过），写 `intensiveWordsOf` 的测试时
  别按「只算背过的」数。

---

## 第十五件：拷打页功能区吸底（2026-11-13 晚，用户 m30980）✅ 已接通（`c1e4cb5`）

用户原话：「拷打下面的功能区（不是那几个列表），吸底」。

**改法**：`lib/views/drill_page.dart` 的 `_RunView` 把 `_ProgressBar` 包进
`Container(color: colorScheme.surface)` + `Divider` 挪到 `Expanded` 外面 ——
进度条吸顶、底栏 `_RunBar` 吸底，中间只有题目区滚动。`_SetupView` / `_DoneView` 不动。
`test/views/drill_page_test.dart` 加了一条「滚题目区时进度条位置不变」（记 `getTopLeft` 后拖 260px 再比）。

---

## 第十六件：跟读的「复读」（2026-11-13 晚，用户 m30980 / m31068）✅ 已接通（`24ecb36`）

用户原话：「跟读功能的复读做了吗」→ 当时没做；随后补充
「说白了就放一句，读一句，基本框架就是这样」。

**做出来的样子**：跟读页底栏最上面一行是复读条 ——
「复读：放一句 → 你读 → 听你读的，读完自动下一句」+「复读这一句」按钮；
跑起来之后文案变成当前步（`正在放标准音…` / `该你读了` / `听你读的…`），按钮变「停下」。
一圈走完自动 `next()` 到下一句。

**四层文件**：
| 层 | 文件 | 说明 |
|---|---|---|
| 规则 | `lib/core/shadowing_cycle.dart` | `enum ShadowCycleStep { idle, reference, record, playback }`、`shadowCycleStepLabel`、`shadowCycleBusy`、`shadowCycleNext(step, {required bool hasTake})` |
| 编排 | `lib/services/shadowing_cycler.dart` | `class ShadowCycleRunner` + `class ShadowCycleHooks`，`start()` 返回「走完了没有」，`stop()` 幂等 |
| 状态 | `lib/viewmodels/shadowing_view_model.dart` | 公开字段 `late final ShadowCycleRunner cycle`；`_takeDone` Completer 让编排器知道「这一遍录完了」 |
| 界面 | `lib/views/shadowing_page.dart` | `_BottomBar` 多一行，key `shadow-cycle-start` / `shadow-cycle-stop` |

**三条关键决策**：
1. **编排器不写在 ViewModel 里** —— `ShadowingViewModel` 的方法数顶到 40 门禁，
   再塞 `start/stop/next` 就超标；`cycle` 做成公开字段（同 `speechEngine` 的做法）。
2. **`startRecording({bool fromCycle = false})`** —— 用户手动开录要打断复读
   （不然编排器录完会自己再放一遍，用户没点就出声），但编排器自己调时必须传
   `fromCycle: true`，否则它一开录就把自己停掉。**这个坑踩过一次**，一开始写成了
   拆两个方法 `_beginRecording`，结果又顶穿方法数门禁，最后改回带参数的同一个方法。
3. **不建表、不存音频** —— 录音全程只有一个临时文件，`RecorderPort.stop()` 不删、
   `clearTake()` 在换句 / 换篇 / 退出 / 下次开录时删。磁盘上任何时刻最多一句，
   不进数据库、不上传。（用户 m31175 专门问过这个。）

**测试**：`test/core/shadowing_cycle_test.dart` 5 例 / `test/services/shadowing_cycler_test.dart` 6 例 /
`test/viewmodels/shadowing_cycle_wiring_test.dart` 5 例（一圈顺序、没录成跳过回放、中途 stop、
跑完自动下一句、切句/换篇/手动开录都停）。

**踩过的坑**：
- 测试里用内存 SQLite 造文章必须先 `ensureSchema(db)`（在 `lib/data/db/migrations.dart`，
  不是 `app_database.dart`），否则 `no such table: articles`。
- `ArticleRepository.save` **不切句**，存进去几句就是几句；测试造两句话得写两个 `Sentence`。
- 一圈跑完会自动 `next()`，所以断言「读了哪一句」要在 `start()` 之前先把 `vm.text` 存下来。

---

## 第十七件：AI 跑批搬进「设置 + 阅读页」（2026-11-13 晚，用户 m31501）✅ 已接通

用户原话：「AI跑批中，连接设置，放设置页面，设置加Sector"AI-deepseek设置"把连接设置搬进去；
跑批范围和开始跑批，放在精读页面进入某篇文章的页面的工具栏，范围默认就是本篇（不需要全库)，
也就不需要跑批范围了，就剩一个开始跑批的功能，名字叫"AI-Batch Work"。注意！不要重复跑……
完成后删除首页的"AI跑批"」

**做出来的样子**：
- 设置页第四张卡「AI-deepseek 设置」→ 服务地址 / API key（带显隐）/ 模型 + 保存 + 测试连接。
- 阅读页顶栏一个「AI-Batch Work」按钮，点开正文最上方出现一条**默认收起**的横条：
  收起时一行摘要「AI-Batch Work · 第 N/M 块 · 完成 X · 失败 Y」，点开才有进度条、
  开始/继续/暂停/跳过失败、任务清单。
- 只跑当前这一篇；跑过的不会重跑（待办口径就是「缺释义」，落库后自然少一块，不需要另存账本）。
- 首页「AI 跑批」卡删掉，九条 → 八条。

**为什么用横条不用「下拉对话框」**：模态框会挡住正文，横条收起只占一行，
读文章时随时能看到跑到第几块。

**五层文件**：
| 层 | 文件 | 说明 |
|---|---|---|
| 规则 | `lib/core/ai_jobs.dart` | `buildAiLookupJobs(library, {chunkSize, articleId})` —— **没有 scope 参数了**；删掉 `AiScope` / `aiScopeLabel` / `aiScopeBase` |
| 状态 | `lib/viewmodels/ai_batch_view_model.dart` | 删 `_scope`/`setScope`/`scope`；`_loadArticles()` 只跟全局当前篇，全局没选就空着**不退回第一篇** |
| 设置 | `lib/views/ai_settings_page.dart` | 连接设置 + 「跑批怎么用」说明 |
| 横条 | `lib/views/ai_batch_bar.dart` | `AiBatchBar({required String articleId})`，key `ai-batch-toggle` / `ai-batch-run` / `ai-batch-resume` / `ai-batch-pause` |
| 入口 | `lib/views/reader_page.dart` | AppBar `Icons.smart_toy_outlined`，body 顶部 `if (_showBatch) AiBatchBar(articleId: article.id)` |

**踩过的坑**：
- **`AiReply.ok(_table)` 不能加 `const`** —— 测试里 `_table` 是 getter，报 `Not a constant expression.`。
- **widget 测试里造数据必须包 `tester.runAsync`** —— `await _seed(repo)` 直接写，假时钟下 sqflite 的
  Future 永不完成，4 个用例全部 10 分钟超时挂死。改成 `await tester.runAsync(() => _seed(repo));` 立刻过。
- **`dart analyze` 要一次跑 `lib test tool`**，单跑 `lib` 看不到测试里残留的 `AiScope`。

**测试**：`test/core/ai_jobs_test.dart` 14 例（`group('只按篇跑（articleId）')` 5 例）/
`test/viewmodels/ai_batch_view_model_test.dart`（`group('只跑一篇')` 3 例）/
`test/views/ai_settings_page_test.dart` 2 例 / `test/views/ai_batch_bar_test.dart` 4 例。

---

## 第十八件：拷打三需求 —— 自动聚焦 / 先看一遍 / 七档全开（2026-11-14，用户 m32314）✅ 已完成

用户原话（m32314）：「开始拷打后，自动聚焦答案输入框，不要用户自己手动点。记忆拷打和词块拷打
开始填空前，需要让用户看一看拷打题目，具体可以参考 web 端。如果不让用户看就拷打，
我怎么知道填什么。完成后，拷打模块中未实现的可以按照 web 端继续复刻。」
（m32741「先暂停明天继续」→ m32750「继续」，隔夜收尾。）

**三件事 + 一次拆类**：

1. **开始后自动聚焦答案输入框**：`_RunView` 从 StatelessWidget 改 StatefulWidget，
   持 `FocusNode`，每换一题（`vm.index/q.id` 组成 token 防重复）且未判分时，
   `addPostFrameCallback` 里 `requestFocus()`（不能在 build 里直接调）；判分后不抢焦点。
   `test/views/drill_page_test.dart` 有「开始拷打后答案输入框自动聚焦」一条断言
   `field.focusNode?.hasFocus, isTrue`。
2. **记忆 / 词块先「看一遍」**：照 Web `DrillWarmup.tsx` + `quizWarmup.ts` 移植。
   - `lib/core/quiz_warmup.dart`：`DrillWarmupCard` + `buildWarmupCards(items, questions, kind)`
     —— **题目是唯一事实来源**，按 `q.itemId` 去重查词条；记忆档取例句、词块档合并
     phrases/idioms/usage 最多 6 条；`warmupTitle` / `warmupHint`。
   - `lib/views/drill_warmup_view.dart`：卡片列 + 取消 / 换题量（重新抽卡）/「看完了，开始拷打」吸底。
   - 状态机：`launch()` 对 memory/chunk 先出卷**不进 `_queue`**，存预习卡停在预习页；
     `beginWarmup()` 才真正开跑；`cancelWarmup()` 回设置；`setWarmupLimit(n)` 重抽。
     **`start()` 保持「调了就开跑」原语义**（`test/viewmodels/drill_view_model_test.dart`
     出卷组 7 例直接调它断言 `total`/`question`，不能改语义）。
3. **七档全开（复刻 Web 未实现档）**：
   - `quizDrillReady = QuizDrillKind.values`；`quizDrillImplemented` 全 true，界面去掉「待开」。
   - `deep`（英英释义）/ `mark`（语法标记）/ `listen`（听音填空）的 `makeQuestion` 早就在
     `quiz.dart` 里，只是数据要有 definition / 语法标记 / 例句。
   - **`grammar` 是文章级题型**（`QuizKind.isArticle`），`makeQuestion` 首行
     `if (kind.isArticle) return null` 一题都出不来 → 新建 `lib/core/article_quiz.dart`
     移植 Web `src/core/articleQuiz.ts` 六种题型，`buildArticleQuestions(article.sentences, kinds:)`。
     文章级题 `q.itemId` 是句子 id，`_itemOf` 查不到词条 → 不写 SRS，正合设计。
   - `listen` 题干空、`audioText` 是整句 → `_QuestionCard` 加「播放句子」按钮，
     `DrillViewModel` 注入 `SpeechPort`，`speakQuestion()` 调 `speech.speak(...)`；
     `main.dart` 传 `speech: SystemSpeech()`。没注入 speech 时不显示按钮（测试不炸）。
   - 空池子提示改成 `quizDrillEmptyHint(kind)` 七档各自说明原因（grammar 提示去补语言点、
     listen 提示缺例句等）。

**拆类（过上帝类门禁）**：加完预习态后 `DrillViewModel` 实测 **48 方法 > 40**，
`check_god_class` 报「新上帝类，需拆分或登记基线」。新建 `lib/viewmodels/drill_prep.dart`
的 `class DrillPrep`，把「数据准备与持久化」（`bootstrap` / `buildQuestions` / `record` /
`flushWrites` / `poolContext` / `siegePool` / `queueSave` / `write`）共 7 个方法搬走，
错误经 `onError` 回调交 VM 显示；VM 构造签名不变（页面 / 测试 / main.dart 都不用改）。
另把两条字段改成 `var` 声明 —— `check_god_class.dart:95` 的 `fieldDef` 字符类认不了
泛型里的 `,` 与 `.`，`Map<QuizDrillKind, int> _limits = ...` 会被误算成方法（48 里有 2 个假数）。

**五门禁（全绿）**：`dart analyze lib test tool` → No issues found!；
全量 `flutter test -j 4` → **2302 passed / 1 skipped**；
`check_god_class` → 226 文件均未超限；`check_layers` → 226 文件依赖方向合规；
`check_core_tests` → 127 文件都有同名测试（1 例外 `ports.dart`）。
相关分组测试：`quiz_warmup_test.dart` 8 例 / `article_quiz_test.dart` 10 例 /
`quiz_drill_test.dart` 25 例 / `drill_view_model_test.dart` 34 例 / `drill_page_test.dart` 10 例。

**踩过的坑**：
- **探针要用 `Get-Content -Encoding utf8`**：早先用 ANSI 读 Dart 文件数方法得「8 方法」是假数，
  复刻 `check_god_class.dart:91` 正则才得到真值 48。
- `start()` 不能改成「只出预习卷」 —— 20+ 处 VM 测试直接调它断言 `total`/`question`，
  所以预习走独立 `launch()` 入口，界面「开始」与「再打一轮」都改调 `launch()`。
- Flutter 里 `requestFocus()` 必须放帧后回调（build 当帧 TextField 还没挂进树）。
- `LinearProgressIndicator` 让 `pumpAndSettle` 永不 settle，widget 测试统一用 `pump()`
  + `smokeFinish(tester)`。

---

## 第十九件：手机实测八条（2026-11-15，用户 m39731）✅ 全部已改

用户原话（m39731）：「app 手机测试问题：1.全库导入 web 端 json 包，耗时越 20 秒，测试 2 次，
都显示文章 51 篇 · 生词 10826 个，但精读页每篇都显示 0 个生词…」

**① 精读列表「0 个生词」—— 口径错，不是接口错（已修）**
- 根因：`ArticleRow.wordCount` 来自 `lib/core/article_json.dart:99 articleWordCount(SavedArticle a)`，
  只数 `s.vocab`；而 **Web 导出的备份里 `sentences[].vocab` 全是空数组，51 篇全空**，
  生词归属只在 `library.articleEntries` 里（实测 13,463 条覆盖 50 篇）。
- 修法：`lib/core/article_vocab.dart` 新增 `articleVocabCount(library, articleId)` =
  `articleEntryViews(library, articleId).length`（口径同 Web 的 `articleWordsOf`）；
  `articles_page.dart` / `article_picker.dart` / `vocab_filter_sheet.dart` 三处接线。
- 顺带修的隐藏 bug：`articles_page.dart` 的 `initState` 原来只调 `loadArticles()`，
  **不读词库** → `vm.library` 是空的，生词数恒 0；改成 `bootstrap()`（同时拉列表与词库）。
- 「学习 0 / 复习 684 / 回顾 0」**不是 bug**：这批词在 Web 端早就学过了（`repetitions > 0`），
  `learnPool` 只收 `isFresh` 的词，所以全落到复习/回顾；三相数按篇不同（实测 `Shhhh!` 0/684/67、
  `Investing in commodities` 43/684/11）。

**② 输入框默认中文键盘（已修）**：新建 `lib/widgets/english_input.dart`
（`englishKeyboard = TextInputType.visiblePassword` + `autocorrect/suggestions = false`，
`visiblePassword` 在 Android 映射 `TYPE_TEXT_VARIATION_VISIBLE_PASSWORD`，输入法会切回拉丁键盘），
接到 6 处：拷打 `drill-input`、小课堂 `_BlankField`、卡面拼写 `study-spell-input`、
背单词锤炼两处、考试 `quiz-input-*`。

**③ 小课堂填空页撤掉顶部黑框（已修）**：`golden_drill_view.dart` 的 `build` 改成
`if (session.phase != GoldenDrillPhase.fill) _TopBar(...)`，进度（`第 N/M 句 · 填空 x/y`）与
「N 个学习点」挪进填空区第一行小字，正文可用高度变大。

**④ 跟读「听自己读的」三种显示模式都要有（已修）**：按钮原来在 `_VerdictCard` 里，
整篇/聚焦模式要滚到列表底部才看得到；挪进吸底 `_BottomBar` 顶部（`ValueKey('shadow-play-take')`）。

**⑤ 安卓 TTS 引擎选型（用户已拍板，见第二十件）**
- 评估过三个：`neural_tts 0.4.1`（端侧 ONNX：Kitten ~57MB / 235MB RAM、Kokoro 170MB / 510MB、
  Supertonic 265MB / 428MB）、`flutter_edge_tts`（**在线**，微软 Edge 朗读接口，音质最好）、
  `supertonic_flutter`（资产 ~400MB，不适合手机）；另外查过 `flutter_piper_tts` ——
  **要 Rust 工具链**（本机没有 `rustc`/`cargo`）+ 神经 g2p 额外 46MB + 不支持数字 +
  没有语速调节 + 没有逐词进度，被用户否掉。
- **用户最终口径（m40872）**：系统 TTS 兜底 + Kitten 离线档（模型打进 APK，开箱即用）
  + Edge 在线档，三档让用户自己选。落地情况见 **第二十件**。

**⑥⑦ 点句朗读 + 长按复制（精读 / 速读共用，已修）**
- 新建 `lib/views/sentence_tap.dart` 的 `SentenceTapRegion`：`onTap` 朗读、`onLongPress`
  `Clipboard.setData` 复制**这一句**（不是整篇）+ SnackBar「已复制这一句」。
- `ReaderViewModel` / `SpeedReadViewModel` 各加 `SpeechPort? speech` + `speakSentence(...)`，
  `main.dart` 传 `speech: SystemSpeech()`。速读拷打阶段（`showBlank`）不朗读，否则念出答案。
- **删掉 `lib/views/reader_sentence_sheet.dart`（349 行）** —— 点句不再弹取词面板；
  选词模式仍走 `PickableSentence`，长按复制在两种模式下都可用。

**⑧ 精读顶栏 7 个图标收进「更多」菜单（已修）**：选词模式留在顶栏，其余六项
（译文 / 语言点 / 自动标词 / AI-Batch Work / 语言点整篇 / 本篇词表）进 `PopupMenuButton`
（tooltip `更多`），`_onMenu` 统一分发。

**门禁**：`dart analyze lib test tool` No issues found!；全量 **2480 passed / 1 skipped**；
`check_god_class` 242 / `check_layers` 242 / `check_core_tests` 132 全绿。
新增用例 8 例：`sentence_tap_test.dart` 3、`golden_drill_view_test.dart` +1、
`article_vocab_test.dart` +2、`articles_page_test.dart` +1、`shadowing_page_test.dart` +1。

**踩过的坑**：顶栏收了菜单后，三处老测试点的是图标（`find.byIcon(Icons.subtitles)` 等），
必须改成「先点 `更多` 再点文字」；`reader_vocab_drawer_test.dart` 里同一段匹配两次，
改的时候要 `replace_all`。

---

## 第二十件：朗读三档 —— 系统 / 离线 Kitten / Edge 在线（2026-11-15，用户 m40872）✅ 已完成

用户拍板原话：「1 兜底，注意把需要的东西都下好，甚至一并打包进 apk，做到手机开箱即用，
另外再加个 edge_tts，就好比 web 端的做法，用户能选。」

**三档怎么分**
- `system`（默认）：手机自带合成器，0 体积，音色跟着系统走。**永远可用，是一切兜底。**
- `kitten`：`neural_tts` 的 Kitten TTS Nano int8，**模型打进 APK（约 30MB）**，全离线，
  运行时吃 200MB 上下内存，8 个音色。开箱即用，不联网下载。
- `edge`：`flutter_edge_tts`，微软 Edge 朗读接口，音质最好但要联网；**断网自动退回系统朗读**
  （`PickSpeech` 里 `_fellBack` 标记，设置页出红字提示）。

**落地的文件**
- `lib/core/tts_provider.dart`：三档枚举 + 档位文案 + 音色表（Kitten 8 / Edge 6）+
  `parseTtsProvider` / `parseTtsVoice` / `ttsVoiceLabel` + 语速换算
  （`neuralRateOf` 0.45→0.95、`edgeRateOf` 0.45→`-10%`）。纯逻辑，无平台依赖。
- `lib/services/kitten_speech.dart`：`SpeechPort` 实现。首次用时把
  `assets/tts/{kitten/*,en-us.bin}` 用 `rootBundle.load` 拷到
  `getApplicationSupportDirectory()/tts/`，再 `createEngine(EngineId.kitten)` + `load()`。
- `lib/services/edge_speech.dart`：`SpeechPort + SpeechProgressPort`。`synthesizeToFile` 到临时目录
  → `AudioPlayer.play(DeviceFileSource)`；`enableWordBoundary: true` 拿逐词边界，
  `edgeWordSpans()` 转成字符区间喂 `SpeechProgressPort`（跟读逐词高亮可用）。
- `lib/services/pick_speech.dart`：按档位造实现的工厂 + 兜底包装。`speak()` 失败时
  `if (_current == TtsProvider.system) rethrow; _fellBack = true;` 然后用常驻的
  `SystemSpeech` 再读一遍。
- `lib/data/tts_prefs.dart`：`TtsPrefs` 管 `tts:engine` / `tts:provider` / `tts:voice` 三个键
  （**从 `PrefsStore` 搬出来的**，见下面「撞门禁」）。
- `lib/viewmodels/tts_view_model.dart` + `lib/views/tts_settings_page.dart`：设置页第六张卡
  （`settings-entry-tts`）→ 三档单选 + 每档音色 + 系统档还能选合成引擎 + 吸底「试听一句」。
- `lib/main.dart`：`ChangeNotifierProvider<TtsViewModel>` 排在六个读它的 VM 之前，
  六处 `speech:` 全部换成 `context.read<TtsViewModel>().speech`（**全局只有这一份选择**）。

**为什么不用 `neural_tts` 自带的下载器 / `checkStatus()`**
它的 `isEngineDownloaded()` 要求 `espeak-ng-data.zip` 解压后的 `.complete` 存在，
而那个 zip 在 HuggingFace 上**已经 404**（`palshub/phonemizer-dicts` 只剩 `en-us.bin`
与 `en-us.tsv`）→ 走它的状态判定会永远「装不上」。所以我们自己拷资产、自己判「文件在位」。
另外它自带的 `InternalPhonemizer`（`phonemize` 包）在 Dart 侧音素化，**不需要 espeak 数据**。

**撞门禁 / 绕法**
- `PrefsStore` 加 4 个方法后 `check_god_class` 报 `方法数 43 > 40` →
  把六个朗读读写整块搬进 `lib/data/tts_prefs.dart`，`PrefsStore` 只留
  `read(key)` / `write(key, value)` / `remove(key)` 三个薄入口（43 − 6 + 3 = 40）。
- `flutter_edge_tts` 只能锁 **`^0.0.2`**：0.0.3 引入 `audio_decode` → `native_toolchain_c ^0.19.2`，
  与 `neural_tts` 带的 `espeak`（要 `^0.17.4`）冲突，pub 解不出来。

**门禁**：`dart analyze lib test tool` No issues found!；全量 **2502 passed / 1 skipped**；
`check_god_class` 249 / `check_layers` 249 / `check_core_tests` 133 全绿。
新增用例：`tts_provider_test.dart` 15 例、`tts_prefs_test.dart` 11 例
（`prefs_store_test.dart` 的「朗读引擎」组整体搬进 `tts_prefs_test.dart`）。

**未完 / 后续可选**
- 真机上还没试听三档（模拟器没有 Edge 网络环境、Kitten 的 ONNX 也要真机内存）；
  用户下次装 release 包时验一下。
- Kitten / Edge 都没有「逐词进度」以外的语速同步问题：Edge 的 `rate` 是 SSML 百分比字符串，
  换算在 `edgeRateOf`，改语速后要重合成（已在 `speak()` 里每次传 prosody）。

---

## 第二十一件：打包规格对齐 patrol_helper（2026-11-15，用户 m41463）✅ 已完成

用户原话：「不需要全平台兼容，具体的打包规格可以参考 patrol_helper 并写入相关 spec，
暂时就给我自己的手机用。」规格全文见 **`docs/BUILD.md`**。

**为什么 138MB → 52.73MB**
- `flutter build apk --target-platform android-arm64` **只裁 Flutter 自己的产物**。
  带预编译 `.so` 的插件（`onnxruntime` / `neural_tts` / `flutter_onnxruntime`）
  仍把 arm64 + armeabi-v7a + x86_64 三套塞进来：138.08MB 里 `lib/x86_64` 33.2MB +
  `lib/armeabi-v7a` 19.6MB 完全没用，而且这两份目录**只有第三方 so、没有
  `libapp.so` / `libflutter.so`**，是残缺目录。
- 只留 arm64 → 89.3MB；再开 `packaging.jniLibs.useLegacyPackaging = true`
  （so 进 deflate 流）→ **52.73MB（55,292,965 字节）**。
- 最终核对：`aapt2 dump badging` → `native-code: 'arm64-v8a'` 单一 ABI，
  `uses-permission: android.permission.INTERNET` 在。

**改了什么**
- `android/app/build.gradle.kts`：加 `-PtargetAbi` 参数（`arm64` 缺省 / `x64` 给模拟器），
  release 里 `ndk { abiFilters.clear(); abiFilters.addAll(targetAbiFilters) }`，
  加 `packaging { jniLibs { useLegacyPackaging = true } }`。
- `android/gradle.properties`：加 **`disable-abi-filtering=true`** ——
  不加的话 Flutter Gradle 插件会用自己的 ABI 列表覆盖 `abiFilters`，上面那条白写。
- `scripts/build_release.bat` 两个真 bug：
  1. **误报 DONE**：原来只看 `if exist "%APK%"`，上一轮的包还在就立刻报完成，
     并打一个中间态字节数（那天报 56,901,632，实际 144,790,699）→ 改成
     「APK 的 mtime 晚于本轮开始时间」，时间戳存 ISO 字符串
     （存 `Ticks` 数字的话 `[DateTime]::Parse` 会抛
     `该字符串未被识别为有效的 DateTime`，永远判 N）。
  2. 子 powershell 里**别手写 `''%APK%''` 这种嵌套引号** —— 会被解析成空串
     （`Cannot find drive. A drive with the name '\I' does not exist`），
     改用环境变量 `$env:APK_FULL` / `$env:STAMP`。
- 新建 `docs/BUILD.md`：硬规格表 / 为什么必须 abiFilters / 体积构成 / 命令 /
  两种构建期噪音（脚本误报、KGP 警告）/ 装到手机。

**未做**：`signingConfig` 仍是 debug 签名。自己手机装没问题，要发别人得建
`key.properties` + 正式 keystore（照 patrol_helper 的 `signingConfigs.create("release")`）。

---

## 第二十二件：一键处理真机验收（2026-11-15，安卓模拟器）✅ 已完成

`TODO.md` 第 5 条那三项一直挂着「只能真机验」，这次在 **Pixel_4_B 模拟器**
（`emulator-5554`，x86_64）上跑出了数字。新增的第一条集成测试是
`integration_test/asset_cold_start_test.dart`（`integration_test/` 此前是空目录，
`docs/TESTING.md` §一 早就把它定为「跨页面 + 真数据库闭环」的位置）。

跑法（先起模拟器，`flutter devices` 里能看到 `emulator-5554`）：
```powershell
flutter test integration_test/asset_cold_start_test.dart -d emulator-5554
```
注意 `flutter emulators --launch Pixel_4_B` 那条命令即使成功也会报 exit code 1
（Flutter 往 stderr 打「assets downloaded from storage.flutter-io.cn」被 pwsh 当错误），
以 `adb devices` 里出现 `emulator-5554  device` 为准。

### 22.1 9MB 词典的冷启动耗时 —— 不是问题

| 阶段 | 模拟器实测 |
|---|---|
| `words.tsv` 读（7.79MB → 6,969,722 字符） | 147 ms |
| `forms.tsv` 读（1.06MB） | 85 ms |
| `near.tsv` 读（0.30MB） | 11 ms |
| `parseEcdict` 解析（**主** isolate） | 603 ms → 51,796 词条 / 59,637 变体 |
| **`loadDictionary()` 全链路（app 真实路径）** | **1,058 ms** |

`loadDictionary()`（`lib/data/dictionary_loader.dart`）走 `compute` 起后台 isolate，
所以 1,058 ms 里含 isolate 启动 + 9MB 字符串跨 isolate 拷贝。它挂在 `main()` 里
`loadDictionary()` 不 await，**不阻塞首帧**；用完的界面等同一个 Future。
→ 冷启动多付 1 秒但完全在后台，用户感知不到。**结论：不需要为它做额外优化。**

### 22.2 Tatoeba 例句质量 —— 覆盖率就是这个数，且不该导入 sqflite

对 300 个词（从 ECDICT 主表**均匀取样**，代表真实生词分布）抽例句：

| 指标 | 数值 |
|---|---|
| 读 `tatoeba-en.tsv`（6.52MB → 5,933,447 字符） | 113 ms |
| 抽 300 个词 | **184 ms** |
| 命中词数 | 153 个（**51.0%**） |
| 例句总数 / 其中带中文 | 299 条 / **126 条（42%）** |

整表统计（`assets/tatoeba/tatoeba-en.tsv`，107,797 行 / 61,470 个词）：
- **15,137 个词只有带中文的例句**
- **46,333 个词只有纯英文例句**（构建脚本 `--en-only` 分支补的）
- **混合词 0 个** —— 没有任何一个词同时有「带中文」和「不带中文」的候选

**这三条否掉了两个原本想做的改动**：
1. ~~「挑例句时优先挑带中文的」~~：没有混合词，挑选策略改了也不会有任何改善。
   出现在卡片上的英文例句没有中文，是**覆盖度事实**，不是挑选 bug。
2. ~~「把 Tatoeba 导入 sqflite」~~：抽 300 个词只要 184 ms，且只在「一键处理」
   点「补离线例句」时跑一次（`lib/services/dict_tools_service.dart` 的 `_examples()`）。
   为 184 ms 建一张表 + 多一套 SSOT 口径不划算。**明确不做。**

真实覆盖率 51%：一半的词有例句可补，那 49% 查不到的词「补例句」那步会报
「离线例句库里没查到这些词的例句」（已有文案，不是静默失败）。

### 22.3 APK 体积构成 —— 6.5MB 实为 15.7MB，但都对得起

release APK 52.7MB 里 `flutter_assets/assets/` 的实际构成（`System.IO.Compression`
逐条读出来的）：

| 分组 | 体积 | 明细 |
|---|---|---|
| `tts/` | **29.76 MB** | `kitten_tts_nano_v0_8.onnx` 23.24 + `en-us.bin` 3.39 + `voices.npz` 3.13 |
| `ecdict/` | **9.15 MB** | `words.tsv` 7.79 + `forms.tsv` 1.06 + `near.tsv` 0.30 |
| `tatoeba/` | **6.52 MB** | `tatoeba-en.tsv` |
| 其它 | 0.25 MB | `icon.png` 0.22 + `GinShinImapct.webp` 0.03 |

→ 词典 + 例句合计 **15.67 MB**，原 TODO 里写的「6.5MB」只算了 Tatoeba，
把 ECDICT 的 9.15MB 漏了。两者都保留：都是「开箱即用、不联网」的前提
（`pubspec.yaml` 里已写明这是用户要求）。`assets/data/`（34.8MB 真备份）
仍靠 `.gitignore` + `scripts/build_release.bat` 临时移走，**没有进包**。

---

## 第二十三件：AI 真请求的网络栈验收（2026-11-15，安卓模拟器）✅ 已完成

第 3 条与 7.1 都写着「真机跑 AI 真请求」这一条没做，理由是「device 网络栈 /
代理 / 证书测不出来」。这半件事**不需要真 key 就能验**，已验完；真 key 那半
2026-11-15 也补上了。

新增 `integration_test/ai_network_test.dart`，两段：

1. **`[net] 假 key 拿到的是 401，不是网络错误`**（不需要 key，默认就跑）
   用一个格式像样但明显假的 key 真发一次 HTTPS 请求。服务端回 401，
   客户端把它归成 `AiErrorKind.unauthorized`。**只要拿到的是 unauthorized
   而不是 network，就证明手机侧的 DNS + TLS 证书链 + 系统代理 + 出网全都通** ——
   因为网络层任何一环断掉，`AiClient` 都会落到 `on Object catch` 那条
   `网络异常` 分支（见 `lib/services/ai_client.dart:142-146`）。
2. **`[net] 真 key：真发一次请求，拿回模型正文`**（没传 key 时 skip）
   ```powershell
   flutter test integration_test/ai_network_test.dart -d emulator-5554 `
     --dart-define=DLAOSHI_E2E_KEY=sk-xxxx
   ```

**实测（Pixel_4_B / emulator-5554，x86_64，2026-11-15）**：
```
[net] 假 key 请求耗时 756 ms，kind=AiErrorKind.unauthorized，
      error=key 不对或没权限（HTTP 401），去设置里检查一下
[net] 真 key 请求耗时 869 ms，ok=true，正文=通了
```
→ **假 key 756 ms 走完 DNS 解析 + TCP + TLS 握手 + 请求 + 回包**，说明安卓侧网络栈
没问题，之前「只能真机验、模拟器测不出来」的顾虑对**模拟器也不成立**；
**真 key 869 ms 拿回真模型正文**，端到端打通。

**为什么 key 走 `--dart-define` 而不是环境变量**：集成测试跑在**设备**上，
宿主机的环境变量传不进去。`test/e2e` 那套读 `Platform.environment` 只适用于
桌面 `flutter test`。两者刻意用不同通道，别互相抄。

**仍未做**：用真 key 验「真模型回的表格是否被 `parseLookupTable` 吃得干净」——
集成测试这条只发了一句「只回两个字：通了」，验的是「能打通」，不是「解析表格式」。
那件仍属 `test/e2e/ai_batch_e2e_test.dart`（桌面跑、读 `DLAOSHI_E2E_KEY` 环境变量），
2026-11-10 已在桌面验过 30 词一块 9.8s / 30 词全对。

---

## 第二十四件：两个朗读 bug + CursorWindow + 小课堂键盘 / 吸顶（2026-11-15，用户 m01901）✅ 已完成

用户报的五件事（两 bug 三优化）。代码在真机 **vivo V1981A（Android 12 / API 31 / arm64-v8a）**
与模拟器 **Pixel_4_B（API 29 / x86_64）** 上都验过。

### 1. 离线神经朗读点「试听一句」直接闪退 ✅

真机 logcat 现场：

```text
E/AndroidRuntime: FATAL EXCEPTION: pool-2-thread-1
E/AndroidRuntime: java.lang.NoSuchMethodError: No virtual method readNBytes(I)[B
                  in class Ljava/io/InputStream;
E/AndroidRuntime:   at com.localmind.neural_tts.onnx.KittenSession.parseNpy2DFloat(KittenSession.kt:142)
E/AndroidRuntime:   at ...loadVoiceEmbedding(KittenSession.kt:123)
E/AndroidRuntime:   at ...synthesize(KittenSession.kt:65)
E/AndroidRuntime:   at ...KittenEngine.speak(KittenEngine.kt:47)
W/ActivityTaskManager: Force finishing activity com.dlaoshi.dlaoshi_app/.MainActivity
```

`InputStream.readNBytes(int)` 是 **API 33+** 才有的方法，用户的 Android 12（API 31）没有它；
`NoSuchMethodError` 是 `Error` 不是 `Exception`，插件 `NeuralTtsPlugin` 那句
`catch (error: Exception)` 兜不住 → 后台线程崩 → 整个 App 被系统杀掉。
`neural_tts` 在 pub.dev 上只有 0.4.0 / 0.4.1，0.4.1 已是最新，**上游没有修复版本**。

修法：把 `neural_tts 0.4.1` **vendor 进 `packages/neural_tts/`**（`pubspec.yaml` 改 path 依赖），两处：

- `packages/neural_tts/android/src/main/kotlin/com/localmind/neural_tts/onnx/KittenSession.kt`
  新增 `private fun readExactly(stream: InputStream, count: Int): ByteArray`（循环 `stream.read`
  直到读满，遇到 `-1` 抛 `IllegalStateException`），4 处 `readNBytes` 全换成它。
- `packages/neural_tts/android/src/main/kotlin/com/localmind/neural_tts/NeuralTtsPlugin.kt`：
  `catch (error: Exception)` → `catch (error: Throwable)`，非 `Exception` 的包成
  `RuntimeException` 回给 Dart —— 以后再出这类原生错，至少 Dart 侧能 catch 到并优雅降级。

**为什么不用「低 API 就禁用 Kitten」的守卫**：那样用户的 Android 12 永远用不了离线朗读，
而 bug 本身只是插件用了新 API，能修就别阉功能。回退很简单：删 `packages/neural_tts/`，
`pubspec.yaml` 改回 `neural_tts: ^0.4.1`。本地改动记在 `packages/neural_tts/CHANGELOG.md` 顶部。

真机验证（`integration_test/tts_engine_test.dart`）：

```text
[tts] kitten modelsPresent=false
[tts] kitten speak ok, 6256ms
```

以前这一步是整个进程消失，现在 6.2 秒读完一句。模拟器（API 29）同样通过（8775ms）。

### 2. Edge 在线朗读换音色听不出区别 ✅

根因不在我们的代码：六个音色**全部**合成失败。

```text
EdgeTtsException(websocket_upgrade_failed): Edge TTS websocket upgrade failed with status 403
```

而 `lib/services/pick_speech.dart` 的 `catch (e)` 把它静默吞了 —— `_fellBack = true`，退回系统朗读。
于是「任意音色听起来都一样」= 听到的从来都是系统 TTS。

403 排查穷尽，**不是我们能修的**：

| 试过的 | 结果 |
|---|---|
| GEC v1 令牌 | 403 |
| GEC v2 令牌（把 0.0.3 的算法剥出来单验） | 403 |
| 新域名 `api.msedge.net` | DNS 解析不了（errno 11001） |
| 设备与宿主时钟偏差 | 0.0 秒，排除 GEC 过期 |
| HTTPS `voices/list` | 200 / 168,820 字节（网页接口通，只有 WSS 握手被拒） |
| 升级 `flutter_edge_tts 0.0.3` | 装不上：`audio_decode` 要 `native_toolchain_c ^0.19.2`，`espeak` 要 `^0.17.4`，pub 解不出 |

→ 服务端按来源 / IP 拒绝 WSS 握手。既然修不好，就不能再静默：`PickSpeech` 加
`String? fallbackReason` + `_explain()`（认得 `403` / `401` / `websocket_upgrade_failed` /
`connection_failed`），设置页把提示从列表底部挪到**试听条正下方**（原来那个位置用户根本看不到），
key `tts-fallback-note`，文案「连不上微软的在线朗读服务（…），这一次用的是系统朗读 ——
换个网络再试，或者先用离线神经朗读。」

### 3. 进奶牛工棚报 `Row too big to fit into CursorWindow` ✅

原文：

```text
DatabaseException(Row too big to fit into CursorWindow requiredPos=0, totalRows=1)
sql 'SELECT payload FROM vocab WHERE id = 1' args []
```

Android 的 sqflite 把查询结果塞进 `CursorWindow`，**单行 2MB 上限**，BLOB 与 TEXT 一样计入。
词库整库 JSON 真机 16.4MB，`GZipCodec(level: 1)` 压完 **2.14MB** —— 正好越线。
（当初把 level 6 降到 1 是为了省 167ms，代价就是压出来的包大 0.31MB，把这条线踩了。）

修法：新增 `lib/data/db/payload_codec.dart`，**分块读**而不是一次 `SELECT payload`：

- 先 `SELECT typeof(payload) AS kind, length(payload) AS size`（只回一个数字，安全）；
- 再按 256KB 一块 `SELECT substr(payload, ?, ?)` 取回来自己拼；
- `substr` 对 BLOB 按**字节**切、对 TEXT 按**字符**切，所以明文老数据与 gzip 新数据都认。

读 payload 的 **6 处**全部换掉（只补一处会换个页面继续炸）：
`lib/data/repositories/vocab_repository.dart` 的 `loadJson` / `_payloadText` / `loadSnapshot` / `migrate`，
`lib/data/db/projections.dart` 的 `rebuildAllProjections` / `normalizeLegacySourceIds`。
顺带把 `normalizeLegacySourceIds` 的写回从明文 `jsonEncode` 改成 `packPayloadJson`（原来它写明文，
与其它路径不一致）。

**桌面测试测不出这条**（桌面用 sqlite3 ffi，没有 CursorWindow），所以另加真机用例
`integration_test/big_payload_test.dart`：

```text
[big]  写入 4194304 字节，读回一致=true，耗时 362ms，error=null
[big2] JSON 1310680 字符 → gzip 102444 字节，读回一致=true，耗时 101ms
```

4MB 单行（上限的两倍）字节完全一致读回，不再抛窗。桌面侧 `test/data/db/payload_codec_test.dart`
10 例覆盖逻辑，其中「单行 >2MB」那条造数据必须用 `Random` 随机字节 —— 重复中文会被 gzip 压到
57KB，测不出问题。

### 4. 小课堂多个空之间切换，键盘掉下去又升起来 ✅

第一版判断错了方向（以为是焦点节点不够、要 `next` 逐个转焦），改完用户复验**仍然掉**。
真正的根因是 `TextField` 默认的 `onTapOutside`：**点到输入框外面就 unfocus 自己**，
而「点另一个空」正好满足「点到外面」—— 手指按下时旧空先失焦，`textInput` 排队 `hide`，
抬起后新空才要焦点，于是键盘落下又弹起。

最终修法见 **第二十五件**：`onTapOutside: (_) {}` + 每空一个 `FocusNode`
（`List<FocusNode> _focuses`，与 controller 同生命周期重建 / dispose）+
`ValueKey('golden-blank-$index')` 便于测试。焦点节点是「点哪就聚焦哪」的必要条件，
但**真正让键盘不掉的是 `onTapOutside` 置空**。

### 5. 小课堂动作条吸顶 + 长英文可滚 ✅

`_BottomBar` 从 `Column` 最底部移到最上方（正文 `Expanded` 之前、`_TopBar` 之上），
分隔线 `Border(top:)` → `Border(bottom:)`（它现在在屏幕最上面）。正文本来就是
`ListView` + `Wrap`，长句超屏可以滚。

### 收尾

- 三次提交：`5bc7b8d`（词库分块读）/ `72e5556`（朗读两个 bug + vendored 插件）/ `a4caece`（小课堂）。
- 门禁：`flutter analyze` 干净；250 文件过 `check_god_class` / `check_layers`；133 个 core 文件过
  `check_core_tests`；`flutter test -j 4` **2530 passed / 1 skipped**（基线 2519 → 2530，
  新增 10 例 payload_codec + 2 例 golden 焦点）。
- **踩坑（血的教训）：`flutter test -d <真机>` 会先卸旧版再装，跑完还会卸载 —— App 数据
  （含导入的词库）一起没。** 2026-11-15 因此清掉了用户手机上的一份词库。
  跑真机集成测试前必须先提醒用户导出备份，或者用 `flutter run` 手动装。

---

## 第二十五件：release 包离线朗读闪退（R8）+ 小课堂回车交卷（2026-11-15，用户 m03176）✅ 已完成

用户复验三句原话：「1 点击朗读设置，主页精读、词库、等界面的报错不再出现，但是小课堂拼读环节，
当一道题有多个空需要填写，切换不同『空』的时候，键盘还是会落下又弹起，另外我希望键盘上点击回车，
相当于点击『提交这一轮』，好的地方时小课堂的联系中『交这一轮』和挑句都在上方吸顶了，这个是我要的
2 点击朗读设置>离线神经朗读，选任意音色>试听一句还是会跳出 3 点击 Edge 在线朗读任意音色试听还是
系统音色，是打包问题还是？」

第 1 条与 CursorWindow、吸顶已经确认好；本条记剩下两条的根因与修法。

### 1. release 包上离线神经朗读仍然闪退 —— 是 R8，不是 readNBytes ✅

debug 上那个 `InputStream.readNBytes`（API 33+ 才有）已经用 vendored 插件修掉了，
真机集成测试 `[tts] kitten speak ok, 6256ms` 通过。但用户装的是 release 包，一崩是另一副现场：

```text
F libc : Fatal signal 6 (SIGABRT) in tid 11895 (pool-2-thread-1), pid 11820 (shi.dlaoshi_app)
F DEBUG: Abort message: 'JNI DETECTED ERROR IN APPLICATION: java_class == null
F DEBUG:     in call to GetMethodID
F DEBUG:     from boolean[] ai.onnxruntime.OrtSession.run(long, long, long, java.lang.String[],
F DEBUG:       long[], long, long, java.lang.String[], long, ai.onnxruntime.OnnxValue[], long[], long)'
F DEBUG:       #06 libonnxruntime4j_jni.so (convertToTensorInfo+628)
F DEBUG:       #07 libonnxruntime4j_jni.so (convertOrtValueToONNXValue+436)
F DEBUG:       #08 libonnxruntime4j_jni.so (Java_ai_onnxruntime_OrtSession_run+836)
```

解包比对 dex 里的类名（`System.IO.Compression.ZipFile` 读 `classes.dex` 后 ASCII 搜）：

| 类 | release | debug |
|---|---|---|
| `ai/onnxruntime/OrtSession` | ✅ | ✅ |
| `ai/onnxruntime/OnnxTensor` | ✅ | ✅ |
| `ai/onnxruntime/TensorInfo` | ❌ | ✅ |
| `ai/onnxruntime/OnnxJavaType` | ❌ | ✅ |
| `ai/onnxruntime/OrtSession$Result` | ❌ | ✅ |

ONNX Runtime 的 Java 层是 **native 侧 JNI 反查类 / 方法**的，Java 侧没有静态引用，R8 就当成
死代码裁了；`GetMethodID` 拿不到 `java_class` 直接 abort。**所以「debug 集成测试全过、
release 一崩」——不是代码问题，是裁剪问题。**

修法：新建 `android/app/proguard-rules.pro`，`-keep class ai.onnxruntime.** { *; }`、
`-keep interface ai.onnxruntime.** { *; }`、`-keep class com.localmind.neural_tts.** { *; }`、
`-dontwarn` 两条，外加 `-keepattributes Signature / *Annotation* / InnerClasses / EnclosingMethod`；
并在 `android/app/build.gradle.kts` 的 release 块挂
`proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")`。

**为什么非挂不可**：Flutter 的 release 默认开 R8（本仓库没写 `isMinifyEnabled`，
但 `build/app/outputs/mapping/release/` 下生成了 `mapping.txt` / `usage.txt` / `seeds.txt`），
而 `flutter_onnxruntime` 与 `neural_tts` 两个插件的 `android/` 目录里**都没有** `consumerProguardFiles`，
插件自己的规则不会生效，只能由 App 侧兜。

重打后 dex 复查：`TensorInfo` / `OnnxJavaType` / `OrtSession$Result` 全部回来了；
真机点「试听一句」进程存活（`pidof` 有值）、`logcat -b crash` 为空。

### 2. 小课堂：切空不掉键盘 + 回车 = 交这一轮 ✅

见第二十四件第 4 条的订正 —— 根因是 `onTapOutside` 的失焦时序。改法：

- `_BlankField` 的 `TextField` 加 `onTapOutside: (_) {}`：旧空不失焦，新空直接接管输入连接。
- `textInputAction` 统一 `TextInputAction.done`，`onSubmitted` 直接 `_submitFill(session)`
  —— **回车就是「交这一轮」**，不再往后跳空。
- 删掉不再需要的 `_focusNextOrSubmit`；`_FillBody` 的 `onNext` 参数改成 `onSubmit`。

用例：`test/views/golden_drill_focus_test.dart` 第二例改为「点哪个空光标就去哪个空、
全程 `tester.testTextInput.isVisible` 为 true」；新增第三例「键盘回车 = 交这一轮」
（`enterText` → `receiveAction(TextInputAction.done)` → 断言 `drill.roundScored` 为 true）。

真机（vivo V1981A / Android 12 / API 31）实点验证：整块模式一轮 7 个空，点第二个空后
焦点跟过去、`input text` 落进新空，切换全过程轮询 `dumpsys window windows | grep -c 'u0 InputMethod'`
始终为 1（键盘没消失过）；回车后按钮从「交这一轮」变「重试这一轮」，答案被记录。

### 3. Edge 仍然系统音色 —— 只是把「静默退回」改成明说 ✅

403 是微软服务端按来源拒绝的（GEC v1/v2 令牌都试过，`api.msedge.net` 本机 DNS 都解析不了），
客户端改不动。此前 `lib/services/pick_speech.dart` 的 `catch (e)` 静默退回系统朗读，用户听到的
永远是系统 TTS，所以「换音色没变化」。现在会把原因摆到试听条下方：

```text
连不上微软的在线朗读服务（EdgeTtsException(connection_failed): Failed to connect to the
Edge TTS websocket.; cause=…），这一次用的是系统朗读 —— 换个网络再试，或者先用离线神经朗读。
```

真机上已确认这行提示按预期出现（`ValueKey('tts-fallback-note')`）。

### 收尾

- 两次提交：`fb825b5`（小课堂回车 / 键盘）、`1238c19`（proguard 规则）。
- 门禁：`flutter analyze` 干净；250 文件过 `check_god_class` / `check_layers`；133 个 core
  文件过 `check_core_tests`；`flutter test -j 4` **2531 passed / 1 skipped**。
- 真机验证用的是 release 包（`scripts\build_release.bat`，55,333,461 字节），
  不是 debug —— **凡是被 R8 影响的路径，debug 上验过不算数**。

---

## 第二十六件：离线朗读换成 Kokoro-82M（2026-11-15 立项，用户 m04235 / m04271）🟡 真机已出声，待 release 复核（2026-11-16）

用户原话（m04235）：「现在这个离线模型效果差强人意，如何提升？（比如换个运行内存大点的模型？）」
→ 说明方向之后，用户在选项里选了「直接上 Kokoro-82M」，但同时说「做好 todo 即可，明天再说」。
**本条只立项目标与事实，代码零改动，明天照着做。**

### 1. 先纠正一个理解：不是内存问题

Kitten nano 的权重只有 23MB，换到最大的 Kitten mini 也才 75MB；ONNX Runtime 在手机上
峰值几百 MB，插件自己的门槛是 `ttsMinRamBytes = 4GB`。**换更大模型换来的是包体、首次加载时间、
单句合成耗时，不是内存占用。** 用户想表达的「换更强的模型」方向是对的，理由不是内存。

### 2. 现状与四个候选（体积是 2026-11-15 在 HF 上 HEAD 实测的）

| 方案 | 模型文件 | 附带资源 | 预估 APK | 换上去要改什么 |
|---|---|---|---|---|
| Kitten nano int8（**当前**） | 23.2 MB | voices.npz 3.28MB + en-us.bin 3.56MB | 52.7 MB | — |
| Kitten nano fp32 | 54.1 MB | 同上 | ~84 MB | 只换 `.onnx`，同一引擎 |
| Kitten micro | 39.5 MB | 同上 | ~66 MB | 换 `.onnx` + 改 asset 名 |
| Kitten mini | 74.6 MB | 同上 | ~105 MB | 换 `.onnx` + 改 asset 名 |
| **Kokoro-82M v1.0 fp16** | 82 MB | tokenizer.json 500KB + 22 个音色 `.bin` × 524KB | **~140 MB** | 新引擎档位（见下） |
| Supertonic-3 | 4 个 ONNX 流水线 | unicode_indexer.json + 10 个音色 JSON | 待测 | 新引擎档位（同 Kokoro 的工作量） |

**Kitten 四档是同族的，换档真的无痛**：拉 `palshub/kitten-tts-micro-0.8` 与
`palshub/kitten-tts-mini-0.8` 的 `config.json` 比过 —— `voice_aliases` 与
`speed_priors` 之外只有 `model` 字段不同，八个 voice id（`expr-voice-2-f` … `expr-voice-5-m`）
完全一致；而且 `KittenEngine.initialize` 只读 `modelPath` / `voicesPath` / `dictPath` /
`maxChunkSize`，**根本不解析 `config.json`**。所以「换档」= 换一个 `.onnx` + 改
`lib/services/kitten_speech.dart` 里 `kittenAssets` 的一行文件名 + 改 `modelsPresent()` 的检查列表。

**Kokoro 不是换档，是加引擎**。插件里 `KokoroEngine.kt` / `KokoroSession.kt` /
`lib/src/engines/kokoro_engine.dart` / `kokoroVoices`（22 个音色，含英式 `bf_*` / `bm_*`）
都已经写好了，缺的是 App 侧的档位接线与资源。

### 3. Kokoro 落地清单（明天照着走）

1. **`lib/core/tts_provider.dart`**
   - `enum TtsProvider { system, kitten, edge }` 加 `kokoro`（注意：`ttsProviderKey` 存的是字符串，
     老数据 `system` / `kitten` / `edge` 必须继续能解析，`parseTtsProvider` 要能容错）。
   - 新增 `kokoroVoiceOptions`（先挑 6 个：`af_heart` / `af_bella` / `af_nicole` /
     `am_michael` / `bf_emma` / `bm_george`），标签风格照 `kittenVoiceOptions`（`'Heart · 女'`）。
2. **`lib/services/kokoro_speech.dart`（新文件）** —— 照 `lib/services/kitten_speech.dart` 抄骨架：
   - `kokoroAssets` 映射到 `<支持目录>/tts/kokoro/` 与 `<支持目录>/tts/en-us.bin`；
   - 引擎目录必须与 `ModelDownloader.getEngineDir` 一致：`<getApplicationSupportDirectory()>/tts/kokoro`；
   - `createEngine(EngineId.kokoro)` + `engine.load()` + `engine.play(raw, voice, rate:, phonemize: true)`；
   - **`en-us.bin` 已经在 `assets/tts/en-us.bin`（Kitten 复用），Kokoro 也读同一个路径，别重复打包。**
3. **`lib/services/pick_speech.dart`**：`createSpeechFor` 加 `TtsProvider.kokoro` 分支；
   `_explain` 不用动（只在 edge 档用）。
4. **`lib/views/tts_settings_page.dart`**：朗读档位单选加一项；音色列表按 provider 分流
   （现在 `kittenVoiceOptions` / `edgeVoiceOptions` 是硬写的两段）。
5. **资源**：`pubspec.yaml` 的 assets 里加 `assets/tts/kokoro/`；
   模型来自 `https://huggingface.co/onnx-community/Kokoro-82M-v1.0-ONNX/resolve/main`
   （`onnx/model_fp16.onnx` 82MB / `tokenizer.json` / `voices/<id>.bin` 每音色 524KB）。
   **只打用得上的音色**，不要把 22 个都塞进 APK（22 × 524KB ≈ 11.5MB）。
6. **测试**：`test/core/tts_provider_test.dart` 补 `parseTtsProvider('kokoro')` 与音色表；
   沿用 `integration_test/tts_engine_test.dart` 的写法加一个 Kokoro 用例
   （`probe('kokoro speak', ...)`，只打印不断言）。
7. **验证**：`flutter build apk --release` 后**必须解包查 dex**（R8 会不会又裁掉东西），
   再在真机上点「试听一句」看 `pidof` 是否存活。`android/app/proguard-rules.pro` 已经
   `-keep class ai.onnxruntime.** { *; }`，理论上够，但要眼见为实。

### 4. 先做的两件「免费」优化（跟换模型无关，可以先单独试）

用户体验到的「差」有一部分不是模型的锅：

- **播放速率**：`lib/core/tts_provider.dart` 的 `neuralRateOf(rate) => (0.5 + rate).clamp(0.5, 1.8)`，
  默认 `rate = 0.45` → 0.95，而 `packages/neural_tts/.../audio/PcmPlayer.kt:85` 用
  `PlaybackParams().setSpeed(rate).setPitch(pitch)` 做变速 —— Android 的 Sonic 时间拉伸在
  0.95 这种非 1.0 的速度上会有轻微金属感。**试听对比时先把速率钉成 1.0**。
- **硬切分**：`packages/neural_tts/lib/src/constants.dart:32` 的 `maxChunkSize = 200`，
  `KittenEngine.chunkText` 会按句子攒到 200 字符再 `chunked(200)` 硬切，
  长句被从中间断开会让人听出「气口不对」。提到 300～400 再看效果
  （`KittenEngine.initializationArguments()` 里传的是同一个常量）。

### 5. 待确认 / 风险

- **HF 直连能不能下**：2026-11-15 HEAD `palshub/kitten-tts-mini-0.8` 的 `config.json`
  返回 200 但耗时 4.8 秒；`hf-mirror.com` 同一路径返回 **308 Permanent Redirect**，
  要换成能跟重定向的下载方式（`Invoke-WebRequest -MaximumRedirection` 或直接拼 `?download=true`）。
  82MB 走这条线可能要好几分钟，别在 `flutter build` 里同步做。
- **APK 会从 52.7MB 涨到 ~140MB**，用户是否接受要确认一次（表里已列）。
- **首次加载**：Kokoro 82MB 权重，冷启动 `engine.load()` 预计 2～5 秒，
  现在的「试听一句」是同步等 `speak`，要不要加个「正在准备模型…」的进度提示，明天定。
- **要不要顺便做成运行时下载**（用插件自带的 `ModelDownloader`，`downloadEngineFiles(EngineId.kokoro)`）：
  好处是换模型不用重打包、APK 瘦回去；坏处是首用要联网。用户选了「直接上 Kokoro」，
  默认**先按打包进 APK 做**，运行时下载留作后续。

### 6. 明天的第一步

先做第 4 节那两件免费优化（速率 1.0 + `maxChunkSize` 300），重打一版让用户听；
如果「还是不行」，再按第 3 节接 Kokoro。这样能避免「花两小时接完 Kokoro 才发现
问题出在变速上」。

### 7. 落地记录（2026-11-16）🟡 真机已出声；release 包待复核（见第 8 节）

用户当天明确「**不需要在现有引擎调速度了，语音质量差和速度无关**」→ 第 4 节的
两件免费优化（变速、`maxChunkSize`）**没做**，直接接 Kokoro。

已完成：

- `lib/core/tts_provider.dart`：`TtsProvider` 加 `kokoro`（枚举在 `kitten` 与 `edge`
  之间）；标签 `离线神经朗读（Kokoro）`、提示写明 ~88MB / ~500MB 内存；
  `kokoroVoiceOptions` 6 个音色（`af_heart` 默认 / `af_bella` / `af_nicole` /
  `am_michael` / `bf_emma` / `bm_george`）；`defaultTtsVoice` 与
  `ttsVoiceOptionsOf` 补齐分支。`parseTtsProvider` 不用改 —— 存的是枚举名。
- `lib/services/kokoro_speech.dart`（新文件）：照 `KittenSpeech` 骨架；
  `kokoroAssets` 摆到 `<支持目录>/tts/kokoro/`，词典与 Kitten 共用 `<tts>/en-us.bin`；
  `createEngine(EngineId.kokoro)` + `load` + `play(..., phonemize: true)`；
  `modelsPresent` / `installAssetsFromBundle` 幂等。
- `lib/services/pick_speech.dart`：`createSpeechFor` 加分支；换档 / 换音色时
  `KokoroSpeech.dispose()` 释放 ONNX；失败提示「Kokoro 离线朗读没跑起来…」。
- `lib/views/tts_settings_page.dart`：不用改（档位与音色都按
  `ttsProviders` / `voiceOptions` 渲染）。
- 资源：`assets/tts/kokoro/` = `model.onnx`（**model_quantized，int8，92,361,116 字节**）、
  `tokenizer.json`（3.5KB，115 个音素 token）、6 个音色 `.bin`（各 522,240 字节）。
  **`model.onnx` 不进仓库**（用户 2026-11-16 口径：不推、也不做运行时下载，开发机下好即可）：
  已从提交里剔除并写进 `.gitignore`，新机器跑 `tool/fetch_kokoro_assets.sh`
  （说明在 `assets/tts/kokoro/README.md`）。tokenizer 与 6 个音色（共 3.1MB）仍随仓库走。
  **不用 `model_q8f16.onnx`**：2026-11-16 真机实测输出全是 NaN，听到的是十几秒静音（见第 8 节）；
  `model_fp16.onnx`（163MB）会把 APK 顶到 200MB 以上，也不采用。
- 测试：`test/core/tts_provider_test.dart` 改成四档 + Kokoro 音色 / 解析 / 标签；
  新建 `test/services/kokoro_speech_test.dart`（打包文件 ↔ 设置页音色 ↔ 插件路径
  三方一致）；`integration_test/tts_engine_test.dart` 加 `probe('kokoro speak')`。
- 文档：`docs/ARCHITECTURE.md` 新增「十、朗读四档」（2026-11-16 砍掉 Kitten 后改为三档，见第 9 节）。

门禁：`flutter analyze` 干净；253 文件过 `check_god_class` / `check_layers`；
133 个 core 文件过 `check_core_tests`；`flutter test` **2549 passed / 2 skipped**。

### 8. 真机验收（2026-11-16 晚，vivo V1981A / Android 12，`ab8166ef`）

接线本身没问题：引擎起来了，进程 RES ~602MB，`tokens=23`。

**踩到大坑：`model_q8f16.onnx` 在这台手机上输出全是 NaN。**
`KokoroSession.synthesize` 打点：`shape=[1,316200] samples=316200 peak=0.0 nan=316200`
→ 转 PCM 全是 0 → 播放 13.2 秒静音（`AudioTrack stop ... 316200 frames delivered`）。
排除过的：模型 SHA256 与 HuggingFace 一致（没下坏）；系统朗读、Kitten 都正常出声
（手机音频没问题）；tokenizer 与仓库内那份逐字节等价。结论：q8f16 的 f16 算子在
ONNX Runtime 1.28 的 CPU 后端上不成立。

**换 `model_quantized.onnx`（int8，92,361,116 字节）后正常**：
`shape=[1,46800]`（1.95 秒）、`peak=0.5126`、`nan=0`，用户当场确认「声音很棒」；
集成测试 `[tts] kokoro speak ok, 7724ms`（含首次把 88MB 资产拷进支持目录 +
建会话 + 推理 + 播放）。

**顺带补的两个防御**：

- `KokoroSession.synthesize` 检查 NaN / 全静音，发现就抛错 —— 让 `PickSpeech`
  退回系统朗读并提示，而不是让用户听十几秒静音。
- `lib/services/kokoro_speech.dart` 加 `kokoroAssetsRevision`：换模型后老安装
  会整包重拷资产。原先「目标文件存在就跳过」，不卸载 App 就换不掉旧模型。

还没做：

1. **release 包复验**：换模型后首包 119.6MB（四档）；砍掉 Kitten 后重打为
   **97.0MB（101,731,885 字节）**，包内已无 `tts/kitten`；R8 seeds 里
   `ai.onnxruntime` 1150 处、`Kokoro` 33 处仍在，usage 里 0 处。已装到真机
   （vivo V1981A）点「试听一句」确认出声，进程 RSS ~497MB（模型确实加载）。
2. **6 个音色的听感对比**（Heart / Bella / Nicole / Michael / Emma / George）：
   设置页逐个试听，确认不是同一个嗓子。
3. 首次解析 assets 到支持目录是同步 `rootBundle.load`（峰值内存多一份 88MB）；
   若真机 OOM，改成原生 `AssetManager` 直读或运行时下载（`ModelDownloader`）。
4. 换音色会释放并重建引擎（再等一次加载）；如果嫌慢，可改成只换 voice embedding
   不重载模型（插件目前没有这个入口，要动 vendored 包）。

### 9. 砍掉 Kitten 档（2026-11-16，用户「浪费空间」）

Kokoro 真机出声后，用户问「Kitten 那个档还有必要吗？删了得了，浪费空间」。
结论：删。它占 `assets/tts/kitten/` 共 **27MB**（模型 24.4MB + voices.npz 3.3MB），
音色就是当初立项换 Kokoro 的原因（「差强人意」），两个离线神经引擎还要各维护
一套资源拷贝 / 音色表 / 崩溃史。现在只剩三档：系统 / Kokoro / Edge。

改了什么：

- `lib/core/tts_provider.dart`：删 `TtsProvider.kitten`、8 个 `kittenVoiceOptions`、
  标签与提示、各 switch 分支；`ttsProviders` 变三档。
- `lib/services/kitten_speech.dart` 整个删除；`pick_speech.dart` 去掉对应 import /
  分支 / 释放分支 / 降级文案；`integration_test/tts_engine_test.dart` 去掉 Kitten 探针。
- `pubspec.yaml` 去掉 `assets/tts/kitten/`；`git rm` 掉三个文件（含 24.4MB 的
  `kitten_tts_nano_v0_8.onnx`）。`en-us.bin` 保留 —— Kokoro 的音素化还要用。
- `packages/neural_tts` 里 Kitten 的类**不动**（vendored 包，少一处本地分叉）；
  App 不再引用它们，R8 的 `-keep ai.onnxruntime.**` 仍覆盖两者。

老安装的迁移（有测试守着）：

- 存过 `kitten` 档 → `parseTtsProvider` 迁到 `kokoro`，保留「离线神经朗读」的本意；
- 存过 `expr-voice-*` 音色 → 在 Kokoro 档认不出，回默认 `af_heart`。

代价：低端机内存从 Kitten 的 ~235MB 涨到 Kokoro 的 ~500MB。Kokoro 起不来时
`PickSpeech` 仍会退回系统朗读并提示，不会变成「没声」。包体从 119.6MB 降到
**97.0MB（101,731,885 字节）**，省 23.7MB（Kitten 资源压缩后约 22.6MB + 少量代码）。
release 包已装真机试听通过，界面只剩三档，Kokoro 行显示「约 88MB」。

### 10. 预生成朗读缓存（2026-11-16，用户）🟡 WAV 短篇已验收，长篇待验

用户问：「加个功能？预生成朗读？因为手机存储有限，只存 2 篇的朗读音频？大概多大啊？」
按备份里 50 篇的统计（平均 973 词 / 41 句、中位 823 词）算：

| 格式 | 中位一篇 | 两篇 |
|---|---:|---:|
| Kokoro PCM WAV（24kHz/16bit/单声道） | ~15MB | ~30–36MB |
| AAC 64kbps（最终弃用） | ~2.6MB | ~5–6MB |

用户选了 **手动按钮 + AAC 压缩**；AAC 真机产出坏帧（见下），
2026-11-16 最终改为 **WAV**，优先保证读音正确。

已做：

- 阅读页「更多 → 生成离线朗读」：显示预计体积 / 逐句进度 / 取消 / 删除 / 重新生成；
  最多保留 2 篇，第 3 篇按最久未用淘汰。
- 逐句调 `tts.synthesizeToFile`；Kotlin 侧 `KokoroEngine` 把
  `KokoroSession.synthesize` 的 PCM 直接写成 **24kHz/16bit/单声道 WAV**
  （RIFF 头 + PCM），不经过手机编码器，不再有 AAC 坏帧。
- 发音前过 `core/tts_text.dart`：弯引号归一成 ASCII 撇号、双引号去掉、
  长破折号变停顿；否则 `Arabia’s` 会被音素化成 `Arabia` + `’` + `ˈɛs`。
- 生成中面板可以「先退出，后台继续」；点「取消」会调 `speech.stop()` 把原生
  generation 作废。单句另有 60 秒 Dart 超时，不会让 UI 永远停在 0/N。
- 缓存 `<支持目录>/tts_audio/index.json` + `articles/.../<key>.wav`；key 含归一化
  原文 / 音色 / `kokoroAssetsRevision`；坏索引逐条丢弃、文件名白名单防路径穿越。
- 缓存命中时 `KokoroSpeech` 直接播 wav，**不加载 88MB 模型 / 500MB 内存**；
  miss 才即时合成。
- 测试：`test/core/tts_audio_cache_test.dart`（key / 估算 / LRU / 索引守卫）、
  `test/core/tts_text_test.dart`（弯引号 / 破折号 / 幂等）、
  `test/services/tts_audio_cache_test.dart`（文件缓存 / 淘汰 / 取消 / 失败）、
  `test/viewmodels/offline_audio_view_model_test.dart`（状态 / 取消 / 非 Kokoro 档）。
- `integration_test/tts_engine_test.dart` 的 `synthesizeToFile` 探针会打印
  wav 字节数并实际播放一次。

**待验收**（2026-11-16 真机）：

1. ✅ AAC 阶段短句生成成功（19KB，约 4 秒含模型加载），但后续发现 AAC 缓存
   解码报错、文章“读不准”；WAV 版待重新生成确认。
2. ✅ 强杀 App 后重开、点句子：RSS 只涨 ~12MB，缓存命中不加载模型。
3. ⏳ 连生 3 篇的 LRU 淘汰、取消 / 后台继续还没有在长文章上手动过一遍。
4. ⏳ 41 句整篇 WAV 的实际体积 / 耗时（按单句 ~2 秒估算约 1.5 分钟）。

**真机踩坑（AAC 已弃用，记录备查）**：

- `MediaCodec` + `MediaMuxer` 在这台 vivo 上失败：编码器输出 `csd-0` 只有
  2 字节，logcat `csd0 too small`，一帧都不出，面板卡在「0 / N」。
- 改 ADTS 裸流（`.aac`）后能出帧，但生成的文件用 ffmpeg 解码报
  `Invalid data` / 帧边界错位（某帧多出 1 字节），实际文章走缓存就“读不准”。
- `KEY_MAX_INPUT_SIZE` 16KB 会吃满输入槽不出帧；24kHz 也不出帧。这些在
  AAC 方案里都绕过，但最终仍因帧损坏放弃。
- **结论**：预生成走 WAV，不再碰手机 AAC 编码器；试听（实时 PCM）一直正常。
- release 包 97.1MB；WAV 版只改 Dart/Kotlin 代码，资源不变。

---

## 第二十七件：小课堂填空全程保留键盘（2026-11-15，用户）✅ 已完成（`8af1e68`）

**用户反馈（原话要点）**：

- 需求：「小课堂填空的时候，输入键盘一直存在？」「『这一轮全对』或者错误提示放在
  别的位置，我有点不知道为什么，看到那个键盘消失又出现就难受。」
- 验收：「舒服了，太舒适了！不头晕了，也不恶心了」「大概就是因为眼睛上下跳，
  所以不舒服。」

**根因**：交卷时 `unfocus()` 收键盘，判分汇总又塞在正文末尾；下一轮再
`requestFocus`，视线跟着键盘和提示上下搬两次。把输入框改成 `readOnly` /
`enabled: false` 也不行 —— Android 上 `_shouldCreateInputConnection` 会变成
false，输入连接直接关掉，键盘照样落（`editable_text.dart`）。

**做法**：

- 交卷不 `unfocus`；判分后输入框保持可编辑；再打字走
  `GoldenDrillSession.reopenFill()` 撤掉判分，避免「提示说全对、答案却改了」。
- 判分条改为动作条下方的 `_FillVerdict` 固定条，文案带上「回车继续 / 回车重试」。
- 换轮只重建 controller；`FocusNode` / `GlobalKey` 按空位下标跨轮保留
  （`_resizeFocuses` / `_resizeBlankKeys`），焦点直接交给新轮第一个空。
- 回车与动作条共用 `_fillAction`：未交 = 交；已判分 = 下一轮 / 重试。

**验收**：`test/views/golden_drill_focus_test.dart` 断言交卷 / 换轮 / 重试后
`tester.testTextInput.isVisible == true`，且判分条在正文上方；`reopenFill` 有
session 用例。全量 **2540 passed / 1 skipped**，`flutter analyze` + 三个 check 全绿。
release 包（arm64，55,334,349 字节）解包复核过 R8 keep 类。

**以后小课堂的交互原则：视野不跳。** 填空期间不收键盘、不让主要阅读位置上下搬；
状态提示固定在键盘上方，别塞在正文末尾。

---

## 已知的坑（别再踩）

- **release APK 只打 arm64**（2026-11-15 起用 `abiFilters` 锁死），模拟器是 x86_64，
  直接装会崩：`Could not find 'libflutter.so'. Looked for: [x86_64, x86],
  but only found: [arm64-v8a].` 本地调试用
  `flutter build apk --release --target-platform android-x64 -PtargetAbi=x64`。
  规格与体积构成见 **`docs/BUILD.md`**。
- **`android/gradle.properties` 的 `disable-abi-filtering=true` 不能删**：
  删了 Flutter Gradle 插件会覆盖 `app/build.gradle.kts` 里的 `abiFilters`，
  release 包又变回三 ABI 的 138MB，且 armeabi-v7a / x86_64 目录残缺。
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
  - **release 包已不再带它**（2026-11-14）：`scripts/build_release.bat` 构建前后
    自动把它挪出 / 挪回 `assets/data/`，所以**别直接 `flutter build apk --release`**。
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
- **`espeak`（`neural_tts` 的依赖）在 Windows 宿主机上编不过**（2026-11-15 踩）：
  `cl.exe` 报 `error C2491（dllimport 函数的定义）` + `fatal error C1083: 无法打开 “pthread.h”`
  —— 它的 C 源是按 Unix/GCC 写的，`compat/` 里没有 `pthread.h`，这个包在 Windows 上从没编通过。
  `native_toolchain_c` 在 Windows 上**只选 MSVC、不回退 MinGW**，装 GCC 也没用。
  关 `--no-enable-native-assets` 也不行（`sqlite3` / `objective_c` 都要它）。
  **本地补丁（已打，重装 pub cache 会丢）**：在
  `I:\.pub-cache\hosted\pub.flutter-io.cn\espeak-0.1.3\hook\build.dart` 的
  `await build(args, (input, output) async {` 之后加一行
  `if (input.config.code.targetOS == OS.windows) return;`。
  只在宿主机跑测试时生效，**Android 构建仍会正常编 espeak（走 NDK clang）**。
- **`assets/tts/` 是进包资产，别和 `assets/data/` 混**（2026-11-15）：
  Kitten 模型（约 30MB）走 `assets/tts/`，`.gitignore` 没有忽略它，**要进 git**；
  `assets/data/` 的 33MB 真备份则被忽略、且 release 构建时被脚本挪走。
  改动这两个目录里任何东西，都要重打 APK 才生效（HMR 不覆盖 assets）。
- **release 包开 R8，debug 验过不算数**（2026-11-15 踩）：
  Flutter 的 release 默认 minify（本仓库没写 `isMinifyEnabled`，但
  `build/app/outputs/mapping/release/` 会生成 `mapping.txt` / `usage.txt` / `seeds.txt`）。
  ONNX Runtime 这类「Java 类只被 native 侧 JNI 反查」的库，Java 侧没有静态引用就会被裁掉，
  运行期表现为 `JNI DETECTED ERROR ... java_class == null in call to GetMethodID` + `SIGABRT`。
  `flutter_onnxruntime` / `neural_tts` 都**没有** `consumerProguardFiles`，规则只能写在
  `android/app/proguard-rules.pro` 并在 release 块挂上。**凡是被裁剪影响的路径，
  必须在 release 包上验，debug/集成测试全绿不能作数。**
  排查手法：解 APK 的 `classes*.dex`（`System.IO.Compression.ZipFile` 读出来后按 ASCII 搜类名），
  release 与 debug 两份对着看哪些类不见了。
- **`adb` 驱动 Flutter 页面时，文字在 `content-desc` 里，不在 `text`**（2026-11-15 踩）：
  `uiautomator dump` 出来的节点 `text` 基本全空，Flutter 把语义标签写进 `content-desc`，
  且带 `&#10;` 换行转义。按 `text="..."` 正则找按钮会一个都找不到。
  `adb exec-out screencap -p > x.png` 在 pwsh 里落地是 0 字节（二进制被当成文本管道），
  要 `adb shell screencap -p /sdcard/x.png` + `adb pull` 才拿得到图。
- **验证「键盘有没有掉」要用轮询，不能只看一眼**（2026-11-15）：
  `dumpsys input_method` 的 `mInputShown` 在 Flutter + 第三方输入法上不可靠（恒定 false），
  看窗口更准：`dumpsys window windows | grep -c 'u0 InputMethod'`，在点击前后密集采样，
  出现 0 就是掉了。注意 `com.vivo.secime.service` 的 `SecureInputMethod` 窗口是另一回事。
