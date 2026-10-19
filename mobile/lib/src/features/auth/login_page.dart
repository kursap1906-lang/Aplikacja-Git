import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/providers.dart';
import '../../theme.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({this.error, super.key});

  final String? error;

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _confirmationController = TextEditingController();
  bool _loading = false;
  bool _registering = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _displayNameController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      if (_registering) {
        await api.registerAccount(
          email: _emailController.text,
          password: _passwordController.text,
          displayName: _displayNameController.text,
        );
      } else {
        await api.signIn(email: _emailController.text, password: _passwordController.text);
      }
      if (mounted) {
        ref.invalidate(sessionProvider);
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = error.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 410),
                child: Form(
                  key: _formKey,
                  child: AutofillGroup(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: AppColors.blue.withValues(alpha: .14),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.hub_rounded, color: AppColors.blue),
                      ),
                      const SizedBox(height: 24),
                      Text('Copilot\nControl Center', style: Theme.of(context).textTheme.headlineLarge),
                      const SizedBox(height: 10),
                      const Text(
                        'Najpierw zaloguj się do aplikacji. Konta GitHub połączysz później w ustawieniach.',
                        style: TextStyle(color: AppColors.muted, height: 1.55),
                      ),
                      const SizedBox(height: 22),
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(value: false, label: Text('Logowanie')),
                          ButtonSegment(value: true, label: Text('Rejestracja')),
                        ],
                        selected: {_registering},
                        onSelectionChanged: _loading
                            ? null
                            : (selection) => setState(() {
                                  _registering = selection.single;
                                  _error = null;
                                }),
                      ),
                      const SizedBox(height: 18),
                      if (_registering) ...[
                        TextFormField(
                          controller: _displayNameController,
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.name],
                          decoration: const InputDecoration(labelText: 'Nazwa użytkownika', prefixIcon: Icon(Icons.person_outline)),
                          validator: (value) => value != null && value.trim().length > 80 ? 'Maksymalnie 80 znaków.' : null,
                        ),
                        const SizedBox(height: 14),
                      ],
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.username, AutofillHints.email],
                        autocorrect: false,
                        decoration: const InputDecoration(labelText: 'Adres e-mail', prefixIcon: Icon(Icons.mail_outline)),
                        validator: (value) {
                          final email = value?.trim() ?? '';
                          if (!email.contains('@') || email.endsWith('@')) return 'Podaj prawidłowy adres e-mail.';
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: true,
                        enableSuggestions: false,
                        autocorrect: false,
                        textInputAction: _registering ? TextInputAction.next : TextInputAction.done,
                        autofillHints: [_registering ? AutofillHints.newPassword : AutofillHints.password],
                        decoration: InputDecoration(
                          labelText: 'Hasło',
                          helperText: _registering ? 'Minimum 12 znaków.' : null,
                          prefixIcon: const Icon(Icons.lock_outline),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) return 'Podaj hasło.';
                          if (_registering && value.length < 12) return 'Hasło musi mieć co najmniej 12 znaków.';
                          return null;
                        },
                        onFieldSubmitted: (_) => _registering ? null : _submit(),
                      ),
                      if (_registering) ...[
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _confirmationController,
                          obscureText: true,
                          enableSuggestions: false,
                          autocorrect: false,
                          autofillHints: const [AutofillHints.newPassword],
                          decoration: const InputDecoration(labelText: 'Powtórz hasło', prefixIcon: Icon(Icons.lock_reset_outlined)),
                          validator: (value) => value != _passwordController.text ? 'Hasła muszą być takie same.' : null,
                          onFieldSubmitted: (_) => _submit(),
                        ),
                      ],
                      if (_error != null || widget.error != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.coral.withValues(alpha: .08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.coral.withValues(alpha: .4)),
                          ),
                          child: Text(_error ?? widget.error!, style: const TextStyle(color: AppColors.coral)),
                        ),
                      ],
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: FilledButton.icon(
                          onPressed: _loading ? null : _submit,
                          icon: _loading
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : Icon(_registering ? Icons.person_add_alt_1 : Icons.login_rounded),
                          label: Text(_loading ? 'Chwila…' : _registering ? 'Utwórz konto' : 'Zaloguj się'),
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Center(
                        child: Text(
                          'Hasło jest przechowywane jako bezpieczny hash. GitHub połączysz po zalogowaniu.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.5),
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}