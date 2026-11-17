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

### Kitten 是反过来的：它的音素必须来自 **espeak-ng 本体**

Kitten 的 vocab 是 espeak 拼法（178 个符号，含 `ɝ` `ɫ`），喂 misaki 字母表会更糟。
遇到「Kokoro 修好了、Kitten 还错」时不要顺手把同一套转换套过去。

**这一节走过了三次弯路，按时间记下来，免得再走一遍。**

#### 弯路一：Dart `package:phonemize`（规则 G2P）

我们最初给 Kitten 传 `phonemize: true`，让 Dart 的 `package:phonemize` 算音素，
把 `KittenEngine` 自带的「查 `assets/tts/en-us.bin`」那条路整个绕过去了。
对正文高频 2000 词、基准取真 espeak（`EspeakBackend(language="en-us",
preserve_punctuation=True, with_stress=True)`）实测：

| 管线 | 逐字节一致 |
|---|---|
| Dart `phonemize`（规则 G2P） | **2.4%** |
| `assets/tts/en-us.bin`（12.4 万词 EPD1） | **97.4%** |
| Kotlin 整条路径（commonWords + 词典 + 六级瀑布） | **92.6%** |

差异不是个别词，是规律性的：`some sˌʌm / ˈsəm`、`people pˈiːpəl / ˈpipəɫ`、
`about ɐbˈaʊt / əˈbaʊt`、`were wɜː / ˈwɝ`、`all ˈɔːl / ˈɔɫ`、`when wˌɛn / ˈhwɛn`
—— 重音位置、`ɝ`/`ɫ`、`hw` 全不一样。听感就是「每个词都听得出，但重音乱」。

#### 弯路二：改用 Kotlin 自带词典（`phonemize: false`）

**但词表级基准会骗人。** 12.4 万词的 EPD1 词典单个词确实对，可它是**词级**的，
真 espeak 是**句子级**的。拿 5 句 57 个词逐词比（`build/stress_cmp.py`）：

```
逐词完全相同           21/57 = 36.8%
忽略重音符后一致       34/57 = 59.6%
```

差的正好是只有句子级才做得到的两件事：

1. **功能词被塞主重音** —— 词典给 `ðˈɛɹ` / `ˈɔn` / `ˈʌv` / `ˈɪt` / `ʃˈiː`，
   真 espeak 在句子里弱化成 `ðɛɹ` / `ɔn` / `ʌv` / `ɪt` / `ʃiː`；
2. **没有连读** —— `in the` 我们是 `ɪn ðə`，espeak 是 `ɪnðə`；`on the` 同理。

这就是用户说的「**每个词都对，整句调子不对**」—— 也就是「全面的偏差，不是某些
特殊字母、音节的问题」。**别指望词级词典 + 自己写在句子层补齐，那条路等于把
espeak 的 `translate.c` 重写一遍。**

#### 弯路三（也是正解）：直接用 espeak-ng 本体

`espeak` 包的 native assets **早就把 espeak-ng 的 C 库编进 APK 了**
（`lib/arm64-v8a/libespeak_native.so`，534,248 字节），插件的 `Phonemizer` 里也有
现成的 `EspeakPhonemizer`，只是缺数据、没人用。**别再手写 G2P。**

只差英文数据。官方 `espeak-ng-data` 全量 18,373,365 字节，**只要 9 个文件
849,283 字节**（逐文件二分验过：输出与全量数据**逐字节一致**）：

| 文件 | 字节 | 缺了会怎样 |
|---|---|---|
| `en_dict` | 168,204 | 没有英文词典 |
| `phondata` | 554,740 | 音素数据，`espeak_Initialize` 返回 -1 |
| `phontab` | 58,652 | 同上 |
| `phonindex` | 43,316 | 同上 |
| `intonations` | 2,312 | 韵律变平 |
| `phondata-manifest` | 21,866 | 版本校验 |
| `lang/{eu,ko,qu}` | 54/51/88 | 报 `language "en-us" is not supported` |

`voices/` **不需要**。`lang/` 三个空壳文件看着没用，缺了就直接起不来。

