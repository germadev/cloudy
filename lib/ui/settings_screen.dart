import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/sync_controller.dart';
import '../models/app_settings.dart';
import '../services/auth_service.dart';
import '../services/background_sync.dart';
import 'formatting.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _confirmSignOut(BuildContext context) async {
    final auth = context.read<AuthService>();
    final navigator = Navigator.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content: const Text(
          'La sincronización automática se detendrá hasta que vuelvas a '
          'iniciar sesión. Tus carpetas configuradas se conservan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      navigator.popUntil((route) => route.isFirst);
      await auth.signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SyncController>();
    final user = context.watch<AuthService>().user;
    final settings = controller.settings;
    final theme = Theme.of(context);

    void update(AppSettings value) => controller.updateSettings(value);

    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: ListView(
        children: [
          if (user != null)
            ListTile(
              leading: CircleAvatar(
                backgroundImage: user.photoUrl == null
                    ? null
                    : NetworkImage(user.photoUrl!),
                child: user.photoUrl == null ? const Icon(Icons.person) : null,
              ),
              title: Text(user.displayName ?? user.email),
              subtitle: Text(user.email),
              trailing: TextButton(
                onPressed: () => _confirmSignOut(context),
                child: const Text('Cerrar sesión'),
              ),
            ),
          const Divider(),
          _SectionTitle('Sincronización automática'),
          if (!BackgroundScheduler.isSupported)
            const ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('No disponible en esta plataforma'),
            ),
          SwitchListTile(
            secondary: const Icon(Icons.schedule),
            title: const Text('Sincronizar periódicamente'),
            subtitle: const Text(
              'En segundo plano, aunque la app esté cerrada',
            ),
            value: settings.autoSync,
            onChanged: BackgroundScheduler.isSupported
                ? (value) => update(settings.copyWith(autoSync: value))
                : null,
          ),
          ListTile(
            enabled: settings.autoSync,
            leading: const Icon(Icons.timer_outlined),
            title: const Text('Frecuencia'),
            trailing: DropdownButton<int>(
              value: settings.intervalMinutes,
              onChanged: settings.autoSync
                  ? (value) => update(settings.copyWith(intervalMinutes: value))
                  : null,
              items: [
                for (final minutes in AppSettings.intervalOptions)
                  DropdownMenuItem(
                    value: minutes,
                    child: Text(intervalLabel(minutes)),
                  ),
              ],
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.wifi),
            title: const Text('Solo con Wi-Fi'),
            subtitle: const Text('No usar datos móviles'),
            value: settings.wifiOnly,
            onChanged: settings.autoSync
                ? (value) => update(settings.copyWith(wifiOnly: value))
                : null,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.battery_charging_full),
            title: const Text('Solo mientras se carga'),
            value: settings.chargingOnly,
            onChanged: settings.autoSync
                ? (value) => update(settings.copyWith(chargingOnly: value))
                : null,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Text(
              'El sistema decide el momento exacto de cada ejecución para '
              'ahorrar batería, por lo que puede retrasarse respecto a la '
              'frecuencia elegida.',
              style: theme.textTheme.bodySmall,
            ),
          ),
          const Divider(),
          _SectionTitle('Permisos'),
          ListTile(
            leading: Icon(
              controller.hasStorageAccess
                  ? Icons.check_circle_outline
                  : Icons.error_outline,
              color: controller.hasStorageAccess
                  ? Colors.green
                  : theme.colorScheme.error,
            ),
            title: const Text('Acceso a los archivos'),
            subtitle: Text(
              controller.hasStorageAccess ? 'Concedido' : 'No concedido',
            ),
            trailing: controller.hasStorageAccess
                ? null
                : TextButton(
                    onPressed: controller.requestStorageAccess,
                    child: const Text('Conceder'),
                  ),
          ),
          const Divider(),
          const AboutListTile(
            icon: Icon(Icons.info_outline),
            applicationName: 'Cloudy',
            applicationVersion: '1.0.0',
            applicationLegalese:
                'Sincroniza carpetas del dispositivo con Google Drive.',
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}
