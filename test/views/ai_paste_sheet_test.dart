// 「拼提示词 → 复制 → 粘回结果」面板的 smoke：纯 widget，不需要 Provider / SQLite。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dlaoshi_app/views/ai_paste_sheet.dart';

void main() {
  testWidgets('AiPasteSheet 能渲染，提示词与「应用」文案都在', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiPasteSheet(
            title: '查词面板',
            prompt: '请分析这段英文',
            hint: '粘回 v2 JSON',
            onApply: (String raw) async => null,
          ),
        ),
      ),
    );
    await tester.pump();

    // 标题来自构造参数，其余是该面板特有的固定文案。
    expect(find.text('查词面板'), findsOneWidget);
    expect(find.text('复制提示词'), findsOneWidget);
    expect(find.text('请分析这段英文'), findsOneWidget);
    expect(find.text('把 AI 的结果粘到这里'), findsOneWidget);
    expect(find.text('粘回 v2 JSON'), findsOneWidget);
    expect(find.text('应用'), findsOneWidget);
  });
}
