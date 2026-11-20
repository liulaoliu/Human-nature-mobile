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
///   3. 随包的主题曲（[AssetMusic]，播 `assets/audio/crawl_theme.mp3`）。
///
/// 背景音换过两轮：最早是运行时合成的 [SpaceDroneMusic]（几个低频正弦），
/// 后来是合成的 [MainThemeMusic]，现在（2026-11-20）用用户自己给的音频文件
/// 打包进 APK —— 启动零等待、音质就是原文件。合成那两版都留着：换素材时不
/// 会没有兜底，也方便对比。
///
/// 交互：上下拖动可以自己翻，松手后点右下角继续爬；右上角进许可全文。
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show LicenseEntry, LicenseRegistry;
import 'package:flutter/material.dart';

import '../services/asset_music.dart';
import '../services/license_script.dart';
import '../services/melody_music.dart';
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
  late final CrawlMusic _music = widget.music ?? AssetMusic();

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
    final viewport = MediaQuery.sizeOf(context).height;
    // 字幕平面比屏幕高得多。平面上的高度 h 与屏幕高度不是一回事：透视下
    // h 越大，投影到屏幕上的增量越小（h=2000 才挪到屏幕中部），所以要让
    // 字幕爬到屏幕最上沿，平面本身就得有这么高。
    final plane = viewport * _planeOverflow;
    // 顶端留 1.5 个平面：一进页面先看星空，字幕随后从画面下缘升起。
    // 滚动视口 = 平面高，所以「滚到底」= 首行从平面底边走到平面顶边，
    // 正好是屏幕上看到的完整一趟。tail 用 0.5 个平面把滚动行程补齐
    // （行程 = lead + tail - 平面 = 1.5 + 0.5 - 1 = 1 个平面）。
    final lead = plane * 1.5;
    final tail = plane * 0.5;
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          OverflowBox(
            alignment: Alignment.bottomCenter,
            maxHeight: double.infinity,
            child: Transform(
              alignment: Alignment.bottomCenter,
              transform: _tilt,
              child: SizedBox(
                height: plane,
                child: SingleChildScrollView(
                  controller: _scroll,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(height: lead),
                      for (final line in lines) _CrawlText(line: line),
                      SizedBox(height: tail),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // 两端渐隐。远端（屏幕上方）尤其必须有：透视把纵深压得比横向更狠，
          // 远处的行距会挤到小于字号，几行字叠成一坨 —— 用户 2026-11-20 报的
          // 「随滚动同步出现的有节奏的异形」就是这坨。压一层背景色渐变，让它
          // 像电影里那样沉进黑暗里。
          const IgnorePointer(child: _EdgeFade(top: true)),
          const IgnorePointer(child: _EdgeFade(top: false)),
        ],
      ),
    );
  }

  /// 透视矩阵。
  ///
  /// `setEntry(3, 2, k)` 造出 w = 1 + k·z 的投影（k 是「相机距离的倒数」），
  /// `rotateX(-θ)` 让平面上方（h 越大）的 z 越大，于是越往上越小、越往中间收。
  ///
  /// 有个**很容易踩的死穴**：透视下距底边 h 的点，投影到屏幕上离底边的距离是
  /// `h·cosθ / (1 + k·h·sinθ)`，随 h 增大收敛到 `1 / (k·tanθ)` —— 也就是说
  /// **不管平面做多高，可见的那块最多只有 `1/(k·tanθ)` 高**。
  /// 最早写 k=0.0016、θ=1.05，上限只有 358dp，而屏幕有 875dp：字幕永远挤在
  /// 下面 40%，而且那 358dp 里要塞下整个平面，行距被压到比字号还小，才糊成
  /// 一整块纯色（用户说的「占屏幕位置太小」＋「异形」其实是同一个根因）。
  /// 改成 k=0.00035、θ=0.92 后上限约 2176dp，铺满一屏还有余量。
  static final Matrix4 _tilt = Matrix4.identity()
    ..setEntry(3, 2, 0.00035)
    ..rotateX(-0.92);

  /// 平面高度相对屏高的倍数。
  ///
  /// 太小则爬不到顶（屏幕顶端对应平面约 2400dp）；太大则大部分内容挤在远端
  /// 那几像素里，纯粹浪费布局。2.8 倍屏高（875×2.8≈2450dp）刚好盖住一屏，
  /// 同时低于 `1/(k·sinθ)≈3589dp` 的翻面临界点。
  static const double _planeOverflow = 2.8;

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

/// 屏幕上下两端的渐隐遮罩。
///
/// 远端（`top: true`）压得更狠：透视下远处的行距被压到小于字号，几行字会叠成
/// 一块纯色；近端（`top: false`）则是贴脸放大成一整块。电影里字幕也是从黑暗
/// 里浮出来、再沉进黑暗里。
class _EdgeFade extends StatelessWidget {
  const _EdgeFade({required this.top});

  final bool top;

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height;
    const bg = crawlBackground;
    // 上端要盖住「消失点」那一坨，所以比下端更长。
    final height = h * (top ? 0.34 : 0.22);
    final colors = top
        ? const [bg, bg, Color(0x0005060A)]
        : const [Color(0x0005060A), bg, bg];
    final stops = top ? const [0.0, 0.45, 1.0] : const [0.0, 0.62, 1.0];
    return Align(
      alignment: top ? Alignment.topCenter : Alignment.bottomCenter,
      child: IgnorePointer(
        child: Container(
          height: height,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: top ? Alignment.topCenter : Alignment.bottomCenter,
              end: top ? Alignment.bottomCenter : Alignment.topCenter,
              colors: colors,
              stops: stops,
            ),
          ),
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
    // 字号整体抬过一轮（用户 2026-11-20：「占屏幕位置太小了，做大点」）。
    // 透视会把上半部分缩掉，所以平面上的字号必须比「看着合适」再大一档。
    final (style, top) = switch (line.kind) {
      CrawlKind.title => (
        const TextStyle(
          color: crawlAmber,
          fontSize: 46,
          fontWeight: FontWeight.w800,
          letterSpacing: 7,
          height: 1.45,
        ),
        34.0,
      ),
      CrawlKind.subtitle => (
        const TextStyle(
          color: Colors.white,
          fontSize: 24,
          fontWeight: FontWeight.w600,
          height: 1.65,
        ),
        12.0,
      ),
      CrawlKind.packageName => (
        const TextStyle(
          color: crawlAmber,
          fontSize: 28,
          fontWeight: FontWeight.w700,
          height: 1.45,
        ),
        18.0,
      ),
      CrawlKind.body => (
        const TextStyle(
          color: Color(0xFFD7D9E0),
          fontSize: 19,
          height: 1.6,
        ),
        5.0,
      ),
      CrawlKind.gap => (const TextStyle(), 0.0),
    };
    return Padding(
      padding: EdgeInsets.fromLTRB(26, top, 26, 0),
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
