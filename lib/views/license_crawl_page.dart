/// 「开源许可」页 —— 星球大战片头那种爬行字幕。
///
/// 为什么这么做：这不是玩笑，是**可读性问题**的反面。原来的许可页是几千行
/// 密密的白字，用户点进去只会立刻退出来。做成爬行字幕以后，每个组件只露一行
/// 摘要，想看全文再去「许可全文」里逐条展开 —— 引子负责「知道收了什么」，
/// 全文负责「法律上可查」。
///
/// 三个部分：
///   1. 深黑星空，缓慢闪烁并轻微漂移（[_StarsPainter]）；
///   2. 斜着向后退的文字（透视 + 纵向滚动，见 [_tilt]）；
///   3. 自己合成的太空铺底音（[CrawlMusic]，不是星战原声，那个有版权）。
///
/// 交互：上下拖动可以自己翻，松手后点右下角继续爬；右上角进许可全文。
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show LicenseEntry, LicenseRegistry;
import 'package:flutter/material.dart';

import '../services/license_script.dart';
import '../services/space_music.dart';

/// 开场白等多久才开始爬。
const Duration crawlLeadIn = Duration(milliseconds: 900);

/// 页面上那层黑色。
const Color crawlBackground = Color(0xFF05060A);

/// 标题与组件名用的琥珀色，接近片头那种暖黄。
const Color crawlAmber = Color(0xFFFFD86B);

/// 许可爬行页。
class LicenseCrawlPage extends StatefulWidget {
  const LicenseCrawlPage({
    super.key,
    this.music,
    this.appName = 'D哥帮你办',
    this.leadIn = crawlLeadIn,
  });

  /// 背景音。测试里传 [SilentMusic]，就不会碰平台通道。
  final CrawlMusic? music;

  /// 副标题里显示的 App 名。
  final String appName;

  /// 字幕加载完后等多久开始爬。测试传 [Duration.zero]，免得留一个待触发的
  /// 定时器让 widget 测试报「A Timer is still pending」。
  final Duration leadIn;

  @override
  State<LicenseCrawlPage> createState() => _LicenseCrawlPageState();
}

