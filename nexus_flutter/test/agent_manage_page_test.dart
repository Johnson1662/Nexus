import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:nexus_flutter/pages/agent_manage_page.dart';
import 'package:nexus_flutter/providers/chat_provider.dart';
import 'package:nexus_flutter/services/ws_client.dart';

void main() {
  testWidgets('AgentManagePage renders clean terminal-style agent integrations', (WidgetTester tester) async {
    final ws = WSClient();
    final chatProvider = ChatProvider(ws);

    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<ChatProvider>.value(
          value: chatProvider,
          child: const AgentManagePage(),
        ),
      ),
    );

    // Verify header and subtitle matching Image #1
    expect(find.text('settings'), findsOneWidget);
    expect(find.text('integrations'), findsOneWidget);
    expect(find.text('agent integrations'), findsOneWidget);
    expect(find.textContaining('let agents report state directly'), findsOneWidget);

    // Verify presence of default agent identifiers
    expect(find.text('omp'), findsOneWidget);
    expect(find.text('codex'), findsOneWidget);
    expect(find.text('claude'), findsOneWidget);

    // Verify footer
    expect(find.text('esc close'), findsOneWidget);
  });
}
