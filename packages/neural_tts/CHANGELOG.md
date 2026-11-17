# Changelog

## 本地改动（本项目 vendored 副本，基于上游 0.4.1）

这个目录是 `neural_tts 0.4.1` 的本地副本，`pubspec.yaml` 里用 `path:` 引用。
唯一目的：修掉上线前实测到的闪退 / 静音。改动只有四处，都是上游的问题。

### 1. `KittenSession.parseNpy2DFloat` 不再用 `InputStream.readNBytes`

上游用了 `readNBytes`，这是 Java 9 的方法，**Android 上 API 33+ 才存在**，
而插件的 `minSdk` 是 24。所以在 Android 10 / 12 上，只要选「离线神经朗读」
点一下「试听一句」，就会在原生线程抛：

```
java.lang.NoSuchMethodError: No virtual method readNBytes(I)[B in class Ljava/io/InputStream;
  at com.localmind.neural_tts.onnx.KittenSession.parseNpy2DFloat(KittenSession.kt:142)
  at ... loadVoiceEmbedding ... synthesize ... KittenEngine.speak ... TtsManager.speak
```

`NoSuchMethodError` 是 `Error` 不是 `Exception`，上游 `NeuralTtsPlugin` 只
`catch (error: Exception)`，于是线程未捕获异常 → `Force finishing activity`
→ 用户看到的是「点试听，App 直接没了」。

改法：新增 `readExactly(stream, count)` 自己循环 `read` 读满，四处
`readNBytes` 全换成它。依赖退回 API 1。

### 2. `NeuralTtsPlugin` 改成 `catch (Throwable)`

上游只兜 `Exception`。原生层任何 `Error`（`NoSuchMethodError`、
`UnsatisfiedLinkError`、`OutOfMemoryError`）都会漏成进程级崩溃，Dart 侧
连一个失败的 Future 都拿不到。改成兜 `Throwable` 后，这类问题至少会作为
一条 `TTS_ERROR` 回到 Dart，能被 `PickSpeech` 的兜底和界面提示接住。

（Kotlin/Android 惯例是 catch Exception，这里刻意偏离：这个通道的职责就是
「把原生故障翻译成 Dart 异常」，把 Error 漏给默认处理器等于放弃这个职责。）

### 3. `KokoroSession.synthesize` 拒绝全 NaN / 全静音的音频（2026-11-16）

真机验收发现 `model_q8f16.onnx` 在 vivo V1981A（Android 12，ONNX Runtime 1.28 CPU）
上输出 `shape=[1,316200]`、全部 NaN —— 转成 PCM 后是十几秒静音，用户以为没跑起来。
这不是插件代码的 bug（换 `model_quantized.onnx` 就好），但插件**不该把静音当成功**：
现在合成完先扫一遍峰值与 NaN，发现无效就抛 `IllegalStateException`，
`PickSpeech` 会退回系统朗读并给用户一句提示。详见 `docs/TESTING.md` 第十一节。

### 4. 新增 `tts.synthesizeToFile`（2026-11-16，预生成朗读用）

上游只能 `speak` 到扬声器，不能把合成结果落文件。App 的「预生成朗读」需要
逐句生成、缓存、离线播放，所以在 vendored 副本上加了这条通道：

- `engines/KokoroEngine.kt`：把 `KokoroSession.synthesize` 的
  24kHz/16bit/单声道 PCM 直接写成 **WAV**（RIFF 头 + PCM），不经手机编码器。
  最初试过 AAC（`MediaCodec` + `MediaMuxer` → ADTS），但 vivo V1981A
  （Android 12）的编码器输出 `csd-0` 只有 2 字节、ADTS 帧边界错位，缓存音频
  会“读不准”；WAV 与实时朗读逐字节同源，优先保证正确。
- `engines/BaseEngine.kt`：`synthesizeToFile` 默认抛
  `UnsupportedOperationException`；`KokoroEngine.kt` 实现（复用
  `KokoroSession.synthesize` 的 PCM，逐 chunk 写 WAV）。
- `TtsManager.kt` / `NeuralTtsPlugin.kt`：新增 `tts.synthesizeToFile`，
  和 `speak` 共用同一个 worker / generation 取消语义；返回
  `{path, bytes, durationMs}`。
- Dart 侧：`Engine.synthesizeToFile`（默认 `UnsupportedError`）、
  `NativeEngine` 的 `performWith` + 实现、`TtsPlatform` / `TtsMethodChannel`。
- Kitten / Supertonic 不实现，调用会得到 unsupported；App 只用 Kokoro。

注意：这个通道会写文件，路径由 Dart 传；失败 / 取消时由 Dart 侧删临时目录，
插件只负责把当前这一句写完。

### 5. AAC 编码器故障时退回 WAV + 错误信息不再为 null（2026-11-17）

真机（vivo V1981A / Android 12）预生成朗读到第 3–4 句或第 9–10 句随机失败：

```
E MediaCodec: ... Codec reported err 0x80000000, actionCode 0, while in state 6/STARTED
E KokoroSynth: failed: null
E KokoroSynth: java.lang.IllegalStateException
    at android.media.MediaCodec.native_dequeueOutputBuffer(Native Method)
    at ...audio.AacEncoder.drain
    at ...audio.AacEncoder.finish
    at ...engines.KokoroEngine.writeAac
```

`dequeueOutputBuffer` 抛的 `IllegalStateException` **没有 message**，原来的
`Reply.finish` 原样透传，Dart 侧只剩
`PlatformException(TTSError, null, null, null)`；整篇生成随之作废。

- `KokoroEngine.synthesizeToFile`：AAC 失败先换新编码器重试一次；仍失败就把
  同一份 PCM 写成同名 `.wav`（PCM 本来就在内存里，不必重新推理），并返回
  **实际路径**；本次进程后续句子不再尝试 AAC。
- `NeuralTtsPlugin.Reply`：错误 message 至少是 `异常类名[: message]`，
  `Log.getStackTraceString(error)` 放进 `details`。
- 这个通道返回的 `path` 可能不是调用方传入的扩展名，Dart 侧必须按返回值记账
  （`KokoroSpeech.synthesizeToFile` / `TtsAudioService` 已改）。

判据：`adb logcat -d | grep KokoroSynth` 能看到
`AAC 编码失败（第 1 次，...）` 后紧跟 `done ... path=...wav`。

## 0.4.1

- Add a distributable `neural-tts-usage` agent skill with guidance for setup,
  model downloads, playback, streaming, phonemization, and LLM output handling.
- Fix queued runtime cancellation, engine ownership, and load-error propagation.
- Await playback completion and make native stop responsive during inference.
- Preserve streaming settings and reject use of closed or competing streams.
- Fix System TTS initialization and close native/Dart ONNX resources on failure.
- Repair resumed downloads, atomic voice downloads, and staged linguistic-data extraction.
- Restore the example manifest, document Android API 24, and add regression tests.

## 0.4.0

- feat: add phonemization support to TTS engines and implement eSpeak-ng data management and extraction
- Update project metadata and license for public release

## 0.3.0

- refactor: update SupertonicSession to use FloatBuffer for ONNX tensor creation and add error handling for TTS pipeline stages

## 0.2.0

- refactor: optimize AudioTrack playback by reusing instances and removing blocking spin-locks in engine classes.

## 0.1.0

- feat: implement KokoroEngine and update platform-specific native plugin code
