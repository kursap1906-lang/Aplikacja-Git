import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api.dart';
import '../../core/providers.dart';
import '../../theme.dart';

class AccountsPage extends ConsumerStatefulWidget {
  const AccountsPage({super.key});

  @override
  ConsumerState<AccountsPage> createState() => _AccountsPageState();
}

class _AccountsPageState extends ConsumerState<AccountsPage> {
  bool _connecting = false;
  String? _error;

  Future<void> _connect() async {
    setState(() {
      _connecting = true;
      _error = null;
    });
    try {
      final address = await ref.read(apiClientProvider).beginGitHubSignIn(nativeClient: !kIsWeb);
      if (!await launchUrl(Uri.parse(address), mode: LaunchMode.externalApplication)) {
        throw const ApiException('BROWSER_UNAVAILABLE', 'Nie można otworzyć przeglądarki systemowej.');
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(sessionDataProvider);
    return CustomScrollView(slivers: [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(26, 30, 26, 17),
        sliver: SliverToBoxAdapter(child: Row(children: [
          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('GITHUB', style: TextStyle(color: AppColors.blue, fontSize: 11, fontWeight: FontWeight.w700)),
            SizedBox(height: 8),
            Text('Połączone konta', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w700)),
          ])),
          FilledButton.icon(
            onPressed: _connecting ? null : _connect,
            icon: _connecting
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.add_rounded),
            label: const Text('Dodaj konto'),
          ),
        ])),
      ),
      if (_error != null)
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 26),
          sliver: SliverToBoxAdapter(child: Text(_error!, style: const TextStyle(color: AppColors.coral))),
        ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(26, 0, 26, 24),
        sliver: data.when(
          loading: () => const SliverToBoxAdapter(child: LinearProgressIndicator()),
          error: (error, stack) => SliverToBoxAdapter(child: Text(error.toString())),
          data: (response) {
            final accounts = response['githubAccounts'];
            final values = accounts is List
                ? accounts.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList()
                : <Map<String, dynamic>>[];
            if (values.isEmpty) {
              return SliverToBoxAdapter(child: Card(child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Nie połączono jeszcze konta GitHub.', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 7),
                  const Text('Autoryzacja odbywa się na stronie GitHub. Aplikacja nigdy nie prosi o hasło ani kod 2FA.',
                      style: TextStyle(color: AppColors.muted, height: 1.5)),
                  const SizedBox(height: 12),
                  FilledButton.icon(onPressed: _connecting ? null : _connect,
                      icon: const Icon(Icons.open_in_browser_rounded), label: const Text('Połącz z GitHub')),
                ]),
              )));
            }
            return SliverList.builder(
              itemCount: values.length,
              itemBuilder: (context, index) {
                final account = values[index];
                final active = account['status'] == 'ACTIVE';
                return Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                    leading: CircleAvatar(
                      backgroundColor: active ? AppColors.mint.withValues(alpha: .1) : AppColors.amber.withValues(alpha: .1),
                      child: Icon(Icons.code_rounded, color: active ? AppColors.mint : AppColors.amber),
                    ),
                    title: Text('@${account['login'] ?? 'GitHub'}', style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('${active ? 'Połączone' : 'Wymaga ponownej autoryzacji'} · zakres: ${(account['scopes'] as List?)?.join(', ') ?? 'brak'}',
                          style: const TextStyle(color: AppColors.muted)),
                    ),
                    trailing: active
                        ? const Icon(Icons.check_circle_rounded, color: AppColors.mint)
                        : IconButton(tooltip: 'Połącz ponownie', onPressed: _connect, icon: const Icon(Icons.refresh_rounded)),
                  ),
                );
              },
            );
          },
        ),
      ),
      const SliverPadding(
        padding: EdgeInsets.fromLTRB(26, 10, 26, 24),
        sliver: SliverToBoxAdapter(child: Text(
          'OAuth GitHub prosi o scope read:user repo. Połączenia repozytoriów są weryfikowane dla wybranego konta przed utworzeniem bota.',
          style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.5),
        )),
      ),
    ]);
  }
}