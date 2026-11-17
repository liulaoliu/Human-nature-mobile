package com.localmind.neural_tts.engines

import com.localmind.neural_tts.onnx.KittenSession
import com.localmind.neural_tts.phonemizer.Phonemizer
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder

class KittenEngine : BaseEngine {
    private var session: KittenSession? = null
    private val player = com.localmind.neural_tts.audio.PcmPlayer()
    override fun beginOperation() = player.begin()
    private var phonemizer: Phonemizer = Phonemizer()

    /**
     * `config.json` 里的 `speed_priors`。
     *
     * 官方 `kittentts/onnx_model.py` 的 `_prepare_inputs` 有一段：
     * `if voice in self.speed_priors: speed = speed * self.speed_priors[voice]`，
     * 而我们的 `config.json` 里八个音色全是 **0.8**（`expr-voice-4-m` 是 0.9）。
     * 也就是说官方默认语速是 0.8 而不是 1.0 —— 以前我们直接传 1.0，快了约 25%，
     * 元音被压扁（`sexual` 听成 "sex sell" 就是这个道理）。
     */
    private var speedPriors: Map<String, Float> = emptyMap()

    /**
     * 每块**原文**的最大字符数。
     *
     * 官方 `kittentts/onnx_model.py` 的 `chunk_text(text, max_len=400)` 用的就是
     * 400，而且切的是**原文**（按 `[.!?]+` 切句，超长再按词切），不是音素串。
     * 以前这里是 200 且切的是音素串 —— 音素比英文长 10% 左右，200 音素只有
     * 约 180 个英文字符，一句话常被切成两块，块边界还可能落在词中间。
     */
    private var maxChunkSize: Int = 400

    override fun initialize(args: Map<*, *>) {
        val modelPath = args["modelPath"] as? String ?: throw IllegalArgumentException("modelPath required")
        val voicesPath = args["voicesPath"] as? String ?: throw IllegalArgumentException("voicesPath required")
        val dictPath = args["dictPath"] as? String
        maxChunkSize = (args["maxChunkSize"] as? Int) ?: 400
        speedPriors = readSpeedPriors(args["configPath"] as? String)
        phonemizer = Phonemizer(dictPath)

        if (!File(modelPath).exists()) {
            throw IllegalStateException("Model file not found: $modelPath")
        }
        if (!File(voicesPath).exists()) {
            throw IllegalStateException("voices.npz not found: $voicesPath — please re-download the Kitten engine")
        }

        // voicesPath should point to voices.npz (downloaded alongside the ONNX model)
        session = KittenSession(modelPath, voicesPath, dictPath)
    }

    override fun speak(args: Map<*, *>) {
        val text = args["text"] as? String ?: throw IllegalArgumentException("text required")
        val voiceId = args["voiceId"] as? String ?: "expr-voice-2-f"
        val rate = (args["rate"] as? Double) ?: 1.0
        val pitch = (args["pitch"] as? Double) ?: 1.0
        val volume = (args["volume"] as? Double) ?: 1.0

        val isPhonemized = (args["isPhonemized"] as? Boolean) ?: false
        val prior = speedPriors[voiceId] ?: 1.0f

        // 调用方（Dart 的 `EspeakPhonemizer`）已经按官方口径切好块、算好音素了：
        // 每块带着自己的音素串和「这块**原文**的长度」（选 style 行要用原文长度）。
        // 这种情况下**不要**再切 —— 传进来的 text 本身是音素串，比原文长 10%
        // 左右，再按 400 切就会切在音素词中间。
        val phonemeChunks = readPhonemeChunks(args)
        if (phonemeChunks != null) {
            for (chunk in phonemeChunks) {
                player.checkCancelled()
                if (chunk.phonemes.isBlank()) continue
                val wavBytes = session?.synthesize(chunk.phonemes, voiceId, prior, chunk.refLength)
                    ?: throw IllegalStateException("Session not initialized")
                player.play(extractAudioData(wavBytes), extractSampleRate(wavBytes), rate.toFloat(), pitch.toFloat(), volume.toFloat())
            }
            return
        }

        // 按官方口径：先切**原文**，再逐块音素化。
        //
        // 以前是先 `phonemizer.convert(整段)` 再 `chunked(200)` 切音素串 —— 那样
        // 块边界可能落在一个音素词中间（`compan|ies`），模型拿到的是一段残词，
        // 元音自然就歪了。style 行也必须用**这块原文**的长度，不能用音素串长度。
        val chunks = chunkText(text)
        for (chunk in chunks) {
            player.checkCancelled()
            val phonemized = if (isPhonemized) chunk else phonemizer.convert(chunk)
            if (phonemized.isBlank()) continue
            val wavBytes = session?.synthesize(phonemized, voiceId, prior, chunk.length)
                ?: throw IllegalStateException("Session not initialized")
            player.play(extractAudioData(wavBytes), extractSampleRate(wavBytes), rate.toFloat(), pitch.toFloat(), volume.toFloat())
        }
    }

