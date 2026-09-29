/// Preferencias globales de la aplicación.
class AppSettings {
  const AppSettings({
    this.autoSync = false,
    this.intervalMinutes = 60,
    this.wifiOnly = true,
    this.chargingOnly = false,
  });

  /// Intervalos disponibles. Android no permite tareas periódicas de menos de
  /// 15 minutos.
  static const intervalOptions = [15, 30, 60, 180, 360, 720, 1440];

  final bool autoSync;
  final int intervalMinutes;
  final bool wifiOnly;
  final bool chargingOnly;

  AppSettings copyWith({
    bool? autoSync,
    int? intervalMinutes,
    bool? wifiOnly,
    bool? chargingOnly,
  }) {
    return AppSettings(
      autoSync: autoSync ?? this.autoSync,
      intervalMinutes: intervalMinutes ?? this.intervalMinutes,
      wifiOnly: wifiOnly ?? this.wifiOnly,
      chargingOnly: chargingOnly ?? this.chargingOnly,
    );
  }

  Map<String, dynamic> toJson() => {
    'autoSync': autoSync,
    'intervalMinutes': intervalMinutes,
    'wifiOnly': wifiOnly,
    'chargingOnly': chargingOnly,
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
    autoSync: json['autoSync'] as bool? ?? false,
    intervalMinutes: json['intervalMinutes'] as int? ?? 60,
    wifiOnly: json['wifiOnly'] as bool? ?? true,
    chargingOnly: json['chargingOnly'] as bool? ?? false,
  );
}
