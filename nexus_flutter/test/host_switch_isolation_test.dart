import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_flutter/models/message_data.dart';
import 'package:nexus_flutter/models/ws_protocol.dart';
import 'package:nexus_flutter/providers/chat_provider.dart';
import 'package:nexus_flutter/services/ws_client.dart';

HostCapabilities _capsFor(String hostId) => HostCapabilities(
      platform: 'linux',
      arch: 'x64',
      git: GitCapability(available: true),
      herdr: HerdrCapability(available: hostId == 'host-a'),
      agents: [
        AgentRuntimeCapability(
          id: 'omp',
          name: 'OMP',
          enabled: true,
          native: AgentNativeCapability(supported: true, ready: true),
          herdr: AgentHerdrCapability(
            supported: true,
            ready: hostId == 'host-a',
            kind: 'omp',
          ),
        ),
      ],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('switching host clears every host-scoped field', () {
    final provider = ChatProvider(WSClient());

    // Host A: capabilities, sessions, agent metadata, model state, workspace.
    provider.handleMessageForTest(ServerMessage(
      type: 'server_info',
      hostId: 'host-a',
      hostname: 'Host A',
    ));
    provider.handleMessageForTest(ServerMessage(
      type: 'host_capabilities',
      hostId: 'host-a',
      hostCapabilities: _capsFor('host-a'),
    ));
    provider.handleMessageForTest(ServerMessage(
      type: 'session_list',
      sessions: [ServerSessionData(sessionId: 's1', title: 'A session')],
    ));
    provider.state.models = [ModelItem(modelId: 'm1', name: 'M1')];
    provider.state.modes = [ModeItem(value: 'mode1', name: 'Mode 1')];
    provider.state.currentWorkspace = '/home/a/project';
    provider.state.messages = [MessageData(id: 'msg1', role: 'user', content: 'hi')];

    expect(provider.state.hostCapabilities, isNotNull, reason: 'host A capabilities loaded');
    expect(provider.state.sessions, hasLength(1), reason: 'host A sessions loaded');
    expect(provider.state.messages, isNotEmpty, reason: 'host A messages present');

    // Switch to host B.
    provider.handleMessageForTest(ServerMessage(
      type: 'server_info',
      hostId: 'host-b',
      hostname: 'Host B',
    ));

    expect(provider.state.hostCapabilities, isNull, reason: 'capabilities must not leak across hosts');
    expect(provider.state.sessions, isEmpty, reason: 'sessions must not leak across hosts');
    expect(provider.state.messages, isEmpty, reason: 'messages must not leak across hosts');
    expect(provider.state.models, isEmpty, reason: 'models must not leak across hosts');
    expect(provider.state.modes, isEmpty, reason: 'modes must not leak across hosts');
    expect(provider.state.currentWorkspace, isEmpty, reason: 'workspace must not leak across hosts');
    expect(provider.state.agentNames, isEmpty, reason: 'agent list must not leak across hosts');
    expect(provider.state.selectedAgentName, isEmpty);
    expect(provider.state.currentDeviceId, 'host-b');
  });

  test('a capability reply naming another host is ignored', () {
    final provider = ChatProvider(WSClient());

    provider.handleMessageForTest(ServerMessage(
      type: 'server_info',
      hostId: 'host-b',
      hostname: 'Host B',
    ));

    // Late reply from the previous host.
    provider.handleMessageForTest(ServerMessage(
      type: 'host_capabilities',
      hostId: 'host-a',
      hostCapabilities: _capsFor('host-a'),
    ));

    expect(
      provider.state.hostCapabilities,
      isNull,
      reason: 'a stale host snapshot must not repopulate capabilities',
    );
  });

  test('effective backend is recomputed for the newly connected host', () {
    final provider = ChatProvider(WSClient());
    provider.handleMessageForTest(ServerMessage(
      type: 'server_info',
      hostId: 'host-a',
      hostname: 'Host A',
    ));
    provider.handleMessageForTest(ServerMessage(
      type: 'host_capabilities',
      hostId: 'host-a',
      hostCapabilities: _capsFor('host-a'),
    ));
    expect(provider.effectiveBackend, 'native', reason: 'defaults to native without a preference');

    // Host B has no Herdr; a preference for herdr would degrade here, so verify
    // the capability set is what decides, not leftover state from host A.
    provider.handleMessageForTest(ServerMessage(
      type: 'server_info',
      hostId: 'host-b',
      hostname: 'Host B',
    ));
    expect(provider.state.hostCapabilities, isNull);
    expect(provider.effectiveBackend, 'native');
  });
}
