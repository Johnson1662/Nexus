import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../lib/constants/theme.dart';
import '../lib/pages/settings_page.dart';
import '../lib/services/host_store.dart';
import '../lib/widgets/markdown_renderer.dart';

void main() {
  testWidgets('Markdown body uses dark foreground in dark mode', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(
          body: AppMarkdownRenderer(data: 'dark text'),
        ),
      ),
    );

    expect(find.text('dark text'), findsOneWidget);
  });

  testWidgets('manual host dialog accepts an optional token', (tester) async {
    final hostStore = HostStore();
    hostStore.devices.clear();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ChangeNotifierProvider<HostStore>.value(
          value: hostStore,
          child: const SettingsPage(),
        ),
      ),
    );
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();

    final tokenField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.decoration?.labelText == 'Token',
    );
    expect(tokenField, findsOneWidget);
    expect(tester.widget<TextField>(tokenField).obscureText, isTrue);

    await tester.enterText(tokenField, 'bridge-secret');
    expect(tester.widget<TextField>(tokenField).controller?.text,
        'bridge-secret');

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
  });
}
