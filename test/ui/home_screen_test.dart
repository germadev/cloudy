import 'dart:io';

import 'package:cloudy/controllers/sync_controller.dart';
import 'package:cloudy/models/folder_pair.dart';
import 'package:cloudy/services/app_storage.dart';
import 'package:cloudy/services/auth_service.dart';
import 'package:cloudy/ui/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import '../support/fake_remote_drive.dart';

void main() {
  late Directory temp;
  late AppStorage storage;

  setUpAll(() => initializeDateFormatting('es'));

  setUp(() {
    temp = Directory.systemTemp.createTempSync('cloudy_home_test');
    storage = AppStorage(temp);
  });

  tearDown(() => temp.deleteSync(recursive: true));

  Future<SyncController> pumpHome(WidgetTester tester) async {
    final controller = SyncController(
      storage: storage,
      remoteFactory: FakeRemoteDrive.new,
    );
    await tester.runAsync(controller.load);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthService(storage)),
          ChangeNotifierProvider.value(value: controller),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    return controller;
  }

  testWidgets('sin carpetas muestra el estado vacío', (tester) async {
    await pumpHome(tester);

    expect(find.text('Aún no sincronizas ninguna carpeta'), findsOneWidget);
  });

  testWidgets('lista las carpetas configuradas', (tester) async {
    await tester.runAsync(
      () => storage.upsertPair(
        const FolderPair(
          id: 'p1',
          name: 'Documentos',
          localPath: '/storage/emulated/0/Documents',
          remoteFolderId: 'abc',
          remoteFolderPath: 'Mi unidad/Documentos',
        ),
      ),
    );
    await pumpHome(tester);

    expect(find.text('Documentos'), findsOneWidget);
    expect(find.text('Todavía no se ha sincronizado'), findsOneWidget);
  });

  testWidgets('el editor valida que se elijan ambas carpetas', (tester) async {
    await pumpHome(tester);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.text('Nueva sincronización'), findsOneWidget);

    await tester.tap(find.text('Guardar'));
    await tester.pump();

    expect(find.text('Elige una carpeta del dispositivo'), findsOneWidget);
    expect(find.text('Elige una carpeta de Google Drive'), findsOneWidget);
    expect(find.text('Ponle un nombre'), findsOneWidget);
  });
}
