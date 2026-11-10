// 拷打造句批改结果卡的 smoke：纯 widget，不需要 Provider / SQLite。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dlaoshi_app/core/writing.dart';
import 'package:dlaoshi_app/views/drill_sentence_feedback.dart';

void main() {
  testWidgets('DrillFeedbackCard 能渲染分数与维度 chip', (tester) async {
    const feedback = WritingFeedback(
      total: 8,
      max: 10,
      scores: <WritingScore>[
        WritingScore(dimension: '结构', score: 4, max: 5),
        WritingScore(dimension: '用词', score: 4, max: 5),
      ],
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: DrillFeedbackCard(feedback: feedback))),
      ),
    );
    await tester.pump();

    expect(find.text('批改：8/10'), findsOneWidget);
    expect(find.text('结构 4/5'), findsOneWidget);
    expect(find.text('用词 4/5'), findsOneWidget);
  });
}
