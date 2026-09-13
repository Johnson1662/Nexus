import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_flutter/models/ws_protocol.dart';
import 'package:nexus_flutter/providers/chat_provider.dart';
import 'package:nexus_flutter/services/ws_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Parallel fileDiff and fileLog on same file do not cancel each other', () {
    final ws = WSClient();
    final provider = ChatProvider(ws);

    ClientMessage? lastSent;
    ws.onSendForTest = (msg) => lastSent = msg;

    // 1. Request diff for a.ts -> records diff_1
    provider.requestFileDiff('a.ts');
    final diffReqId = lastSent?.requestId;
    expect(diffReqId, startsWith('diff_'));

    // 2. Before diff returns, request commit history for a.ts -> records log_1
    provider.requestFileLog('a.ts');
    final logReqId = lastSent?.requestId;
    expect(logReqId, startsWith('log_'));

    // 3. Server finishes diff first and replies with diff_1
    provider.handleMessageForTest(ServerMessage(
      type: 'file_diff',
      path: 'a.ts',
      diff: '+line 1\n+line 2',
      requestId: diffReqId,
    ));

    // Both the diff and selected file must be preserved
    expect(provider.state.fileDiff, '+line 1\n+line 2');
    expect(provider.state.selectedFilePath, 'a.ts');

    // 4. Server finishes log next and replies with log_1
    provider.handleMessageForTest(ServerMessage(
      type: 'file_log',
      path: 'a.ts',
      logEntries: [
        {'hash': 'abc', 'message': 'initial'}
      ],
      requestId: logReqId,
    ));

    // Both diff and log are preserved!
    expect(provider.state.fileDiff, '+line 1\n+line 2');
    expect(provider.state.fileLogEntries.length, 1);
    expect(provider.state.fileLogEntries.first['hash'], 'abc');
  });

  test('Fast file switch discards slow response from previous file', () {
    final ws = WSClient();
    final provider = ChatProvider(ws);

    ClientMessage? lastSent;
    ws.onSendForTest = (msg) => lastSent = msg;

    // 1. User clicks a.ts -> diff_1
    provider.requestFileDiff('a.ts');
    final reqA = lastSent?.requestId;

    // 2. User immediately clicks b.ts -> diff_2
    provider.requestFileDiff('b.ts');
    final reqB = lastSent?.requestId;
    expect(reqA != reqB, true);

    // 3. Slow response for a.ts arrives
    provider.handleMessageForTest(ServerMessage(
      type: 'file_diff',
      path: 'a.ts',
      diff: '+diff for a',
      requestId: reqA,
    ));

    // Must be discarded!
    expect(provider.state.selectedFilePath, 'b.ts');
    expect(provider.state.fileDiff, isNull);

    // 4. Response for b.ts arrives
    provider.handleMessageForTest(ServerMessage(
      type: 'file_diff',
      path: 'b.ts',
      diff: '+diff for b',
      requestId: reqB,
    ));

    // Accepted!
    expect(provider.state.selectedFilePath, 'b.ts');
    expect(provider.state.fileDiff, '+diff for b');
  });

  test('Closing file panel discards in-flight file diff response', () {
    final ws = WSClient();
    final provider = ChatProvider(ws);

    ClientMessage? lastSent;
    ws.onSendForTest = (msg) => lastSent = msg;

    provider.requestFileDiff('a.ts');
    final reqId = lastSent?.requestId;

    // User navigates back to file list (sets selectedFilePath to null)
    provider.requestWorkspaceFiles();
    expect(provider.state.selectedFilePath, isNull);

    // Response for a.ts arrives
    provider.handleMessageForTest(ServerMessage(
      type: 'file_diff',
      path: 'a.ts',
      diff: '+diff for a',
      requestId: reqId,
    ));

    // Must NOT re-select a.ts
    expect(provider.state.selectedFilePath, isNull);
    expect(provider.state.fileDiff, isNull);
  });
}
