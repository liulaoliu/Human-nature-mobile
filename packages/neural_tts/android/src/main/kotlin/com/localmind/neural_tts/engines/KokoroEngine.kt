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

    /**
     * AAC 编码器还能不能信。
     *
     * 2026-11-17 真机（vivo V1981A / Android 12）实测：`c2.qti.aac.encoder`
     * 会在随机某一句上报
     * `Codec reported err 0x80000000 ... while in state 6/STARTED`，
     * 随后 `dequeueOutputBuffer` 抛 `IllegalStateException`（message 为 null）。
     * 一旦它坏掉就整篇生成作废，用户看到的是
     * `PlatformException(TTSError, null, null, null)`，白等十几句。
     *
     * 所以这里把「压缩」降级成可选：PCM 已经在内存里，AAC 写不出来就写 WAV
     * （体积约 6 倍，但绝对能出文件）。连续失败两次后本次进程不再试 AAC，
     * 免得每一句都先卡在坏编码器上。
     */
    private var aacWorks = true

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

        var actualPath = outPath
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
            // 落盘格式由扩展名决定：`.aac` 优先走 AAC-LC/ADTS（约 1/6 体积），
            // 编码器坏了（见 [aacWorks]）就退回 WAV。两条路都是同一份 PCM，
            // 听感一致；返回的 `path` 是**实际**写出的文件，扩展名可能变了。
            val written = writeBest(actualPath, data)
            actualPath = written.first
            val file = File(actualPath)
            android.util.Log.i(
                "KokoroSynth",
                "done total=${android.os.SystemClock.elapsedRealtime() - started}ms " +
                    "bytes=${file.length()} path=$actualPath",
            )
            return mapOf(
                "path" to actualPath,
                "bytes" to file.length(),
                "durationMs" to written.second,
            )
        } catch (t: Throwable) {
            android.util.Log.e("KokoroSynth", "failed: ${t.javaClass.name}: ${t.message}", t)
            runCatching { File(outPath).delete() }
            if (actualPath != outPath) runCatching { File(actualPath).delete() }
            throw t
        }
    }

    /**
     * 按扩展名选编码器，返回「实际写出的路径 + 时长（毫秒）」。
     *
     * AAC 失败不往上抛：先重试一次（换一个新的编码器实例），还不行就把
     * [aacWorks] 置 false、改写成同目录的 `.wav`。理由见 [aacWorks]。
     */
    private fun writeBest(outPath: String, pcm: ByteArray): Pair<String, Long> {
        if (!aacWorks || !outPath.endsWith(".aac", ignoreCase = true)) {
            return writeRaw(outPath, pcm)
        }
        var last: Throwable? = null
        for (attempt in 1..2) {
            try {
                return outPath to writeAac(outPath, pcm)
            } catch (t: Throwable) {
                last = t
                runCatching { File(outPath).delete() }
                android.util.Log.e(
                    "KokoroSynth",
                    "AAC 编码失败（第 $attempt 次，${t.javaClass.name}: ${t.message}）",
                    t,
                )
            }
        }
        aacWorks = false
        android.util.Log.e(
            "KokoroSynth",
            "AAC 编码器在这个进程里不再使用（最后一次：${last?.javaClass?.name}: ${last?.message}），" +
                "本篇剩余句子改写 WAV",
        )
        return writeRaw(outPath, pcm)
    }

    /** 不经过任何编码器，直接写 WAV；`outPath` 是 `.aac` 时改成同名 `.wav`。 */
    private fun writeRaw(outPath: String, pcm: ByteArray): Pair<String, Long> {
        val file = File(outPath)
        val path = if (outPath.endsWith(".aac", ignoreCase = true)) {
            File(file.parentFile, "${file.nameWithoutExtension}.wav").path
        } else {
            outPath
        }
        writeWav(path, pcm, 24000, 1)
        return path to pcm.size * 1000L / (24000 * 2)
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
     * 把 espeak 教科书 IPA 转成 Kokoro 训练时用的 misaki 字母表。
     *
     * 为什么必须转（2026-11-16 查证）：
     * Kokoro-82M 是在 [misaki](https://github.com/hexgrad/misaki) 的输出上训练的，
     * 它把双元音和塞擦音写成**单个**符号（`ʧ`、`ʤ`、`A`、`I`、`O`、`W`、`Y`），
     * 而且美音输出**没有**长音符 `ː`。espeak（以及 Dart 的 phonemize 包）吐的是
     * 教科书 IPA：`tʃ`、`dʒ`、`eɪ`、`aɪ`、`oʊ`、`ɾ`，还带 `ː`。
     *
     * 关键点：**这些 espeak 写法的符号全部都在 Kokoro 的 vocab 里**，所以
     * tokenizer 一个都不会丢、不会报错 —— 模型只是收到了训练时从没见过的
     * token 组合，于是音频「跑偏」。这就是「字都在、读出来还是怪」的原因，
     * 也是之前只补 `ɝ`/`ɫ` 两条映射没治好的根子。
     *
     * 对照规则来自官方实现（CrispASR #316 的 `phoneme_dialect.h`、skadoosh 的
     * `normalize_ipa`），并且用 16 组「我们的输出 → misaki 实际输出」逐字节样本
     * 校验过（见 test/core/kokoro_dialect_test.dart）。
     *
     * 扫描方式：从左到右**最长优先**，替换结果不再回扫，所以 `tʃ`→`ʧ` 之后
     * 不会又被当成一个 `t` 去匹配别的规则。
     */
    private fun normalizePhonemes(ipa: String): String {
        val out = StringBuilder(ipa.length + 8)
        var i = 0
        while (i < ipa.length) {
            // ɚ 紧跟 ɹ 时整体吃掉，只吐一个 əɹ：espeak 把 "parameters" 写成
            // pɚɹ…，天真的 ɚ→əɹ 会得到 əɹɹ，misaki 从不这么写。
            if (i + 1 < ipa.length && ipa[i] == 'ɚ' && ipa[i + 1] == 'ɹ') {
                out.append("əɹ")
                i += 2
                continue
            }
            val two = if (i + 1 < ipa.length) ipa.substring(i, i + 2) else null
            val pair = when (two) {
                "tʃ" -> "ʧ"
                "dʒ" -> "ʤ"
                "eɪ" -> "A"
                "aɪ" -> "I"
                "oʊ" -> "O"
                "əʊ" -> "O"
                "aʊ" -> "W"
                "ɔɪ" -> "Y"
                "ɜː" -> "ɜɹ"
                else -> null
            }
            if (pair != null) {
                out.append(pair)
                i += 2
                continue
            }
            when (val ch = ipa[i]) {
                'ː' -> Unit // 美音没有长音符；留着会让模型读成 RP
                'ɝ' -> out.append("ɜɹ")
                'ɚ' -> out.append("əɹ")
                'ɾ' -> out.append('T')
                'r' -> out.append('ɹ')
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
            i += 1
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
