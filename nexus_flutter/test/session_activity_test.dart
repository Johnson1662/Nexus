import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/constants/theme.dart';
import '../lib/models/ws_protocol.dart';
import '../lib/widgets/session_tile.dart';

void main() {
  group('ServerSessionData — lastActivity', () {
    test('parses lastActivity from JSON', () {
      final s = ServerSessionData.fromJson({
        'sessionId': 's1',
        'title': 'Chat',
        'agent': 'codex',
        'cwd': '/home/proj',
        'createdAt': 1000,
        'lastActivity': 2000,
        'status': 'running',
      });

      expect(s.lastActivity, 2000);
      expect(s.title, 'Chat');
      expect(s.agent, 'codex');
      expect(s.cwd, '/home/proj');
    });

    test('allows absent lastActivity (null)', () {
      final s = ServerSessionData.fromJson({
        'sessionId': 's2',
        'createdAt': 1000,
      });

      expect(s.lastActivity, isNull);
      expect(s.createdAt, 1000);
    });
  });

  group('SessionTile activity state', () {
    Future<void> pumpTile(
      WidgetTester tester, {
      required String status,
      required int lastActivity,
    }) {
      return tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: SessionTile(
              session: ServerSessionData(
                sessionId: 's1',
                title: 'Chat',
                agent: 'codex',
                createdAt: lastActivity,
                lastActivity: lastActivity,
                status: status,
              ),
              onTap: () {},
            ),
          ),
        ),
      );
    }

    testWidgets('shows running status', (tester) async {
      await pumpTile(
        tester,
        status: 'running',
        lastActivity: DateTime.now().millisecondsSinceEpoch,
      );

      expect(find.text('进行中'), findsOneWidget);
      expect(find.text('Chat'), findsOneWidget);
    });

    testWidgets('shows waiting-input status', (tester) async {
      await pumpTile(
        tester,
        status: 'waiting_input',
        lastActivity: DateTime.now().millisecondsSinceEpoch,
      );

      expect(find.text('等待输入'), findsOneWidget);
      expect(find.text('进行中'), findsNothing);
    });
  });
}
