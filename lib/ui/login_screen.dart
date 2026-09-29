import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final theme = Theme.of(context);
    final needsAuthorization = auth.status == AuthStatus.needsAuthorization;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.cloud_sync_rounded,
                    size: 96,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text('Cloudy', style: theme.textTheme.displaySmall),
                  const SizedBox(height: 8),
                  Text(
                    'Mantén las carpetas de tu dispositivo sincronizadas con '
                    'Google Drive.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 40),
                  if (needsAuthorization) ...[
                    Text(
                      'Has iniciado sesión como ${auth.user?.email}, pero '
                      'Cloudy necesita permiso para ver y modificar tus '
                      'archivos de Google Drive.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: auth.busy ? null : auth.authorizeDrive,
                      icon: const Icon(Icons.lock_open),
                      label: const Text('Conceder acceso a Drive'),
                    ),
                    TextButton(
                      onPressed: auth.busy ? null : auth.signOut,
                      child: const Text('Usar otra cuenta'),
                    ),
                  ] else
                    FilledButton.icon(
                      onPressed: auth.busy ? null : auth.signIn,
                      icon: const Icon(Icons.login),
                      label: const Text('Iniciar sesión con Google'),
                    ),
                  if (auth.busy) ...[
                    const SizedBox(height: 24),
                    const CircularProgressIndicator(),
                  ],
                  if (auth.error != null) ...[
                    const SizedBox(height: 24),
                    Text(
                      auth.error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
