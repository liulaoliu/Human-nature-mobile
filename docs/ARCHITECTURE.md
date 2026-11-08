# 架构

「D老师帮你办」安卓版。**这是 `I:\Examples\Stutterer`（React + TS Web 版）的重写**，
不是它的壳、也不是它的分支：两份代码互不引用，语义以 Web 版为准。

## 一、分层

```
lib/models/              纯数据（freezed）：VocabItem / VocabLibrary / Article / Learning …
      ↑
lib/core/                纯领域逻辑：拆句、判分、日期键、归一化、复习调度 …
      ↑                  （不许 import Flutter / sqflite / SharedPreferences）
lib/data/repositories/   实现 core 声明的端口：sqflite、SharedPreferences、文件
lib/services/            跨仓库编排：导入导出、备份、AI 跑批
      ↑
lib/viewmodels/          ChangeNotifier：把仓库/服务的结果变成视图状态
      ↑
lib/views/ + lib/widgets/  Flutter 界面（不许直接开数据库）
```

依赖只能**单向往里收**：`views → viewmodels → services → repositories → core → models`。
`dart run tool/check_layers.dart` 会拦违规（R1–R4）。

### 为什么 core 要这么干净

core 是这套 App 里唯一能脱离手机跑的部分（`flutter test` 里秒级跑完，不用模拟器），
也是从 Web 版**逐函数搬过来**的部分。core 一旦能 import Flutter，就等于把
「搬对了没有」这件事变成只能靠手点验证 —— 所以端口模式是硬要求：

```dart
// lib/core/ports.dart —— 只声明，不实现
abstract class VocabRepository {
  Future<VocabLibrary> load();
  Future<void> save(VocabLibrary library, {String? baseUpdatedAt});
}
```

实现放 `lib/data/repositories/`，由 `main.dart` 注入到 ViewModel。

## 二、服务端整个消失

Web 版有 `server/`（Node + `node:sqlite` + HTTP `/api/store/*`，24 文件 4.5k 行）。
手机上不需要它：

| Web 版 | 安卓版 |
|---|---|
| `src/adapters/sqliteRepo.ts` 走 HTTP 打 `/api/store/*` | `lib/data/repositories/*.dart` 直接读写 sqflite |
| `src/adapters/*Repo.ts` 的 IndexedDB 兜底 | 不需要（sqflite 就是本机库） |
| `server/sqliteStore.ts` 的 13 版迁移 | `lib/data/db/schema.dart`，**迁移史照搬** |
| `server/appServer.ts`（`npm run serve`） | 不存在 |

**迁移史必须照搬**：Web 版 `PRAGMA user_version` 从 1 走到 13，每一步都带着数据回填
（v1 老库要补 `articles.title/sentence_count/word_count/created_at`、v7 要同时建
V8/V9/V11/V13 并写派生基线）。老用户的备份要能直接导入，所以这 13 步一步都不能跳。

## 三、视图层是重新设计，不是翻译

Web 版 `src/reader` 有 291 个文件 42.9k 行 React，里面大量依赖 Web 语义：
URL query 驱动面板（`?p=write&wv=history`）、sticky 吸顶/吸底、hover 卡片、
`<details>` 折叠、浏览器返回键。

手机上这些语义**要么换载体，要么砍掉**：

| Web 语义 | 安卓对应 |
|---|---|
| URL query 驱动的面板状态 | Navigator 路由 + 参数（要能深链接，也要能返回） |
| `position: sticky` 吸顶/吸底 | `SliverAppBar` / 固定底部按钮区 |
| hover 卡片（`WritingHoverCard`） | 长按弹出 / 列表项直接显示摘要 |
| `<details>` 折叠 | `ExpansionTile` |
| 浏览器返回键 | 系统返回键（`PopScope`） |
| `localStorage` 草稿 | SharedPreferences（小）或 sqflite（大） |

**不要照抄 React 组件树**。先想「手机上这件事应该怎么做」，再写 Flutter。

## 四、数据与存储

- 主存：sqflite（`lib/data/db/`），表结构与 Web 版 SQLite 对齐。
- 小状态（当前文章、主题、字号、上次停留位置）：SharedPreferences。
- 草稿（仿写作答、造句草稿、产出草稿）：sqflite（量可能大，别塞 SharedPreferences）。
- 词典数据（`ecdict.tsv` 7.8MB / `tatoeba-en.tsv` 6.5MB / `mwld.tsv` 4.3MB，共约 18.6MB）：
  预置进 `assets/`，首次启动导入 sqflite（不要每次启动都解析 tsv）。

## 五、门禁

```bash
flutter analyze                       # 0 error / 0 warning
dart run tool/check_god_class.dart    # 类体 800 行 / 方法 40 / 字段 30 / 注入仓库 4
dart run tool/check_layers.dart       # R1–R4 依赖方向
dart run tool/check_core_tests.dart   # core 每个文件都要有同名测试
flutter test                          # 全量
```

