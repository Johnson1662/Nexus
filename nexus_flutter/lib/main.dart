import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'constants/theme.dart';
import 'providers/chat_provider.dart';
import 'services/host_store.dart';
import 'services/ws_client.dart';
import 'services/app_preference_service.dart';
import 'models/device_entry.dart';
import 'pages/home_page.dart';
import 'pages/chat_page.dart';
import 'pages/settings_page.dart';
import 'pages/workspace_detail_page.dart';
import 'pages/workspace_list_page.dart';
import 'pages/agent_detail_page.dart';
import 'pages/agent_manage_page.dart';
import 'pages/new_session_wizard.dart';
import 'pages/search_page.dart';
import 'pages/kit_test_page.dart';
import 'pages/session_detail_page.dart';
import 'models/ws_protocol.dart';

void main() {
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
  };

  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
    ));

    try {
      final prefs = AppPreferenceService();
      await prefs.init();
    } catch (e) {
      debugPrint('AppPreferenceService init failed: $e');
    }

    HostStore hostStore;
    try {
      hostStore = HostStore();
      await hostStore.loadFromDisk();
    } catch (e) {
      debugPrint('HostStore init failed: $e');
      hostStore = HostStore();
    }

    final workspaceProvider = WorkspaceProvider();
    late ChatProvider chatProvider;
    try {
      final ws = WSClient();
      chatProvider = ChatProvider(ws, workspaceProvider: workspaceProvider);
      await chatProvider.initFromDisk();
    } catch (e) {
      debugPrint('ChatProvider init failed: $e');
      final ws = WSClient();
      chatProvider = ChatProvider(ws, workspaceProvider: workspaceProvider);
    }

    try {
      await workspaceProvider.loadWorkspaces();
    } catch (e) {
      debugPrint('WorkspaceProvider load failed: $e');
    }

    // Immediately launch App UI — never block runApp with network probes!
    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: chatProvider),
          ChangeNotifierProvider.value(value: workspaceProvider),
          ChangeNotifierProvider.value(value: hostStore),
        ],
        child: const NexusApp(),
      ),
    );

    // Background network probe & auto-connect (non-blocking)
    if (hostStore.devices.isNotEmpty) {
      _probeAndAutoConnect(hostStore, chatProvider);
    }
  }, (error, stack) {
    final errStr = error.toString();
    if (errStr.contains('WebSocketChannelException') ||
        errStr.contains('HttpException') ||
        errStr.contains('SocketException') ||
        errStr.contains('Connection reset by peer')) {
      debugPrint('[ZoneGuarded] Ignored uncaught network error: $error');
      return;
    }
    debugPrint('Fatal error: $error\n$stack');
    runApp(MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'App Error: $error',
              style: const TextStyle(fontSize: 16, color: Colors.red),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    ));
  });
}

class NexusApp extends StatelessWidget {
  const NexusApp({super.key});

  @override
  Widget build(BuildContext context) {
    // 监听主题偏好变化，设置页切换深浅色时实时刷新根组件
    return ListenableBuilder(
      listenable: AppPreferenceService(),
      builder: (context, _) => MaterialApp(
        title: 'Nexus',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: AppPreferenceService().themeMode,
      home: const HomePage(),
      builder: (context, widget) {
        ErrorWidget.builder = (details) {
          return Scaffold(
            backgroundColor: Colors.white,
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 48, color: Colors.red),
                    const SizedBox(height: 16),
                    Text('Error', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.red.shade700)),
                    const SizedBox(height: 8),
                    Text(details.exceptionAsString(), style: const TextStyle(fontSize: 12, color: Colors.black87), textAlign: TextAlign.center, maxLines: 20),
                  ],
                ),
              ),
            ),
          );
        };
        return widget ?? const SizedBox();
      },
      routes: {
        '/chat': (context) => const ChatPage(),
        '/settings': (context) => const SettingsPage(),
        '/workspace-list': (context) => const WorkspaceListPage(),
        '/workspace-detail': (context) => const WorkspaceDetailPage(),
        '/agent-detail': (context) => const AgentDetailPage(),
        '/agent-manage': (context) => const AgentManagePage(),
        '/session-detail': (context) {
          final session = ModalRoute.of(context)?.settings.arguments;
          if (session is ServerSessionData) {
            return SessionDetailPage(session: session);
          }
          return const SizedBox();
        },
        '/new-session': (context) => const NewSessionWizard(),
        '/search': (context) => const SearchPage(),
        '/test-kits': (context) => const KitTestPage(),
      },
      ),
    );
  }
}

