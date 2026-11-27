import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:malvifactor/main.dart';

void main() {
  testWidgets('MalviFactorApp builds cleanly', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: MalviFactorApp()));
    expect(find.byType(MalviFactorApp), findsOneWidget);
  });
}
