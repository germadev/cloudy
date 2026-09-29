import 'package:cloudy/models/folder_pair.dart';
import 'package:cloudy/models/sync_report.dart';
import 'package:cloudy/ui/pair_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  final pair = FolderPair(
    id: 'p1',
    name: 'Fotos',
    localPath: '/storage/emulated/0/DCIM/Camera',
    remoteFolderId: 'abc',
    remoteFolderPath: 'Mi unidad/Fotos',
    lastSyncAt: DateTime.now().subtract(const Duration(minutes: 5)),
    lastOutcome: SyncOutcome.success,
    lastMessage: '3 subidos',
  );

  Future<void> pump(
    WidgetTester tester, {
    SyncProgress? progress,
    VoidCallback? onSync,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PairCard(
            pair: pair,
            progress: progress,
            pending: false,
            onTap: () {},
            onSync: onSync ?? () {},
            onToggleEnabled: (_) {},
            onDelete: () {},
          ),
        ),
      ),
    );
  }

  testWidgets('muestra las carpetas y el último resultado', (tester) async {
    await pump(tester);

    expect(find.text('Fotos'), findsOneWidget);
    expect(find.text('Bidireccional'), findsOneWidget);
    expect(find.text('/storage/emulated/0/DCIM/Camera'), findsOneWidget);
    expect(find.text('Mi unidad/Fotos'), findsOneWidget);
    expect(find.text('hace 5 min · 3 subidos'), findsOneWidget);
  });

  testWidgets('el botón sincroniza', (tester) async {
    var synced = false;
    await pump(tester, onSync: () => synced = true);

    await tester.tap(find.byTooltip('Sincronizar ahora'));
    expect(synced, isTrue);
  });

  testWidgets('muestra el progreso y desactiva el botón', (tester) async {
    await pump(
      tester,
      progress: const SyncProgress(
        phase: SyncPhase.transferring,
        completed: 2,
        total: 8,
        currentPath: 'IMG_001.jpg',
      ),
    );

    expect(find.text('2 de 8 · IMG_001.jpg'), findsOneWidget);
    final indicator = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(indicator.value, 0.25);
    final button = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.sync),
    );
    expect(button.onPressed, isNull);
  });
}
