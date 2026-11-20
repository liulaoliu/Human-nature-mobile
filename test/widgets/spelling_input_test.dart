import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dlaoshi_app/widgets/english_input.dart';
import 'package:dlaoshi_app/widgets/spelling_input.dart';

/// 34.3 / 34.4 的守护用例：拼写输入框的键盘口径与尺寸口径。
///
/// 这两条都是「三处输入框要一致」的要求（卡面拼写 / 组末拼写 / 锤炼拼写）。
/// 以前三处各写一个 `TextField`，配置就散了：卡面设了 `visiblePassword` 但没关
/// 自动大写，组末那处连 `keyboardType` 都没配 —— 于是「输入 reve 弹 revenge」
/// 只在其中一处复现。现在统一走 [SpellingInput]，这里锁住它的口径。
void main() {
  Future<TextField> pumpInput(
    WidgetTester tester, {
    TextEditingController? controller,
    bool enabled = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SpellingInput(
            controller: controller,
            hintText: '拼出这个英文单词，回车检查',
            enabled: enabled,
            onChanged: (_) {},
            onSubmitted: (_) {},
          ),
        ),
      ),
    );
    return tester.widget<TextField>(find.byType(TextField));
  }

  group('键盘（34.3）', () {
    testWidgets('拉丁键盘 + 关联想 + 不纠错', (tester) async {
      final TextField field = await pumpInput(tester);
      expect(field.keyboardType, englishKeyboard);
      expect(field.autocorrect, englishAutocorrect);
      expect(field.enableSuggestions, englishSuggestions);
      expect(field.keyboardType, TextInputType.visiblePassword);
    });

    testWidgets('不自动首字母大写、不做智能标点替换', (tester) async {
      final TextField field = await pumpInput(tester);
      expect(
        field.textCapitalization,
        TextCapitalization.none,
        reason: '首字母被自动大写，拼写判分虽然大小写不敏感，但用户看到的字是错的',
      );
      expect(field.smartDashesType, SmartDashesType.disabled);
      expect(field.smartQuotesType, SmartQuotesType.disabled);
    });

    testWidgets('回车就是交卷（done）', (tester) async {
      final TextField field = await pumpInput(tester);
      expect(field.textInputAction, TextInputAction.done);
    });

    testWidgets('禁用时不再是可编辑状态（锤炼拼错后锁住）', (tester) async {
      final TextField field = await pumpInput(tester, enabled: false);
      expect(field.enabled, isFalse);
    });
  });

  group('尺寸（34.4）', () {
    testWidgets('字号 ≥ 28sp、居中、无外框', (tester) async {
      final TextField field = await pumpInput(tester);
      final double? size = field.style?.fontSize;
      expect(size, isNotNull);
      expect(
        size!,
        greaterThanOrEqualTo(28),
        reason: '360dp 宽的屏幕上要肉眼明显大于正文（34.4 验收）',
      );
      expect(field.textAlign, TextAlign.center);
      final InputDecoration deco = field.decoration!;
      expect(deco.border, InputBorder.none);
      expect(deco.enabledBorder, InputBorder.none);
      expect(deco.focusedBorder, InputBorder.none);
      expect(
        deco.contentPadding,
        const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      );
    });

    testWidgets('点击命中高度 ≥ 56dp', (tester) async {
      await pumpInput(tester);
      final Size box = tester.getSize(find.byType(TextField));
      expect(
        box.height,
        greaterThanOrEqualTo(56),
        reason: '34.4 验收：点击输入区域命中范围 ≥ 56dp',
      );
    });

    testWidgets('长单词不换行：maxLines 保持 1', (tester) async {
      final TextField field = await pumpInput(tester);
      expect(field.maxLines, 1);
    });

    testWidgets('无外框时靠底色区分输入区', (tester) async {
      final TextField field = await pumpInput(tester);
      final InputDecoration deco = field.decoration!;
      expect(deco.filled, isTrue);
      expect(deco.fillColor, isNotNull);
    });
  });

  group('三处都走同一个组件', () {
    testWidgets('组末拼写能用外部 controller 清空', (tester) async {
      final TextEditingController controller = TextEditingController();
      addTearDown(controller.dispose);
      await pumpInput(tester, controller: controller);
      await tester.enterText(find.byType(TextField), 'alpha');
      expect(controller.text, 'alpha');
      controller.clear();
      await tester.pump();
      expect(find.text('alpha'), findsNothing);
    });
  });
}
