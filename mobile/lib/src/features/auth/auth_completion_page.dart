import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api.dart';
import '../../core/providers.dart';
import '../../theme.dart';

class AuthCompletionPage extends ConsumerStatefulWidget {
  const AuthCompletionPage({super.key});

  @override
  ConsumerState<AuthCompletionPage> createState() => _AuthCompletionPageState();
}

class _AuthCompletionPageState extends ConsumerState<AuthCompletionPage> {
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _completeSignIn());
  }

  Future<void> _completeSignIn() async {
    final query = Uri.base.queryParameters;
    final code = query['code'];
    final state = query['state'];

    if (code == null || state == null || code.isEmpty || state.isEmpty) {
      setState(() => _error = 'Link logowania jest nieprawidłowy. Zaloguj się ponownie.');
      return;
    }

    try {
      await ref.read(apiClientProvider).exchangeOAuthHandoff(code, state);
      ref.invalidate(sessionProvider);
      ref.invalidate(sessionDataProvider);
      ref.invalidate(botsProvider);
      if (mounted) context.go('/dashboard');
    } on Object catch (_) {
      if (mounted) setState(() => _error = 'Nie udało się dokończyć logowania. Zaloguj się ponownie.');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_error == null) ...[
                      const CircularProgressIndicator(),
                      const SizedBox(height: 18),
                      const Text('Kończę bezpieczne logowanie przez GitHub.'),
                    ] else ...[
                      const Icon(Icons.error_outline_rounded, color: AppColors.coral, size: 36),
                      const SizedBox(height: 14),
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () => context.go('/login'),
                        icon: const Icon(Icons.login_rounded),
                        label: const Text('Wróć do logowania'),
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