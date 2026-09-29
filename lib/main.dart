import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'controllers/sync_controller.dart';
import 'services/app_storage.dart';
import 'services/auth_service.dart';
import 'services/background_sync.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es');

  final storage = await AppStorage.open();
  final auth = AuthService(storage);
  final controller = SyncController(
    storage: storage,
    remoteFactory: auth.createRemote,
  );

  await BackgroundScheduler.initialize();
  await controller.load();
  // Vuelve a registrar la tarea periódica por si el sistema la descartó.
  await BackgroundScheduler.apply(controller.settings);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: auth),
        ChangeNotifierProvider.value(value: controller),
      ],
      child: const CloudyApp(),
    ),
  );

  await auth.init();
}
