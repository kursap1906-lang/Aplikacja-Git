import 'package:flutter/material.dart';

const workspaceNavigation = [
  ('Pulpit', Icons.dashboard),
  ('Zespoły AI', Icons.groups),
  ('Boty i role', Icons.smart_toy),
  ('Projekty i PDF', Icons.folder_copy),
  ('GitHub i PR', Icons.call_merge),
  ('Koszty i kredyty', Icons.account_balance_wallet),
  ('Kalendarz', Icons.calendar_month),
  ('Ustawienia', Icons.settings),
];

class WorkspaceShell extends StatelessWidget {
  const WorkspaceShell({
    required this.page,
    required this.title,
    required this.body,
    required this.banner,
    required this.status,
    required this.onNavigate,
    required this.onLogout,
    required this.onNotifications,
    this.loggingOut = false,
    this.headerTrailing,
    super.key,
  });

  final int page;
  final String title;
  final Widget body;
  final String banner;
  final String status;
  final ValueChanged<int> onNavigate;
  final VoidCallback onLogout;
  final VoidCallback onNotifications;
  final bool loggingOut;
  final Widget? headerTrailing;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    Widget navigation() => ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const SizedBox(height: 12),
        const ListTile(
          leading: Icon(Icons.hub),
          title: Text(
            'AI Workspace',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        const Divider(),
        for (var i = 0; i < workspaceNavigation.length; i++)
          ListTile(
            dense: true,
            selected: page == i,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            leading: Icon(workspaceNavigation[i].$2),
            title: Text(workspaceNavigation[i].$1),
            onTap: () {
              if (!wide) Navigator.maybePop(context);
              onNavigate(i);
            },
          ),
      ],
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Copilot Control Center',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 19),
        ),
        actions: [
          IconButton(
            tooltip: 'Wyloguj',
            onPressed: loggingOut ? null : onLogout,
            icon: const Icon(Icons.logout),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(child: Chip(label: Text(status))),
          ),
          IconButton(
            onPressed: onNotifications,
            icon: const Icon(Icons.notifications_none),
          ),
        ],
      ),
      drawer: wide ? null : Drawer(child: SafeArea(child: navigation())),
      body: Row(
        children: [
          if (wide) SizedBox(width: 220, child: navigation()),
          Expanded(
            child: Column(
              children: [
                MaterialBanner(
                  content: Text(banner, style: const TextStyle(fontSize: 12)),
                  actions: const [SizedBox.shrink()],
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1100),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    title,
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineMedium,
                                  ),
                                ),
                                ?headerTrailing,
                              ],
                            ),
                            const SizedBox(height: 16),
                            body,
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class WorkspacePanel extends StatelessWidget {
  const WorkspacePanel({
    required this.title,
    required this.child,
    this.trailing,
    super.key,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    ),
  );
}

class WorkspaceTextField extends StatelessWidget {
  const WorkspaceTextField({
    required this.controller,
    required this.label,
    required this.maxLength,
    this.lines = 1,
    this.isRequired = false,
    this.enabled = true,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final int maxLength;
  final int lines;
  final bool isRequired;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: controller,
      enabled: enabled,
      minLines: lines,
      maxLines: lines + 3,
      maxLength: maxLength,
      decoration: InputDecoration(labelText: label),
      validator: (value) {
        if (isRequired && (value == null || value.trim().isEmpty)) {
          return 'Uzupełnij to pole.';
        }
        if (value != null && value.trim().length > maxLength) {
          return 'Maksymalnie $maxLength znaków.';
        }
        return null;
      },
    ),
  );
}
