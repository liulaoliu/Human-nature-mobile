# 绕行记录与第三方代码来源

> 2026-11-17 建这份文档（用户 m09750 要求：「你做了很多 bypass，还用了三方包的程序片段
> （虽然这是完全合理的），这是很高端的行为，注意记入开发文档」）。
>
> 两件事分开记：
> **第一节 —— 我们绕过了什么**（为什么绕、绕在哪、失效了怎么发现、怎么退回）；
> **第二节 —— 我们用了别人的什么**（哪份文件、什么许可、改了什么）。
>
> 为什么值得单独写：这些都是**「不写下来就会被后人当垃圾删掉」的东西**。
> 删掉一个 `.gitattributes`、改回一行 `if exist`、把 `packages/` 换成 `^0.4.1`，
> 本地 `flutter test` 全绿、`flutter build` 也能过，**只有真机 release 包会炸**。
> 反过来，把这条链写清楚，下一个人（或下一个 AI）就不必再从零复现一遍。

---

## 一、绕行清单

判断标准：**正常该做的事我们没做 / 用了非常规手段代替**。每条都带「怎么发现它坏了」。

### 1. `packages/neural_tts/` —— 把第三方插件 vendor 进仓库

| 项 | 内容 |
|---|---|
| 绕了什么 | 不装 `neural_tts: ^0.4.1`，改成复制进 `packages/neural_tts/`，`pubspec.yaml` 用 `path:` 引用 |
| 为什么 | 上游 0.4.1 有两个会让 App 直接消失的 bug，且**没有修复版本**：① `KittenSession` 用了 Java 9 的 `InputStream.readNBytes`（Android 要 API 33+），低版本抛 `NoSuchMethodError`；② 插件只 `catch (Exception)`，而 `NoSuchMethodError` 是 `Error`，漏成进程级崩溃 |
| 改了什么 | 5 处，逐条在 `packages/neural_tts/CHANGELOG.md` 顶部（`readNBytes`→`readExactly`、`catch (Exception)`→`catch (Throwable)`、Kokoro 拒绝全 NaN、新增 `synthesizeToFile`、AAC 失败退回 WAV） |
| 怎么发现坏了 | 离线神经朗读点「试听一句」→ App 直接消失；`adb logcat -b crash` 里有 `NoSuchMethodError` 或 `JNI DETECTED ERROR` |
| 怎么退回 | 删 `packages/neural_tts/`，`pubspec.yaml` 改回 `neural_tts: ^0.4.1`（**但上面五个 bug 会全部回来**） |
| 注意 | 三个门禁脚本（`tool/check_*.dart`）只扫 `lib/`，`packages/` 不受约束 —— 也别在里面写业务逻辑 |

### 2. `android/app/proguard-rules.pro` —— 手写 R8 keep 规则

| 项 | 内容 |
|---|---|
| 绕了什么 | 插件都没带 `consumerProguardFiles`，只能由 App 侧补规则 |
| 为什么 | Flutter 的 release **默认开 R8**（本仓库没写 `isMinifyEnabled`，但会生成 `build/app/outputs/mapping/release/mapping.txt`）。`ai.onnxruntime.TensorInfo` / `OnnxJavaType` / `OrtSession$Result` 只被 native 侧 JNI 反查、Java 里无静态引用 → 被当死代码裁掉 → `java_class == null` → `SIGABRT` |
| 改了什么 | `-keep class ai.onnxruntime.** { *; }`、`-keep class com.localmind.neural_tts.** { *; }`、`-keepattributes` |
| 怎么发现坏了 | release 包点试听崩溃、debug 完全正常；`logcat -b crash` 里 `JNI DETECTED ERROR ... in call to GetMethodID` |
| 怎么验证 | 解 APK 的 `classes*.dex` 按 ASCII 搜类名，release 与 debug 对比（手法见 `docs/TESTING.md` 第七节） |
| 注意 | **新增依赖 native 库的插件时，回头检查这份规则** |

### 3. `.gitattributes` —— 禁止 git 做换行转换

