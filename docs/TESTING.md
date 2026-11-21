# 测试

## 一、分层判定矩阵

| 你改的是 | 该写哪种测试 | 放哪 |
|---|---|---|
| `lib/core/` 的纯函数（拆句、判分、归一化、日期键） | 单元测试 | `test/core/<同路径>/<同名>_test.dart`（**必须存在**，门禁会查） |
| `lib/models/` 的序列化 / 归一化 | 单元测试 | `test/models/` |
| `lib/data/repositories/` 的 SQL | 用 `sqflite_common_ffi` 起真库的测试 | `test/data/` |
| `lib/viewmodels/` 的状态迁移 | 单元测试（注入假仓库） | `test/viewmodels/` |
| `lib/views/` 的页面交互 | Widget 测试 | `test/views/` |
| 跨页面 + 真数据库闭环 | 集成测试 | `integration_test/`（需要模拟器/真机） |
| 真网络 / 真凭据（第三方 API） | e2e，**默认 skip** | `test/e2e/`（见本文件 §五） |

**core 的门槛是硬的**：`dart run tool/check_core_tests.dart` 会要求
`lib/core/x/y.dart` 存在 `test/core/x/y_test.dart`。纯接口文件登记在
`tool/check_core_tests.dart` 的 `_allowNoTest` 里并写理由。

## 二、移植时怎么定「搬对了」

Web 版的测试用例是**验收基准**，不是参考。移植某个 core 模块时：

1. 先打开 Web 版同名测试（如 `src/core/activity.test.ts`）；
2. 把用例逐条翻成 Dart（用例名照抄中文，方便两边对照）；
3. 跑测试 —— 红了说明移植错了，不是测试写错了；
4. 只有 Web 版测试本身覆盖不到的新分支，才补新用例。

已完成的移植对照：

| Web 版 | 安卓版 | 用例数 |
|---|---|---|
| `src/core/activity.ts`（200 行） | `lib/core/activity/activity.dart` | 20 |
| `src/core/entryKind.ts` | `lib/core/entry_kind.dart` | 6 |

### 用例来源要能分辨：`[Web]` 与 `[Dart]`

用例总数（现在是 1,700+）只说明「覆盖得多」，不说明「覆盖的是什么」。
**逐条翻自 Web 版的用例证明「移植没搬错」，为 Dart 侧新分支写的用例才证明「这边也对」**，
两类不能混着数。新写 / 改写的用例在名字前加来源标签：

| 前缀 | 含义 | 例 |
|---|---|---|
| `[Web]` | Web 版同名测试里逐条翻过来，**期望值必须与那边一致** | `test('[Web] 四种吃法的标题', ...)` |
| `[Dart]` | Dart 侧独有的边界 / 分支，Web 版没有对应用例 | `test('[Dart] 温度超过上限被夹到 2', ...)` |
| 无前缀 | 存量老用例，暂不追溯；**改它时顺手补标签** | `test('空串 / a / hello 四个真值', ...)` |

真实例子：

- `test/core/ai_jobs_test.dart` 的 `test('空串 / a / hello 四个真值', ...)` —— 断言的是
  `aiFingerprint` 与 Web `src/core/aiPackIO.ts` 的 `fnv1a` **逐位一致**，属 `[Web]`；
- 同文件的 `test('词组 / 习语 / 用法笔记不进词级任务', ...)` —— 口径来自 Web `aiTodos.ts` 的
  `isWordEntry` 过滤，也是 `[Web]`；
- `test/viewmodels/ai_batch_view_model_test.dart` 的「模型多回一个没请求的词」——
  Web 版是服务端跑批，客户端根本没有这条分叉，属 `[Dart]`；
- `test/viewmodels/vocab_browse_view_model_test.dart` 的「两千条词时，一帧连读多次也只扫一次」——
  纯 Dart 性能口径，属 `[Dart]`。

**不要求改存量**：1,700+ 例全部补标签是纯改名的体力活。规则是**新写的必须带**，
**动到的顺手带**。想知道某模块「移植对不对」，看它的 `[Web]` 用例是否齐全；
想知道「Dart 这边有没有洞」，看它有没有 `[Dart]` 用例。

## 三、踩坑清单（别再犯）

**1. `flutter create` 的 `--description` 不能带中文和 `/`。**
在 Git Bash 里 `-c` 传含中文的描述会报
`No option specified for the output directory`。做法：先 `write` 一个 `.sh` 脚本再 `bash` 跑，
描述写纯 ASCII，事后手改 `pubspec.yaml`。

**2. Dart 的命名参数要显式声明，TS 的对象入参不会自动跟过来。**
`isWordEntry({kind})` 漏了 `word` → `kindOf` 的词形兜底不生效，
测试直接编译失败 `No parameter named 'word'`。移植带「可选字段」的函数时，
逐个核对 Web 版入参对象里的每个字段。

**3. `DateTime.weekday` 是 1=周一…7=周日，不是 0=周日。**
`buildHeatmap` 里要用 `weekday % 7` 换算（周日→0，周一→1）。
Web 版 `getDay()` 是 0=周日，直接抄会把整个热力图错位一格。

**4. .bat 脚本必须是纯 ASCII。**
cmd.exe 用 OEM 代码页（简中 GBK）读 `.bat`，UTF-8 中文注释会被拆成乱码命令，
报一堆 `'xxx' is not recognized`。要写中文就写进 `.md` / `.ps1`（带 BOM）。

**5. 不要提交「隐藏窗口 + Start-Process + 重定向」的看护脚本。**
2026-11-08 建仓时写过 `scripts/run_with_watch.bat`（照 patrol_helper 的模式），
落地即被杀毒软件删掉 —— 隐藏窗口起进程再重定向输出是典型告警特征。
长命令直接后台跑，或 `flutter test 2>&1 | tail -40`。