    private class PhonemeChunk(val phonemes: String, val refLength: Int)

    /** 读 Dart 传来的 `phonemeChunks`（`[{phonemes, refLength}, …]`），没有就返回 null。 */
    private fun readPhonemeChunks(args: Map<*, *>): List<PhonemeChunk>? {
        val raw = args["phonemeChunks"] as? List<*> ?: return null
        if (raw.isEmpty()) return null
        val chunks = raw.mapNotNull { item ->
            val map = item as? Map<*, *> ?: return@mapNotNull null
            val phonemes = map["phonemes"] as? String ?: return@mapNotNull null
            val refLength = (map["refLength"] as? Number)?.toInt() ?: -1
            PhonemeChunk(phonemes, refLength)
        }
        return chunks.ifEmpty { null }
    }


    override fun streamAppend(args: Map<*, *>) = speak(args)
    override fun streamFinalize(args: Map<*, *>) {}
    override fun streamCancel(args: Map<*, *>) = stop()

    /**
     * 合成到文件（WAV 24kHz 单声道）。
     *
     * 之前 Kitten 没有这个方法，所以「预生成朗读缓存」只能用在 Kokoro 上。
     * 顺带它也是排查朗读问题的抓手：把设备上真正合成的音频原样导出，
     * 再和桌面用同样的音素、同样的模型合出来的结果对比，就能判断偏差是
     * 出在音素、模型还是播放链路上。
     */
    override fun synthesizeToFile(
        args: Map<*, *>,
        checkCancelled: () -> Unit,
    ): Map<String, Any?> {
        val text = args["text"] as? String ?: throw IllegalArgumentException("text required")
        val voiceId = args["voiceId"] as? String ?: "expr-voice-2-f"
        val outPath = args["outPath"] as? String
            ?: throw IllegalArgumentException("outPath required")
        val isPhonemized = (args["isPhonemized"] as? Boolean) ?: false

        val chunks = chunkText(text)
        if (chunks.isEmpty()) throw IllegalArgumentException("text is empty")
        val prior = speedPriors[voiceId] ?: 1.0f
        val pcm = java.io.ByteArrayOutputStream()
        var sampleRate = 24000
        val started = android.os.SystemClock.elapsedRealtime()
        for (chunk in chunks) {
            checkCancelled()
            val phonemized = if (isPhonemized) chunk else phonemizer.convert(chunk)
            if (phonemized.isBlank()) continue
            val wav = session?.synthesize(phonemized, voiceId, prior, chunk.length)
                ?: throw IllegalStateException("Session not initialized")
            sampleRate = extractSampleRate(wav)
            val data = extractAudioData(wav)
            pcm.write(data, 0, data.size)
        }
        val bytes = pcm.toByteArray()
        writeWav(outPath, bytes, sampleRate, 1)
        val durationMs = bytes.size * 1000L / (sampleRate * 2)
        android.util.Log.i(
            "KittenSynth",
            "done total=${android.os.SystemClock.elapsedRealtime() - started}ms " +
                "bytes=${bytes.size} durationMs=$durationMs path=$outPath",
        )
        return mapOf(
            "path" to outPath,
            "bytes" to bytes.size,
            "durationMs" to durationMs,
        )
    }

