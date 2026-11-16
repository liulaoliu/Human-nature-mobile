package com.localmind.neural_tts.engines

import com.localmind.neural_tts.onnx.KokoroSession
import com.localmind.neural_tts.phonemizer.Phonemizer
import java.io.File

class KokoroEngine : BaseEngine {
    private var session: KokoroSession? = null
    private val player = com.localmind.neural_tts.audio.PcmPlayer()
    override fun beginOperation() = player.begin()
    private var maxChunkSize: Int = 200
    private var phonemizer: Phonemizer = Phonemizer()

    override fun initialize(args: Map<*, *>) {
        val modelPath = args["modelPath"] as? String ?: throw IllegalArgumentException("modelPath required")
        val tokenizerPath = args["tokenizerPath"] as? String ?: throw IllegalArgumentException("tokenizerPath required")
        val voicesDir = args["voicesDir"] as? String ?: throw IllegalArgumentException("voicesDir required")
        val dictPath = args["dictPath"] as? String
        maxChunkSize = (args["maxChunkSize"] as? Int) ?: 200
        phonemizer = Phonemizer(dictPath)

        if (!File(modelPath).exists()) {
            throw IllegalStateException("Model file not found: $modelPath")
        }

        session = KokoroSession(modelPath, tokenizerPath, voicesDir, dictPath)
    }

    override fun speak(args: Map<*, *>) {
        val text = args["text"] as? String ?: throw IllegalArgumentException("text required")
        val voiceId = args["voiceId"] as? String ?: "af_bella"
        val rate = (args["rate"] as? Double) ?: 1.0
        val pitch = (args["pitch"] as? Double) ?: 1.0
        val volume = (args["volume"] as? Double) ?: 1.0

        val isPhonemized = (args["isPhonemized"] as? Boolean) ?: false
        val raw = if (isPhonemized) text else phonemizer.convert(text)
        val phonemized = normalizePhonemes(raw)
        logPhonemes(raw, phonemized)
        val chunks = chunkText(phonemized)

        for (chunk in chunks) {
            player.checkCancelled()
            val audioBytes = session?.synthesize(chunk, voiceId)
                ?: throw IllegalStateException("Session not initialized")
            player.play(audioBytes, 24000, rate.toFloat(), pitch.toFloat(), volume.toFloat())
        }
    }

    override fun streamAppend(args: Map<*, *>) = speak(args)
    override fun streamFinalize(args: Map<*, *>) {}
    override fun streamCancel(args: Map<*, *>) = stop()

    override fun synthesizeToFile(
        args: Map<*, *>,
        checkCancelled: () -> Unit,
    ): Map<String, Any?> {
        val text = args["text"] as? String ?: throw IllegalArgumentException("text required")
        val voiceId = args["voiceId"] as? String ?: "af_heart"
        val outPath = args["outPath"] as? String
            ?: throw IllegalArgumentException("outPath required")
        val isPhonemized = (args["isPhonemized"] as? Boolean) ?: false
        val raw = if (isPhonemized) text else phonemizer.convert(text)
        val phonemized = normalizePhonemes(raw)
        logPhonemes(raw, phonemized)
        val chunks = chunkText(phonemized)
        if (chunks.isEmpty()) throw IllegalArgumentException("text is empty")

        try {
            val started = android.os.SystemClock.elapsedRealtime()
            val pcm = java.io.ByteArrayOutputStream()
            for (chunk in chunks) {
                checkCancelled()
                val t0 = android.os.SystemClock.elapsedRealtime()
                val bytes = session?.synthesize(chunk, voiceId)
                    ?: throw IllegalStateException("Session not initialized")
                checkCancelled()
                android.util.Log.i(
                    "KokoroSynth",
                    "chunk ${chunk.length} chars synth=${android.os.SystemClock.elapsedRealtime() - t0}ms pcm=${bytes.size}",
                )
                pcm.write(bytes)
            }
            val data = pcm.toByteArray()
            // 落盘格式由扩展名决定：`.aac` 走 AAC-LC/ADTS（约 1/6 体积），
            // 其它一律写 WAV。两条路都是无损可达的原始 PCM 派生，听感一致。
            val durationMs = if (outPath.endsWith(".aac", ignoreCase = true)) {
                writeAac(outPath, data)
            } else {
                writeWav(outPath, data, 24000, 1)
                data.size * 1000L / (24000 * 2)
            }
            val file = File(outPath)
            android.util.Log.i(
                "KokoroSynth",
                "done total=${android.os.SystemClock.elapsedRealtime() - started}ms bytes=${file.length()}",
            )
            return mapOf(
                "path" to outPath,
                "bytes" to file.length(),
                "durationMs" to durationMs,
            )
        } catch (t: Throwable) {
            android.util.Log.e("KokoroSynth", "failed: ${t.message}", t)
            runCatching { File(outPath).delete() }
            throw t
        }
    }

