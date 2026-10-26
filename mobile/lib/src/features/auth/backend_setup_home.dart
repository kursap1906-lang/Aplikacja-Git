import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../accounts/accounts_page.dart';
import 'authenticated_workspace_gate.dart';

class BackendSetupHome extends StatefulWidget {
  const BackendSetupHome({super.key});

  @override
  State<BackendSetupHome> createState() => _BackendSetupHomeState();
}

class _BackendSetupHomeState extends State<BackendSetupHome> {
  int _refresh = 0;

  @override
  Widget build(BuildContext context) {
    return AuthenticatedWorkspaceGate(
      key: ValueKey(_refresh),
      builder: (context, session, logout) => Scaffold(
        appBar: AppBar(
          title: const Text('Konfiguracja połączenia GitHub'),
          actions: [
            IconButton(
              tooltip: 'Odśwież połączenia',
              onPressed: () => setState(() => _refresh++),
              icon: const Icon(Icons.refresh),
            ),
            TextButton.icon(
              onPressed: () async {
                try {
                  await logout();
                } on Exception catch (error) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text(error.toString())));
                  }
                }
              },
              icon: const Icon(Icons.logout),
              label: const Text('Wyloguj'),
            ),
          ],
        ),
        body: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Ten ekran zapisuje prawdziwe połączenia kont w backendzie. '
                'Panel główny korzysta z danych zapisanych na Twoim koncie. '
                'Połączenie GitHub nie uruchamia żadnego bota.',
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: FilledButton.icon(
                onPressed: () => context.go('/workspace'),
                icon: const Icon(Icons.dashboard),
                label: const Text('Otwórz panel API (beta)'),
              ),
            ),
            const Expanded(child: AccountsPage()),
          ],
        ),
      ),
    );
  }
}