**6. `dart run tool/*.dart` 会先跑 build hooks（可能打印 `Running build hooks...`）。**
那是正常现象，不影响退出码。

**7. 安卓 TTS 的逐词进度是字符区间，不是毫秒。**
`flutter_tts` 的 `setProgressHandler` 回调给 `(text, start, end, word)`，没有时间戳；
`start/end` 相对传给 `speak()` 的文本。安卓 < 26 只在开口时回一条「整句」区间，
拿它当第一个词会让第一个词亮一整句 —— `spokenWordIndex` 对整句区间返回 null。
fake 测试里用 `Completer` 把 `speak()` 挂住，才拿得到「朗读中」的状态。

**8. 6.5MB 的 Tatoeba 例句表不要整表进内存。**
`lib/data/tatoeba_loader.dart` 读 asset 后交给后台 isolate，`examplesForWords` 只抽
生词本里需要的词（几百条），整表对象随即丢掉。测试用 `background: false` 直接在主
isolate 解析，别在 `testWidgets` 的 fake async 里起 isolate。asset 路径
`assets/tatoeba/tatoeba-en.tsv` 必须留在 `pubspec.yaml`，否则「补离线例句」会静默降级。

**9. 9MB 离线词典要在后台 isolate 解析。**
`loadDictionary()` 默认走 `compute`（主 isolate 解析会让首帧冻几秒）；
测试注入 `loader` 时走主 isolate，保证 `dictionary_loader_test` 不依赖 isolate。
`main()` 启动后立刻预热，阅读页的词典兜底与「一键处理」共用同一个 Future；
不要在 ViewModel 里再写一套加载逻辑。

**10. 「一键处理」写库冲突要重放变换，不是重试写旧结果。**
`DictToolsService._mutate` 读最新库 → 变换 → `save(baseUpdatedAt: ...)`；
`VocabConflict` 时**重读并重跑同一个 transform**（最多 3 次）。拿冲突前的库对象
再 save 会覆盖别人刚写的内容。`runAll` 里某一步失败不阻断后面步骤（Web 同口径）。

**11. 文章级题判分不要写进错题本 / SRS。**
文章题的 `itemId` 是句子 / 段落 id，不是词条 id。`DrillPrep.record` 用
`isArticleQuestion(q)`（`source == 'article' || kind.isArticle`）挡住这两条写路径；
只看 `source` 会漏掉 `source == null` 但 kind 是文章级的题。活动分类走
`quizActivityCat`，不要在两处各写一份 `if`。

**12. 整卷考试交卷只记一次成绩。**
`QuizViewModel._finish` 用 `_recorded` 守卫；`retryWrong()` **不能**清它，
否则做完错题会再写一条 `practice`。`restart()` 才清。写 `practice` 是
「`learning.load()` → `addPracticeRecord` → `writeSection(practice)`」，
`writeSection` 是清表重插，不能只传一条新记录。

## 四、门禁怎么跑

```bash
flutter analyze                                          # 期望 No issues found!
dart run tool/check_god_class.dart                       # 期望 ✅ 上帝类体检通过
dart run tool/check_layers.dart                          # 期望 ✅ 分层门禁通过
dart run tool/check_core_tests.dart                      # 期望 ✅ core 测试覆盖门禁通过
flutter test                                             # 期望 All tests passed!
```

四条全绿再 commit。`flutter test` 里出现 `+N -M` 的 `-M` 就是失败数，不是跳过数；
`+N ~M` 的 `~M` 才是跳过数（真网络 e2e 默认就是跳过）。

## 五、真网络 e2e（默认跳过，手动开）

离线用例里 `AiClient` 的请求体 / header / 超时 / 错误分相都只在 `MockClient` 上验过，
**从没真发过一个请求**。`test/e2e/ai_batch_e2e_test.dart` 补的就是这一段：真调
`api.deepseek.com` → `parseAnalysis` → `applyWordAnalysis` → 写进 SQLite，验完再读回来。

```powershell
# 默认行为（CI / 日常全量）：没有 key 就 skip，不联网
flutter test

# 手动跑一次真网络
$env:DLAOSHI_E2E_KEY = '<你的 key>'
flutter test test/e2e -j 1
Remove-Item Env:DLAOSHI_E2E_KEY
```

- **key 只从环境变量读**，不写任何文件、不进仓库。
- 可选：`DLAOSHI_E2E_BASE_URL`（默认 `https://api.deepseek.com`）、
  `DLAOSHI_E2E_MODEL`（默认 `deepseek-chat`）。换中转站时改这两个。
- 断言的是「每个词的释义 / 音标非空 + `status == queried` + 来源标记是 `ai`」，
  不比对具体中文译文 —— 模型每次措辞会变，钉死译文等于给自己埋 flaky。
- 真跑一次约 4–10 秒（5 个词一块），走 5 词不是 30 词，省额度。

2026-11-10 实测记录（DeepSeek 官方 `deepseek-chat`）：
- 30 词一块 → 9.8s 回 5,513 字符，30/30 全部解析正确，`max_tokens: 4096` 够用；
- 错误分相全对：坏 key → `unauthorized`（HTTP 401 文案）、空 key → 立刻
  `还没填 API key` 不发请求、不存在的模型 → `badResponse`（HTTP 400）、
  域名不通 → `network`（`Failed host lookup`）、`ftp://` → `badResponse`（客户端守卫）。

## 六、集成测试（真机 / 模拟器，默认不跑）

`integration_test/` 放「跨页面 + 真数据库闭环」和「只有真机才量得准的东西」。
**它不在 `flutter test` 里**（那样需要设备，会拖垮日常全量），要显式指设备：

```powershell
flutter emulators --launch Pixel_4_B          # 或插真机
adb devices                                   # 等到出现 emulator-5554  device
flutter test integration_test/asset_cold_start_test.dart -d emulator-5554
```

