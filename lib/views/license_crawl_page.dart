/// 「开源许可」页 —— 星球大战片头那种爬行字幕。
///
/// 为什么这么做：这不是玩笑，是**可读性问题**的反面。原来的许可页是几千行
/// 密密的白字，用户点进去只会立刻退出来。做成爬行字幕以后，每个组件只露一行
/// 摘要，想看全文再去「许可全文」里逐条展开 —— 引子负责「知道收了什么」，
/// 全文负责「法律上可查」。
///
/// 三个部分：
///   1. 深黑星空，缓慢闪烁并轻微漂移（[_StarsPainter]）；
///   2. 斜着向后退的文字（逐行仿射，见 [CrawlPainter]）；
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
    show
        LicenseEntry,
        LicenseRegistry,
        ValueListenable,
        ValueNotifier,
        visibleForTesting;
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
  late final AnimationController _anim;
  late final CrawlMusic _music = widget.music ?? AssetMusic();

  /// 当前爬到哪了，单位是「内容深度 dp」（0 = 片名正贴着屏幕上沿）。
  /// 用 ValueNotifier 直接驱动 [CrawlPainter] 重画，不走 setState —— 一帧
  /// 只重画几十行字，不重建整棵子树。
  final ValueNotifier<double> _position = ValueNotifier<double>(0);

  List<CrawlLine>? _lines;
  Object? _error;
  bool _playing = false;
  bool _musicOn = false;

  // 排版与几何按「屏幕尺寸 + 文案」缓存，热重载改了常量也能靠尺寸变化重建。
  CrawlPlaneGeometry? _geo;
  List<CrawlLineLayout>? _content;
  double _contentDepth = 0;
  int _layoutLinesStamp = -1;
  Size _layoutSize = Size.zero;

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

  /// 爬到头的位置：最后一行刚好爬出屏幕上沿，再多留 20% 屏高当尾巴。
  double get _maxPosition {
    final geo = _geo;
    if (geo == null || _contentDepth <= 0) return 0;
    final max = _contentDepth - geo.topDepth + geo.viewport * 0.2;
    return max < 0 ? 0 : max;
  }

  /// 按当前屏幕尺寸把文案排一遍（只在尺寸/文案变了时做）。
  void _ensureLayout(List<CrawlLine> lines, Size size, int stamp) {
    if (_content != null && _layoutSize == size && _layoutLinesStamp == stamp) {
      return;
    }
    _layoutSize = size;
    _layoutLinesStamp = stamp;
    _geo = CrawlPlaneGeometry(viewport: size.height);
    _content = layoutCrawlLines(lines, width: size.width);
    _contentDepth = _content!.isEmpty
        ? 0
        : _content!.last.depth + _content!.last.height;
  }

  /// 把动画进度映射成当前深度。
  void _follow() {
    final max = _maxPosition;
    if (max <= 0) return;
    _position.value = (_anim.value * max).clamp(0.0, max);
  }

  void _onDrag(DragUpdateDetails d) {
    final max = _maxPosition;
    if (max <= 0) return;
    if (_playing) {
      _anim.stop();
      setState(() => _playing = false);
    }
    // 手指往下拉 = 往回看。内容深度靠近端（屏幕下方）是 1:1，远处的字被
    // 透视压扁了，所以整体取 1.15 让「拉一下」在视觉上走得差不多。
    final next = (_position.value - d.delta.dy * 1.15).clamp(0.0, max);
    _position.value = next;
    _anim.value = max <= 0 ? 0 : next / max;
  }

  void _togglePlay() {
    if (_playing) {
      _anim.stop();
      setState(() => _playing = false);
      return;
    }
    if (_anim.value >= 1) {
      _anim.value = 0;
      _position.value = 0;
    }
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
    _position.dispose();
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
    final size = MediaQuery.sizeOf(context);
    _ensureLayout(lines, size, identityHashCode(lines));
    final geo = _geo!;
    final content = _content!;
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 🪤 不要退回「Transform 透视 + 整棵滚动子树」的老做法。
          // 2026-11-21 在这台模拟器（x86_64 + SwiftShader）上实测：
          //   · 不传 filterQuality：约三分之一的帧会甩出一大块黄白梯形（亮斑）
          //     盖住字幕 —— 用户报的「黄色/白色的异形」就是它；
          //   · 传 filterQuality：闪块没了，但 Impeller 把整棵子树先光栅化成
          //     一张图再采样，透视下这张图被画小、往中间缩（一屏的红块只盖住
          //     y=168..730dp），「没有占满整个屏幕」有一半是它造成的；
          //   · 再套 RepaintBoundary：更糟，整块黄白把右边三分之二的字都盖了。
          // 所以根治办法是**根本不用透视矩阵**：每行自己 translate + scale
          // 画（纯仿射，没有 layer、没有透视），闪块和缩水一起消失，字形还按
          // 最终尺寸光栅化，比采样那张大位图更清楚。几何全在
          // [CrawlPlaneGeometry] 里，和原来那套投影公式一一对应。
          RepaintBoundary(
            child: CustomPaint(
              painter: CrawlPainter(
                lines: content,
                position: _position,
                geometry: geo,
              ),
              size: Size.infinite,
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

/// 斜着往后退的角度（弧度）。0.52 ≈ 30°，接近片头那种「抬头看」的机位。
const double crawlTiltAngle = 0.52;

/// 远端（屏幕最上面那一行）的缩放。0.42 ≈ 远处的字还剩四成大小，
/// 再小就认不出字形、叠成一片；再大就没有景深、看着像贴纸。
const double crawlFarScale = 0.42;

/// 爬行平面的几何：平面该多高、相机多远、内容和屏幕怎么对位。
///
/// 透视投影（Transform 以底边中点为原点）下，平面上离底边 `u` 的点（向上为负）
/// 投到屏幕上离底边 `y = u·cosθ / (1 - k·u·sinθ)`，局部缩放是
/// `cosθ / (1 - k·u·sinθ)²`。u→-∞ 时 y 收敛到 `1/(k·tanθ)` —— **不管平面做
/// 多高，投影最多这么高**。所以「平面高度」不能拍脑袋写成几倍屏高：
///
/// 给定屏高 h、倾角 θ、屏幕最上面那一行的缩放 s，屏幕顶正好是平面顶时
///
///   P = h·w / cosθ，  w = √(cosθ / s)
///   k = (w - 1) / (P·sinθ)
///
/// 这时 1/(k·tanθ) = P·w > h，铺满一屏是够的，而且平面刚好一屏（不是两三倍），
/// 内容一进来就从屏幕最上面开始，不会跳过开头。
///
/// 早先的版本把平面写成 2.8 倍屏高、k/θ 又调过几轮，屏幕可见的其实只有平面
/// 底部约 1000dp，开头 1180dp 的内容永远在屏幕上沿之外（片名直接被吞掉）。
@visibleForTesting
class CrawlPlaneGeometry {
  CrawlPlaneGeometry({
    required this.viewport,
    this.angle = crawlTiltAngle,
    this.farScale = crawlFarScale,
  }) {
    final cosA = math.cos(angle);
    final sinA = math.sin(angle);
    final w = math.sqrt(cosA / farScale);
    _coverPlane = viewport * w / cosA;
    cameraK = (w - 1) / (_coverPlane * sinA);
    // 屏幕上沿对应平面上离底边多远（解 project(-x) = -viewport）。
    _topDepth = viewport / (cosA - viewport * cameraK * sinA);
  }

  /// 屏幕高度（逻辑像素）。
  final double viewport;

  /// 倾角，见 [crawlTiltAngle]。
  final double angle;

  /// 远端缩放，见 [crawlFarScale]。
  final double farScale;

  /// 透视强度（相机距离的倒数）。
  late final double cameraK;

  late final double _coverPlane;
  late final double _topDepth;

  /// 刚好从屏幕上沿铺到屏幕下沿的平面高度。
  double get coverPlane => _coverPlane;

  /// 屏幕上沿在平面上有多深（离平面底边的距离）。按这套参数它正好等于
  /// [coverPlane]：平面上从 0 到 topDepth 这一段，投影下来正好铺满一屏。
  double get topDepth => _topDepth;

  /// 平面上离底边 `u` 的点（向上为负）投到屏幕上离**底边**的距离。
  double project(double u) {
    final w = 1 - cameraK * u * math.sin(angle);
    return u * math.cos(angle) / w;
  }

  /// 平面上 `u` 那一行的局部缩放（近端是 cosθ）。
  double scaleAt(double u) {
    final w = 1 - cameraK * u * math.sin(angle);
    return math.cos(angle) / (w * w);
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
    // 🪤 这里曾经把下端的 colors 写反（`[透明, bg, bg]` + begin=bottomCenter），
    // 结果是「屏幕最底边透明、往上 300px 却是纯背景色」—— 字幕被一条硬邦邦的
    // 黑带从中间切断，下面还露出一截，用户 2026-11-21 报的「下方和上方断开」
    // 就是它。两端都必须写成「贴着屏幕边缘那一侧不透明、往里渐透明」。
    // 高度别贪大：这两层是不透明背景色，涂太多就等于把画面上下切掉，用户
    // 2026-11-21 抱怨的「高度没有占满」一多半是早先 22%+26% 的遮罩造成的。
    // 现在平面按几何刚好盖满一屏，遮罩只负责把「最远那几行」和「刚进画面
    // 的那一行」揉进黑暗里，上下各留一条薄边。
    final height = h * (top ? 0.09 : 0.06);
    const colors = [bg, bg, Color(0x0005060A)];
    final stops = top ? const [0.0, 0.35, 1.0] : const [0.0, 0.45, 1.0];
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

/// 空行（[CrawlKind.gap]）的高度。
const double crawlGapHeight = 18;

/// 一行字幕的字号、颜色和上边距。字号与颜色按 [CrawlLine.kind] 分。
///
/// 字号整体抬过一轮（用户 2026-11-20：「占屏幕位置太小了，做大点」）。
/// 透视会把上半部分缩掉，所以平面上的字号必须比「看着合适」再大一档。
(TextStyle, double) crawlLineStyle(CrawlKind kind) => switch (kind) {
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
    const TextStyle(color: Color(0xFFD7D9E0), fontSize: 19, height: 1.6),
    5.0,
  ),
  CrawlKind.gap => (const TextStyle(), 0.0),
};

/// 排好版的一行：文本、它在内容里有多深、它自己多高。
@visibleForTesting
class CrawlLineLayout {
  CrawlLineLayout({
    required this.painter,
    required this.depth,
    required this.height,
  });

  final TextPainter painter;

  /// 这一行顶部离内容开头的距离（平面上的 dp）。
  final double depth;

  /// 这一行自己的高度（平面上的 dp）。
  final double height;
}

/// 把剧本排成一条「内容深度 → 文本」的清单。
///
/// 只在排版时做一次：文本按自然宽高排好，之后由 [CrawlPainter] 每帧按透视
/// 缩放去画 —— 这样字形是按最终尺寸光栅化的，比「整块子树缩放后采样」清楚。
@visibleForTesting
List<CrawlLineLayout> layoutCrawlLines(
  List<CrawlLine> lines, {
  required double width,
}) {
  // 左右各留 26 的边距，和原来 Padding(26, …) 一致。
  final maxWidth = math.max(80.0, width - 52);
  var depth = 0.0;
  final out = <CrawlLineLayout>[];
  for (final line in lines) {
    if (line.kind == CrawlKind.gap) {
      depth += crawlGapHeight;
      continue;
    }
    final (style, top) = crawlLineStyle(line.kind);
    final painter = TextPainter(
      text: TextSpan(text: line.text, style: style),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);
    depth += top;
    out.add(
      CrawlLineLayout(painter: painter, depth: depth, height: painter.height),
    );
    depth += painter.height;
  }
  return out;
}

/// 逐行画爬行字幕：每一行只做「平移到该在的高度 + 缩放」。
///
/// 为什么不用 `Transform` 给整棵子树套透视矩阵：
///   · 那会把整块子树先光栅化成一张大图再采样，Impeller 在这台模拟器上
///     三分之一的帧会甩出一大块黄白梯形（用户 2026-11-21 报的「异形」）；
///   · 补 `filterQuality` 只是把那张图缩小了，几何跟着错（没占满屏）。
/// 逐行绘制只用仿射变换，没有 layer、没有透视，两个毛病一起没了。
@visibleForTesting
class CrawlPainter extends CustomPainter {
  CrawlPainter({
    required this.lines,
    required this.position,
    required this.geometry,
  }) : super(repaint: position);

  final List<CrawlLineLayout> lines;

  /// 当前深度（内容 dp，越大越往上）。
  final ValueListenable<double> position;

  final CrawlPlaneGeometry geometry;

  /// 这一帧该画的行，附带屏幕上的 y（行顶）和这一行的缩放。
  ///
  /// 单独抽出来是为了能单测「哪几行在画面里、落在哪」——像素没法稳定断言。
  @visibleForTesting
  List<CrawlVisibleLine> visibleLines(Size size) {
    final h = size.height;
    final now = position.value;
    final out = <CrawlVisibleLine>[];
    for (final line in lines) {
      // u < 0 = 比平面底边更远（更靠屏幕上方）；u > 0 = 还没进画面。
      final uTop = line.depth - now - geometry.topDepth;
      if (uTop > 0) break;
      final y = h + geometry.project(uTop);
      final scale = geometry.scaleAt(uTop + line.height / 2);
      if (y + line.height * scale < 0) continue;
      out.add(CrawlVisibleLine(line, y, scale));
      if (y > h) break;
    }
    return out;
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (final visible in visibleLines(size)) {
      final painter = visible.line.painter;
      canvas.save();
      canvas.translate(size.width / 2, visible.y);
      canvas.scale(visible.scale);
      painter.paint(canvas, Offset(-painter.width / 2, 0));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(CrawlPainter old) =>
      old.lines != lines ||
      old.position != position ||
      old.geometry != geometry;
}

/// [CrawlPainter.visibleLines] 的结果：一行 + 它在屏幕上的位置与缩放。
@visibleForTesting
class CrawlVisibleLine {
  const CrawlVisibleLine(this.line, this.y, this.scale);

  final CrawlLineLayout line;

  /// 这一行顶部在屏幕上的 y。
  final double y;

  /// 这一行的缩放（近端 ≈ cosθ，远端 = [crawlFarScale]）。
  final double scale;
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
