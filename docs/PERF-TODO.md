# 性能待办：词库写路径（交给别的 AI 也能直接开工）

> 写于 2026-11-15。当前 `HEAD` 以 `origin/master` 为准，工作区干净。
> 这份文档是**自包含**的：背景、实测数字、改哪个文件哪一行、怎么验收、有哪些坑，
> 都在这里。不需要先读别的文档也能动手。

---

## 1. 为什么做这件事

`I:\Examples\dlaoshi_app` 是「D老师帮你办」的 Flutter 安卓版（英语精读 / 背单词 / 产出训练）。
词库（`VocabLibrary`）是**整段 JSON** 存在 SQLite 的 `vocab.payload` 里（gzip 压缩后约 1.8MB），
另外有一层派生表（`words` + 8 张 `word_*` 表）供搜索 / 筛选。

真机数据规模：**10,892 条词条 / 51 篇文章 / 13,463 条按篇关联**，整库 JSON **16.4MB**。

问题：**每答一道题都要把整库重写一遍**。用户感觉不到明显卡顿，是因为界面上做的是
「先回界面、写盘合并到后台」，但写盘本身很慢 —— 桌面 1.5 秒，手机上只会更慢。
导入一份 Web 备份要 20 秒左右，其中 9 秒是重建派生表。

把这两条降下来，是**当前唯一还有实质收益的代码工作**（其余 TODO 项要么只能用户做，要么明确不做）。

## 2. 实测数字（先跑一遍确认没退化）

```powershell
cd I:\Examples\dlaoshi_app
& "I:\tools\flutter\bin\flutter.bat" test test/bench/save_stages.dart
```

`test/bench/save_stages.dart` 是**一次性探针**（文件名故意不带 `_test`，全量测试不收），
把一次保存拆成几段打印耗时。2026-11-15 桌面（真备份 10,892 词）实测：

| 阶段 | 耗时 | 备注 |
| --- | --- | --- |
| 读文件 33MB | 270 ms | 只在基准里 |
| `parseBackupPayload` | 1400 ms | 只在导入时 |
| `compactSentenceTexts` | 110 ms | 每次保存都跑 |
| `encodeVocabLibrary` | 396 ms | 产出 16.4MB 字符串 |
| `utf8.encode` | 102 ms | |
| `gzip` level 6 | 254 ms | → 1.83MB |
| `gzip` level 1 | 84 ms | → 2.14MB（对照） |
| `vocabLibraryToJson` | 111 ms | 给派生表用的 Map 形状 |
| prev 逐条 `jsonEncode` | 260 ms | 增量 diff 用 |
| next 逐条 `jsonEncode` | 219 ms | 增量 diff 用 |
| **save 首次（全量投影）** | **9244 ms** | 导入 / 迁移走这条 |
| **save 增量（改 1 条）** | **1536 ms** | 每次评分 / 自动补全走这条 |

另外两个数字（同日实测，桌面）：

- `load` 冷（新实例，解 gzip + 解析）：1174 ms；`load` 暖（走内存缓存）：**0 ms**；
  `meta()`（只查版本号）：**0 ms**。→ **读路径已经被缓存兜住了，别去优化读。**
- release APK 52.73MB / arm64-only（见 `docs/BUILD.md`）。

## 3. 三个改动（按收益排序）

### 任务 A（最大头）：派生表别一条一条插

**位置**：`I:\Examples\dlaoshi_app\lib\data\db\projections.dart`
函数 `rebuildVocabProjection(DatabaseExecutor db, Object? lib, {Object? prevLib})`（约 `:201`）。

**现状**：词条循环里对 `words` / `word_usage` / `word_phrases` / `word_idioms` / `word_tags` /
`word_grammar_marks` / `word_examples` / `word_contexts` / `word_confusables` 逐条
`await db.rawInsert(...)`。1 万词 × 平均 6 条语句 ≈ **6 万次 FFI 往返**，这就是 9.2 秒的主因。

**改法**：循环前 `final batch = db.batch();`，循环里所有 `await db.rawInsert(` 改成
`batch.rawInsert(`（**注意去掉 `await`**），循环结束后 `await batch.commit(noResult: true);`。

**只改 `rebuildVocabProjection` 里那一段**。同一个文件里的 `rebuildArticleProjection`（约 `:60`）
也有 `await db.rawInsert(`，**不要一起改** —— 它没有 `batch` 变量，改了直接编译不过。

