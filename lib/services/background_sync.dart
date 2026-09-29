import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../models/app_settings.dart';
import '../models/log_entry.dart';
import 'app_storage.dart';
import 'google_auth.dart';
import 'google_drive_remote.dart';
import 'sync_runner.dart';

const _periodicTaskName = 'es.germade.cloudy.periodicSync';
const _periodicUniqueName = 'cloudy-periodic-sync';

/// Punto de entrada de la tarea en segundo plano. Se ejecuta en un isolate
/// distinto, sin interfaz, así que todo el estado se lee desde disco.
@pragma('vm:entry-point')
void backgroundCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    try {
      await runBackgroundSync();
    } catch (e, stack) {
      debugPrint('Cloudy: error en la sincronización automática: $e\n$stack');
      try {
        final storage = await AppStorage.open();
        await storage.appendLog(
          LogEntry(
            time: DateTime.now(),
            level: LogLevel.error,
            title: 'Sincronización automática',
            message: '$e',
          ),
        );
      } catch (_) {}
    }
    // Siempre se devuelve true: los fallos se reintentan en el siguiente
    // periodo en vez de acumular reintentos del sistema.
    return true;
  });
}

Future<void> runBackgroundSync() async {
  final storage = await AppStorage.open();
  final settings = await storage.loadSettings();
  final account = await storage.loadAccount();
  if (!settings.autoSync || account == null) return;

  final pairs = await storage.loadPairs();
  final ids = [
    for (final pair in pairs)
      if (pair.enabled) pair.id,
  ];
  if (ids.isEmpty) return;

  final client = createDriveHttpClient(
    userId: account.id,
    email: account.email,
  );
  try {
    await SyncRunner(
      storage: storage,
      remote: GoogleDriveRemote(client),
    ).run(ids, automatic: true);
  } finally {
    client.close();
  }
}

/// Programa o cancela la tarea periódica según los ajustes.
///
/// Solo en Android: en iOS el sistema no garantiza ejecuciones periódicas y
/// además el acceso a carpetas externas a la app caduca al cerrarla.
class BackgroundScheduler {
  static bool get isSupported => !kIsWeb && Platform.isAndroid;

  static Future<void> initialize() async {
    if (!isSupported) return;
    await Workmanager().initialize(backgroundCallbackDispatcher);
  }

  static Future<void> apply(AppSettings settings) async {
    if (!isSupported) return;
    if (!settings.autoSync) {
      await Workmanager().cancelByUniqueName(_periodicUniqueName);
      return;
    }
    await Workmanager().registerPeriodicTask(
      _periodicUniqueName,
      _periodicTaskName,
      frequency: Duration(minutes: settings.intervalMinutes),
      constraints: Constraints(
        networkType: settings.wifiOnly
            ? NetworkType.unmetered
            : NetworkType.connected,
        requiresCharging: settings.chargingOnly,
        requiresBatteryNotLow: true,
      ),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    );
  }
}
