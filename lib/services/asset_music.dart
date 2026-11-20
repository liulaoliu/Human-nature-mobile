/// 随包打进去的许可页背景音。
///
/// 为什么不再现合成：合成那版（[MainThemeMusic]）是为了绕开版权 —— 它自己算
/// 采样点，法律上干净，代价是每次启动要算几十万采样点、机型慢的时候进页面会
/// 卡一下，而且音色受限于纯算术。用户（2026-11-20）给了自己的音频文件，
/// 直接打包进 APK 播，启动零等待、音质就是原文件。
///
/// 打包的是 `assets/audio/crawl_theme.mp3`：44.1kHz 立体声 128kbps，
/// 163 秒。**已经切掉了原文件开头 0.6 秒与结尾 7.2 秒的静音**，还在两端各
/// 做了 0.45 秒淡入淡出 —— 否则循环回到开头会先空 0.6 秒、结尾空 7 秒，
/// 听感就是「每隔两分半断一次」。
///
/// 注意：`AudioSource` 走 `AudioCache`，它会先把 asset 拷到临时目录再交给
/// 播放器（Flutter 的播放器只吃文件路径，不吃 asset）。所以第一次播放会多
/// 一次 2.6MB 的拷贝，之后命中缓存。
///
/// 版权：文件名反过来读是 Imperial March，但那是噱头 —— 用户从网上找的搞笑版，
/// 实测（2026-11-20，chroma / 音级分布 / 旋律滑窗匹配）曲中**没有**帝国进行曲
/// 的主题：十二个音级全在 5–13% 之间（最热比最冷只有 2.5:1，原作那四个音占
/// 84.8%、这里只占 41.7%）、低音主音是 B 不是 G、把原作
/// 主题合成出来做模板匹配最佳 cos 只有 0.557（同曲不同段通常 >0.9）。所以它
/// 不是那段有版权的录音。真要公开发布前想更稳，把 `assets/audio/crawl_theme.mp3`
/// 换掉即可，代码不用动。
library;

import 'package:audioplayers/audioplayers.dart';

import 'space_music.dart' show CrawlMusic;

/// 打包在 APK 里的背景音。
class AssetMusic implements CrawlMusic {
  AssetMusic({this.assetPath = crawlThemeAsset, this.volume = 0.42});

  /// asset 路径（相对 `assets/`，因为 `AudioCache.prefix` 默认就是 `assets/`）。
  final String assetPath;

  /// 播放音量。字幕是要读的，音乐只能垫底；0.42 在真机上「听得出有音乐、
  /// 又不抢注意力」。
  final double volume;

  /// 随包的主题曲。
  static const String crawlThemeAsset = 'audio/crawl_theme.mp3';

  /// 打包进 APK 的完整路径（`rootBundle` / 测试用）。
  static const String crawlThemeBundlePath = 'assets/$crawlThemeAsset';

  /// 播放器 id。与 [SpaceDroneMusic] / [MainThemeMusic] 分开，免得互相顶掉。
  static const String playerId = 'license_crawl_theme';

  AudioPlayer? _player;

  @override
  Future<void> start() async {
    final existing = _player;
    if (existing != null) {
      await existing.resume();
      return;
    }
    final player = AudioPlayer(playerId: playerId);
    await player.setReleaseMode(ReleaseMode.loop);
    await player.setVolume(volume);
    await player.play(AssetSource(assetPath));
    _player = player;
  }

  @override
  Future<void> stop() async {
    await _player?.pause();
  }

  @override
  Future<void> dispose() async {
    final player = _player;
    _player = null;
    await player?.dispose();
  }
}