数据放 `assets/tts/espeak/`，运行时拷到 `<支持目录>/tts/espeak/`，然后
`Espeak.init(那个目录)` —— **`dataPath` 是「里面直接放 `en_dict` 的目录本身」**，
不是它的父目录（`speech.c` 的 `check_data_path` 先试 `<path>/espeak-ng-data`
再当目录用，而 `synthdata.c` 直接 `sprintf("%s/%s", path_home, "phontab")`）。

#### 仍要保留 Dart 侧的 `prepareText`

即使换成真 espeak，它读**未归一化的原文**也会错：

```
In the 1990s the price rose 30,000 megawatts.
  → ɪnðə nˈaɪntiːnhˈʌndɹɪd nˈaɪnti z ðə pɹˈaɪs ...   ← "nineteen hundred ninety z"
喂 "nineteen ninety's ... thirty thousand ..."
  → ɪnðə nˈaɪntiːn nˈaɪntiz ðə pɹˈaɪs ...            ← 正确
```

所以 `normalizeTtsText` + `expandTtsNumbers` 与「用哪套音素器」无关，必须留着。
（`1st`/`2nd`/`3rd` espeak 自己能读对；`%` 读 `pɚsˈɛnt`；弯引号 `’` 它也认。）

#### 顺序要照官方 `onnx_model.py` 的 `generate`

1. `chunk_text(原文, max_len=400)` —— 切**原文**，不是切音素串；
2. 每块 `phonemizer.phonemize` —— 真 espeak，句子级；
3. 每块 `ref_id = min(len(该块原文), 399)` —— style 行按**原文**长度取。

我们在 `lib/services/kitten_speech.dart` 的 `phonemeChunksFor()` 里做完这三步，
把 `[{phonemes, refLength}]` 作为 `phonemeChunks` 交给引擎，Kotlin 只做 ONNX
推理与播放（`lib/core/tts_chunk.dart` 与官方 `chunk_text` 逐行对齐）。

#### 两个环境坑

- **桌面跑不了 `EspeakPhonemizer`**：`espeak` 包的 `hook/build.dart` 里有一段
  `[local patch]`，对 Windows 目标直接 `return`（espeak-ng 的 C 源在 MSVC 上编
  不过），所以 `flutter test` 里 `Espeak.init` 一定失败 —— 单测要用
  `PassthroughPhonemizer` 测「切块 → 逐块音素化」的编排，真 espeak 留给真机。
- **git 的 CRLF 会把这套数据改坏**：本机 `core.autocrlf = true`，不标记的话
  全新 clone 出来的 `phondata-manifest` 与 `lang/*` 与源文件 SHA256 不一致，
  然后 `espeak_Initialize` 静默失败（表现是「点试听没声音」，不是报错）。
  `.gitattributes` 里必须写 `assets/tts/espeak/** -text`（同类还有
  `assets/ecdict/*.tsv`、`assets/tatoeba/*.tsv`、`assets/data/*.json`）。


### Kitten 的 tokenizer 词汇表必须逐字符照抄官方

Kitten 的 token 表是**硬编码在 `Tokenizer.kt` 里的一张字符串**，抄错一位，
后面全部错位，而**不报错、不丢字符**，只在听感上表现为「辅音对、元音怪」。
2026-11-17 就是这么栽的：表里用中文弯引号 `“”`(U+201C/201D) 顶替了直引号
`"` 与撇号 `'`，又把 `\u0329` 写成了 `\u0301`，于是 `"` 的 id 从 15 变 11、
`ᵻ` 从 177 变 176 —— `companies` 的 `ʌ`、`introverts` 的 `ə`、
`discriminating` 的 `ᵻ` 全被喂成训练分布外的 id。

三个必须记住的点：

1. **表长 178，不是 177。** 有重复字符（`"` 出现 3 次、`'` 出现 2 次）。
2. **重复 key 取最后出现的位置**（Python `{s: i for i, s in enumerate(seq)}`
   是覆盖写）。Kotlin 侧必须 `vocab[char] = idx`，写成 `putIfAbsent` 就错。
3. **别用弯引号、别用 `\u0301`。** 官方是 ASCII `"` `'` 与 `\u0329`。

`test/services/kitten_tokenizer_vocab_test.dart` 把官方表钉死，改常量会立刻红。

### `\w` 在 Kotlin 是 ASCII-only，在 Python 是 Unicode 感知