**为什么非真机不可**：桌面 `flutter test` 用的是桌面 CPU + 桌面文件系统，
量不出手机上的 asset 读速、单核主频、isolate 启动开销。同一份代码在模拟器上
比桌面慢 2–3 倍是常态，而产品要面对的是前者。

现有用例 `asset_cold_start_test.dart` 量三件事（结论记在 `docs/TODO.md` 第二十二件）：
ECDICT 三份 tsv 读取 + 解析、从 ECDICT 均匀取样 300 个词抽 Tatoeba 例句、
以及 app 真实路径 `loadDictionary()`（后台 isolate）的冷启动。

`ai_network_test.dart` 验 AI 真请求的网络栈（结论记在第二十三件）：
用假 key 真发一次请求，拿 401 就证明 DNS / TLS / 代理 / 出网全通。
真 key 那段走 `--dart-define`：

```powershell
flutter test integration_test/ai_network_test.dart -d emulator-5554 `
  --dart-define=DLAOSHI_E2E_KEY=sk-xxxx
```

**踩坑**：
- 断言只写「下限」（表非空、`loadDictionary()` 返回 true），毫秒数用
  `print('[bench] ...')` 打日志，**别把具体毫秒写成断言** —— 模拟器 / 真机 / 负载
  不同就飘，那种断言只会变成下一轮的 flaky。
- 用例体内要读 `rootBundle` 时套 `await tester.runAsync(() async { ... })`，
  否则假时钟不会推进真实 IO，测试直接超时。
- `flutter emulators --launch ...` 即使成功也可能报 `exit code: 1`（Flutter 把
  「assets downloaded from ...」打到 stderr，pwsh 当错误）。以 `adb devices` 为准。
- release APK 只打 arm64（见 `docs/BUILD.md`），**装不进 x86_64 模拟器**；
  模拟器上跑集成测试走的是 debug 构建，不受这条影响。
- **集成测试跑在设备上，宿主机的环境变量传不进去**。要往用例里递参数用
  `--dart-define` + `String.fromEnvironment`。`test/e2e` 那套读
  `Platform.environment` 的写法只适用于桌面 `flutter test`，别互相抄。
- `testWidgets` 的 `skip` 只收 `bool?`，**不像 `test()` 能塞一句「为什么跳过」**。
  想留理由就写进用例描述或 `print` 里。
- **`flutter test -d <真机>` 会先卸旧版、跑完再卸一遍，App 数据（含导入的词库）一起没**。
  2026-11-15 因此清掉了用户手机上一份真词库。上真机前先让用户导出备份，
  或者改用 `flutter run` / `adb install -r` 手动装。

## 七、release 包也得验（R8 会裁掉「只有 JNI 在用」的类）

**集成测试永远跑 debug 构建**，所以「集成测试全绿」推不出「release 包没问题」。
2026-11-15 踩过一次：离线神经朗读在 debug 上修好、集成测试通过，release 包一按试听就
`SIGABRT`，原因是 R8 把 `ai.onnxruntime.TensorInfo` / `OnnxJavaType` / `OrtSession$Result`
当死代码裁了 —— ONNX Runtime 的 Java 类只被 native 侧 JNI 反查，Java 侧没有静态引用。
（详见 `docs/TODO.md` 第二十五件。）

判断某个改动是不是「release 敏感」：动了插件的 Java/Kotlin 侧、动了 native 库、
或者报错只在 release 包上出 —— 都要按下面这条链路验：

```powershell
cmd /c scripts\build_release.bat                       # 出 build\app\outputs\flutter-apk\app-release.apk
adb -s <真机> install -r build\app\outputs\flutter-apk\app-release.apk
adb -s <真机> logcat -c
adb -s <真机> shell am start -n com.dlaoshi.dlaoshi_app/.MainActivity
# 手点（或用下面「八」的 adb 驱动）走一遍可疑路径，然后：
adb -s <真机> shell pidof com.dlaoshi.dlaoshi_app      # 还有 pid = 没崩
adb -s <真机> logcat -d -b crash -t 40                 # 空 = 没崩过
```

想确认某个类有没有被裁，直接解 APK 比「猜规则」快：

```powershell
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path 'build\app\outputs\flutter-apk\app-release.apk'))
$dex = $zip.Entries | Where-Object { $_.Name -like 'classes*.dex' } | Select-Object -First 1
$ms = New-Object System.IO.MemoryStream; $s = $dex.Open(); $s.CopyTo($ms); $s.Close()
[System.Text.Encoding]::ASCII.GetString($ms.ToArray()).Contains('ai/onnxruntime/TensorInfo')
```

同一份代码打 debug 包跑同样的检查，两次结果对着看就知道是谁被裁了。

GPL 合规也从 release 包里验：`unzip -l build/app/outputs/flutter-apk/app-release.apk`
里要能看到 `assets/flutter_assets/assets/licenses/GPL-3.0.txt` 和
`espeak-ng-NOTICE.txt`；装上后走「设置 → 关于 → 开源许可」，全文能滚到底。
`test/services/third_party_notices_test.dart` 守仓库文件和 `pubspec.yaml` 声明。

## 八、用 adb 直接驱动 App（不想手动点、也写不进集成测试时）

有些路径只有 release 包上才复现（见上一节），而 `integration_test` 只能跑 debug。
这时用 `adb shell input` 手点，配合 `uiautomator dump` 确认当前页面。

**Flutter 的文案在 `content-desc` 里，不在 `text` 里**，且换行是 `&#10;`；
按 `text="..."` 找按钮会一个都找不到：

```powershell
adb -s <真机> shell uiautomator dump /sdcard/ui.xml
adb -s <真机> pull /sdcard/ui.xml build\ui.xml
# 再看 <node content-desc="..." bounds="[x1,y1][x2,y2]" clickable="true">
```

