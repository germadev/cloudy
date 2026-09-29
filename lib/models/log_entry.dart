enum LogLevel { info, warning, error }

/// Entrada del registro de actividad.
class LogEntry {
  const LogEntry({
    required this.time,
    required this.level,
    required this.title,
    required this.message,
    this.details = const [],
  });

  final DateTime time;
  final LogLevel level;
  final String title;
  final String message;
  final List<String> details;

  Map<String, dynamic> toJson() => {
    'time': time.toIso8601String(),
    'level': level.name,
    'title': title,
    'message': message,
    if (details.isNotEmpty) 'details': details,
  };

  factory LogEntry.fromJson(Map<String, dynamic> json) => LogEntry(
    time: DateTime.parse(json['time'] as String),
    level: LogLevel.values.firstWhere(
      (l) => l.name == json['level'],
      orElse: () => LogLevel.info,
    ),
    title: json['title'] as String? ?? '',
    message: json['message'] as String? ?? '',
    details: (json['details'] as List<dynamic>?)?.cast<String>() ?? const [],
  );
}
