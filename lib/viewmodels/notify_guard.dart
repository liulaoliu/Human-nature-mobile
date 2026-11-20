import 'package:flutter/foundation.dart';

/// 给 ViewModel 加一道「销毁后不再通知」的护栏。
///
/// 为什么需要：判分 / 落盘这类操作一旦改成「界面先出结果、写盘在背后跑」
/// （34.1），写盘收尾的回调就可能晚于页面销毁。那时再 `notifyListeners()`
/// 会抛「A ChangeNotifier was used after being disposed」。
///
/// 用 mixin 而不是在每个 ViewModel 里重复写 `_disposed` 字段 + 两个 override：
/// - 重复写会让上帝类体检（`tool/check_god_class.dart`）把这两个 override
///   也算进方法数（`StudyViewModel` 因此一度 42 > 40）；
/// - 语义本来就一样，抽出来后每处只要 `with NotifyGuard` 一行。
///
/// 用法：
/// ```dart
/// class FooViewModel extends ChangeNotifier with NotifyGuard {
///   ...
/// }
/// ```
///
/// `dispose()` 由本 mixin 接管（标记 + 转发给 `ChangeNotifier`），所以子类
/// **不用再写一层 override** —— 少一个方法就少占一个上帝类体检的名额
/// （`StudyViewModel` 正是卡在 41 > 40 上）。真有别的清理要做时再 override：
/// ```dart
/// @override
/// void dispose() {
///   _timer?.cancel();
///   super.dispose();   // 走到本 mixin，标记 + 转给 ChangeNotifier
/// }
/// ```
mixin NotifyGuard on ChangeNotifier {
  bool _disposed = false;

  /// 已经销毁了。
  bool get isDisposed => _disposed;

  /// 在 `dispose()` 里、`super.dispose()` 之前调（override 了 dispose 的地方）。
  void markDisposed() {
    _disposed = true;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }
}