拿到 `bounds` 后取中点 `input tap`。验证「键盘有没有掉」不能只看一眼，
`dumpsys input_method` 的 `mInputShown` 在 Flutter + 第三方输入法上恒定 false，
要看 IME 窗口，且要在点击前后密集采样：

```powershell
adb -s <真机> shell "input tap 288 963; for i in 1 2 3 4 5 6 7 8 9 10 11 12; do dumpsys window windows | grep -c 'u0 InputMethod'; sleep 0.05; done"
```

出现 `0` 就是键盘掉过。截图别用 `adb exec-out screencap -p > x.png`（pwsh 里落地 0 字节），
用 `adb shell screencap -p /sdcard/x.png` + `adb pull`。

## 九、小课堂填空：正文流排版 + 键盘别挡住当前空

`lib/views/golden_fill_view.dart` 把每个空做成 `Text.rich` 里的 `WidgetSpan`（行内
下划线输入框），换行交给段落排版。**不要退回 `Wrap` + 固定宽度 `SizedBox`**：
`Wrap` 按整行宽度测量每个 child，长文本段会独占一行，整句会排成「一列盒子」
（用户 2026-11-15 报的现象）。

两个必须保留的细节：

- controller 按**空**（`cloze.blanks` 的一条）建：按词的细碎轮会去重重复学习点，
  此时两处空位共用一个 controller、打字同步；`FocusNode` / `GlobalKey` 一律按
  **空位**建 —— 一个 `FocusNode` 不能挂两个 `TextField`，一个 `GlobalKey` 不能
  用在两个 `WidgetSpan` 上。两种粒度混用会直接报 duplicate GlobalKey。
- 键盘挡住最下面的空时，`GoldenDrillView` 在 `didChangeMetrics` 里补一次
  `Scrollable.ensureVisible`（已完整可见就不滚）。测试用
  `tester.view.viewInsets = FakeViewPadding(bottom: ...)` 模拟键盘，断言聚焦空的
  `rect.bottom` 在键盘上沿之上；见 `test/views/golden_drill_focus_test.dart`。

填空一律「一个词一个空」：`buildGoldenFillPlan` 不再接受整块（`blankUnit: 'target'`），
缩写（`China's`）在 `golden_drill.dart` 的 `_blankWords` 里并成一个词。

填空全程**不收键盘**（用户 2026-11-15 要求）：

- 判分后不要 `unfocus()`，也不要把输入框改成 `readOnly` / `enabled: false` ——
  Android 上 `readOnly` 会走 `_shouldCreateInputConnection == false`，直接关掉
  输入连接，键盘照样落下（Flutter 源码 `editable_text.dart`）。输入框保持可编辑，
  再打字时由 `GoldenDrillSession.reopenFill()` 撤掉判分。
- 判分提示不再塞在正文末尾，改为动作条下方的 `_FillVerdict` 固定条，键盘挡不到。
- 换轮时 controller 重建，但 `FocusNode` / `GlobalKey` 按空位下标**跨轮保留**
  （`_resizeFocuses` / `_resizeBlankKeys`），旧轮的空把焦点直接交给新轮第一个空，
  键盘连接不重建。测试断言 `tester.testTextInput.isVisible` 在交卷、换轮后仍为
  `true`，见 `test/views/golden_drill_focus_test.dart`。
- 一格填到与答案一致（`isGoldenBlankCorrect`）就**自动跳下一个空**；填错不跳，
  用户仍可自己点（用户 2026-11-16 要求）。跳转由 `GoldenDrillView._focusNextBlank`
  做，`GoldenFillView.onBlankFilled` 只上报「第几个空位填对了」。
- 拼句阶段原文只画**挖空版**（`lib/views/golden_assemble_view.dart`），词块一个一份、
  点过置灰；判错只说「顺序不对」，**不报正确顺序**（报了等于送答案）。

## 十、麒麟 aarch64 开发机：`flutter test` 起不了 sqlite / 连不上 flutter_tester

**① `sqlite3_initialize` 解析失败（GLIBC 2.33）**

现象：DB / Repository / ViewModel / 页面 smoke 一开跑就报

```
SqfliteFfiException ... Couldn't resolve native function 'sqlite3_initialize'
... /lib/aarch64-linux-gnu/libc.so.6: version `GLIBC_2.33' not found
```

原因：`sqlite3` 3.5 的预编译 native asset 要 GLIBC ≥ 2.33，麒麟 aarch64 只有 2.31。
`pubspec.yaml` 已配（**别删**）：

```yaml
hooks:
  user_defines:
    sqlite3:
      source: system
      name_windows: winsqlite3   # 别删，见下
```

改成 dlopen 系统库，依赖系统软链
`/usr/lib/aarch64-linux-gnu/libsqlite3.so -> libsqlite3.so.0`（麒麟自带）。
改过这段之后先 `rm -rf build/native_assets` 再跑，否则还会加载旧的 `.so`。
同机的 `patrol_helper` 也是这么配的（其 AGENTS.md「Kylin FFI 环境」）。

⚠️ **Windows 开发机必须带 `name_windows: winsqlite3`**（2026-11-16 踩）：
`source: system` 全平台生效，Windows 上没有 `sqlite3.dll`，所有 DB / Repository /
ViewModel 测试会报 `Failed to load dynamic library 'sqlite3.dll' ... error code: 126`。
Windows 10+ 自带 `System32\winsqlite3.dll`，用 `name_windows` 指过去即可；
只改 `name_windows` 不影响 Linux（那边仍按 `name` 走 `libsqlite3.so`）。
改完同样要 `rm -rf build/native_assets`。

**② `Invalid WebSocket upgrade request`（本机代理）**

现象：所有测试在 loading 阶段就失败，`Unable to connect to flutter_tester
process: WebSocketException: Invalid WebSocket upgrade request`。
本机 `ALL_PROXY=socks://127.0.0.1:20170/` 会把 flutter_tester 的本地 WebSocket
也代理走。跑测试时临时摘掉代理即可：

