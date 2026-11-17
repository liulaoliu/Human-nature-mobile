package com.localmind.neural_tts.phonemizer

/**
 * Tokenizer that maps IPA phoneme characters to integer token IDs.
 *
 * 这张表**必须**与训练时逐字符一致 —— 差一个字符，后面所有 token 的 id 全部错位，
 * 模型收到的是训练分布外的 id，听感上表现为「辅音对、元音怪」（2026-11-17 踩过）。
 *
 * 权威来源：官方 pip 包 `kittentts` 的 `KittenTTS.__init__`（v0.1.3）：
 *
 * ```python
 * self._word_index_dictionary = {symbol: i for i, symbol in enumerate(list(
 *   '$;:,.!?¡¿—…"«»"" ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz'
 *   'ɑɐɒæɓʙβɔɕçɗɖðʤəɘɚɛɜɝɞɟʄɡɠɢʛɦɧħɥʜɨɪʝɭɬɫɮʟɱɯɰŋɳɲɴøɵɸθœɶʘɹɺɾɻʀʁɽʂʃʈʧʉʊʋⱱʌɣɤʍχʎʏʑʐʒʔʡʕʢ'
 *   'ǀǁǂǃˈˌːˑʼʴʰʱʲʷˠˤ˞↓↑→↗↘\'̩\'ᵻ'))}
 * ```
 *
 * 三个容易抄错的地方（都是这次踩过的）：
 * 1. 表长 **178**，不是 177 —— `'` 出现了两次（下标 174 和 176），`"` 出现了三次
 *    （11 / 14 / 15）。
 * 2. Python 的 dict comprehension 遇到重复 key 时**后面的下标覆盖前面的**，
 *    所以最终 `"` → **15**、`'` → **176**；`buildVocab()` 里的 `forEachIndexed`
 *    天然也是这个语义，不要改成 `putIfAbsent`。
 * 3. 不要把 `"` 写成中文弯引号 `“”`，也不要把 `'`（U+0027）+ `̩`（U+0329）写成
 *    `\u0301`（combining acute）—— 那样 `ᵻ` 会拿到 176（应为 177），
 *    带弱化元音的词（`discriminating`、`introverted`）元音就错了。
 *
 * 序列形状也与官方一致：`[PAD] + tokens… + [PAD]`，**中间没有 EOS**。
 */
class Tokenizer(private val vocabPath: String? = null) {
    private val vocab = mutableMapOf<String, Int>()
    private var initialized = false

    companion object {
        /** Index 0 reserved for PAD / start / end boundary. */
        const val PAD = 0

        /**
         * 官方 vocab 表，逐字符照抄（178 项）。锚点：`"` → 15、`'` → 176、
         * `̩`(U+0329) → 175、`ᵻ`(U+1D7B) → 177。
         *
         * `test/services/kitten_tokenizer_vocab_test.dart` 会把本常量从文件里抠出来
         * 与官方表逐位比对，改动这里会红。
         */
        const val SYMBOLS =
            "\$;:,.!?¡¿—…\"«»\"\" ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz" +
                "ɑɐɒæɓʙβɔɕçɗɖðʤəɘɚɛɜɝɞɟʄɡɠɢʛɦɧħɥʜɨɪʝɭɬɫɮʟɱɯɰŋɳɲɴøɵɸθœɶʘɹɺɾɻʀʁɽʂʃʈʧʉʊʋⱱʌɣɤʍχʎʏʑʐʒʔʡʕʢ" +
                "ǀǁǂǃˈˌːˑʼʴʰʱʲʷˠˤ˞↓↑→↗↘'\u0329'ᵻ"

        /** 官方 `' '.join(re.findall(r"\w+|[^\w\s]", ipa))` 的等价物。 */
        private val tokenPattern = Regex("[\\p{L}\\p{N}_]+|[^\\s]")
    }

    fun initialize() {
        if (initialized) return
        buildVocab()
        initialized = true
    }

    /**
     * Encode text as a sequence of token IDs, with KittenTTS boundary tokens:
     *   [PAD, token…, PAD]
     *
     * 与官方一致：先按 `\w+|[^\w\s]` 切词并**用空格重新拼接**（把标点与单词分开），
     * 再逐字符查表，查不到的直接跳过。
     */
    fun encode(text: String): LongArray {
        if (!initialized) initialize()
        val spaced = tokenPattern.findAll(text).joinToString(" ") { it.value }
        val result = mutableListOf<Long>()
        result.add(PAD.toLong())         // start token
        for (char in spaced) {
            vocab[char.toString()]?.let { result.add(it.toLong()) }
        }
        result.add(PAD.toLong())         // end token（官方没有 EOS，直接 PAD 收尾）
        return result.toLongArray()
    }

    // ── Vocabulary construction ────────────────────────────────────────────

    private fun buildVocab() {
        // 重复字符取最后一次出现的下标 —— 与 Python dict comprehension 一致。
        SYMBOLS.forEachIndexed { idx, char ->
            vocab[char.toString()] = idx
        }
    }
}
