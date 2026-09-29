import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/sync_controller.dart';
import '../models/folder_pair.dart';
import '../services/auth_service.dart';
import 'activity_screen.dart';
import 'pair_card.dart';
import 'pair_editor_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final controller = context.read<SyncController>();
      if (!controller.isRunning) controller.refresh();
    }
  }

  Future<void> _sync(Future<String?> Function() action) async {
    final messenger = ScaffoldMessenger.of(context);
    final message = await action();
    if (message != null && mounted) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _openEditor([FolderPair? pair]) async {
    final controller = context.read<SyncController>();
    final result = await Navigator.of(context).push<FolderPair>(
      MaterialPageRoute(builder: (_) => PairEditorScreen(initial: pair)),
    );
    if (result == null) return;
    await controller.savePair(result);
    if (pair == null) {
      // Primera sincronización nada más crear el emparejamiento.
      await _sync(() => controller.sync([result.id]));
    }
  }

  Future<void> _confirmDelete(FolderPair pair) async {
    final controller = context.read<SyncController>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Dejar de sincronizar'),
        content: Text(
          '¿Quieres dejar de sincronizar «${pair.name}»? No se borrará ningún '
          'archivo, ni en el dispositivo ni en Drive.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Dejar de sincronizar'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) await controller.deletePair(pair.id);
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SyncController>();
    final auth = context.watch<AuthService>();
    final pairs = controller.pairs;
    final user = auth.user;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cloudy'),
        actions: [
          if (controller.isRunning)
            IconButton(
              tooltip: 'Detener sincronización',
              icon: const Icon(Icons.stop_circle_outlined),
              onPressed: controller.cancel,
            )
          else
            IconButton(
              tooltip: 'Sincronizar todo',
              icon: const Icon(Icons.sync),
              onPressed: pairs.isEmpty ? null : () => _sync(controller.syncAll),
            ),
          IconButton(
            tooltip: 'Actividad',
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const ActivityScreen())),
          ),
          IconButton(
            tooltip: 'Ajustes',
            icon: user?.photoUrl == null
                ? const Icon(Icons.account_circle_outlined)
                : CircleAvatar(
                    radius: 14,
                    backgroundImage: NetworkImage(user!.photoUrl!),
                  ),
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: controller.refresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            if (!controller.hasStorageAccess)
              SliverToBoxAdapter(child: _StorageAccessBanner()),
            if (controller.loaded && pairs.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyState(onAdd: () => _openEditor()),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                sliver: SliverList.separated(
                  itemCount: pairs.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final pair = pairs[index];
                    return PairCard(
                      pair: pair,
                      progress: controller.progressOf(pair.id),
                      pending: controller.isPending(pair.id),
                      onTap: () => _openEditor(pair),
                      onSync: () => _sync(() => controller.sync([pair.id])),
                      onToggleEnabled: (enabled) =>
                          controller.setEnabled(pair.id, enabled),
                      onDelete: () => _confirmDelete(pair),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.create_new_folder_outlined),
        label: const Text('Añadir carpeta'),
      ),
    );
  }
}

class _StorageAccessBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.folder_off_outlined,
                  color: theme.colorScheme.onErrorContainer,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Cloudy necesita acceso a los archivos del dispositivo '
                    'para poder sincronizar tus carpetas.',
                    style: TextStyle(color: theme.colorScheme.onErrorContainer),
                  ),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () =>
                    context.read<SyncController>().requestStorageAccess(),
                child: const Text('Conceder acceso'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.folder_copy_outlined,
            size: 72,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            'Aún no sincronizas ninguna carpeta',
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            'Elige una carpeta del dispositivo y la carpeta de Google Drive '
            'con la que quieres mantenerla sincronizada.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FilledButton.tonalIcon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('Añadir carpeta'),
          ),
        ],
      ),
    );
  }
}