```bash
env -u ALL_PROXY -u all_proxy -u HTTP_PROXY -u HTTPS_PROXY \
    -u http_proxy -u https_proxy flutter test
```

## 十一、Kokoro 离线朗读「跑起来了但没声音」：先看 PCM 是不是 NaN

**现象**（2026-11-16，vivo V1981A / Android 12）：设置页点「试听一句」，界面不报错、
进程内存涨到 ~602MB（模型确实加载了），但**完全没有声音**；`AudioTrack` 日志显示
播了十几秒（`stop ... 316200 frames delivered`），即 PCM 全零。

**原因**：用了 `model_q8f16.onnx`（82MiB）。它在这台手机的 ONNX Runtime 1.28
CPU 后端上输出全 NaN：

```
KokoroDbg: tokens=23 outInfo=...FLOAT shape=[1, 316200] samples=316200 peak=0.0 nan=316200
```

`Float.NaN * 32767 .toInt()` 在 Kotlin 里是 0，所以 PCM 全零。换
`model_quantized.onnx`（int8，88MiB）后 `shape=[1,46800] peak=0.5126 nan=0`，正常。

**怎么查**：在 `packages/neural_tts/android/.../onnx/KokoroSession.kt` 的
`synthesize` 里打一行 `Log.i("KokoroDbg", "samples=$peak nan=$nan")`，
`adb logcat -s KokoroDbg`。现在这行改成了硬校验：NaN / 全静音直接抛错，
`PickSpeech` 会退回系统朗读并在设置页提示（不会再静默播静音）。

**别单独拿「集成测试全绿」当结论**：`probe()` 只打印「speak ok / 耗时」，
PCM 是静音也算 ok。模型变体换了，要同时看 `peak`/`nan` 和真机耳朵。

**换模型后老安装不生效**：`installAssetsFromBundle` 原来「文件存在就跳过」，
旧模型留在支持目录里，卸载 App 才换得掉。现在用 `kokoroAssetsRevision` 标记，
版本变了整包重拷 —— 改模型时记得同步改这个常量。

## 十二、预生成朗读缓存：staging 目录先 load 再建

**现象**：`TtsAudioCache.commitArticle` 报
`PathNotFoundException: Rename failed ... staging\saved_1-...`，临时目录明明刚建过。

**原因**：`createStagingDir` 原来先建目录、`commitArticle` 里才 `ensureLoaded()`；
而 `_load()` 会把 `<cache>/staging/` 整个删掉（清理上次 App 被杀留下的半成品），
于是刚建的目录被自己删了。**`createStagingDir` 必须先 `await ensureLoaded()`**。

**测法**：`test/core/tts_audio_cache_test.dart` 守纯规则（key / 估算 / LRU /
坏索引逐条丢弃 / 路径穿越）；`test/services/tts_audio_cache_test.dart` 用
`Directory.systemTemp` 跑真文件（提交 / 命中 / 删除 / 淘汰 / 取消 / 失败清理）；
`test/viewmodels/offline_audio_view_model_test.dart` 跑状态机（非 Kokoro 档拒绝、
取消回 idle、重开文章读回缓存）。不需要起手机。

**原生 TTS 只能在真机验**：Dart 单测覆盖不到 Kokoro 的 PCM / 文件落盘。

**2026-11-16 真机踩坑（vivo V1981A / Android 12）**：

1. 第一版用 `AAC`（`MediaCodec` + `MediaMuxer`）。编码器输出格式的
   `csd-0` 只有 2 字节，logcat 打 `E/Utils: csd0 too small`，然后**一帧都不出**，
   面板永远停在「正在生成 0 / N 句」。
2. 改 ADTS 裸流（`.aac`）后能出帧，但真实文章走缓存时用户反馈「读不准」。
   把缓存文件拉出来用 ffmpeg 解码：`Invalid data` / 帧边界错位（某帧之后
   少/多 1 字节）。
3. 当天退回 **WAV**：`KokoroEngine.synthesizeToFile` 把 `KokoroSession` 的
   24kHz/16bit/单声道 PCM 直接写 RIFF+WAV，不经过 `MediaCodec`。
   代价是一篇 800 词约 15MB、两篇约 30MB；优点是和实时朗读逐字节同源。
4. **2026-11-16 晚查明 2 的根因，不是「AAC 不行」**：旧 `AacEncoder.drain()`
   把编码器吐出的整块输出缓冲当成**一个** AAC 帧，不校验 `info.size` 装不装得进
   ADTS 的 13 位 `frame_length`（≤8191）。编码器合并多个 access unit 时，
   后面那段没有自己的头 → 解码器撞半截同步字。重写编码器（长度越界直接抛、
   剔除 `BUFFER_FLAG_CODEC_CONFIG`、逐帧记账打日志、上采样改线性插值）后
   AAC 又换回来了：**17KB vs 98KB，1/5.8**。
5. 文本侧还有一个独立问题：`phonemize` 不认弯引号 `’`，`Arabia’s` 会变成
   `Arabia` + `’` + `ˈɛs`（把 `'s` 念成「S」）。进入 Kokoro 前必须过
   `core/tts_text.dart` 的 `normalizeTtsText`。预览句是纯 ASCII，所以听不出来；
   文章里所有格很多，Kitten 时代也有同一个问题（只是它的模型本来也不准）。
