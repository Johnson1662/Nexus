import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:nexus_flutter/models/ws_protocol.dart';
import 'package:nexus_flutter/pages/agent_manage_page.dart';
import 'package:nexus_flutter/providers/chat_provider.dart';
import 'package:nexus_flutter/services/ws_client.dart';

void main() {
  test('AgentNativeCapability deserializes hook fields', () {
    final cap = AgentNativeCapability.fromJson({
      'supported': true,
      'ready': true,
      'executable': '/usr/bin/omp',
      'hookSupported': true,
      'hookInstalled': true,
      'hookDescription': 'Nexus Ambient Extension',
    });

    expect(cap.supported, true);
    expect(cap.ready, true);
    expect(cap.executable, '/usr/bin/omp');
    expect(cap.hookSupported, true);
    expect(cap.hookInstalled, true);
    expect(cap.hookDescription, 'Nexus Ambient Extension');
  });

  testWidgets('AgentManagePage in Native mode renders CLI detection and Hook install action', (tester) async {
    final ws = WSClient();
    final provider = ChatProvider(ws);

    ClientMessage? lastSent;
    ws.onSendForTest = (msg) => lastSent = msg;

    provider.state.registryAgents = [
      RegistryAgentInfo.fromJson({
        'id': 'omp',
        'name': 'Oh My Pi (OMP)',
        'description': 'ACP coding agent',
      }),
      RegistryAgentInfo.fromJson({
        'id': 'opencode',
        'name': 'OpenCode',
        'description': 'OpenCode agent',
      }),
    ];

    provider.state.hostCapabilities = HostCapabilities(
      platform: 'linux',
      arch: 'x64',
      git: const GitCapability(available: true),
      herdr: const HerdrCapability(available: false, transport: 'cli'),
      agents: [
        const AgentRuntimeCapability(
          id: 'omp',
          name: 'Oh My Pi (OMP)',
          enabled: false,
          native: AgentNativeCapability(
            supported: true,
            ready: true,
            executable: '/usr/local/bin/omp',
            hookSupported: true,
            hookInstalled: false,
            hookDescription: '环境会话接入',
          ),
          herdr: AgentHerdrCapability(
            supported: true,
            ready: false,
            integrationState: 'not installed',
          ),
        ),
        const AgentRuntimeCapability(
          id: 'opencode',
          name: 'OpenCode',
          enabled: false,
          native: AgentNativeCapability(
            supported: true,
            ready: true,
            executable: '/usr/local/bin/opencode',
            hookSupported: false,
            hookInstalled: false,
          ),
          herdr: AgentHerdrCapability(
            supported: true,
            ready: false,
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<ChatProvider>.value(
          value: provider,
          child: const AgentManagePage(),
        ),
      ),
    );

    // In Native mode:
    // 1. Should show CLI detected path
    expect(find.textContaining('已检测到 CLI (/usr/local/bin/omp)'), findsOneWidget);
    expect(find.textContaining('已检测到 CLI (/usr/local/bin/opencode)'), findsOneWidget);

    // 2. OMP should show Hook status and install button
    expect(find.textContaining('Hook: 未安装'), findsOneWidget);
    final installHookBtn = find.text('安装 Hook');
    expect(installHookBtn, findsOneWidget);

    // 3. OpenCode has no hook, should display native ACP
    expect(find.text('通信方式: 原生 ACP 协议 (无需 Hook)'), findsOneWidget);

    // 4. Tap "安装 Hook" sends install_native_hook
    await tester.tap(installHookBtn);
    await tester.pump();
    expect(lastSent?.type, 'install_native_hook');
    expect(lastSent?.agentId, 'omp');
  });

  testWidgets('AgentManagePage in Herdr mode renders Herdr integration status', (tester) async {
    final ws = WSClient();
    final provider = ChatProvider(ws);

    provider.setUseHerdrBackend(true);

    provider.state.registryAgents = [
      RegistryAgentInfo.fromJson({
        'id': 'omp',
        'name': 'Oh My Pi (OMP)',
        'description': 'ACP coding agent',
      }),
    ];

    provider.state.hostCapabilities = HostCapabilities(
      platform: 'linux',
      arch: 'x64',
      git: const GitCapability(available: true),
      herdr: const HerdrCapability(available: true, transport: 'cli'),
      agents: [
        const AgentRuntimeCapability(
          id: 'omp',
          name: 'Oh My Pi (OMP)',
          enabled: false,
          native: AgentNativeCapability(
            supported: true,
            ready: true,
            executable: '/usr/local/bin/omp',
            hookSupported: true,
            hookInstalled: false,
          ),
          herdr: AgentHerdrCapability(
            supported: true,
            ready: true,
            integrationId: 'omp',
            integrationState: 'not installed',
          ),
        ),
      ],
    );

    provider.state.herdrIntegrations = [
      {'target': 'omp', 'state': 'not installed'},
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<ChatProvider>.value(
          value: provider,
          child: const AgentManagePage(),
        ),
      ),
    );

    // In Herdr mode:
    expect(find.textContaining('Herdr 就绪'), findsOneWidget);
    expect(find.text('Herdr 集成: not installed'), findsOneWidget);
    expect(find.text('安装 Herdr 集成'), findsOneWidget);
    // Should NOT show native hook labels in Herdr mode
    expect(find.text('安装 Hook'), findsNothing);
  });
}
