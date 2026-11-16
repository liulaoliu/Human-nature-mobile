#!/usr/bin/env bash
# 下载 Kokoro-82M 的打包权重（int8 量化，约 88MiB）。仓库里不带它，见
# assets/tts/kokoro/README.md。
#
# 为什么是 model_quantized 而不是更小的 model_q8f16（82MiB）：
# 2026-11-16 真机验收发现 q8f16 在 vivo V1981A / ONNX Runtime 1.28 的 CPU
# 后端上输出全是 NaN（转 PCM 后是十几秒静音）；model_quantized 正常出声。
#
# 用法（仓库根目录）：
#   tool/fetch_kokoro_assets.sh
# 走系统代理（https_proxy 等）时不用额外参数 —— curl 认环境变量。
set -euo pipefail

base='https://huggingface.co/onnx-community/Kokoro-82M-v1.0-ONNX/resolve/main'
root="$(cd "$(dirname "$0")/.." && pwd)"
dir="$root/assets/tts/kokoro"
mkdir -p "$dir/voices"

fetch() {
  local url="$1" out="$2"
  echo "→ $out"
  curl -fL --retry 3 --retry-delay 2 --connect-timeout 30 -o "$out" "$url"
}

fetch "$base/onnx/model_quantized.onnx" "$dir/model.onnx"
fetch "$base/tokenizer.json" "$dir/tokenizer.json"
for v in af_heart af_bella af_nicole am_michael bf_emma bm_george; do
  fetch "$base/voices/$v.bin" "$dir/voices/$v.bin"
done

echo
ls -l "$dir" "$dir/voices"