6. **AAC 编码器还会在真机上随机报 `0x80000000`**（2026-11-17）：预生成朗读
   第 3–4 句或第 9–10 句失败，界面只有
   `PlatformException(TTSError, null, null, null)`。`adb logcat -d` 里是
   `E MediaCodec: ... Codec reported err 0x80000000 ... while in state 6/STARTED`
   → `E KokoroSynth: java.lang.IllegalStateException at MediaCodec.native_dequeueOutputBuffer`
   → `AacEncoder.finish`。修法：AAC 失败重试一次，仍失败就写同名 `.wav`
   并返回真实路径（本次进程后续句子直接 WAV）；Dart 侧按返回路径记索引。
   详见 `docs/TTS-PITFALLS.md` 第四节末尾。
7. **集成测试只看「没抛异常」不够**：要打印字节数并用 `AudioPlayer`
   真播一遍（`onPlayerComplete`）；AAC 那版 `playback ok` 也过了，但音频是坏的。
   两层更硬的校验，都不需要把文件拉出设备（`flutter test` 跑完会卸载 App，
   `/sdcard` 上的产物也就没了）：
   - 设备内：用 `lib/core/tts_audio_adts.dart` 的 `scanAdts(bytes)` 扫帧结构，
     抓「找不到同步字」「采样率漂移」「不是 AAC-LC」「文件被截断」「尾部残留」；
   - 桌面上：把字节以 base64 打进日志，落地后用
     `ffmpeg -v error -i x.aac -f null -`（应退出码 0、stderr 为空）+
     `ffmpeg ... -af volumedetect`（`mean_volume` 不能是 `-inf`，否则是静音）。
   实测一次：`frames=96 rate=48000Hz ch=1 duration=2048ms payload=16385`、
   `mean_volume: -23.6 dB / max_volume: -6.9 dB`。
8. **生成中切后台，60 秒超时不能按墙钟算**（2026-11-17）：进程被系统冻结时
   Dart 定时器和原生线程一起停摆，用户切出去两分钟再回来就收到
   `TimeoutException after 0:01:00`。`TtsAudioService._awakeTimeout` 用
   「定时器两次回调间隔 > 3 秒就跳过」的近似算法只累计醒着的时间；
   `test/services/tts_audio_cache_test.dart` 用 400ms 的短超时守「前台真卡住仍会报错」，
   真机再验「切后台两分钟回来能继续」。
9. **整篇播放不能在线上现合成**（2026-11-17）：Kokoro 在这台手机上约 5–7 秒/句，
   点一下等十几秒才出声，还会跟预生成抢 CPU。所以 `ArticleAudioViewModel` 只认
   `TtsAudioCache` 里的文件（缺文件提示重新生成），播放/高亮/停止用
   `test/viewmodels/article_audio_view_model_test.dart` 的假播放器守；真机验收看
   顶栏 ▶ 能按句念完、点句朗读会先停掉整篇。
10. **语速上限不是全局一个数**（2026-11-17）：`maxTtsRate = 1.5` 只给 Kokoro / Kitten；
    系统档和 Edge 用 `maxTtsRateOf(provider)` 保持 1.0，滑块的 `divisions` 按档算
    （系统 18 格、神经 28 格）。`test/core/tts_provider_test.dart` 钉住
    `1.5 → 2.0`、`1.0 → 1.5`，以及系统档存 1.5 会回默认。
    2026-11-18 真机复核：150% 正常出声，用户确认速度合适、没有明显金属声；
    若以后换设备出现明显失真，把神经档上限降到 1.4（→1.9）。

## 十三、离线 TTS「读错词」：在电脑上复刻整条链路来查（真机 logcat 靠不住）

**症状**：设置页短预览正常，文章句子「有些词特别标准、有些错得离谱」，
像在念外语。改完 IPA 映射之后还剩一部分。

**为什么当时没上机查**：2026-11-16 这台 vivo V1981A 的 `adb logcat -s <tag>` 一直是
0 行（`-b all` / `--pid` / `settings put global log_switch 1/0` 全试过）。
**2026-11-17 查明：不是 logcat 死了，是这台机器把三方 App 的 `Log.i` 过滤掉了** ——
`adb logcat -b all -d` 有 3.5 万行系统日志，我们插的 `Log.i("KokoroSynth", ...)`
一条不剩，而 `Log.e` / `Log.w` 照样能看（AAC 编码器故障就是靠
`E MediaCodec` + `E KokoroSynth` 定位的）。**给真机留的诊断日志请用 `Log.w`/`Log.e`，
或者干脆把结论写进文件 / 界面。** 纯 Dart 链路的复刻方法仍然适用，见下。

**能复刻到哪一步**：`normalizeTtsText`（Dart）→ `phonemize`（Dart，纯 Dart
实现）→ 查 `assets/tts/kokoro/tokenizer.json` 的 vocab（就是
`KokoroSession.encode` 干的事）。这三段是**纯 Dart**，桌面全跑得动。
跑不到的只有最后一段 ONNX 推理（Kotlin + native），但那一段的输入已经全部可见了。

**标准套路**（写个 `tool/tmp_xxx.dart`，`dart run` 直跑，用完删）：

```dart
import 'package:dlaoshi_app/core/tts_text.dart';
import 'package:phonemize/phonemize.dart' as p;

p.initDefaultProcessors();
final ipa = p.phonemize(normalizeTtsText(sentence), language: 'en-us',
                         stripStress: false, format: 'ipa');
// 再从 tokenizer.json 的 model.vocab 取单字符串元，逐字符查表，
// 不在表里的收集起来打印 —— 那些就是会被静默吞掉的字符。
```

**已查出的两类根因**（都属于「文本侧」，与模型无关）：

1. **IPA 字符不在 vocab 里**：`ɝ`(U+025D)、`ɫ`(U+026B)、`ê` → `KokoroSession.encode`
   静默跳过 → `perfect`→`pfɪkt`、`global`→`ɡoʊbə`。修法：`KokoroEngine` 里
   `normalizePhonemes` 映射（`ɝ→ɜɹ`、`ɫ→l`、各种带调拉丁字母→去调）。
