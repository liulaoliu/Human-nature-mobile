# 离线 TTS 朗读「不准确」的坑（实战记录）

> 2026-11-16 一次性踩完的坑，写成手册。**后来的人（或以后的我）动朗读功能前先读这篇。**
>
> 一句话总结：**「朗读不准」几乎从来不是模型的问题，是「喂给模型的东西」不对。**
> 而且「跑通了」「不报错」「字符没丢」都不能证明「读对了」——必须有参考输出做对照。

---

## 一、先建立一个心智模型：三层，每层都能错

```
原文文本 ──①文本归一化──▶ 干净的英文 ──②音素化(G2P)──▶ 音素串 ──③声学模型──▶ PCM
            lib/core/tts_text.dart        KokoroG2P / phonemize          ONNX / MediaCodec
```

任何一层出错，听感都是「读错了」，但**修法完全不同**。定位第一步永远是确定错在哪一层。

| 症状 | 大概率是哪层 | 怎么确认 |
|---|---|---|
| 数字丢了、`1990s` 只读出一个 `s` | ① 文本 | 打印归一化后的字符串 |
| 每个词都听得出，但调子飘、像外语 | ② 音素（字母表不对） | 把音素与参考 G2P 输出逐字节比 |
| 某个词固定读错、别的都对 | ② 音素（词典没这个词） | 查该词在词典里命中没有 |
| 整段是静音 / 全 NaN | ③ 声学 | 看输出 PCM 的 peak / NaN 计数 |
| 试听正常、缓存音频不对 | ③ 编码器 | `ffmpeg -v error -i x.aac -f null -` |

---

## 二、①文本层：阿拉伯数字是重灾区

`lib/core/tts_text.dart` 的 `normalizeTtsText`。踩过的具体坑：

- **`1990s` 整段被吞，只剩一个 `s`**。因为 `phonemize` 的年份规则写的是
  `RegExp(r'\b(1[89]\d{2}|20\d{2})\b')` —— `1990` 后面紧贴字母 `s`，`\b` 不成立，
  整条规则跳过，数字进模型前就被 tokenizer 静默丢掉。
  **最小改法是补撇号**（`1990s → 1990's`），让它的年份规则生效，读成
  "nineteen nineties"。自己写数字转英文是重复造轮子。
- **千分位逗号必须去**：`30,000` 会被读成 "thirty, zero"；去掉逗号才是 "thirty thousand"。
- **单位缩写它不认**：`254gw` → `...gw`（读成字母）；`2m` → `ˈtu ˈɛm`（不是 million）。
  必须自己展开成 `gigawatts` / `million` / `kilometres` 这些整词。
- **字母数字粘连处要拆开**：`3D`→`3 D`、`5G`→`5 G`、`B2B`→`B 2 B`、`4x4`→`4 x 4`。
- **⚠️ 拆的时候必须排除序数**：语料里序数 1,200 多处，`1st` 拆成 `1 st` 会读成
  `ˈwən ˈstɹit`（"one street"）、`3rd` → `3 rd` 读成 "three road"。
  正确写法：`RegExp(r'(\d)(?!(?:st|nd|rd|th)\b)([A-Za-z])')`。
- **规则顺序是有意义的**：更具体的规则（`20s → twenties`）必须排在通用的
  （`\d{2,4}s → \d{2,4}'s`）前面。
- 弯引号 `’` `‘` 要换成直引号 `'`，否则 `don't` 会读成 `dɑn ... ti`。

**验收手法**：写个临时探针对全语料跑
`normalizeTtsText → phonemize → 查目标 vocab`，统计「有字母被丢的句子数」。
改前基线是 273 个 token / 6,844 次，改后 2,462 句 → 0。

---

## 三、②音素层：最大的坑 —— **两套字母表**

这是最坑的一层，因为**它不报错**。

### 事实

