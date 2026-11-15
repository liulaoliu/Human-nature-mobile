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


