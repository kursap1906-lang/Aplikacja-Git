import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api.dart';
import '../../core/providers.dart';
import '../../theme.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool _checking = false;
  bool _openingEditor = false;
  String? _diagnostics;

  Future<void> _openEditor() async {
    setState(() => _openingEditor = true);
    try {
      await openCodeEditor(ref.read(apiClientProvider));
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _openingEditor = false);
    }
  }

  Future<void> _checkServer() async {
    setState(() {
      _checking = true;
      _diagnostics = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      final health = await api.request('/../health/ready');
      final capabilities = await api.request('/capabilities');
      if (mounted) {
        setState(
          () => _diagnostics =
              'Połączenie: aktywne · Baza: ${health['database']}\nCopilot coding agent: ${capabilities['copilotAgent']}',
        );
      }
    } on Object catch (error) {
      if (mounted) setState(() => _diagnostics = error.toString());
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _logout() async {
    try {
      await ref.read(apiClientProvider).request('/auth/logout', method: 'POST');
    } on ApiException catch (error) {
      if (error.statusCode != 401) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(error.message)));
        }
      }
    } finally {
      await ref.read(apiClientProvider).forgetSession();
      ref.invalidate(sessionProvider);
      if (mounted) context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(26),
    children: [
      const Text(
        'SYSTEM',
        style: TextStyle(
          color: AppColors.blue,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 8),
      const Text(
        'Ustawienia',
        style: TextStyle(fontSize: 25, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 22),
      Card(
        child: ListTile(
          leading: const Icon(Icons.dns_outlined, color: AppColors.blue),
          title: const Text('Diagnostyka API'),
          subtitle: Text(
            ref.read(apiClientProvider).baseUrl,
            style: const TextStyle(color: AppColors.muted),
          ),
          trailing: IconButton(
            tooltip: 'Sprawdź połączenie i bazę danych',
            onPressed: _checking ? null : _checkServer,
            icon: _checking
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.monitor_heart_outlined),
          ),
        ),
      ),
      if (_diagnostics != null)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: SelectableText(
              _diagnostics!,
              style: const TextStyle(color: AppColors.muted, height: 1.5),
            ),
          ),
        ),
      const SizedBox(height: 10),
      if (kIsWeb) ...[
        Card(
          child: ListTile(
            leading: const Icon(Icons.code_rounded, color: AppColors.mint),
            title: const Text('Edytor kodu'),
            subtitle: const Text(
              'Otwórz VS Code w przeglądarce i edytuj projekt na stagingu.',
              style: TextStyle(color: AppColors.muted),
            ),
            trailing: _openingEditor
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.open_in_new_rounded),
            onTap: _openingEditor ? null : _openEditor,
          ),
        ),
        const SizedBox(height: 10),
      ],
      Card(
        child: ListTile(
          leading: const Icon(
            Icons.notifications_active_outlined,
            color: AppColors.amber,
          ),
          title: const Text('Powiadomienia push'),
          subtitle: const Text(
            'Wymagają konfiguracji Firebase dla danej platformy.',
            style: TextStyle(color: AppColors.muted),
          ),
        ),
      ),
      const SizedBox(height: 10),
      Card(
        child: ListTile(
          leading: const Icon(Icons.security_outlined, color: AppColors.mint),
          title: const Text('Połączenie GitHub'),
          subtitle: const Text(
            'OAuth przez przeglądarkę systemową. Tokeny pozostają zaszyfrowane na backendzie.',
            style: TextStyle(color: AppColors.muted),
          ),
        ),
      ),
      const SizedBox(height: 10),
      Card(
        child: ListTile(
          leading: const Icon(Icons.block_rounded, color: AppColors.amber),
          title: const Text('GitHub Copilot coding agent'),
          subtitle: const Text(
            'Uruchamianie zadań korzysta z public preview GitHub Agent Tasks API; wymaga planu Copilot Business/Enterprise i uprawnień repozytorium.',
            style: TextStyle(color: AppColors.muted),
          ),
        ),
      ),
      const SizedBox(height: 24),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: _logout,
          icon: const Icon(Icons.logout_rounded),
          label: const Text('Wyloguj'),
        ),
      ),
      const SizedBox(height: 12),
      const Text(
        'Wersja 0.1.0 · Przepływ akceptacji PR nie scala automatycznie żadnej gałęzi.',
        style: TextStyle(color: AppColors.muted, fontSize: 11),
      ),
    ],
  );
}
