import 'package:flutter_test/flutter_test.dart';

import 'package:dlaoshi_app/main.dart';

void main() {
  testWidgets('首页三条入口都在，未接通的标「开发中」', (tester) async {
    await tester.pumpWidget(const DlaoshiApp());

    expect(find.text('精读'), findsOneWidget);
    expect(find.text('背单词'), findsOneWidget);
    expect(find.text('产出训练'), findsOneWidget);

    // 一期还没接通，三个入口都必须是「开发中」，不许出现可点的假按钮。
    expect(find.text('开发中'), findsNWidgets(3));
  });
}