| 项 | 内容 |
|---|---|
| 绕了什么 | 本机 `core.autocrlf = true`，git 会在 checkout 时把 LF 换成 CRLF |
| 为什么 | espeak 的 `phontab` / `phondata` / `phonindex` / `phondata-manifest` / `en_dict` 是自己格式的二进制；tsv 词典里带 `\r` 就永远匹配不上 |
| 怎么发现坏了 | **不报错**：`espeak_Initialize` 返回 -1，表现是「点试听没声音」。实测手法：`git --work-tree=<临时目录> checkout HEAD -- assets` 模拟全新 clone，逐文件比 SHA256 |
| 怎么退回 | 别退回。`.gitattributes` 少了这几行，全新 clone 就会坏 |

### 4. `android/gradle.properties` —— 关掉 Flutter 插件的 ABI 覆盖 + 压短网络超时

| 项 | 内容 |
|---|---|
| 绕了什么 | `disable-abi-filtering=true`；`connectionTimeout=15000` / `socketTimeout=30000` |
| 为什么 | ① 不关的话 Flutter Gradle 插件会把三套 ABI 都塞进来，`ndk.abiFilters` 被无视 —— release 包 138MB，且 `armeabi-v7a` / `x86_64` 目录里只有第三方 so、没有 `libapp.so`，是残缺目录。② 本机到镜像的 TCP 连接会「假活」（连接在、数据不来），`jstack` 里线程停在 `NioSocketImpl.timedRead`，gradle 要等默认 30s~5min 才重试，构建看起来像卡死 |
| 怎么发现坏了 | ① APK 体积暴涨、`unzip -l` 里多出两个 ABI 目录；② 构建卡住不报错不前进 |
| 注意 | 不要设 `org.gradle.java.home`（会破坏 Gradle 的 JDK 检测） |

### 5. `scripts/build_release.bat` —— 构建脚本里的五处绕行

| 绕行 | 为什么 |
|---|---|
| 构建前把 `assets/data/economist-backup-2026-11-10.json`（34.8MB 开发样本）`move` 到 `%TEMP%`，结束再挪回 | `pubspec.yaml` 的 `assets/` 是全局的，那份完整备份 JSON 会被原样打进 release 包 |
| 用 `%TEMP%\dlaoshi_build.stamp`（ISO 字符串）+ APK `LastWriteTime` 判「本轮新鲜产物」 | 旧写法只看 `if exist "%APK%"`，上一轮的包还在时立刻误报 DONE，还会报中间态字节数（2026-11-15 报过 56,901,632 而实际 144,790,699）。**存 Ticks 数字不行** —— `[DateTime]::Parse` 认不出 ISO 以外的格式，会抛「该字符串未被识别为有效的 DateTime」 |
| `Start-Process -NoNewWindow cmd.exe` 后台跑 `flutter build` + 重定向日志 | Gradle 输出被 flutter 吞掉，只能靠产物判断进度 |
| 每 16 秒 `ping -n 16 127.0.0.1` 轮询，打「第 N 次检查」 | 不是 `sleep`，Windows 上 `timeout` 在无 TTY 时会直接返回 |
| 失败时只 `Get-Content -Tail 40` 日志尾巴 | 全量日志几万行，看不完 |

**坑**：别在 PowerShell 里手写引号拼路径 —— `''%APK%''` 这种嵌套引号会被解析成空串，永远判出 `N`，2026-11-15 就因此误报过 FAILED。用环境变量 `$env:APK_FULL` / `$env:STAMP`。

### 6. sqlite3 的 native asset 手工就位

| 项 | 内容 |
|---|---|
| 绕了什么 | 不靠 hook 自动下载，手工把 `.so` 放进缓存目录 |
| 为什么 | `sqlite3-3.5.2` 的 build hook 要从 GitHub Releases 下 `libsqlite3.arm64.android.so`，国内直连超时 → `build.dart returned with exit code: 255` |
| 怎么做 | `Invoke-WebRequest "https://gh-proxy.com/https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-3.5.2/libsqlite3.arm64.android.so"` → 校验 sha256 与 `sqlite3-3.5.2/lib/src/hook/asset_hashes.dart` 里期望值一致（`0c2d3bfc…`）→ 放到 `.dart_tool/hooks_runner/shared/sqlite3/build/download-0c2d3bfc/libsqlite3.so` |
| 为什么能复用 | `PrecompiledBinary.downloadIntoOutputDirectoryShared` 对已存在文件算 sha256 比对，一致就跳过下载 |
| 怎么发现坏了 | arm64 构建报上面那段 `failed to download` |

