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
 * ## 为什么是 ADTS 而不是 M4A
 *
 * vivo V1981A（Android 12）的 AAC 编码器输出的 `csd-0` 只有 2 字节，
 * `MediaMuxer` 打 `csd0 too small` 之后一帧都不出。ADTS 每帧自带 7 字节头，
 * 不需要 `csd-0`，所有 Android 播放器（MediaPlayer / audioplayers）都能直接播。
 *
 * ## 上一版为什么会写出「坏音频」（2026-11-16 重写的原因）
 *
 * 旧版直接把 `MediaCodec` 每次吐出来的输出缓冲当成**一个** AAC 帧，套一个
 * ADTS 头就写盘。桌面 ffmpeg 解码时报 `Invalid data` / 帧边界错位 ——
 * 一旦编码器把多个 access unit 合并进同一个输出缓冲（或吐出一个超长缓冲），
 * 后面那段数据就没有自己的 ADTS 头，解码器读完 13 位 frame_length 就撞上
 * 半截同步字。
 *
 * 这一版的做法：
 * 1. **逐帧校验** —— `size` 必须 > 0 且 `frameLength = 7 + size` 必须装得进
 *    ADTS 的 13 位长度字段（≤ 8191）。装不下就抛错，而不是静默写出坏文件。
 * 2. **跳过 codec config** —— 带 `BUFFER_FLAG_CODEC_CONFIG` 的缓冲是
 *    AudioSpecificConfig，不是音频帧，混进去同样会让解码器错位。
 * 3. **帧大小记账** —— 每帧的字节数打到 logcat，异常时能一眼看出是
 *    「合并帧」还是「空帧」。
 *
 * 采样率 48kHz：24kHz 的配置在这台机器上同样不出帧；24k → 48k 用线性插值
 * （旧版是零阶保持，直接复制采样，听感更毛糙）。
 *
 * 体积参考：64kbps = 8KB/s，一篇 800 词约 5 分钟 ≈ 2.4MB；
 * 同内容的 WAV（24kHz/16bit 单声道）是 48KB/s ≈ 14MB。
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
    private var writtenFrames = 0L
    private var writtenBytes = 0L
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
        Log.i(
            TAG,
            "finish frames=$writtenFrames bytes=$writtenBytes " +
                "durationMs=${totalFrames * 1000L / sampleRate}",
        )
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
                    val isConfig =
                        (bufferInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG) != 0
                    if (output != null && bufferInfo.size > 0 && !isConfig) {
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
        // ADTS 的 frame_length 是 13 位：超过 8191 就写不下，硬写会得到
        // 一个「头说 8000 字节、实际更多」的坏帧，解码器从这里开始错位。
        if (frameLength > 0x1FFF) {
            throw IllegalStateException(
                "AAC 帧太大（${info.size} 字节），ADTS 装不下；" +
                    "多半是编码器把多个 access unit 合并吐出来了",
            )
        }
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

        writtenFrames += 1
        writtenBytes += frameLength
        // 只打前几帧和后几帧，中间每 100 帧打一次，避免刷爆 logcat。
        if (writtenFrames <= 5 || writtenFrames % 100 == 0L) {
            Log.i(TAG, "frame#$writtenFrames size=${info.size} total=$writtenBytes")
        }
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

    /**
     * 24kHz → 48kHz：线性插值。
     *
     * 旧版是零阶保持（每个采样复制两遍），等价于在 24kHz 上叠加一层
     * 高频镜像，语音听起来会发毛。线性插值多两个加法，听感更接近原始 PCM。
     */
    private fun upsample(pcm: ByteArray): ByteArray {
        if (sampleRate != 48000) return pcm
        val frames = pcm.size / 2
        if (frames == 0) return pcm
        val outBytes = ByteArray(frames * 4)
        var j = 0
        var prev = readSample(pcm, 0)
        // 第一帧：重复第一个采样，保持时长严格是两倍。
        writeSample(outBytes, j, prev); j += 2
        writeSample(outBytes, j, prev); j += 2
        for (i in 1 until frames) {
            val cur = readSample(pcm, i)
            writeSample(outBytes, j, prev); j += 2
            // 线性插值中点。
            writeSample(outBytes, j, ((prev.toInt() + cur.toInt()) / 2).toShort()); j += 2
            prev = cur
        }
        return if (j == outBytes.size) outBytes else outBytes.copyOf(j)
    }

    private fun readSample(pcm: ByteArray, index: Int): Short {
        val i = index * 2
        if (i + 1 >= pcm.size) return 0
        val lo = pcm[i].toInt() and 0xFF
        val hi = pcm[i + 1].toInt()
        return ((hi shl 8) or lo).toShort()
    }

    private fun writeSample(dst: ByteArray, offset: Int, value: Short) {
        if (offset + 1 >= dst.size) return
        dst[offset] = (value.toInt() and 0xFF).toByte()
        dst[offset + 1] = ((value.toInt() shr 8) and 0xFF).toByte()
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
