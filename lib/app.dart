import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'services/auth_service.dart';
import 'ui/home_screen.dart';
import 'ui/login_screen.dart';

class CloudyApp extends StatelessWidget {
  const CloudyApp({super.key});

  static const _seed = Color(0xFF1A73E8);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cloudy',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: _seed),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seed,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      locale: const Locale('es'),
      supportedLocales: const [Locale('es')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: const _AuthGate(),
    );
  }
}

/// Muestra la pantalla de acceso o la principal según el estado de la sesión.
class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    final status = context.select<AuthService, AuthStatus>((a) => a.status);
    return switch (status) {
      AuthStatus.initializing => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      AuthStatus.signedOut ||
      AuthStatus.needsAuthorization => const LoginScreen(),
      AuthStatus.ready => const HomeScreen(),
    };
  }
}