### 7. 依赖版本锁定

- `flutter_edge_tts: ^0.0.2` —— 0.0.3 引入 `audio_decode → native_toolchain_c ^0.19.2`，
  与 `neural_tts` 带的 `espeak`（要 `^0.17.4`）冲突，pub 解不出来。**且 0.0.3 修的是
  GEC v2 令牌，而我们的 403 是服务端按来源拒绝，升上去也没用**（见 `docs/TTS-PITFALLS.md` 第六节）。
- `espeak: ^0.1.3`、`phonemize: ^1.0.0`、`number_to_words_english: ^3.0.4` 原本都是
  `neural_tts` / `phonemize` 的传递依赖，**运行时要用就必须提成直接依赖**，
  否则 `depend_on_referenced_packages` 会拦。

### 8. 大文件不进仓库

| 文件 | 大小 | 处理 |
|---|---|---|
| `assets/tts/kokoro/model.onnx` | 88MiB | `.gitignore` 排除，新机器跑 `tool/fetch_kokoro_assets.sh` |
| 同上（历史遗留） | 52MB 单文件上限 | 这也是为什么不走 GitHub 直存 |
| 开发用完整备份 JSON | 34.8MB | 留在仓库但构建时挪走（见第 5 条） |

缺 `model.onnx` 时：`flutter build` 直接报缺 asset（预期行为）；运行时缺失则
`modelsPresent()` 为 false、退回系统朗读。

### 9. 最小化第三方数据子集而不是整包

| 场景 | 全量 | 我们放的 | 怎么验的 |
|---|---|---|---|
| espeak-ng 数据（Kitten 用） | 18,373,365 字节 | **849,283 字节**（9 个文件） | 逐文件二分，输出与全量数据**逐字节一致** |
| Kokoro 词典（malsami 用） | 6,100,244 字节（两份 json） | **1,433,111 字节**（gzip） | 解压后逐条比对 |
| Kokoro 模型 | 310.5MB（fp32） | 88.1MB（int8 量化） | 真机出声 + 非静音判据 |

espeak 那 849KB 是**从 pip 包 `espeakng_loader` 里直接拷编译产物**，不走 `espeak` 包的
`bin/compile_data.dart`（那个要先 `curl` GitHub `master.tar.gz` ~56MB 再现场编）。

### 10. 真机取证手段（不走常规路）

| 常规做法 | 为什么不行 | 替代 |
|---|---|---|
| `adb logcat` 看日志 | vivo V1981A 上 `logcat` **恒 0 行**（`-b all`、`--pid`、`log_switch`、重定向全试过） | 桌面上用 Dart 探针复刻整条链路 |
| `uiautomator dump` 按 `text=` 找控件 | Flutter 的文案在 `content-desc` 里，`text` 是空的 | 按 `content-desc` 匹配，`bounds` 取中点再 `input tap` |
| `dumpsys input_method` 看 `mInputShown` | Flutter + 第三方输入法上恒定 false | 密集采样 `dumpsys window windows \| grep -c 'u0 InputMethod'` |
| `flutter test -d <真机>` 验行为 | 会先卸载再装、跑完还卸载 → **手机上的 App 数据一起没** | 能用集成测试的用，其余手动 |
| 比波形判断 TTS 改动 | 这个 ONNX 图里有 `RandomUniformLike` / `RandomNormalLike`，同输入两跑差 0.14 | 只比 **token id / 采样数 / duration** |
| `adb install` 直接装 | vivo 要人在手机上点「继续安装」，否则 `INSTALL_FAILED_ABORTED: User rejected permissions` | 提前跟用户说一声，或 `adb install-multiple` 也没有用 |

---

## 二、第三方代码与数据来源（含许可）

**这一节是给「要发版 / 要做合规」的人看的。** 一句话结论：
**`assets/tts/espeak/` 那 849KB 数据来自 espeak-ng，是 GPL v3，不是 MIT。**
其余都是 MIT / Apache-2.0 / 纯事实性数据。