**注意**：`_deleteWordIds` / `_clearWordProjection` 仍是直接调用，不要塞进 batch
（它们要先生效，而且分块删是为了绕开 SQLite 参数上限）。

**验收**：`save 首次` 从 9244 ms 降下来（预期 2–4 秒量级）；派生表内容一字不差 ——
跑 `flutter test test/data -j 1` 与全量测试，所有词库投影相关用例必须全绿。

### 任务 B（第二大头）：增量 diff 别逐条 `jsonEncode`

**位置**：同文件 `rebuildVocabProjection` 开头（约 `:206-219`）：

```dart
final prevById = <String, String>{
  for (var i = 0; i < prevItems.length; i++) _wordIdOf(prevItems[i], i): jsonEncode(prevItems[i]),
};
final nextById = <String, String>{
  for (var i = 0; i < items.length; i++) _wordIdOf(items[i], i): jsonEncode(items[i]),
};
```

把 1 万个词条**各编码两遍**（共 479 ms），只为了判断「这一条变没变」。

**改法（推荐）**：不编码整条 JSON，改成「只算投影真正用到的字段」的指纹。
投影写入的字段就是 `words` 那 24 列 + 各 `word_*` 子表的内容，所以
「没进投影的字段变了」本来就不需要重写派生表 —— 比现在更准，不是妥协。

实现建议：写一个 `String _fingerprint(Map<String, Object?> it)`，用 `StringBuffer` 拼
`id|word|lemma|kind|langPointId|phonetic|partOfSpeech|meaning|definition|status|note|`
`source.articleId|source.fileName|source.sentenceId|source.sentenceText|`
`reviewState.ease/due/interval/repetitions/lapses|lastPrintedAt|priorityUntil|createdAt|updatedAt|`
`usage/phrases/idioms/tags/grammarMarks 的 join|examples 的 join|contexts 的 join|confusables 的 join`。

- 用 `|` 分隔时**每段都要带长度前缀或改用不含分隔符的转义**，否则 `["a|b"]` 和 `["a","b"]`
  会撞成同一个指纹。最省事的做法：每段写成 `${s.length}:$s`。
- 改了字段就别怕长 —— 只要别是整条 `jsonEncode`。

**更省的一半**：`prevById` 在「缓存命中」路径上是**同一版词库**反复重算的
（`save()` 里 `prevLib` 优先吃 `_cachedJson`）。可以在 `VocabRepository` 里把
「上一版逐条指纹」跟着 `_cachedAt` 一起缓存，命中就直接用，省掉那 260 ms。
**这一步可选**，先做上面那条。

**验收**：`save 增量` 从 1536 ms 降到 ~1000 ms 上下；**关键正确性**：
改一条词的任何一个投影字段都能被重新写进派生表（写个用例：只改 `meaning`、只改
`reviewState.repetitions`、只改 `contexts` 里一句，各断言派生表跟着变了；
再改一条**不在投影里**的字段，断言派生表没重写 —— 用 rowid 不变来验证）。

### 任务 C（小头，改一行）：gzip 从 level 6 降到 level 1

**位置**：`I:\Examples\dlaoshi_app\lib\data\repositories\vocab_repository.dart:101`

```dart
final GZipCodec _gzip = GZipCodec(level: 6);
```

改成 `level: 1`：254 ms → 84 ms（省 170 ms），代价是落盘从 1.83MB 涨到 2.14MB（+0.3MB）。
gzip 是自描述格式，**解压完全不受影响**，老数据照样读得回来，不需要迁移。

**注意**：文件头 `:13-17` 的注释写着「压一次 ~280ms」「1.5MB」，改完要顺手把这些数字订正，
别留一句和代码对不上的说明。`article_repository.dart` 也有一个 `_pack`，**这条只改 vocab 的**。

## 4. 收尾：门禁 + 提交

改完**必须**跑（一条都别跳）：

```powershell
cd I:\Examples\dlaoshi_app
& "I:\tools\flutter\bin\dart.bat" analyze lib test tool
& "I:\tools\flutter\bin\flutter.bat" test -j 4
& "I:\tools\flutter\bin\dart.bat" run tool/check_god_class.dart
& "I:\tools\flutter\bin\dart.bat" run tool/check_layers.dart
& "I:\tools\flutter\bin\dart.bat" run tool/check_core_tests.dart
```

