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
        val phonemized = if (isPhonemized) text else phonemizer.convert(text)
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
        val bitRate = (args["bitrate"] as? Int) ?: 64000
        val isPhonemized = (args["isPhonemized"] as? Boolean) ?: false
        val phonemized = if (isPhonemized) text else phonemizer.convert(text)
        val chunks = chunkText(phonemized)
        if (chunks.isEmpty()) throw IllegalArgumentException("text is empty")

        val encoder = com.localmind.neural_tts.audio.AacEncoder(
            outPath,
            48000,
            1,
            bitRate,
        )
        try {
            val started = android.os.SystemClock.elapsedRealtime()
            for (chunk in chunks) {
                checkCancelled()
                val t0 = android.os.SystemClock.elapsedRealtime()
                val pcm = session?.synthesize(chunk, voiceId)
                    ?: throw IllegalStateException("Session not initialized")
                checkCancelled()
                android.util.Log.i(
                    "KokoroSynth",
                    "chunk ${chunk.length} chars synth=${android.os.SystemClock.elapsedRealtime() - t0}ms pcm=${pcm.size}",
                )
                encoder.write(pcm, checkCancelled)
            }
            val durationUs = encoder.finish(checkCancelled)
            val file = File(outPath)
            android.util.Log.i(
                "KokoroSynth",
                "done total=${android.os.SystemClock.elapsedRealtime() - started}ms bytes=${file.length()}",
            )
            return mapOf(
                "path" to outPath,
                "bytes" to file.length(),
                "durationMs" to durationUs / 1000,
            )
        } catch (t: Throwable) {
            android.util.Log.e("KokoroSynth", "failed: ${t.message}", t)
            runCatching { File(outPath).delete() }
            throw t
        } finally {
            encoder.close()
        }
    }

    override fun stop() = player.stop()
    override fun release() {
        stop()
        session?.close()
        session = null
    }

    private fun chunkText(text: String): List<String> {
        val sentences = splitSentences(text)
        val chunks = mutableListOf<String>()
        var current = StringBuilder()

        for (sentence in sentences) {
            if (current.isNotEmpty() && current.length + sentence.length > maxChunkSize) {
                chunks.add(current.toString().trim())
                current = StringBuilder()
            }
            if (current.isNotEmpty()) current.append(" ")
            current.append(sentence)
        }
        if (current.isNotEmpty()) chunks.add(current.toString().trim())
        return chunks.flatMap { it.chunked(maxChunkSize.coerceIn(1, 400)) }
    }

    private fun splitSentences(text: String): List<String> {
        return text.split(Regex("(?<=[.!?])\\s+"))
    }
}
