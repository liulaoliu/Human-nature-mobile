const ttsPreviewSample =
    "Oh, hello there! I've been waiting for you to test me. I sound pretty good!";

const ttsMinRamBytes = 4 * 1024 * 1024 * 1024;

const ttsParentSubdir = 'tts';
const kittenModelSubdir = 'tts/kitten';
const kokoroModelSubdir = 'tts/kokoro';
const supertonicModelSubdir = 'tts/supertonic';

const ttsDictUrl =
    'https://huggingface.co/datasets/palshub/phonemizer-dicts/resolve/main/en-us.bin';
const espeakDataUrl =
    'https://huggingface.co/datasets/palshub/phonemizer-dicts/resolve/main/espeak-ng-data.zip';

const kittenModelBaseUrl =
    'https://huggingface.co/palshub/kitten-tts-nano-0.8-fp32/resolve/main';

const kokoroModelBaseUrl =
    'https://huggingface.co/onnx-community/Kokoro-82M-v1.0-ONNX/resolve/main';
const kokoroVoicesBaseUrl = '$kokoroModelBaseUrl/voices';

const supertonicModelBaseUrl =
    'https://huggingface.co/Supertone/supertonic-3/resolve/main';
const supertonicVoicesBaseUrl = '$supertonicModelBaseUrl/voice_styles';

// NOTE: palshub/tts-manifests is a private HuggingFace repo (returns 401).
// The Tokenizer already includes a full fallback vocab, so this file is not
// required. The URL is kept here for reference only.
// const voicesManifestUrl = 'https://huggingface.co/palshub/tts-manifests/resolve/main/voices-manifest.json';

const maxChunkSize = 200;

/// Kitten 每块**原文**的最大字符数。
///
/// 官方 `kittentts/onnx_model.py` 的 `chunk_text(text, max_len=400)` 就是 400，
/// 切的也是原文（按 `[.!?]+` 切句，超长再按词切）。Kokoro 那条路还是 200
/// （它切的是音素串，口径不同），所以两者不能共用一个常量。
const kittenMaxChunkSize = 400;
const streamTargetChars = 300;
const supertonicStepsDefault = 20;
const supertonicStepsOptions = [1, 2, 3, 5, 10, 20];

const maxRetries = 3;
const retryDelayMs = 150;
