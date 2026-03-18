import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spark/main.dart';

void main() {
  testWidgets('Spark app starts', (WidgetTester tester) async {
    await tester.pumpWidget(const SparkApp());
    await tester.pumpAndSettle();
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