官方 `basic_english_tokenize` 用 `re.findall(r"\w+|[^\w\s]", ipa)` 切音素串，
Python 的 `\w` 认 Unicode，**整个 IPA 词是一个 token**。Kotlin/Java 默认只认
`[a-zA-Z0-9_]`，同一句会被切成**每个音素一个 token**，中间全被插入空格
（id 16）：一句 28 个 id 变成 47 个，其中 20 个是空格。

这就是「辅音听得清、元音全歪」的典型机制 —— 模型看到的序列密度完全不对。
Kotlin 侧必须写 `Regex("[\\p{L}\\p{N}_]+|[^\\s]")`。

### 切块要切**原文**，语速要乘 `speed_priors`，style 行用原文长度

三条都是「模型输入跟训练分布不一样」，听感全是元音压扁：

| 项 | 我们的旧做法 | 官方做法 |
|---|---|---|
| 切块 | 先音素化，再 `chunked(200)` 硬切音素串 | 切原文，`[.!?]+` 分句 + 按词拼，`max_len=400`，每块补标点 |
| 语速 | 传 `1.0` | `speed *= speed_priors[voice]`，八个音色全是 **0.8** |
| style 行 | `min(音素串长度, 399)` | `min(原文长度, 399)` |

- 硬切音素串会把词切断（`compan|ies`），200 音素只对应约 180 个英文字符。
- 传 1.0 等于比训练分布**快 25%**：同一段 `companies`，`speed=1.0` 出 16200
  采样、`0.8` 出 19800 —— 元音被时间压缩，`sexual` 就听着像 "sex sell"。
- 音素串比原文长约 9%，取 style 行会系统性偏后十来行（音色与时长度都变）。

**判据约束**：这个 ONNX 图里有 `RandomUniformLike` / `RandomNormalLike`，
同一输入连跑两次波形差 0.14。所以验改动只能比 **token id / 采样数 / duration**，
**不能比波形**。

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

### 语速：三层串联，两处相乘（2026-11-17，用户 m10083）

「Kitten 明显偏慢，另外两档还行」—— 单看任何一处代码都正常，因为**同一句话被变速了两次**：

| 层 | 参数 | 作用 |
|---|---|---|
| Dart UI | `TtsViewModel.rate`（0–1 刻度） | 用户看到的百分比 |
| ① ONNX `speed` | Kitten: `speed_priors[voice]`（8 个音色全是 **0.8**）<br>Kokoro: 1.0 | 改变**合成出来的音频本身**（元音会被压扁，不只是变快） |
| ② `AudioTrack` | `PlaybackParams().setSpeed(rate)` | 只改**播放速率**，不改波形 |

默认 0.45 经 `neuralRateOf` 得 **0.95**；Kitten 再乘 0.8 → 净 **0.76**，所以只有它听起来慢。

排查/修改时记住三条：

- **`speed_priors` 来自 `assets/tts/kitten/config.json`**，官方 pip 包也是这么乘的，
  所以 0.8 本身不是 bug —— 不能为了「好快一点」直接把它改成 1.0（那是训练分布外的）。
- **要改听感就改 `defaultTtsRateOf`**：Kitten 的默认值单独设成 0.7（→ 1.2，再 ×0.8 ≈ 0.96），
  与其它档的 0.95 对齐。
- **语速必须按档存**（`tts:rate:<枚举名>`）：四档的刻度本来就不一样，
  共用一个值等于逼用户每换一次档重调一次。跟读页的 `shadowing.ui.speechRate`
  是**另一件事**（跟读自己的节奏），别合并。

将来换模型 / 换音色后 `speed_priors` 一变，这套默认值要重新校一次。

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
- [ ] **动手写 G2P / 音素转换 / 数字展开之前，先在 `pubspec.lock` 与 `build/` 里搜一遍
      「这个能力是不是已经在依赖里了」**（2026-11-17 的教训：手写了整套 espeak 替代品，
      而 espeak-ng 本体早就编进 APK 了，只缺 849KB 数据。见 `docs/BYPASS.md` 第四节）