门禁规则（数字是 2026-11-15 的基线，**只会往上加**）：

- 全量测试基线 **2502 passed / 1 skipped**；源文件 **249**；core 文件 **133**。
- `check_god_class`：文件 ≤ 800 行、类体 ≤ 800 行、方法 ≤ 40、字段 ≤ 30、注入仓库 ≤ 4，`_baseline = {}` 不许欠债。
- `check_layers`：R1 `core` 禁 flutter/sqflite/shared_preferences；R2 core 禁上层；R3 data 禁界面；R4 views/widgets 禁 sqflite。
- `check_core_tests`：每个 `lib/core/x.dart` 必须有 `test/core/x_test.dart`（唯一例外 `ports.dart`）。

**判成功看输出文字，不看退出码**：pwsh 里 `flutter test` / `dart analyze` / `git push` 的
stderr 会让命令显示 `[exit code: 1]`，实际是成功的。认这些字样：
`All tests passed!` / `No issues found!` / `xxx..yyy master -> master` / `✅`。

**提交**（中文提交信息必须走文件，别在命令行里写）：

```powershell
cd I:\Examples\dlaoshi_app
# 1. 用 write 工具写 .commit-msg.txt（第一行 feat:/fix:/perf: + 中文简述，下面空行写要点）
# 2. 用 write 工具写 tool/do_commit.sh：
#    set -e
#    cd /i/Examples/dlaoshi_app
#    git add <显式列出的每个文件>
#    git commit -F .commit-msg.txt
#    echo "commit-exit=$?"
#    rm -f .commit-msg.txt tool/do_commit.sh
#    git status --short
#    git log --oneline -1
& "D:\Program Files\Git\bin\bash.exe" -lc "cd /i/Examples/dlaoshi_app && sh tool/do_commit.sh"
```

- **别用 `git add -A`**，显式列文件。
- **别 `git add .commit-msg.txt`**（`.gitignore` 里已忽略，但它就在工作区）。
- 脚本最后会 `rm` 掉自己 → pwsh 报 `[exit code: 1]` 是正常的。
- 一个主题一个 commit；改完跑 `git push origin master`（仓库 `git@github.com:liulaoliu/Human-nature-mobile.git`，SSH）。

## 5. 坑（都是踩过的，别重踩）

1. **含中文的文件只能用 `write` / `edit` 工具改**。用 pwsh 的
   `(Get-Content -Raw).Replace(...) | Set-Content` 会：给文件加 BOM、把 UTF-8 写坏、
   把 `${...}` 当变量展开吃掉。2026-11-15 就因为这个把 `projections.dart` 改坏过一次
   （好在 `git checkout --` 救回来了）。
2. **`edit` 的 `old_string` 必须唯一**。同一段代码出现两次就用更大的上下文，或 `replace_all`。
3. **改 `.bat` 必须 CRLF 行尾**，否则 cmd 解析中文 `REM` 会整行错位
   （报 `'oNewWindow' is not recognized`）。改完用字节数核对 `CRLF` 数量。
4. **`test/bench/*.dart` 不带 `_test` 后缀**，全量测试不会收它，要跑得显式指定文件名。
5. **widget 测试里别直接 `await` 会碰真 SQLite IO 的调用**（`vm.start()` / `vm.submit()`）——
   假时钟下永远不返回，会挂死到超时。用 `await tester.runAsync(vm.start)`。
6. **`dart analyze` 不支持 `--no-pub`**；一次跑 `lib test tool` 三个目录才查得全。
7. **别改 `I:\Examples\Stutterer`**（Web 版）。这次任务只在 `I:\Examples\dlaoshi_app`。
8. **别把 `assets/data/economist-backup-2026-11-10.json`（33MB）提交进 git**，它只在本地当基准数据用。
9. 跑全量测试约 2 分半，**用后台任务**，别在前台死等。

## 6. 不要做的事（已经明确否掉的）

- 不许写文件导入 / PDF / EPUB 解析（用户 m08236 明确要求只保留「粘贴原文」）。
- 打印 / 导出（Anki CSV、词表、错题表）不做（m16220）。
- 不加新的全局状态库、不新增 HTML 入口（那是 Web 版的事）。
- API key 只存 `shared_preferences`，绝不进 git / 备份 JSON / `local.properties`。
- `http` 只允许出现在 `lib/services/`，不许进 `lib/core/`。