// ── Startup Probe & AutoConnect (non-blocking) ──

Future<void> _probeAndAutoConnect(
  HostStore hostStore,
  ChatProvider chatProvider,
) async {
  debugPrint('[Startup] Asynchronously probing ${hostStore.devices.length} saved hosts...');
  await _probeAllHosts(hostStore, chatProvider: chatProvider);
  if (hostStore.devices.isNotEmpty) {
    final onlineDevice = hostStore.devices.firstWhere(
      (d) => hostStore.isOnline(d.hostId),
      orElse: () => hostStore.devices.first,
    );
    final hk = onlineDevice.hostId.isNotEmpty ? onlineDevice.hostId : onlineDevice.name;
    final urls = onlineDevice.urls;
    if (urls.isNotEmpty) {
      debugPrint('[Startup] Auto-connecting to ${onlineDevice.name} with ${urls.length} candidate URLs');
      chatProvider.connectBest(urls, hostKey: hk);
    }
  }
}

/// Probes all saved hosts via HTTP GET /probe and marks them online/offline.
Future<void> _probeAllHosts(
  HostStore hostStore, {
  ChatProvider? chatProvider,
}) async {
  for (final device in hostStore.devices) {
    final hostKey = device.hostId.isNotEmpty ? device.hostId : device.name;
    if (hostKey.isEmpty) continue;

    bool foundOnline = false;
    for (final url in device.urls) {
      final client = io.HttpClient();
      try {
        // Convert ws:// → http://, wss:// → https://
        final probeUrl = url
            .replaceFirst('ws://', 'http://')
            .replaceFirst('wss://', 'https://');
        client.connectionTimeout = const Duration(seconds: 5);
        final request = await client.getUrl(Uri.parse('$probeUrl/probe'));
        final authToken = device.authToken;
        if (authToken != null && authToken.isNotEmpty) {
          request.headers.set('Authorization', 'Bearer $authToken');
        }
        final response = await request.close().timeout(const Duration(seconds: 5));
        if (response.statusCode == 200) {
          final raw = await response.transform(utf8.decoder).join();
          final json = jsonDecode(raw) as Map<String, dynamic>;
          if (json['ok'] == true) {
            final hostId = json['hostId'] as String? ?? '';
            final hostname = json['hostname'] as String? ?? '';
            if (hostId.isNotEmpty && hostId != device.hostId) {
              final oldKey = hostKey;
              hostStore.devices[hostStore.devices.indexOf(device)] = DeviceEntry(
                hostId: hostId,
                name: hostname.isNotEmpty ? hostname : device.name,
                urls: device.urls,
                relayUrl: device.relayUrl,
                relayPin: device.relayPin,
                authToken: device.authToken,
              );
              hostStore.migrateHostId(oldKey, hostId);
              chatProvider?.migrateHostKey(oldKey, hostId);
              hostStore.markOnline(hostId, url);
            } else {
              hostStore.markOnline(hostKey, url);
            }
            foundOnline = true;
            debugPrint('[Probe] $hostKey ONLINE via $url (hostname=$hostname)');
            break;
          }
        }
      } catch (_) {
        // Try next URL
      } finally {
        client.close(force: true);
      }
    }
    if (!foundOnline) {
      hostStore.markOffline(hostKey);
      debugPrint('[Probe] $hostKey OFFLINE');
    }
  }
  hostStore.deduplicate();
  await hostStore.saveToDisk();
}

/// Catches widget build errors