class _LicenseCrawlPageState extends State<LicenseCrawlPage>
    with SingleTickerProviderStateMixin {
  final ScrollController _scroll = ScrollController();
  late final AnimationController _anim;
  late final CrawlMusic _music = widget.music ?? SpaceDroneMusic();

  List<CrawlLine>? _lines;
  Object? _error;
  bool _playing = false;
  bool _musicOn = false;

  @override
  void initState() {
    super.initState();
    // 时长按行数给：行多就慢一点，免得字幕跑得比读得快。
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 70),
    )..addListener(_follow);
    _load();
    _startMusic();
  }

  Future<void> _load() async {
    try {
      final entries = await LicenseRegistryHelper.collect();
      if (!mounted) return;
      setState(() {
        _lines = buildLicenseScript(entries, appName: widget.appName);
      });
      // 先等一帧让滚动视图把 maxScrollExtent 算出来，再开爬。
      if (widget.leadIn > Duration.zero) {
        await Future<void>.delayed(widget.leadIn);
        if (!mounted) return;
      }
      _anim
        ..duration = Duration(
          seconds: 55 + (_lines?.length ?? 0) ~/ 2,
        )
        ..repeat();
      setState(() => _playing = true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  Future<void> _startMusic() async {
    try {
      await _music.start();
      if (!mounted) return;
      setState(() => _musicOn = true);
    } catch (_) {
      // 背景音失败不该影响看许可；静默降级成没有声音。
      if (!mounted) return;
      setState(() => _musicOn = false);
    }
  }

  /// 把动画进度映射成滚动位置。
  void _follow() {
    if (!_scroll.hasClients) return;
    final max = _scroll.position.maxScrollExtent;
    if (max <= 0) return;
    _scroll.jumpTo((_anim.value * max).clamp(0.0, max));
  }

  void _onDrag(DragUpdateDetails d) {
    if (!_scroll.hasClients) return;
    final max = _scroll.position.maxScrollExtent;
    if (max <= 0) return;
    if (_playing) {
      _anim.stop();
      setState(() => _playing = false);
    }
    // 手指往下拉 = 往回看（同一方向），乘 1.6 是因为透视把纵向压扁了，
    // 一比一手感会显得「拖不动」。
    final next = (_scroll.offset - d.delta.dy * 1.6).clamp(0.0, max);
    _scroll.jumpTo(next);
    _anim.value = next / max;
  }

  void _togglePlay() {
    if (_playing) {
      _anim.stop();
      setState(() => _playing = false);
      return;
    }
    if (_anim.value >= 1) _anim.value = 0;
    _anim.repeat();
    setState(() => _playing = true);
  }

  Future<void> _toggleMusic() async {
    if (_musicOn) {
      await _music.stop();
      if (!mounted) return;
      setState(() => _musicOn = false);
      return;
    }
    await _startMusic();
  }

  void _openFullText() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const LicensePage(
          applicationName: 'D哥帮你办',
          applicationLegalese: '第三方组件许可全文',
        ),
      ),
    );
  }

  @override
  void dispose() {
    _anim.dispose();
    _scroll.dispose();
    _music.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: crawlBackground,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: _onDrag,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const RepaintBoundary(child: _StarField()),
            if (_error != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    '许可列表读不出来：$_error',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
              )
            else if (_lines == null)
              const Center(child: CircularProgressIndicator())
            else
              _buildCrawl(_lines!),
            _buildOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _buildCrawl(List<CrawlLine> lines) {
    // 内容顶端留一整屏空白：字幕从屏幕下方「升起来」，不是一进页面就满屏。
    final spacer = MediaQuery.sizeOf(context).height * 0.92;
    return ClipRect(
      child: Transform(
        alignment: Alignment.bottomCenter,
        transform: _tilt,
        child: SingleChildScrollView(
          controller: _scroll,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(height: spacer),
              for (final line in lines) _CrawlText(line: line),
              SizedBox(height: spacer),
            ],
          ),
        ),
      ),
    );
  }

  /// 透视矩阵。
  ///
  /// `setEntry(3, 2, k)` 造出 w = 1 + k·z 的投影；`rotateX(-θ)` 配
  /// `Alignment.bottomCenter` 让「越靠上越远」，于是同一行字往上走时会一边
  /// 缩小一边向消失点收拢 —— 就是片头那个效果。θ 越大越陡，0.9 太扁、1.2 太
  /// 挤，1.05 附近字幕还能读。
  static final Matrix4 _tilt = Matrix4.identity()
    ..setEntry(3, 2, 0.0016)
    ..rotateX(-1.05);

  Widget _buildOverlay() {
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Row(
          children: [
            IconButton(
              key: const ValueKey<String>('crawl-back'),
              tooltip: '返回',
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back, color: Colors.white70),
            ),
            const Spacer(),
            if (_lines != null)
              IconButton(
                key: const ValueKey<String>('crawl-play'),
                tooltip: _playing ? '暂停' : '继续',
                onPressed: _togglePlay,
                icon: Icon(
                  _playing ? Icons.pause : Icons.play_arrow,
                  color: Colors.white70,
                ),
              ),
            IconButton(
              key: const ValueKey<String>('crawl-music'),
              tooltip: _musicOn ? '关掉背景音' : '打开背景音',
              onPressed: _toggleMusic,
              icon: Icon(
                _musicOn ? Icons.volume_up : Icons.volume_off,
                color: Colors.white70,
              ),
            ),
            TextButton(
              key: const ValueKey<String>('crawl-full-text'),
              onPressed: _openFullText,
              child: const Text(
                '许可全文',
                style: TextStyle(color: crawlAmber),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 一行字幕。字号与颜色按 [CrawlLine.kind] 分。
class _CrawlText extends StatelessWidget {
  const _CrawlText({required this.line});

  final CrawlLine line;

  @override
  Widget build(BuildContext context) {
    if (line.kind == CrawlKind.gap) {
      return const SizedBox(height: 18);
    }
    final (style, top) = switch (line.kind) {
      CrawlKind.title => (
        const TextStyle(
          color: crawlAmber,
          fontSize: 34,
          fontWeight: FontWeight.w800,
          letterSpacing: 6,
          height: 1.5,
        ),
        28.0,
      ),
      CrawlKind.subtitle => (
        const TextStyle(
          color: Colors.white,
          fontSize: 17,
          fontWeight: FontWeight.w600,
          height: 1.7,
        ),
        10.0,
      ),
      CrawlKind.packageName => (
        const TextStyle(
          color: crawlAmber,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          height: 1.5,
        ),
        14.0,
      ),
      CrawlKind.body => (
        const TextStyle(
          color: Color(0xFFD7D9E0),
          fontSize: 14,
          height: 1.6,
        ),
        4.0,
      ),
      CrawlKind.gap => (const TextStyle(), 0.0),
    };
    return Padding(
      padding: EdgeInsets.fromLTRB(32, top, 32, 0),
      child: Text(line.text, textAlign: TextAlign.center, style: style),
    );
  }
}

/// 深黑星空。
class _StarField extends StatefulWidget {
  const _StarField();

  @override
  State<_StarField> createState() => _StarFieldState();
}

class _StarFieldState extends State<_StarField>
    with SingleTickerProviderStateMixin {
  late final AnimationController _twinkle;

  @override
  void initState() {
    super.initState();
    _twinkle = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 9),
    )..repeat();
  }

  @override
  void dispose() {
    _twinkle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _twinkle,
      builder: (_, _) => CustomPaint(
        painter: _StarsPainter(_twinkle.value),
        size: Size.infinite,
      ),
    );
  }
}

class _StarsPainter extends CustomPainter {
  _StarsPainter(this.t);

  /// 0–1 的循环进度。
  final double t;

  /// 固定 seed：每次进页面星星位置一样，不会「闪一下换个天」。
  static final List<_Star> _stars = _makeStars();

  static List<_Star> _makeStars() {
    final rnd = math.Random(20261120);
    return [
      for (var i = 0; i < 220; i++)
        _Star(
          x: rnd.nextDouble(),
          y: rnd.nextDouble(),
          r: 0.4 + rnd.nextDouble() * 1.3,
          phase: rnd.nextDouble(),
          speed: 0.4 + rnd.nextDouble() * 0.9,
        ),
    ];
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    for (final star in _stars) {
      // 呼吸：每个星自己的相位，正弦做 0.25–1 的亮度。
      final phase = (t * star.speed + star.phase) % 1.0;
      final twinkle = 0.25 + 0.75 * (0.5 + 0.5 * math.sin(phase * 2 * math.pi));
      // 极慢的上浮，循环一圈正好回到原位（用取模保证无缝）。
      final dy = (t * 0.01) % 1.0;
      final y = (star.y + dy) % 1.0;
      paint.color = Colors.white.withValues(alpha: twinkle * 0.9);
      canvas.drawCircle(
        Offset(star.x * size.width, y * size.height),
        star.r,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_StarsPainter old) => old.t != t;
}

class _Star {
  const _Star({
    required this.x,
    required this.y,
    required this.r,
    required this.phase,
    required this.speed,
  });

  final double x;
  final double y;
  final double r;
  final double phase;
  final double speed;
}

/// 把 `LicenseRegistry.licenses` 收成一个列表。
///
/// 单独包一层是为了测试能拦住「注册被误删」：列表空了就说明
/// `registerThirdPartyLicenses()` 没跑。
abstract final class LicenseRegistryHelper {
  static Future<List<LicenseEntry>> collect() => LicenseRegistry.licenses.toList();
}
