import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/models/ws_protocol.dart';
import '../lib/providers/chat_provider.dart';
import '../lib/services/notification_service.dart';
import '../lib/services/ws_client.dart';

ServerMessage _modelMessage(int sequence) => ServerMessage(
      type: 'model_list',
      messageId: 'session:$sequence',
      models: [
        ModelItem(modelId: 'model-$sequence', name: 'Model $sequence'),
      ],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    NotificationService.onPermissionAction = null;
  });

  tearDown(() {
    NotificationService.onPermissionAction = null;
  });

  test('同一 WS 的 Provider 可独立解绑监听', () {
    final ws = WSClient();
    final provider1 = ChatProvider(ws);
    final provider2 = ChatProvider(ws);

    ws.debugDispatch(_modelMessage(1));
    expect(provider1.state.models.single.id, 'model-1');
    expect(provider2.state.models.single.id, 'model-1');

    provider1.dispose();
    ws.debugDispatch(_modelMessage(2));
    expect(provider1.state.models.single.id, 'model-1');
    expect(provider2.state.models.single.id, 'model-2');

    provider2.dispose();
    ws.dispose();
  });

  test('每条消息只通知仍存活的 Provider 一次', () {
    final ws = WSClient();
    final provider1 = ChatProvider(ws);
    final provider2 = ChatProvider(ws);
    var provider1Notifications = 0;
    var provider2Notifications = 0;
    provider1.addListener(() => provider1Notifications++);
    provider2.addListener(() => provider2Notifications++);

    ws.debugDispatch(_modelMessage(1));
    ws.debugDispatch(_modelMessage(2));
    expect(provider1Notifications, 2);
    expect(provider2Notifications, 2);

    provider1.dispose();
    ws.debugDispatch(_modelMessage(3));
    expect(provider1Notifications, 2);
    expect(provider2Notifications, 3);

    provider2.dispose();
    ws.dispose();
  });

  test('原生权限动作只进入当前 Provider', () {
    final ws = WSClient();
    final provider1 = ChatProvider(ws);
    provider1.state.pendingPermissions['request-1'] = PendingPermission(
      requestId: 'request-1',
      toolCall: 'tool-1',
      options: const [],
    );
    var provider1Notifications = 0;
    provider1.addListener(() => provider1Notifications++);

    final provider2 = ChatProvider(ws);
    provider2.state.pendingPermissions['request-2'] = PendingPermission(
      requestId: 'request-2',
      toolCall: 'tool-2',
      options: const [],
    );
    var provider2Notifications = 0;
    provider2.addListener(() => provider2Notifications++);
    final provider2Action = NotificationService.onPermissionAction;

    provider1.dispose();
    expect(NotificationService.onPermissionAction, same(provider2Action));

    NotificationService.onPermissionAction!.call('request-2', false);
    expect(provider1.state.pendingPermissions, contains('request-1'));
    expect(provider1Notifications, 0);
    expect(provider2.state.pendingPermissions, isEmpty);
    expect(provider2Notifications, 1);

    provider2.dispose();
    expect(NotificationService.onPermissionAction, isNull);
    ws.dispose();
  });

  test('dispose 首次调用不抛异常，解绑器可重复调用', () {
    final ws = WSClient();
    final disposers = <ListenerDisposer>[
      ws.onMessage((_) {}),
      ws.onStateChange((_, __) {}),
      ws.onServerInfo(() {}),
      ws.onAgentList((_) {}),
      ws.onError((_) {}),
      ws.onRegistryList((_) {}),
      ws.onPhaseChange((_) {}),
    ];
    final provider = ChatProvider(ws);

    expect(() => provider.dispose(), returnsNormally);
    for (final dispose in disposers) {
      expect(() => dispose(), returnsNormally);
      expect(() => dispose(), returnsNormally);
    }

    ws.dispose();
  });
}
