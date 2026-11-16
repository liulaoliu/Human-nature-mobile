package com.localmind.neural_tts.engines

interface BaseEngine {
    fun beginOperation() {}
    fun initialize(args: Map<*, *>)
    fun speak(args: Map<*, *>)

    /**
     * 合成到文件（只给「预生成朗读」用）。默认不支持，由需要的引擎覆盖。
     * 返回 `{path, bytes, durationMs}`。
     */
    fun synthesizeToFile(
        args: Map<*, *>,
        checkCancelled: () -> Unit = {},
    ): Map<String, Any?> =
        throw UnsupportedOperationException("synthesizeToFile not supported")
    fun streamAppend(args: Map<*, *>)
    fun streamFinalize(args: Map<*, *>)
    fun streamCancel(args: Map<*, *>)
    fun stop()
    fun release()
}