上帝类门禁的基线（`_baseline`）目前是**空 Map**：新仓库从零开始，不许一上来就欠债。
真要登记基线，必须写明理由，且拆分后同步下调。

## 六、跟读：语音现合成，不存音频

**手机上不存「参考音」音频文件。** 跟读的参考音一律由 TTS 当场合成：

| 环节 | 做法 |
|---|---|
| 参考音播放 | `flutter_tts` 合成整句（`setSpeechRate` 控速、`setLanguage` 控口音） |
| 逐词高亮 / 点词跳播 | 不要指望 TTS 给逐词时间戳（Android 的 `TtsEngine` 只给整句区间）。改用「按词切段合成」：把句子按词切成若干段分别 `speak`，用回调里的边界算进度 |
| 用户录音 | `record` 插件录到临时文件，算完波形/相似度后**立刻删**（只保留统计结果，不保留音频） |
| 波形显示 | 录音期间用 `record` 的 `onAmplitudeChanged` 实时画，不落盘 |

为什么这样：Web 版靠服务端 Edge TTS（`/api/tts`）返回 mp3，还要 `/api/tts/words` 拿逐词时间戳，
并有 `ttsCache.ts` 做预热 —— 那套在手机上等于「自带一个服务器」，不划算。
现合成的代价是**逐词高亮精度不如服务端时间戳**，但换来零网络、零缓存、零音频文件。

`flutter_tts` 的已知坑（写实现前先看）：中文/英文混排要用 `setLanguage('en-US')` 显式指定；
连续 `speak` 会互相打断，所以「按词切段」必须用 `awaitSpeakCompletion(true)` 串起来；
部分机型首次调用有 200–500ms 延迟，别把第一句的计时算进跟读成绩。

## 七、跨设备数据迁移（PC → 手机，不经网络）

Web 版「导出备份」产出的 `economist-backup-<day>.json` 就是迁移载体：

```
PC（Web 版）点「导出备份」→ economist-backup-2026-11-08.json
        ↓  U 盘 / 微信文件传输助手 / 数据线 / 局域网共享（任意一种，不经我的服务器）
手机 App「设置 → 从电脑导入」→ 选这个 JSON → 解析 → 合并或覆盖
```

**JSON 结构照 Web 版 `exportFiles.ts:66 exportAll()` 原样支持**（那是契约，不能改）：

| 键 | 内容 |
|---|---|
| `version` / `exportedAt` | 备份格式版本与时间 |
| `library` | 词库（`{schemaVersion, items}`，走 `migrateLibrary` 洗） |
| `articles` | 已保存的文章（含 `sentences` / `paragraphs` / `golden`） |
| `stats` / `studyStats` | 选词会话 / 背词日统计（老键名，`parseBackupPayload` 会映射到 `sessions` / `studyDays`） |
| `activity` | 活动热力图数据 |
| `writingHistory` / `backTranslations` / `retells` | 仿写记录 / 回译 / 复述 |
| `practice` / `mistakes` / `studiedDays` / `skimmed` / `kindStats` | 练习 / 错题 / 背过的词 / 略读 / 题型统计 |
| `answerEvents` / `goldenDrills` | 答题事件 / 金句锤炼 |
| `writingErrorProgress` / `productionProgress` / `readDone` | 错因复习 / 工棚进度 / 读完记录 |
| `readGoal` / `goalMemo` | 阅读目标 / 目标备忘 |
| `productionDraft` | 奶牛工棚草稿（外部输入，导入时再 normalize） |

导入分两种（照 `backupIO.ts` 的语义，别自己发明）：

- **覆盖导入**：词库整库替换、统计整段替换、文章按 id 写入。
  **词库必须先落盘成功**才写统计 —— 否则 409/磁盘满时会出现「统计换了、词库没换」的半截状态。
- **合并导入**：保留现有数据，词库按 lemma 去重、统计按天累加、错题按 id 累加。
  要记「这份文件已导入」的指纹（`backupFingerprint` + 20 条账本），
  且**指纹必须在词库真正落盘之后才写** —— 否则重试同一份文件会被去重直接跳过。

**外部输入必须过守卫**：`parseBackupPayload` 逐段检查、坏条目丢弃并计数，
返回的 `dropped > 0` 必须在界面上提示（`lib/core/backup_parse.dart` 是它的 Dart 版）。
不许 `jsonDecode` 之后直接当强类型用 —— 一条缺 `lemma` 的词条就能把整库弄坏。

文章还可以单独走**文章包**（`format: 'xueba-article-package'`，一篇一个文件），
手机上「导入文章包」只做合并，不做覆盖（覆盖会把词库清成只剩这一篇）。

