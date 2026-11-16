package com.localmind.neural_tts.audio

import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.os.SystemClock
import android.util.Log
import java.io.BufferedOutputStream
import java.io.File
import java.io.FileOutputStream

/**
 * 把 16bit PCM 编码成 AAC-LC，写成 **ADTS**（`.aac`）。
 *
 * 为什么不用 MP4/M4A：vivo V1981A（Android 12）的 AAC 编码器输出的
 * `csd-0` 只有 2 字节，`MediaMuxer` 打 `csd0 too small` 后不再出帧。
 * ADTS 每帧自带头，不需要 `MediaMuxer` / `csd-0`，所有 Android 播放器
 * （MediaPlayer / audioplayers）都能直接播。
 *
 * 采样率 48kHz：24kHz 的配置在这台机器上同样不出帧；24k → 48k 用零阶保持
 * （每个采样重复两次），语音听不出差别。
 */
class AacEncoder(
    outputPath: String,
    private val sampleRate: Int = 48000,
    private val channels: Int = 1,
    bitRate: Int = 64000,
) {
    private val codec: MediaCodec
    private val out: BufferedOutputStream
    private val bufferInfo = MediaCodec.BufferInfo()
    private var sampleRateIndex = 3 // 48000
    private var channelConfig = 1 // mono
    private var totalFrames = 0L
    private var finished = false

    init {
        Log.i(TAG, "init path=$outputPath rate=$sampleRate ch=$channels bitRate=$bitRate")
        val format = MediaFormat.createAudioFormat(
            MediaFormat.MIMETYPE_AUDIO_AAC,
            sampleRate,
            channels,
        ).apply {
            setInteger(
                MediaFormat.KEY_AAC_PROFILE,
                MediaCodecInfo.CodecProfileLevel.AACObjectLC,
            )
            setInteger(MediaFormat.KEY_BIT_RATE, bitRate)
            // 一句话 PCM 约 200KB；给一个足够大的输入槽，避免 vivo 编码器
            // 因为输入槽不够而一直压着不出帧。
            setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 1 shl 20)
        }
        File(outputPath).parentFile?.mkdirs()
        out = BufferedOutputStream(FileOutputStream(outputPath))
        codec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC)
        codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        codec.start()
        Log.i(TAG, "codec ready name=${codec.name}")
    }

    /** 喂一段 PCM16LE；可以多次调用，内部按需切块。 */
    fun write(pcm: ByteArray, checkCancelled: () -> Unit = {}) {
        check(!finished) { "AacEncoder 已经 finish 过了" }
        val input = upsample(pcm)
        var offset = 0
        val bytesPerFrame = 2 * channels
        var stalls = 0
        while (offset < input.size) {
            checkCancelled()
            drain(false)
            val inputIndex = codec.dequeueInputBuffer(10_000)
            if (inputIndex < 0) {
                drain(true)
                if (++stalls > 500) {
                    throw IllegalStateException("AAC 编码器 5 秒没有输入槽")
                }
                continue
            }
            stalls = 0
            val buffer = codec.getInputBuffer(inputIndex) ?: continue
            buffer.clear()
            val size = minOf(buffer.remaining(), input.size - offset)
            if (size <= 0) {
                throw IllegalStateException("AAC input buffer is empty")
            }
            buffer.put(input, offset, size)
            codec.queueInputBuffer(
                inputIndex,
                0,
                size,
                presentationTimeUs(totalFrames),
                0,
            )
            totalFrames += size / bytesPerFrame
            offset += size
        }
        drain(false)
    }

    /** 排空编码器并封口；返回音频时长（微秒）。 */
    fun finish(checkCancelled: () -> Unit = {}): Long {
        check(!finished) { "AacEncoder 已经 finish 过了" }
        var queued = false
        val deadline = SystemClock.elapsedRealtime() + 10_000
        while (!queued) {
            checkCancelled()
            drain(false)
            val inputIndex = codec.dequeueInputBuffer(10_000)
            if (inputIndex < 0) {
                drain(true)
                if (SystemClock.elapsedRealtime() > deadline) {
                    throw IllegalStateException("AAC 编码器 10 秒没有输入槽")
                }
                continue
            }
            codec.queueInputBuffer(
                inputIndex,
                0,
                0,
                presentationTimeUs(totalFrames),
                MediaCodec.BUFFER_FLAG_END_OF_STREAM,
            )
            queued = true
        }
        drain(true)
        out.flush()
        finished = true
        return totalFrames * 1_000_000L / sampleRate
    }

    private fun presentationTimeUs(frames: Long): Long =
        frames * 1_000_000L / sampleRate

    private fun drain(waitForEos: Boolean) {
        val deadline = if (waitForEos) {
            SystemClock.elapsedRealtime() + 10_000
        } else {
            0L
        }
        while (true) {
            val outIndex = codec.dequeueOutputBuffer(bufferInfo, if (waitForEos) 10_000 else 0)
            when {
                outIndex == MediaCodec.INFO_TRY_AGAIN_LATER -> {
                    if (!waitForEos) return
                    if (SystemClock.elapsedRealtime() > deadline) {
                        throw IllegalStateException("AAC 编码器 10 秒没有输出")
                    }
                    continue
                }
                outIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    val format = codec.outputFormat
                    sampleRateIndex = samplingFrequencyIndex(
                        format.getInteger(MediaFormat.KEY_SAMPLE_RATE),
                    )
                    channelConfig = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                    Log.i(
                        TAG,
                        "output format rate=${format.getInteger(MediaFormat.KEY_SAMPLE_RATE)} " +
                            "ch=$channelConfig",
                    )
                }
                outIndex >= 0 -> {
                    val output = codec.getOutputBuffer(outIndex)
                    if (output != null &&
                        bufferInfo.size > 0 &&
                        (bufferInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG) == 0
                    ) {
                        writeAdts(output, bufferInfo)
                    }
                    codec.releaseOutputBuffer(outIndex, false)
                    if (bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                        return
                    }
                }
            }
        }
    }

    /** 每个 AAC 原始帧前加 7 字节 ADTS 头。 */
    private fun writeAdts(buffer: java.nio.ByteBuffer, info: MediaCodec.BufferInfo) {
        val frameLength = 7 + info.size
        val header = ByteArray(7)
        val profile = 2 // AAC LC；ADTS 里存 profile-1
        header[0] = 0xFF.toByte()
        header[1] = 0xF1.toByte()
        header[2] = (((profile - 1) shl 6) or (sampleRateIndex shl 2) or
            (channelConfig shr 2)).toByte()
        header[3] = (((channelConfig and 3) shl 6) or (frameLength shr 11)).toByte()
        header[4] = ((frameLength shr 3) and 0xFF).toByte()
        header[5] = (((frameLength and 7) shl 5) or 0x1F).toByte()
        header[6] = 0xFC.toByte()
        out.write(header)
        buffer.position(info.offset)
        buffer.limit(info.offset + info.size)
        val bytes = ByteArray(info.size)
        buffer.get(bytes)
        out.write(bytes)
    }

    private fun samplingFrequencyIndex(rate: Int): Int = when (rate) {
        96000 -> 0
        88200 -> 1
        64000 -> 2
        48000 -> 3
        44100 -> 4
        32000 -> 5
        24000 -> 6
        22050 -> 7
        16000 -> 8
        12000 -> 9
        11025 -> 10
        8000 -> 11
        else -> 3
    }

    private fun upsample(pcm: ByteArray): ByteArray {
        if (sampleRate != 48000) return pcm
        val outBytes = ByteArray(pcm.size * 2)
        var j = 0
        var i = 0
        while (i + 1 < pcm.size) {
            val lo = pcm[i]
            val hi = pcm[i + 1]
            outBytes[j++] = lo
            outBytes[j++] = hi
            outBytes[j++] = lo
            outBytes[j++] = hi
            i += 2
        }
        return if (j == outBytes.size) outBytes else outBytes.copyOf(j)
    }

    /** 释放资源；异常路径也要调，避免编码器泄漏。 */
    fun close() {
        runCatching { codec.stop() }
        runCatching { codec.release() }
        runCatching { out.close() }
    }

    companion object {
        private const val TAG = "AacEncoder"
    }
}