### 2.1 直接依赖（`pubspec.yaml`）

| 包 | 版本 | 许可 | 我们怎么用 |
|---|---|---|---|
| `neural_tts` | 0.4.1（vendored） | MIT（Copyright (c) Abdul Momin Sakib） | ONNX 引擎 + Dart 侧通道，改了 5 处 |
| `malsami` | 0.0.3 | MIT（Copyright (c) 2025 Seongbin Yoon） | Kokoro 的英语 G2P 主路 |
| `phonemize` | 1.0.0 | MIT（同上作者） | Kokoro 兜底；`tts_number_words.dart` 的来源 |
| `number_to_words_english` | 3.0.4 | MIT | 数字转英文单词 |
| `espeak` | 0.1.3 | **包本身 MIT（gaumoe）**，但它 vendored 的 `native/espeak-ng/src/libespeak-ng/*.c` 是 **GPL v3**（`speech.c` 头部写明 Jonathan Duddington / Reece H. Dunn / GPL v3） | 编译期把 espeak-ng 编成 `libespeak_native.so` 打进 APK；运行时我们只**调它的 `phonemize`** |
| `flutter_edge_tts` | 0.0.2（锁版本） | MIT | Edge 在线档（国内 403，只能显式告知） |

### 2.2 我们搬进来的代码片段