2. **阿拉伯数字一个都不在 vocab 里**：`1990s`、`B2B`、`5G`、`3D` 全被吞。
   光靠 `phonemize` 自带的年份规则不够（`\b(1[89]\d{2}|20\d{2})\b` 在 `1990s` 上不成立），
   要在 `normalizeTtsText` 里补：年代加撇号、去千分位逗号、单位缩写展开、
   字母数字交界拆开（**排除序数**）。

**判据**：全语料跑一遍，统计「有字母被丢的句子数 / 丢弃总次数」。
2026-11-16 用备份里的 2,462 句英文做基线：改前 273 个 token / 6,844 次，
改后 **0 / 0**。回归守护放单测里，不必每次跑全语料：

- `test/core/tts_text_test.dart` —— 归一化规则（含序数不能被拆开）。
- `test/services/kokoro_phoneme_test.dart` —— 「音素化产出必须全在 Kokoro vocab 里」，
  另有一条反例证明这条测不是空转。

## 十四、别用 PowerShell 正则改含中文的源文件

`(Get-Content -Raw) -replace '...' | Set-Content -Encoding utf8` 这套写法会把
UTF-8 中文读成 GBK 再写回，源码里的中文全变成乱码（`testWidgets('EdgeSpeech
閭ｄ竴灞傦細...`），`dart analyze` 立刻炸出几十个 error，而且 `-replace` 是正则，
手滑就会顺带改掉不想改的地方（这次还把一个 `import` 弄丢了）。

**规矩**：改 `.dart` / `.md` / `.kt` 一律用编辑工具（`edit`），不要用 shell 的
读-改-写。真要用 PowerShell 批量处理，先 `git status` 确认能回滚，处理完立刻
`git diff` 逐行看有没有乱码。

**回滚姿势**：`git checkout -- <file>`（未 `git add` 的改动会丢，但比留着乱码好），
然后用 `edit` 重做。这次是靠 `git status --porcelain` 发现只有那一个文件被动过，
才干净还原的。

## 十五、学习四选一的「已落库」状态不能等写盘回来

`StudyCardFlow.pickMeaning` 里如果先 `await _vm.learnStep(...)` 再置
`_learnCommitted`，真机上写一次词库要 1–2 秒，用户这期间点「继续」会被当成 hold
路径再判一次 `again` —— 同一个新词 `hard + again` 双写，`repetitions` 被清零、
还白进一次重学。**能同步判定的状态必须在 `await` 之前置位。**

widget 测里「点正确选项 → 立刻点继续」就是守这条的
（`test/views/study_page_test.dart` 的「学习四选一选对：进卡后只给下一词，不重复评分」）。
假时钟下写盘 Future 要 `runAsync` 才走，但界面回调一 `pump` 就会跑，正好复现这个竞态。

## 十六、词库测试要分清「行表」与「payload」两条路（v15）

v15 把事实来源反转到 `vocab_items` / `vocab_extras` 后，`vocab.payload` 只是**导出
缓存**，由 `flushPayload()` 在切后台/结束时追平。写测试时记住三条：

1. **不要用「直接 `UPDATE vocab SET payload = ...`」模拟外部写库**。行表还在，读路径
   优先信行表，你会读到旧内容。要模拟并发写，用另一个 `VocabRepository(db)` 实例
   正常 `save`（见「外部把 updated_at 改了，缓存就失效」那条）。
2. **断言 payload / 快照之前先 `await repo.flushPayload()`**。`save()` 的建库那一次
   会顺手写一份 payload 和第一张快照，之后的评分只写行表 —— 所以「快照攒到 12 张」
   必须循环里 `save` 完再 `flushPayload`。
3. **想测「payload 坏了怎么办」，得先让行表不可信**：`await db.delete('vocab_extras')`
   把标记行 `@rows` 删掉，`readVocabRows` 才会返回 null 退回读 payload。否则行表
   照样读得出来 —— 这本身也是一条该有的用例（「新实例没缓存，但行表在，payload
   坏了照样读得出」）。

另：`test/bench/save_row.dart` 是新路径的分段计时探针（10892 词真备份），改写入
路径前先跑它，别凭感觉优化。

## 十七、`vocab_extras` 单行能超 2MB：桌面 ffi 测不出，真机必炸 CursorWindow

`sentenceTexts` 是**一整段**（按 `articleId\u0000sentenceId` 汇总，拆不开）存在
`vocab_extras` 的一行里，真机词库这一行有 13MB。一次 `SELECT doc` 直接报：

```
DatabaseException(Row too big to fit into CursorWindow requiredPos=2, totalRows=3)
sql 'SELECT key, doc FROM vocab_extras ORDER BY ordinal ASC' args []
```

桌面 `sqflite_common_ffi` 没有 CursorWindow，所以 15 例单测全绿也测不出 —— 2026-11-21
在 vivo V1981A 上第一次撞到（首页点「精读」就弹红条）。

**规矩**：读 `vocab_extras` / `vocab.payload` 这类可能超 2MB 的列，一律先
`SELECT key` 再逐键 `readBigPayload(...)`（`lib/data/db/payload_codec.dart`，按 256KB
分块 `substr`）。别再写 `SELECT key, doc` 这种一次取全文的查询。

**回归用例**在 `test/data/db/vocab_rows_store_test.dart` 的
`group('库级大字段（真机 CursorWindow 上限）')`。写这类用例有个坑：数据必须真的超过
2MB（6000 条 × `'line $i ' * 40`）；3000 条只有 1.25MB，会在桌面 ffi 上「顺利通过」
却什么都没测到 —— 用例里那句 `expect(utf8.encode(jsonEncode(big)).length,
greaterThan(2 * 1024 * 1024))` 就是防这个的。

