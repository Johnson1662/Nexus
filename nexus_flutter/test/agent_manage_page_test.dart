import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:nexus_flutter/pages/agent_manage_page.dart';
import 'package:nexus_flutter/models/ws_protocol.dart';
import 'package:nexus_flutter/providers/chat_provider.dart';
import 'package:nexus_flutter/services/ws_client.dart';

void main() {
  testWidgets('AgentManagePage renders mobile native agent integrations settings', (WidgetTester tester) async {
    final ws = WSClient();
    final chatProvider = ChatProvider(ws);
    chatProvider.state.registryAgents = [
      RegistryAgentInfo.fromJson({
        'id': 'omp',
        'name': 'Oh My Pi (OMP)',
        'description': 'ACP coding agent',
      }),
      RegistryAgentInfo.fromJson({
        'id': 'codex',
        'name': 'Codex CLI',
        'description': 'Codex terminal agent',
      }),
      RegistryAgentInfo.fromJson({
        'id': 'claude',
        'name': 'Claude Code',
        'description': 'Claude Code agent',
      }),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<ChatProvider>.value(
          value: chatProvider,
          child: const AgentManagePage(),
        ),
      ),
    );

    // Verify native mobile AppBar and description banner
    expect(find.text('Agent 集成'), findsOneWidget);
    expect(find.textContaining('可选集成'), findsOneWidget);

    // Verify presence of default agents
    expect(find.text('Oh My Pi (OMP)'), findsOneWidget);
    expect(find.text('Codex CLI'), findsOneWidget);
    expect(find.text('Claude Code'), findsOneWidget);
  });
}
