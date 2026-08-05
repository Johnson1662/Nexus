import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../lib/services/storage_service.dart';

void main() {
  late Directory sandbox;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('nexus_storage_test');
    StorageService.sandboxForTest = sandbox.path;
    StorageService.resetForTest();
  });

  tearDown(() async {
    StorageService.resetForTest();
    StorageService.sandboxForTest = null;
    if (await sandbox.exists()) await sandbox.delete(recursive: true);
  });

  test('concurrent getInstance calls share one initialized instance', () async {
    final instances = await Future.wait(
      List.generate(20, (_) => StorageService.getInstance()),
    );

    expect(instances.every((instance) => identical(instance, instances.first)),
        isTrue);
  });

  test('putString is persisted across initialization reset', () async {
    final service = await StorageService.getInstance();
    await service.putString('k', 'v');

    StorageService.resetForTest();
    final reloaded = await StorageService.getInstance();

    expect(reloaded.getString('k'), 'v');
  });

  test('initialization cannot overwrite a write from a concurrent caller',
      () async {
    final firstInit = StorageService.getInstance();
    final secondInit = StorageService.getInstance();

    final service = await secondInit;
    await service.putString('k', 'v');
    await firstInit;

    expect(service.getString('k'), 'v');
  });
}
