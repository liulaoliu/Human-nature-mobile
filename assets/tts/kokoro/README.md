# Kokoro-82M 打包资源（模型不进仓库）

`model.onnx` 是 **86,033,585 字节（82MiB）** 的 ONNX 权重，超过 GitHub 建议的
50MB 单文件上限，所以**只在开发机上放一份**，不提交、也不做运行时下载
（用户 2026-11-16 口径：开发机下好即可）。

新机器 / 清过工作区后，在仓库根目录跑一次：

```bash
tool/fetch_kokoro_assets.sh
```

它会把下面这些文件下到本目录（tokenizer 与 voices 已随仓库一起带，脚本是幂等覆盖）：

| 文件 | 大小 | 来源 |
|---|---|---|
| `model.onnx` | 82MiB | `onnx/model_q8f16.onnx` |
| `tokenizer.json` | 3.5KB | 仓库自带 |
| `voices/<id>.bin` × 6 | 各 522KB | 仓库自带（af_heart / af_bella / af_nicole / am_michael / bf_emma / bm_george） |

`en-us.bin` 音素词典在 `assets/tts/en-us.bin`，与 Kitten 共用，别在这里再放一份。

**没有 `model.onnx` 时 `flutter build` / `flutter run` 会报缺 asset** —— 这是预期，
先跑脚本。运行时若文件缺失，`KokoroSpeech.modelsPresent()` 返回 false，
朗读会退回系统档并在设置页提示。