## 十八、渲染问题（闪块 / 花屏）只能在真机或模拟器上取证，别指望 `flutter test`

2026-11-21 查许可爬行页「屏幕右侧白/黄一闪一闪」踩到的整套方法论，**下次遇到渲染类
bug 直接照这个走**：

1. **桌面 `flutter test` 抓不到现场**。`test` 环境里 `LicenseRegistry` 只有 Flutter
   框架自身条目，`buildLicenseScript` 只产出 7 行开场白、字幕根本不铺屏 ——
   用 `boundary.toImage()` 连续渲染 60 帧，画面里一行字幕都没有。取证必须上设备。
2. **`screencap` 轮询比 `screenrecord` 可靠（真机上）**。vivo V1981A 上
   `screenrecord` 只落 3.7KB（被系统拦）；模拟器上正常，12 秒 5.4MB。
   `adb shell screenrecord --time-limit 12 --bit-rate 8000000 /sdcard/x.mp4` + `adb pull`，
   然后 `ffmpeg -v error -i x.mp4 -vf fps=10 out/v%03d.png` 抽帧。
3. **截图一律 `cmd /c "adb exec-out screencap -p > build\xxx.png"`**。PowerShell 的
   `>` 重定向会把二进制写坏。
4. **配一个量化判据**：当时用一次性 Python 脚本（用后已删）统计右条 `x ≥ 0.80w` 内
   亮度 > 90 的像素数 —— 正常帧 3000–6100、故障帧 13.7–18.5 万，差 30 倍以上。
   人眼看「好像闪了」不可靠，**先有数字再谈修**；判据要把「正常」和「故障」拉开一个
   数量级，否则一堆噪声帧会把你带偏。
5. **区分「与状态有关」还是「与状态无关」**：点暂停后再抓 20 帧照样闪 8 帧 →
   与滚动位置、动画进度都无关，是纯光栅化问题。这一步能省掉一堆瞎改。
6. **A/B 要一次只动一个变量**，且 `static final` 字段改值 **热重载不生效，必须 `R` 热重启**
   （`Set-Content .hmr-trigger 'R' -Encoding ascii -NoNewline`），改完先确认
   `build/hmr.log` 里有 `→ 热重启` / `Restarted application`。
7. **热重载验证通过 ≠ 用户装得到。验收必须重打包。** 2026-11-21 栽过一次：改完用 `r`
   热重载、连拍 70 帧零闪，就下了「修好了」的结论并提交；但 `app-debug.apk` 还是
   13:52 打的旧包，用户 `am force-stop` 重开后跑的是**旧内核**（热重载补丁只活在当前
   isolate 里），看到问题照旧。规矩：**凡是要给用户看的修复，先
   `flutter build apk --debug` + `adb install -r` + `am force-stop` + `am start` 全新
   冷启动，再复验一遍**，并顺手对一下 `(Get-Item build\app\outputs\flutter-apk\app-debug.apk).LastWriteTime`
   晚于最后一次改动。

8. **`filterQuality` 不是修闪块的正道，它是「把问题缩小藏起来」。** 2026-11-21
   又栽一次：给透视 `Transform` 传 `FilterQuality.medium`，闪块确实没了，但 Impeller
   会把整棵子树先光栅化成一张位图再按变换采样，透视下这张位图被画小、往中间缩 ——
   把字幕换成一整块纯红 `Container` 量过：只盖住 y=168..730dp（应该是 0..781），
   上下各留一条星空。用户反复说的「crawl 没有占满整个屏幕」有一半就是它造成的
   （另一半是平面高度拍脑袋写成 2.8 倍屏高，屏幕上沿只对应到内容 1180dp 处，片名
   被直接吞掉）。`RepaintBoundary` 更糟：整块黄白把右边三分之二的文字都盖住。
   → **用「纯色块替换可疑子树」量它到底盖住了哪一块**，是这类问题最快的一刀。

**结论性的一条**：**别用 `Transform` 给一大块子树套 3D 透视。** 传不传 `filterQuality`
都会栽：前者（不传）`RenderTransform.alwaysNeedsCompositing` 为 false，变换被下发到
每条绘制命令，Impeller（这台模拟器是 x86_64 + SwiftShader 软渲染）会把部分 tile 的
变换算错，甩出一大块黄白梯形 —— 就是用户说的「黄色/白色的异形」；后者（传了）把
子树画小，「没占满屏」。正解是**自己算投影、逐行画**（`lib/views/license_crawl_page.dart`
的 `CrawlPainter`）：每行 `canvas.translate(w/2, y)` + `canvas.scale(s)` 之后
`TextPainter.paint`，只有仿射变换，没有 layer、没有透视矩阵，两个毛病一起消失，字形
还按最终尺寸光栅化（比采样那张大位图清楚）。几何全在 `CrawlPlaneGeometry` 里：
`w = √(cosθ/farScale)`、平面高 `P = h·w/cosθ`、`k = (w-1)/(P·sinθ)`，这套参数下
平面上 0..`topDepth` 那段正好铺满一屏，第 0 行贴着屏幕上沿、缩放正好是 `farScale`。

回归用例（`test/views/license_crawl_page_test.dart`）锁的是**结构**不是像素：
「字幕由逐行仿射的 `CrawlPainter` 画，不再套透视 `Transform`」（断言
`CrawlPainter` 的祖先里没有 `Transform`、也没有 `Scrollable`）、「上下拖动改变爬行
深度」、以及 `CrawlPlaneGeometry` 的两条几何不变量（上沿缩放 = `farScale`、下沿 =
`cosθ`）。注意 widget 测试里 `LicenseRegistry` 是空的，凑不满一屏就没有可爬的余地，
用例开头注册了一批 fixture 条目把内容撑长。
