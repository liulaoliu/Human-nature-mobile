import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dlaoshi_app/widgets/status_bar.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('error() 用红底、不可关，文字就是传入的 message', (tester) async {
    await tester.pumpWidget(wrap(const StatusBar.error(message: '存不进去')));

    expect(find.text('存不进去'), findsOneWidget);
    expect(find.byType(IconButton), findsNothing);
    final container = tester.widget<Container>(find.byType(Container).first);
    final scheme = Theme.of(tester.element(find.text('存不进去'))).colorScheme;
    expect(container.color, scheme.errorContainer);
  });

  testWidgets('notice() 可关，点叉触发 onClose', (tester) async {
    var closed = 0;
    await tester.pumpWidget(wrap(StatusBar.notice(
      message: '已暂停，下次接着做',
      onClose: () => closed++,
    )));

    expect(find.text('已暂停，下次接着做'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);
    final container = tester.widget<Container>(find.byType(Container).first);
    final scheme =
        Theme.of(tester.element(find.text('已暂停，下次接着做'))).colorScheme;
    expect(container.color, scheme.secondaryContainer);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(closed, 1);
  });
}