| | 用的符号 | 长音符 |
|---|---|---|
| **Kokoro**（训练在 [misaki](https://github.com/hexgrad/misaki) 输出上） | `ʧ` `ʤ` `A` `I` `O` `W` `Y` | **没有** `ː` |
| **Kitten**（训练在 espeak 上） | `tʃ` `dʒ` `eɪ` `aɪ` `oʊ` | 有 `ː` |
| `phonemize` 包（espeak 底子）输出 | 教科书 IPA，即上面的 Kitten 那套 | 有 |

**两套符号全都在 Kokoro 的 vocab 里**（我们本地 vocab 115 个单字符）。
所以喂错字母表 → tokenizer 一个字符都不丢、一句错也不报 → 模型只是收到
**训练分布外**的 token → 症状是「每个词都能听出来，但调子飘」。

我们曾经把「语料零丢弃」当成「读对了」写进文档 —— **那是必要条件，不是充分条件。**

### 客观基准（怎么判断一段 G2P 到底行不行）

不要靠耳朵，也不要靠「没报错」。用官方 misaki 生成黄金答案，逐词比：

```powershell
# 一次性环境（spacy 必须 <3.8，否则 thinc 在 py3.9 上没有 wheel）
py -3.9 -m pip install misaki==0.9.4 num2words "spacy<3.8" en_core_web_sm==3.7.1
$env:PYTHONIOENCODING='utf-8'   # 必须，否则 GBK 控制台报 UnicodeEncodeError
```

```python
from misaki import en
g2p = en.G2P(trf=False, british=False, fallback=None)
print(g2p('Reading makes perfect.')[0])   # ɹˈidɪŋ mˌAks pˈɜɹfəkt.
```

实测三条管线（正文高频 3000 词）：

| 管线 | 逐字节一致 | 只差重音 |
|---|---|---|
| `phonemize` + 自己写的字符映射 | **3.3%** | 49.3% |
| `malsami`（misaki 的 Dart 移植） | **84.8%** | — |
| `malsami` + `ɾ→T` | **90.2%** | 0.9% |

→ **别自己写音标转换器。** 现成的 `malsami`（纯 Dart、MIT、只支持英语正好够用）
一条 `ɾ→T` 就到 90%。

### 现状实现

`lib/services/kokoro_g2p.dart` 的 `KokoroG2P` = **malsami 主路 + `phonemize` 兜底**。
`lib/core/kokoro_dialect.dart` 是 espeak→misaki 的转换表，带 16 组
[CrispASR](https://github.com/CrispStrobe/CrispASR/commit/ec96d6691e2b5a01a03cbbcf3bd3f0b1a1f59a5c)
公开黄金样本做测试。

转换里最容易漏的几条：

- `ɜː → ɜɹ`（**必须排在删 `ː` 之前**，否则 `world` 变 `wˈɜld`，少一个 r）
- `ɚ → əɹ`，但 `ɚ` 后面已经跟着 `ɹ` 时要整体吃掉，否则出双 `ɹɹ`
- `ɾ → T`（美音闪音）、`ʔ → t`（喉塞化，`certainly → sˈɜɹʔnli`）
- 扫描方式：**左到右最长优先、单次扫描、替换结果不回扫**

### malsami 的两个坑

1. `Lexicon.initialize()` **写死** `rootBundle.loadString('assets/us_gold.json')`
   （相对 assets 根，不是包内路径）。解决：子类覆盖 `initialize()` 读自己的
   gzip（`assets/lexicons/us_{gold,silver}.json.gz`，6.1MB → 1.43MB）。
   **`lexicon.golds` / `lexicon.silvers` 是 public 可写字段**，所以不用改包。
2. 它按 `RegExp(r'[^\s]+|\s+')` 切词，**标点跟着词走** → `lookup('perfect.')` 查不到，
   掉进兜底。解决：摘掉首尾标点重查一次。

### 兜底逻辑里的致命细节

从 malsami 掉进兜底时，**绝不能「只留字母」**：

```dart
// ❌ 这样 1st → st，读成 street
word.replaceAll(RegExp(r'^[^A-Za-z]+|[^A-Za-z]+$'), '')
// ✅ 只削首尾标点，数字留着
_splitPunct(word).core   // 判据用 \p{L}\p{N}
```

malsami 的 `isNumeric` 认不出带字母的序数/年代（`1st`、`1990's`），
这几类**必定**走兜底 —— 恰好在兜底里把它们削掉，就得到 `1st → street` 这种离谱结果。

### 别忘了还有一层：引擎自己会再算一遍

`packages/neural_tts` 的 `NativeEngine._text()` 在 `isPhonemized == true` 时
**会用 `phonemizer.convert()` 再算一次音素**。我们在 Dart 侧算好音素传进去后，
必须把它换掉，否则被覆盖回 espeak 拼法：

```dart
engine.setPhonemizer(const PassthroughPhonemizer());  // 原样透传
```

`NativeEngine._text()` 是 `play` / `synthesizeToFile` / 流式三条路径的**唯一入口**。

### Kitten 是反过来的：它的音素必须来自 espeak 词典

**Kitten 的 vocab 是 espeak 拼法（177 个单字符，含 `ɝ` `ɫ`），喂 misaki 字母表会更糟。**
遇到「Kokoro 修好了、Kitten 还错」时不要顺手把同一套转换套过去。

更坑的是**反方向**也错：别以为「用一个 G2P 包统一给两档算音素」省事。
我们最初给 Kitten 传 `phonemize: true`，让 Dart 的 `package:phonemize`（规则 G2P）
算音素，把 `KittenEngine` 自带的「查 `assets/tts/en-us.bin`」那条路整个绕过去了。
对正文高频 2000 词、基准取真 espeak（`EspeakBackend(language="en-us",
preserve_punctuation=True, with_stress=True)`）的实测：

| 管线 | 逐字节一致 |
|---|---|
| Dart `phonemize`（规则 G2P） | **2.4%** |
| `assets/tts/en-us.bin`（12.4 万词 EPD1） | **97.4%** |
| Kotlin 整条路径（commonWords + 词典 + 六级瀑布） | **92.6%** |

差异不是个别词，是规律性的：`some sˌʌm / ˈsəm`、`people pˈiːpəl / ˈpipəɫ`、
`about ɐbˈaʊt / əˈbaʊt`、`were wɜː / ˈwɝ`、`all ˈɔːl / ˈɔɫ`、`when wˌɛn / ˈhwɛn`
—— 重音位置、`ɝ`/`ɫ`、`hw` 全不一样。听感就是「每个词都听得出，但重音乱」。

**正确做法**：`phonemize: false`，音素交给引擎自己查词典。

```dart
await engine.play(raw, voice, rate: neuralRateOf(rate), phonemize: false);
```

**配套必须做的一件事：数字要在 Dart 侧先展开成英文单词。**
`Phonemizer.expandDigits` 是**逐位**替换（`.replace("0", " zero ")` …），
`30,000` → `"three zero, zero zero zero"`、`1990's` → `"one nine nine zero's"`、
`1st` → `"one sont"`。用 `lib/core/tts_number_words.dart` 的 `expandTtsNumbers()`
先处理，再交给引擎。

**不要动 Kotlin 的取词顺序。** 词表级看「词典优先」比「commonWords 优先」
多 0.6 个百分点，但句子级正好相反 —— espeak 在句子里会弱化功能词
（`of the → ʌvðə`、`to → tə`、`a → ɐ`、`is → ɪz`），词典优先会给 `the/of/and`
加上重音，反而更不像 espeak。**词表级基准会骗人，句子级才算数。**

---

## 四、③声学 / 模型层

- **同一个模型家族、不同量化版本，行为可能完全不同**：Kokoro 的
  `model_q8f16.onnx`（82MiB）在 vivo V1981A（Android 12 / ONNX Runtime 1.28 CPU）
  上输出 **全 NaN**（`peak=0.0 nan=316200`，听感是十几秒静音）；
  换 `model_quantized.onnx`（int8，88MiB）正常（`peak≈0.51 nan=0`）。
  **体积更小 ≠ 更好，必须真机出声验。**
- 内存是真约束：Kitten ~235MB、Kokoro ~500MB。低端机只有 Kitten 能用。
- 首次朗读要把模型从 assets 拷到 `<应用支持目录>/tts/`（`rootBundle.load` 主
  isolate 读 24–88MB），**首读慢是正常的**；用 `revision.txt` 记版本号，
  换模型后整包重拷。

### 预生成朗读还有第四个编码器：AAC 会随机报 0x80000000（2026-11-17）

现象：Kokoro 档、精读「生成离线朗读」，**第 3–4 句或第 9–10 句随机失败**
（每篇不一样），界面只有一行
`PlatformException(TTSError, null, null, null)`。真机 logcat（E 级还能看）：

```
E MediaCodec: com.dlaoshi.dlaoshi_app Codec reported err 0x80000000, actionCode 0, while in state 6/STARTED
E KokoroSynth: failed: null
E KokoroSynth: java.lang.IllegalStateException
    at android.media.MediaCodec.native_dequeueOutputBuffer(Native Method)
    at ...audio.AacEncoder.drain
    at ...audio.AacEncoder.finish
    at ...engines.KokoroEngine.writeAac
```

不是模型、不是音素，是高通 AAC 编码器（`c2.qti.aac.encoder`）偶发把状态
打成错误；`dequeueOutputBuffer` 抛的 `IllegalStateException` **没有 message**，
插件又原样透传，所以 Dart 侧只剩一个 null。

修法（原则：**压缩器失败不能毁掉已经合成好的 PCM**）：

- `KokoroEngine.synthesizeToFile`：AAC 失败先换个新编码器重试一次；仍失败就
  写同名 `.wav` 并返回**实际路径**，本进程后续句子直接写 WAV
  （否则每一句都要先卡一次坏编码器）。
- Dart 侧 `synthesizeToFile` 返回实际路径；`TtsAudioService` 按返回值记账 ——
  缓存索引本来就是「key → 文件名」，混合扩展名天然支持。
- 插件的错误通道不许再出现 null：`message` 为空时至少给类名，stack trace 放
  `details`。

验收：`adb logcat -d | grep KokoroSynth`，应看到
`AAC 编码失败（第 1 次，java.lang.IllegalStateException）` 之后紧跟
`done ... path=...wav`，界面进度继续往前走、整篇能生成完。

**同一台手机的第二个坑：切后台会把超时算成墙钟**（2026-11-17 晚，用户复现两次）
现象：生成中按 Home 去做别的事，回来界面报
`TimeoutException after 0:01:00.000000: Future not completed`，整篇作废。
根因：Android 把后台进程冻结时，原生合成线程和 Dart 定时器一起停摆；单句的
`Future.timeout(60s)` 按墙钟算，冻结的几分钟照扣。修法：`TtsAudioService`
的 `_awakeTimeout` 每 250ms 检查一次，**两次回调间隔超过 3 秒就当被冻结过、
这一段不计入**；前台真卡死仍会在 60 秒「醒着的时间」后报错（错误里带第几句）。
验收：生成中切出去 1–2 分钟再回来，进度继续走，不报 `Future not completed`。

### 点单词发声会不会攒碎片文件？（2026-11-17）

不会。四条朗读路径的落盘情况：

| 档位 | 点词 / 点句即时朗读 | 落盘 |
|---|---|---|
| 系统 TTS | 交给系统合成器 | 无（系统自己管） |
| Kitten / Kokoro | `engine.play` 在内存里合成 PCM，直接送 `AudioTrack` | **无文件** |
| Edge | 合成到系统临时目录的 `edge_tts_<时间戳>.mp3` | 播完 / 出错 / 停止时 `_cleanupTemp()` 删 |
| 预生成离线音频 | 整篇一次性提交到 `tts_audio/articles/...` | 最多 2 篇，LRU 淘汰；`staging/` 失败 / 取消 / 下次启动都删 |

词库点词、背单词点词都走第一/二/三行的即时朗读，**不会**生成按词缓存的音频，
所以不存在「词越背越多、文件越攒越大」。唯一会长期占空间的是离线整篇缓存，
面板里能看到体积、能删除，第 3 篇会自动挤掉最久没用的一篇。

---

## 五、Android 打包层：debug 绿 ≠ release 绿

- **R8 会裁掉「只有 JNI 在用」的类**。`ai.onnxruntime.TensorInfo` / `OnnxJavaType` /
  `OrtSession$Result` 在 Java 代码里没人直接引用，release 包里被删 →
  JNI `GetMethodID` 拿到 `java_class == null` → `SIGABRT`：
  ```
  Abort message: 'JNI DETECTED ERROR IN APPLICATION: java_class == null
      in call to GetMethodID
      from ... ai.onnxruntime.OrtSession.run(...)'
  ```
  必须自己在 `android/app/proguard-rules.pro` 里 keep（插件都没带
  `consumerProguardFiles`）：`-keep class ai.onnxruntime.** { *; }`。
  **验证手法**：解 APK 的 `classes.dex` 按 ASCII 搜类名，release 与 debug 对比。
- **第三方插件可能用了高 API 的方法**。`neural_tts 0.4.1` 在
  `KittenSession.kt` 用了 Java 9 的 `InputStream.readNBytes(int)`（Android 上要
  **API 33+**），在 Android 12 上抛 `NoSuchMethodError` —— 而它是 `Error` 不是
  `Exception`，插件的 `catch (e: Exception)` **兜不住**，直接整进程被杀（表现为
  「点试听就跳出 App」）。修法：vendor 进 `packages/neural_tts/` 自己改，
  兜底 `catch (Throwable)`。
- **native assets 要联网下载**（`sqlite3` 的 `.so`）：国内直连 GitHub Releases
  会超时，构建报 `build.dart returned with exit code: 255`。走镜像下好、校验
  sha256、放进 `.dart_tool/hooks_runner/shared/sqlite3/build/download-<hash8>/libsqlite3.so`，
  hook 会复用它不再下载。
- **`flutter test -d <真机>` 会先卸载再装、跑完还卸载 → 手机上 App 数据一起没。**
  验真机行为前先想清楚代价。

---

## 六、网络档（Edge）：403 只能显式告知

`flutter_edge_tts` 的 WSS 握手在国内网络被服务端 **403**（`websocket_upgrade_failed`），
六种音色全一样。排查穷尽过：GEC v1 与 v2 令牌都 403、`api.msedge.net` 新域名 DNS
解析不了、设备与宿主时钟零偏差、HTTPS 的 `voices/list` 返 200 —— 是**服务端按来源
拒绝**，升级包修不了。

所以唯一的修法是**别静默兜底**：`PickSpeech` 原来 catch 到异常就 `_fellBack = true`
退回系统朗读，用户听到的永远是系统 TTS，还以为「换音色没用」。
现在会把原因显式显示在试听条下方（`ValueKey('tts-fallback-note')`）。

---

## 七、调试方法：真机 logcat 靠不住时怎么办

- **vivo 真机上 `adb logcat` 恒 0 行**（`-b all`、`--pid`、`settings put global
  log_switch 1/0`、重定向 `/sdcard/log.txt` 全试过）→ 加了日志也看不到。
- 替代方案：**在电脑上用 Dart 探针复刻整条链路**。
  `normalizeTtsText → phonemize → 套映射 → 查 tokenizer.json 的 vocab`，
  纯 Dart，桌面就能跑，几十行。前面的根因全是这么找出来的。
- **听感之外的客观判据**：
  - 音素：与官方 misaki 逐词比（见第三节）
  - 音频文件：`ffmpeg -v error -i x.aac -f null -`（零报错）
    + `ffprobe` 看 codec/duration + `volumedetect` 看不是静音
  - 大 payload 落库：真机跑集成测试写 4MB 再读回来比
- 临时探针一律 `tool/tmp_*.dart` / `test/tmp_*_test.dart`，**用完就删**。

---

## 八、动朗读功能前的验收清单

- [ ] 文本层：全语料跑一遍「有字母被丢的句子数 = 0」，且序数/年代/单位抽查正确
- [ ] 音素层：与参考 G2P 的逐字节一致率跑一次（别用「没报错」当通过）
- [ ] 音素层：核对**每个引擎要哪套字母表**（Kokoro=misaki、Kitten=espeak 词典），别一套通吃
- [ ] 音素层：输出字符全部落在目标模型的 vocab 里
- [ ] 引擎层：确认没有两层音素化互相覆盖（`PassthroughPhonemizer` 还在）
- [ ] 单元测试：`test/core/kokoro_dialect_test.dart` + `test/services/kokoro_g2p_test.dart`
- [ ] **release 包在真机上点一遍试听**（R8、ABI 只在 release 暴露问题）
- [ ] 听那句 `Reading makes perfect.`（我们的回归基准句）

---

## 附：关键文件与常量

| 东西 | 位置 |
|---|---|
| 文本归一化 | `lib/core/tts_text.dart` 的 `normalizeTtsText` |
| 数字展开成英文 | `lib/core/tts_number_words.dart` 的 `expandTtsNumbers` |
| espeak→misaki 转换 | `lib/core/kokoro_dialect.dart` 的 `toMisakiAlphabet` |
| Kokoro 的 G2P 主路 | `lib/services/kokoro_g2p.dart` 的 `KokoroG2P` |
| Kitten 的送文本前处理 | `lib/services/kitten_speech.dart` 的 `prepareText` |
| Kitten 的 espeak 词典 | `assets/tts/en-us.bin`（12.4 万词 EPD1），Kotlin 侧 `Phonemizer` 查它 |
| 词典资源 | `assets/lexicons/us_{gold,silver}.json.gz`（1.43MB） |
| 引擎音素器透传 | `packages/neural_tts/lib/src/phonemizer.dart` 的 `PassthroughPhonemizer` |
| Kotlin 侧音素收尾 | `packages/neural_tts/android/.../engines/KokoroEngine.kt` 的 `normalizePhonemes` |
| R8 规则 | `android/app/proguard-rules.pro` |
| Kokoro 模型说明 | `assets/tts/kokoro/README.md` |
| 集成测试 | `integration_test/tts_engine_test.dart` |

相关的 TODO 章节：第二十四件（两个朗读 bug + CursorWindow）、第二十五件（R8 闪退）、
第二十六件（换 Kokoro）、**第二十八件（音素改用 misaki 字母表，本篇的来源）**、
**第二十九件（Kitten 改回引擎自带 espeak 词典）**。
