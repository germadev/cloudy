import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/folder_pair.dart';

String modeLabel(SyncMode mode) => switch (mode) {
  SyncMode.twoWay => 'Bidireccional',
  SyncMode.uploadOnly => 'Solo subir',
  SyncMode.downloadOnly => 'Solo descargar',
};

String modeDescription(SyncMode mode) => switch (mode) {
  SyncMode.twoWay =>
    'Los cambios en el dispositivo y en Drive se replican en ambos sentidos.',
  SyncMode.uploadOnly =>
    'Copia de seguridad: lo que cambie en el dispositivo se sube a Drive. '
        'Los cambios hechos en Drive no se descargan.',
  SyncMode.downloadOnly =>
    'Lo que cambie en Drive se descarga al dispositivo. Los cambios locales '
        'no se suben.',
};

IconData modeIcon(SyncMode mode) => switch (mode) {
  SyncMode.twoWay => Icons.sync,
  SyncMode.uploadOnly => Icons.cloud_upload_outlined,
  SyncMode.downloadOnly => Icons.cloud_download_outlined,
};

String conflictLabel(ConflictPolicy policy) => switch (policy) {
  ConflictPolicy.keepBoth => 'Conservar ambas versiones',
  ConflictPolicy.preferLocal => 'Gana la del dispositivo',
  ConflictPolicy.preferRemote => 'Gana la de Drive',
  ConflictPolicy.preferNewest => 'Gana la más reciente',
};

String intervalLabel(int minutes) {
  if (minutes < 60) return 'Cada $minutes minutos';
  final hours = minutes ~/ 60;
  if (hours == 1) return 'Cada hora';
  if (hours == 24) return 'Una vez al día';
  return 'Cada $hours horas';
}

String relativeTime(DateTime time, {DateTime? now}) {
  final diff = (now ?? DateTime.now()).difference(time);
  if (diff.inSeconds < 60) return 'hace un momento';
  if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'hace ${diff.inHours} h';
  if (diff.inDays == 1) return 'ayer';
  if (diff.inDays < 7) return 'hace ${diff.inDays} días';
  return DateFormat('d MMM yyyy', 'es').format(time);
}

String dateTimeLabel(DateTime time) =>
    DateFormat("d MMM yyyy, HH:mm", 'es').format(time);
