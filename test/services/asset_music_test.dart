import 'package:dlaoshi_app/services/asset_music.dart';
import 'package:dlaoshi_app/services/space_music.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 随包主题曲的守护测试。
///
/// 两件事容易悄悄坏掉：
/// 1. `pubspec.yaml` 漏登记 `assets/audio/`（或文件被误删）—— 页面照样能开，
///    只是永远没声音，用户听不出是配置问题还是手机静音；
/// 2. 文件被换成别的格式（比如为了「优化」转成 wav 但改错后缀）—— 播放器
///    静默失败。
///
/// 所以这里直接读 `rootBundle`，校验「在 + 非空 + MP3 帧同步字」。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('assets/audio 里的主题曲', () {
    test('打进了包：读得出来、有量、是 MP3', () async {
      final ByteData data = await rootBundle.load(AssetMusic.crawlThemeBundlePath);
      expect(data.lengthInBytes, greaterThan(1000000),
          reason: '主题曲应该有一两分钟，体积太小说明文件被截断或没打进去');

      final Uint8List bytes = data.buffer
          .asUint8List(data.offsetInBytes, data.lengthInBytes);

      // ID3v2 标签可以出现在最前面，先跳过再看帧头
      var at = 0;
      if (bytes.length > 10 &&
          bytes[0] == 0x49 &&
          bytes[1] == 0x44 &&
          bytes[2] == 0x33) {
        final int size = (bytes[6] & 0x7f) << 21 |
            (bytes[7] & 0x7f) << 14 |
            (bytes[8] & 0x7f) << 7 |
            (bytes[9] & 0x7f);
        at = 10 + size;
      }
      expect(at, lessThan(bytes.length - 2), reason: 'ID3 标签长度不合法');
      // MP3 帧同步：11 个 1
      expect(bytes[at], 0xFF, reason: '不是 MP3 帧头：第一个字节应为 0xFF');
      expect(bytes[at + 1] & 0xE0, 0xE0, reason: '不是 MP3 帧头：同步字不全');
    });
  });

  group('AssetMusic', () {
    test('默认参数指向随包主题曲，且实现 CrawlMusic', () {
      final music = AssetMusic();
      expect(music, isA<CrawlMusic>());
      expect(music.assetPath, AssetMusic.crawlThemeAsset);
      expect(music.volume, inInclusiveRange(0.1, 1.0),
          reason: '背景音要垫在字幕下面，不能盖过人声/提示音');
    });

    test('bundle 路径就是 assets/ 前缀加 asset 路径', () {
      expect(AssetMusic.crawlThemeBundlePath,
          'assets/${AssetMusic.crawlThemeAsset}');
      expect(AssetMusic.crawlThemeAsset.endsWith('.mp3'), isTrue);
    });

    test('可以换成别的音频（换素材不用改代码）', () {
      final music = AssetMusic(assetPath: 'audio/other.mp3', volume: 0.2);
      expect(music.assetPath, 'audio/other.mp3');
      expect(music.volume, 0.2);
    });
  });
}