- [ ] 音素层：与参考 G2P 的逐字节一致率跑一次（别用「没报错」当通过）
- [ ] 音素层：核对**每个引擎要哪套字母表**（Kokoro=misaki、Kitten=espeak-ng 本体），别一套通吃
- [ ] 音素层：**句子级**基准，不是词表级（词级词典与句级 espeak 只有 36.8% 一致）
- [ ] 音素层：输出字符全部落在目标模型的 vocab 里
- [ ] 引擎层：确认没有两层音素化互相覆盖（Kokoro 的 `PassthroughPhonemizer` 还在）
- [ ] 引擎层：Kitten 的 `phonemeChunks` 顺序是「切原文 → 逐块 espeak → refLength 取原文长度」
- [ ] 单元测试：`test/core/kokoro_dialect_test.dart` + `test/services/kokoro_g2p_test.dart`
      + `test/core/tts_chunk_test.dart` + `test/services/kitten_speech_test.dart`
- [ ] 资源层：`.gitattributes` 里 `assets/tts/espeak/** -text` 还在（CRLF 会让 espeak 静默起不来）
- [ ] 资源层：`assets/tts/espeak/lang/` **整棵 141 个文件在不在**（只有 `lang/gmw/en-US` 才能让
      `espeak_SetVoiceByName('en-us')` 成功；`pubspec.yaml` 的 assets 目录声明**不递归**，
      33 个子目录要逐个列，或者用 `AssetManifest.listAssets()` 筛前缀整棵拷）
- [ ] 语速层：画一张「哪个参数进哪一层」的表（ONNX `speed` / `speed_priors` / `PlaybackParams`），
      确认没有两处相乘；改 `speed_priors` 或换音色后要重校 `defaultTtsRateOf`
- [ ] **release 包在真机上点一遍试听**（R8、ABI、native assets 只在 release 暴露问题）
- [ ] 听那句 `Reading makes perfect.`，再听一篇长文里的 `companies` / `introverts`

---

## 附：关键文件与常量

| 东西 | 位置 |
|---|---|
| 文本归一化 | `lib/core/tts_text.dart` 的 `normalizeTtsText` |
| 数字展开成英文 | `lib/core/tts_number_words.dart` 的 `expandTtsNumbers` |
| 按官方口径切块 | `lib/core/tts_chunk.dart` 的 `ttsChunkText` |
| espeak→misaki 转换 | `lib/core/kokoro_dialect.dart` 的 `toMisakiAlphabet` |
| Kokoro 的 G2P 主路 | `lib/services/kokoro_g2p.dart` 的 `KokoroG2P` |
| Kitten 的送文本前处理 | `lib/services/kitten_speech.dart` 的 `prepareText` |
| Kitten 的切块+音素化 | `lib/services/kitten_speech.dart` 的 `phonemeChunksFor` |
| Kitten 的音素器 | `EspeakPhonemizer` + `assets/tts/espeak/`（849KB 英文子集） |
| 引擎音素器透传 | `packages/neural_tts/lib/src/phonemizer.dart` 的 `PassthroughPhonemizer` |
| Kotlin 侧音素收尾 | `packages/neural_tts/android/.../engines/KokoroEngine.kt` 的 `normalizePhonemes` |
| R8 规则 | `android/app/proguard-rules.pro` |
| 换行转换豁免 | `.gitattributes`（espeak 数据、tsv、json） |
| Kokoro 模型说明 | `assets/tts/kokoro/README.md` |
| 集成测试 | `integration_test/tts_engine_test.dart` |
| 每档的语速键 / 默认值 | `lib/core/tts_provider.dart` 的 `ttsRateKey` / `defaultTtsRateOf` |
| 语速读写 | `lib/data/tts_prefs.dart` 的 `loadRate` / `saveRate` |
| 语速 UI | `lib/views/tts_settings_page.dart` 的 `_RateSection` |

相关的 TODO 章节：第二十四件（两个朗读 bug + CursorWindow）、第二十五件（R8 闪退）、
第二十六件（换 Kokoro）、**第二十八件（音素改用 misaki 字母表）**、
第二十九件（Kitten 改回引擎自带 espeak 词典）、
**第三十件（Kitten 改用真 espeak-ng，本篇「弯路三」的来源）**、
第三十二件（朗读语速按档分开 + espeak 的 `lang/` 目录）。

「这套东西为什么长这样、哪条能删、用了谁的代码、什么许可」——
见 [`docs/BYPASS.md`](BYPASS.md)（绕行清单与第三方来源）。
