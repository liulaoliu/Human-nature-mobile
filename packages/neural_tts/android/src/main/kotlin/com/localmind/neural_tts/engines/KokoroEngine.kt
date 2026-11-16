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
        val phonemized = normalizePhonemes(
            if (isPhonemized) text else phonemizer.convert(text),
        )
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
        val phonemized = normalizePhonemes(
            if (isPhonemized) text else phonemizer.convert(text),
        )
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
            writeWav(outPath, data, 24000, 1)
            val file = File(outPath)
            android.util.Log.i(
                "KokoroSynth",
                "done total=${android.os.SystemClock.elapsedRealtime() - started}ms bytes=${file.length()}",
            )
            val durationMs = data.size * 1000L / (24000 * 2)
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
     * 直接写 WAV（16bit PCM 24kHz mono）。
     *
     * 为什么不走 AAC：vivo V1981A 的 MediaCodec 输出 ADTS 时帧边界错位
     * （ffmpeg 解码报 invalid data），缓存的朗读会“读不准”。预生成宁可
     * 大一点，也不能把错音频存下来；WAV 是 Kokoro 原始 PCM，和实时朗读
     * 完全一致。
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
