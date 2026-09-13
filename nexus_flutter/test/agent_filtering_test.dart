import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_flutter/models/ws_protocol.dart';
import 'package:nexus_flutter/providers/chat_provider.dart';
import 'package:nexus_flutter/services/ws_client.dart';

/// Fixture: one agent usable on both backends, one disabled, one whose Herdr
/// backend is not ready.
HostCapabilities _caps() => const HostCapabilities(
      platform: 'linux',
      arch: 'x64',
      git: GitCapability(available: true),
      herdr: HerdrCapability(available: true),
      agents: [
        AgentRuntimeCapability(
          id: 'omp',
          name: 'Oh My Pi (OMP)',
          enabled: true,
          native: AgentNativeCapability(supported: true, ready: true),
          herdr: AgentHerdrCapability(supported: true, ready: true, kind: 'omp', integrationId: 'omp', integrationInstalled: true),
        ),
        AgentRuntimeCapability(
          id: 'disabled-agent',
          name: 'Disabled',
          enabled: false,
          native: AgentNativeCapability(supported: true, ready: true),
          herdr: AgentHerdrCapability(supported: true, ready: true),
        ),
        AgentRuntimeCapability(
          id: 'native-only',
          name: 'Native Only',
          enabled: true,
          native: AgentNativeCapability(supported: true, ready: true),
          herdr: AgentHerdrCapability(supported: true, ready: false),
        ),
      ],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('enabledHerdrAgents and enabledNativeAgents filter independently', () {
    final provider = ChatProvider(WSClient());
    provider.handleMessageForTest(
      ServerMessage(type: 'host_capabilities', hostCapabilities: _caps()),
    );

    expect(
      provider.enabledHerdrAgents.map((a) => a.id).toList(),
      ['omp'],
      reason: 'a disabled agent and a not-ready Herdr backend are both excluded',
    );
    expect(
      provider.enabledNativeAgents.map((a) => a.id).toList(),
      ['omp', 'native-only'],
      reason: 'native readiness does not depend on Herdr readiness',
    );
  });

  test('capabilityFor resolves an agent by id and reports null when unknown', () {
    final provider = ChatProvider(WSClient());
    provider.handleMessageForTest(
      ServerMessage(type: 'host_capabilities', hostCapabilities: _caps()),
    );

    expect(provider.capabilityFor('omp')?.herdr.kind, 'omp');
    expect(provider.capabilityFor('omp')?.native.ready, isTrue);
    expect(provider.integrationFor('omp'), isNull, reason: 'no integration list received yet');
    expect(provider.capabilityFor('missing'), isNull);
  });

  test('disabling an agent removes it from both backend lists', () {
    final provider = ChatProvider(WSClient());
    provider.handleMessageForTest(
      ServerMessage(
        type: 'host_capabilities',
        hostCapabilities: const HostCapabilities(
          platform: 'linux',
          arch: 'x64',
          git: GitCapability(available: true),
          herdr: HerdrCapability(available: true),
          agents: [
            AgentRuntimeCapability(
              id: 'omp',
              name: 'OMP',
              enabled: false,
              native: AgentNativeCapability(supported: true, ready: true),
              herdr: AgentHerdrCapability(supported: true, ready: true),
            ),
          ],
        ),
      ),
    );

    expect(provider.enabledHerdrAgents, isEmpty);
    expect(provider.enabledNativeAgents, isEmpty);
    expect(provider.state.agentNames, isEmpty);
  });
}