    /**
     * 写 AAC-LC（ADTS）到 [outPath]，返回时长（毫秒）。
     *
     * 24kHz mono 的 PCM 交给编码器时按 2 倍线性插值升到 48kHz ——
     * vivo 的编码器在 24kHz 下不出帧（见 `AacEncoder` 类注释）。
     */
    private fun writeAac(outPath: String, pcm: ByteArray): Long {
        val encoder = com.localmind.neural_tts.audio.AacEncoder(outPath, 48000, 1)
        try {
            encoder.write(pcm)
            val durationUs = encoder.finish()
            android.util.Log.i(
                "KokoroSynth",
                "aac durationMs=${durationUs / 1000} bytes=${File(outPath).length()}",
            )
            return durationUs / 1000
        } finally {
            encoder.close()
        }
    }

    /**
     * 直接写 WAV（16bit PCM 24kHz mono）。
     *
     * 什么时候走这里：调用方给的路径不是 `.aac`（老缓存、调试导出）。
     * 体积是 AAC 的六倍左右，但它是 Kokoro 的原始 PCM，一个字都不改。
     */
    private fun writeWav(
        outPath: String,
        pcm: ByteArray,
        sampleRate: Int,
        channels: Int,
    ) {
        File(outPath).parentFile?.mkdirs()
        val header = java.nio.ByteBuffer.allocate(44)
            .order(java.nio.ByteOrder.LITTLE_ENDIAN)
        header.put("RIFF".toByteArray())
        header.putInt(36 + pcm.size)
        header.put("WAVE".toByteArray())
        header.put("fmt ".toByteArray())
        header.putInt(16)
        header.putShort(1) // PCM
        header.putShort(channels.toShort())
        header.putInt(sampleRate)
        header.putInt(sampleRate * channels * 2)
        header.putShort((channels * 2).toShort())
        header.putShort(16)
        header.put("data".toByteArray())
        header.putInt(pcm.size)
        java.io.FileOutputStream(outPath).use { out ->
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

    /**
     * 打一行 `KokoroPhoneme` 日志：原始 IPA、映射后 IPA、仍不被 vocab 认识的字符。
     *
     * `adb logcat -s KokoroPhoneme` 就能看，不必再靠听感猜是哪个符号漏网。
     */
    private fun logPhonemes(raw: String, mapped: String) {
        val s = session ?: return
        // unsupportedChars 自己会补读 tokenizer，日志可能早于第一次 synthesize。
        val left = s.unsupportedChars(mapped)
        android.util.Log.i(
            "KokoroPhoneme",
            "raw=[$raw] mapped=[$mapped] dropped=${left.joinToString("")} " +
                "codes=[${left.joinToString(",") { "U+%04X".format(it.code) }}]",
        )
    }

    /**
     * Kokoro 的 tokenizer vocab 只有 115 个音素；Dart 的 en-us 音素化器会
     * 产出 `ɝ`（bird/perfect）和 `ɫ`（global/clear），这两个符号不在 vocab，
     * tokenizer 会把它们删掉，词就变成「pfɪkt」「ɡoʊbə」这种怪音。
     * 进 tokenizer 前换成模型认识、听感最接近的符号：
     *   ɝ → ɜɹ（美音 r 化，保留 r；若太卷可改 ɜː）
     *   ɫ → l
     * 其余重音/特殊符号先映射到基础字母，避免整词被吞。
     */
    private fun normalizePhonemes(ipa: String): String {
        val out = StringBuilder(ipa.length)
        for (ch in ipa) {
            when (ch) {
                'ɝ' -> out.append("ɜɹ")
                'ɫ' -> out.append('l')
                'ê', 'é', 'è', 'ë' -> out.append('e')
                'á', 'à', 'â', 'ä', 'ã' -> out.append('a')
                'í', 'ì', 'î', 'ï' -> out.append('i')
                'ó', 'ò', 'ô', 'ö', 'õ' -> out.append('o')
                'ú', 'ù', 'û', 'ü' -> out.append('u')
                'ñ' -> out.append('n')
                'ç' -> out.append('s')
                '’', '‘' -> out.append('\'')
                '-', '–', '—', '[', ']', '【', '】', '（', '）', '|', '#' -> out.append(' ')
                else -> out.append(ch)
            }
        }
        return out.toString().replace(Regex("\\s+"), " ").trim()
    }

    private fun chunkText(text: String): List<String> {
        // 按「词」拼块，不按字符硬切：200 字符正好落在单词中间时，
        // 前一块会把半个词合成一个怪音，后一块再读剩下半个。
        // 用户听到的就是「同一句里有些词很标准，有些错得离谱」。
        val words = mutableListOf<String>()
        for (sentence in splitSentences(text)) {
            for (word in sentence.trim().split(Regex("\\s+"))) {
                if (word.isNotEmpty()) words.add(word)
            }
        }
        val chunks = mutableListOf<String>()
        var current = StringBuilder()
        for (word in words) {
            if (current.isNotEmpty() && current.length + 1 + word.length > maxChunkSize) {
                chunks.add(current.toString())
                current = StringBuilder()
            }
            if (current.isNotEmpty()) current.append(' ')
            current.append(word)
        }
        if (current.isNotEmpty()) chunks.add(current.toString())
        return chunks.flatMap { chunk ->
            if (chunk.length <= maxChunkSize) {
                listOf(chunk)
            } else {
                // 单个超长词（URL / 代码）才硬切。
                chunk.chunked(maxChunkSize.coerceIn(1, 400))
            }
        }
    }

    private fun splitSentences(text: String): List<String> {
        return text.split(Regex("(?<=[.!?])\\s+"))
    }
}