    private fun writeWav(path: String, pcm: ByteArray, sampleRate: Int, channels: Int) {
        val header = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN)
        header.put("RIFF".toByteArray())
        header.putInt(36 + pcm.size)
        header.put("WAVE".toByteArray())
        header.put("fmt ".toByteArray())
        header.putInt(16)
        header.putShort(1)
        header.putShort(channels.toShort())
        header.putInt(sampleRate)
        header.putInt(sampleRate * channels * 2)
        header.putShort((channels * 2).toShort())
        header.putShort(16)
        header.put("data".toByteArray())
        header.putInt(pcm.size)
        java.io.File(path).outputStream().use { out ->
            out.write(header.array())
            out.write(pcm)
        }
    }

    override fun stop() = player.stop()
    override fun release() {
        stop()
        session?.close()
        session = null
    }

    /** 读 `config.json` 里 `speed_priors` 那几个 0.8；读不到就当 1.0（官方也是这个兜底）。 */
    private fun readSpeedPriors(configPath: String?): Map<String, Float> {
        if (configPath == null) return emptyMap()
        val file = File(configPath)
        if (!file.exists()) return emptyMap()
        return try {
            val root = org.json.JSONObject(file.readText())
            val priors = root.optJSONObject("speed_priors") ?: return emptyMap()
            buildMap {
                for (key in priors.keys()) put(key, priors.optDouble(key, 1.0).toFloat())
            }
        } catch (e: Exception) {
            android.util.Log.w("KittenEngine", "读 speed_priors 失败：$e")
            emptyMap()
        }
    }

    /**
     * 切**原文**，不是切音素串。
     *
     * 对齐官方 `chunk_text(text, max_len=400)`：按 `[.!?]+` 切句，句子本身超长
     * 就按词切；每块末尾保证有标点（官方 `ensure_punctuation` 补逗号），因为
     * 没有标点收尾的句子模型容易拖音。
     */
    private fun chunkText(text: String): List<String> {
        val sentences = text.split(Regex("[.!?]+"))
        val chunks = mutableListOf<String>()

        for (raw in sentences) {
            val sentence = raw.trim()
            if (sentence.isEmpty()) continue
            if (sentence.length <= maxChunkSize) {
                chunks.add(ensurePunctuation(sentence))
                continue
            }
            var current = StringBuilder()
            for (word in sentence.split(Regex("\\s+"))) {
                if (current.isEmpty()) {
                    current.append(word)
                } else if (current.length + 1 + word.length <= maxChunkSize) {
                    current.append(' ').append(word)
                } else {
                    chunks.add(ensurePunctuation(current.toString()))
                    current = StringBuilder(word)
                }
            }
            if (current.isNotEmpty()) chunks.add(ensurePunctuation(current.toString()))
        }
        return chunks
    }

    /** 官方 `ensure_punctuation`：结尾不是 `. ! ? , ; :` 就补一个逗号。 */
    private fun ensurePunctuation(text: String): String {
        val s = text.trim()
        if (s.isEmpty()) return s
        val last = s.last()
        return if (last in ".!?,;:") s else "$s,"
    }

    private fun extractSampleRate(wavBytes: ByteArray): Int {
        val buffer = ByteBuffer.wrap(wavBytes)
        buffer.order(ByteOrder.LITTLE_ENDIAN)
        buffer.position(24)
        return buffer.getInt()
    }

    private fun extractAudioData(wavBytes: ByteArray): ByteArray {
        val buffer = ByteBuffer.wrap(wavBytes)
        buffer.order(ByteOrder.LITTLE_ENDIAN)
        buffer.position(40)
        val dataSize = buffer.getInt()
        return wavBytes.copyOfRange(44, 44 + dataSize)
    }
}