| 文件 | 来源 | 许可 | 改了什么 |
|---|---|---|---|
| `lib/core/tts_number_words.dart` | `phonemize 1.0.0` 的 `lib/src/expand.dart` | MIT | 移植 `expandTtsNumbers`，去掉用不到的 `expandAbbreviations`；不改包本身（那个文件未 export，直接 import 会触发 `implementation_imports`，项目不许用 `// ignore:`） |
| `lib/core/kokoro_dialect.dart` | [CrispASR](https://github.com/CrispStrobe/CrispASR) 的 `src/core/phoneme_dialect.h` | MIT（Copyright (c) 2023-2026 The ggml authors + Silero Team） | 重写为 Dart；规则表照抄 12 条 + 16 组黄金样本做测试（**先抄样本、再写实现**，这是唯一能证明「转换对」的办法） |
| `packages/neural_tts/android/.../KittenSession.kt` 的 `readExactly` | 自写（替代上游的 `readNBytes`） | — | 循环 `read` 读满，`n < 0` 抛 `IllegalStateException` |
| `packages/neural_tts/android/.../phonemizer/Tokenizer.kt` 的 `SYMBOLS` | `kittentts` 官方 `onnx_model.py` 的 `TextCleaner` 常量表 | 该 pip 包 METADATA **没有 License 字段** → 只当「行为规格 / 事实性数据」用，不拷实现代码 | 逐字符照抄 178 项（重复 key 取最后位置）；`test/services/kitten_tokenizer_vocab_test.dart` 钉死 |
| `lib/core/tts_chunk.dart` | `kittentts` 的 `chunk_text()` / `ensure_punctuation()` | 同上 | 按行为重写为 Dart，`test/core/tts_chunk_test.dart` 守恒 |
| `lib/services/kokoro_g2p.dart` 的 `_GzipLexiconG2P` | 覆盖 malsami 的 `Lexicon.initialize()` | MIT | 只改「从哪读词典」，词典逻辑仍是 malsami 的 |
| `packages/neural_tts/android/.../audio/AacEncoder.kt` | 自写（旧版是上游没有的） | — | 三处校验：帧长越界抛错、剔除 `BUFFER_FLAG_CODEC_CONFIG`、逐帧记账 |

### 2.3 我们搬进来的数据

| 数据 | 来源 | 许可 | 处理 |
|---|---|---|---|
| `assets/lexicons/us_gold.json.gz` / `us_silver.json.gz`（1.43MB） | [hexgrad/misaki 0.9.4](https://github.com/hexgrad/misaki) 的 `misaki/data/us_*.json` | **Apache License 2.0** | 压 gzip（6.1MB→1.43MB）；本地运行时不经 Python |
| `assets/tts/espeak/`（849KB） | [espeak-ng](https://github.com/espeak-ng/espeak-ng) 的编译产物（经 pip 包 `espeakng_loader 0.2.4`） | **GPL v3** | 只放英文子集 9 个文件；**这是本仓库唯一的 GPL 内容** |
| `assets/tts/kitten/`（27MB） | [KittenML/KittenTTS](https://github.com/KittenML/KittenTTS) `kitten-tts-nano-0.8-int8` | 模型权重（见上游仓库） | 逐字节核对：`kitten_tts_nano_v0_8.onnx` SHA256 `F7B0AFCB…76FC`、`voices.npz` `8AA7CEE2…9B3F`，与 HF 官方一致 |
| `assets/tts/kokoro/`（88MiB，不进仓库） | [onnx-community/Kokoro-82M-v1.0-ONNX](https://huggingface.co/onnx-community/Kokoro-82M-v1.0-ONNX) 的 `model_quantized.onnx` + 6 个音色 | 模型权重（见上游） | `tool/fetch_kokoro_assets.sh` 下载 |

### 2.4 只用来「生成参考答案」的开发期工具（**不进 APK、不进仓库**）

| 工具 | 用途 | 许可 |
|---|---|---|
| `misaki 0.9.4`（Python）+ `spacy 3.7.5` + `en_core_web_sm 3.7.1` | 生成「官方正确答案」当基准，量化各条管线的一致率 | Apache-2.0（misaki） |
| `kittentts 0.1.3` / `0.8.0`（pip） | 读官方实现理解行为（数字预处理、切块、style 行口径） | METADATA 无 License 字段 → **只读不拷** |
| `onnxruntime 1.19.2` + `numpy` + `onnx` | 桌面对照渲染、算子嗅探（发现 `RandomNormalLike`） | MIT / BSD |
| `espeakng_loader 0.2.4` + `phonemizer 3.4.1` | 桌面跑真 espeak 当基准 | MIT / GPL（同 espeak-ng 本体） |

**发版前该做而还没做的**：在应用「关于」页或随包 `NOTICE` 里附 GPL v3 全文与
espeak-ng 的版权声明。当前 `assets/tts/espeak/` 只有数据、`libespeak_native.so` 是
编译产物，**没有随包带 COPYING**。

---

## 三、如果哪天这些绕行失效了

按这个顺序查（都是从踩过的坑里反推的）：

1. `flutter build` 能过但真机崩 → 先看 `logcat -b crash`：`NoSuchMethodError` / `JNI ... java_class == null`
   → 分别是 API 兼容、R8（第 1、2 条）。
2. 点试听没声音、不报错 → espeak 数据被 CRLF 改坏（第 3 条），或 `dataPath` 传错层级。
3. APK 体积暴涨到 130MB+ → ABI 覆盖没关（第 4 条），或开发样本没挪走（第 5 条）。
4. 构建卡住不前进 → 网络假活（第 4 条），或 native asset 下载超时（第 6 条）。
5. `pub get` 解不出来 → 依赖冲突（第 7 条），别硬试，先看 `flutter pub deps`。
6. 全新 clone 后行为与开发机不同 → 第一个怀疑 `.gitattributes`（第 3 条），
   第二个怀疑「大文件没下载」（第 8 条）。

---

## 四、附：「最搞笑的坑」

用户 m09387 原话：**「我听了，你的和官方的差距也不大啊，但是你有点搞笑，又重复造轮子了。」**

完整故事写在 `docs/TTS-PITFALLS.md` 的「Kitten 是反过来的」一节（三次弯路）。
一句话版：**为了让 Kitten 的读音对，我手写了一套 espeak-ng 的替代品 ——
12.4 万词的 EPD1 词典解析、六级查词瀑布、80 个功能词硬编码、31 条后缀规则、
数字逐位展开 —— 折腾两天，最后发现 espeak-ng 本体早就被 `espeak` 包编成
`libespeak_native.so`（534,248 字节）躺在我们的 APK 里了，插件的
`EspeakPhonemizer` 也早就写好了，只缺 849KB 数据。**

教训写进 `docs/TTS-PITFALLS.md` 的验收清单第二条：**动手写 G2P 之前，
先在 `pubspec.lock` / `build/` 里搜一遍「这个能力是不是已经在依赖里了」。**
