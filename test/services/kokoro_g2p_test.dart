import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:dlaoshi_app/core/kokoro_dialect.dart';
import 'package:dlaoshi_app/services/kokoro_g2p.dart';

/// `KokoroG2P` 的契约测试：算出来的音素必须**全部**在 Kokoro 的 vocab 里，
/// 而且是 misaki 字母表（不含 espeak 教科书写法）。
///
/// 为什么守这两条（2026-11-16 用户报「reading makes perfect 被读成
/// reading are makes perfect」）：Kokoro 训练在 misaki 的输出上，但我们过去
/// 喂的是 `package:phonemize` 的 espeak 拼法 —— 那些符号**全都在 vocab 里**，
/// 所以 tokenizer 不丢、不报错，模型只是收到训练时没见过的 token，音频跑偏。
/// 「不丢字符」是必要条件，不是充分条件，所以要额外守「没有 espeak 残留」。
void main() {
  // malsami 的词典走 rootBundle，需要测试绑定。`File` 读 tokenizer.json 也是一样。
  TestWidgetsFlutterBinding.ensureInitialized();

  late Set<String> vocab;

  setUpAll(() {
    final json =
        jsonDecode(File('assets/tts/kokoro/tokenizer.json').readAsStringSync())
            as Map<String, dynamic>;
    final model = json['model'] as Map<String, dynamic>;
    final raw = model['vocab'] as Map<String, dynamic>;
    // `KokoroSession.encode` 是逐字符查表的，所以只收单字符串元。
    vocab = raw.keys.where((k) => k.runes.length == 1).toSet();
  });

  /// 模拟 `KokoroSession.encode`：vocab 里没有的字符会被静默跳过。
  Set<String> droppedBy(String phonemes) => {
        for (final ch in phonemes.split(''))
          if (!vocab.contains(ch)) ch,
      };

  const sentences = <String>[
    'Reading makes perfect.',
    'The global economy has many ailments and few easy remedies.',
    'A decade or so, when mainstream politicians such as Britain\'s '
        'David Cameron were petting huskies and embracing environmental issues.',
    'She was reading a book about the world.',
    'Hospitals and elections mattered to the countries involved.',
    'In 1990s the price rose 30,000 megawatts per year.',
  ];

  test('主路输出全部落在 Kokoro vocab 里', () async {
    final g2p = KokoroG2P();
    for (final s in sentences) {
      final ps = await g2p.phonemize(s);
      expect(ps, isNotEmpty, reason: s);
      expect(
        droppedBy(ps),
        isEmpty,
        reason: '这句有字符不在 vocab 里：$s\n音素=$ps',
      );
    }
  });

  test('输出是 misaki 字母表，没有 espeak 残留', () async {
    final g2p = KokoroG2P();
    for (final s in sentences) {
      final ps = await g2p.phonemize(s);
      expect(
        espeakResidue(ps),
        isEmpty,
        reason: '还有 espeak 专属写法：$s\n音素=$ps',
      );
    }
  });

  test('用户报障的那句不再读成 reading are makes perfect', () async {
    final g2p = KokoroG2P();
    final ps = await g2p.phonemize('Reading makes perfect.');
    // 关键点：makes 不能被拆成两个音节、perfect 的重音要在第二音节。
    // 注：官方 misaki 给 makes 的是**次**重音 mˌAks，不是主重音。
    expect(ps, contains('mAks'), reason: '音素=$ps');
    // 重音符在 p 之后（pˈɜɹfəkt），所以只断言音节本体。
    expect(ps, contains('ɜɹfəkt'), reason: '音素=$ps');
    // 当年读错的症状：多出一个 are、perfect 掉了词首的 p 与尾音。
    expect(ps, isNot(contains('ɑɹ')), reason: '音素=$ps');
    expect(ps, isNot(contains(' meɪks ')), reason: '音素=$ps');
    expect(ps, contains('fəkt'), reason: '音素=$ps');
  });

  test('词典查不到的词走兜底，而不是变成 ❓', () async {
    final g2p = KokoroG2P();
    // `hospitals` / `elections` 不在 malsami 的 gold 词典里（复数缺）。
    final ps = await g2p.phonemize('hospitals elections countries');
    expect(ps, isNot(contains(kUnknownPhoneme)));
    expect(ps.split(' ').length, greaterThanOrEqualTo(3));
  });
}
