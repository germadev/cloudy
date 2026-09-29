import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/sync_controller.dart';
import '../models/log_entry.dart';
import 'formatting.dart';

class ActivityScreen extends StatelessWidget {
  const ActivityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SyncController>();
    final entries = controller.log;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Actividad'),
        actions: [
          IconButton(
            tooltip: 'Borrar registro',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: entries.isEmpty ? null : controller.clearLog,
          ),
        ],
      ),
      body: entries.isEmpty
          ? const Center(child: Text('Sin actividad reciente'))
          : ListView.separated(
              itemCount: entries.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) => _EntryTile(entries[index]),
            ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile(this.entry);

  final LogEntry entry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (icon, color) = switch (entry.level) {
      LogLevel.info => (Icons.check_circle_outline, Colors.green),
      LogLevel.warning => (Icons.warning_amber_rounded, Colors.orange),
      LogLevel.error => (Icons.error_outline, colors.error),
    };
    final subtitle = Text('${dateTimeLabel(entry.time)}\n${entry.message}');

    if (entry.details.isEmpty) {
      return ListTile(
        leading: Icon(icon, color: color),
        title: Text(entry.title),
        subtitle: subtitle,
        isThreeLine: true,
      );
    }
    return ExpansionTile(
      leading: Icon(icon, color: color),
      title: Text(entry.title),
      subtitle: subtitle,
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final detail in entry.details)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              '• $detail',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}
