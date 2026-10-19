import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api.dart';
import '../../core/providers.dart';
import '../../theme.dart';

class PullRequestPage extends ConsumerStatefulWidget {
  const PullRequestPage({required this.botId, required this.pullRequestId, super.key});

  final String botId;
  final String pullRequestId;

  @override
  ConsumerState<PullRequestPage> createState() => _PullRequestPageState();
}

class _PullRequestPageState extends ConsumerState<PullRequestPage> {
  final _commentController = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submitComment() async {
    final body = _commentController.text.trim();
    if (body.isEmpty) return;

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(apiClientProvider).request(
        '/bots/${widget.botId}/pull-requests/${widget.pullRequestId}/comments',
        method: 'POST',
        data: {'body': body},
      );
      _commentController.clear();
      ref.invalidate(pullRequestProvider((botId: widget.botId, pullRequestId: widget.pullRequestId)));
    } on Object catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final request = ref.watch(pullRequestProvider((botId: widget.botId, pullRequestId: widget.pullRequestId)));
    return request.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => _LoadError(
        message: error.toString(),
        onRetry: () => ref.invalidate(pullRequestProvider((botId: widget.botId, pullRequestId: widget.pullRequestId))),
      ),
      data: (response) {
        final pullRequest = Map<String, dynamic>.from(response['pullRequest'] as Map);
        final checks = _records(response['checks']);
        final comments = _records(response['comments']);
        final ciStatus = pullRequest['ciStatus']?.toString() ?? 'NO_CHECKS';
        return CustomScrollView(slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(26, 28, 26, 14),
            sliver: SliverToBoxAdapter(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('PULL REQUEST', style: TextStyle(color: AppColors.blue, fontSize: 11, fontWeight: FontWeight.w700)),
              const SizedBox(height: 9),
              Text('#${pullRequest['number']} · ${pullRequest['title']}',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              const SizedBox(height: 9),
              Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                _Badge(icon: Icons.account_tree_outlined, text: '${pullRequest['headBranch']} → ${pullRequest['baseBranch']}'),
                _Badge(icon: Icons.fact_check_outlined, text: _ciLabel(ciStatus), color: _ciColor(ciStatus)),
                OutlinedButton.icon(
                  onPressed: () async {
                    final address = Uri.tryParse(pullRequest['url']?.toString() ?? '');
                    if (address != null && address.scheme == 'https' && address.host == 'github.com') {
                      await launchUrl(address, mode: LaunchMode.externalApplication);
                    }
                  },
                  icon: const Icon(Icons.open_in_new_rounded, size: 17),
                  label: const Text('GitHub'),
                ),
              ]),
              if (pullRequest['body'] is String && (pullRequest['body'] as String).isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(pullRequest['body'].toString(), style: const TextStyle(color: AppColors.muted, height: 1.55)),
              ],
            ])),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(26, 0, 26, 22),
            sliver: SliverToBoxAdapter(child: _ChecksPanel(checks: checks, status: ciStatus)),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(26, 4, 26, 10),
            sliver: const SliverToBoxAdapter(child: Text('Zmiany', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600))),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(26, 0, 26, 20),
            sliver: SliverToBoxAdapter(child: _DiffPanel(diff: response['diff']?.toString() ?? '', truncated: response['diffTruncated'] == true)),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(26, 0, 26, 10),
            sliver: SliverToBoxAdapter(child: Text('Komentarze · ${comments.length}',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600))),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(26, 0, 26, 15),
            sliver: comments.isEmpty
                ? const SliverToBoxAdapter(child: Text('Brak komentarzy w historii.', style: TextStyle(color: AppColors.muted)))
                : SliverList.builder(
                    itemCount: comments.length,
                    itemBuilder: (context, index) => _CommentRow(comment: comments[index]),
                  ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(26, 10, 26, 38),
            sliver: SliverToBoxAdapter(child: Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  TextField(
                    controller: _commentController,
                    minLines: 2,
                    maxLines: 5,
                    maxLength: 20000,
                    decoration: const InputDecoration(labelText: 'Nowy komentarz', alignLabelWithHint: true),
                    onChanged: (_) => setState(() {}),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 5),
                    Text(_error!, style: const TextStyle(color: AppColors.coral, fontSize: 12)),
                  ],
                  FilledButton.icon(
                    onPressed: _submitting || _commentController.text.trim().isEmpty ? null : _submitComment,
                    icon: _submitting
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.send_rounded, size: 17),
                    label: const Text('Opublikuj komentarz'),
                  ),
                ]),
              ),
            )),
          ),
        ]);
      },
    );
  }

  static List<Map<String, dynamic>> _records(Object? value) => value is List
      ? value.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList()
      : [];

  static String _ciLabel(String status) => switch (status) {
        'SUCCESS' => 'CI zaliczone',
        'FAILURE' => 'CI niezaliczone',
        'IN_PROGRESS' => 'CI w toku',
        _ => 'Brak checków',
      };

  static Color _ciColor(String status) => switch (status) {
        'SUCCESS' => AppColors.mint,
        'FAILURE' => AppColors.coral,
        'IN_PROGRESS' => AppColors.amber,
        _ => AppColors.muted,
      };
}

class _ChecksPanel extends StatelessWidget {
  const _ChecksPanel({required this.checks, required this.status});

  final List<Map<String, dynamic>> checks;
  final String status;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: checks.isEmpty
              ? Text(status == 'NO_CHECKS' ? 'Repozytorium nie zwróciło check-runs dla tego commita.' : 'Status CI: $status',
                  style: const TextStyle(color: AppColors.muted))
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('STATUSY CI', style: TextStyle(color: AppColors.muted, fontSize: 10, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 9),
                  for (final check in checks)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 7),
                      child: Row(children: [
                        Icon(
                          check['conclusion'] == 'success'
                              ? Icons.check_circle_outline_rounded
                              : check['conclusion'] == 'failure'
                                  ? Icons.error_outline_rounded
                                  : Icons.sync_rounded,
                          size: 17,
                          color: check['conclusion'] == 'success' ? AppColors.mint : check['conclusion'] == 'failure' ? AppColors.coral : AppColors.amber,
                        ),
                        const SizedBox(width: 9),
                        Expanded(child: Text(check['name']?.toString() ?? 'Check', style: const TextStyle(fontSize: 13))),
                        Text(check['conclusion']?.toString() ?? check['status']?.toString() ?? '',
                            style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                      ]),
                    ),
                ]),
        ),
      );
}

class _DiffPanel extends StatelessWidget {
  const _DiffPanel({required this.diff, required this.truncated});

  final String diff;
  final bool truncated;

  @override
  Widget build(BuildContext context) {
    if (diff.isEmpty) {
      return const Card(child: Padding(
        padding: EdgeInsets.all(16),
        child: Text('GitHub nie zwrócił treści diffu.', style: TextStyle(color: AppColors.muted)),
      ));
    }

    return Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (truncated)
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 13, 14, 0),
            child: Text('Diff ograniczono do 200 KB.', style: TextStyle(color: AppColors.amber, fontSize: 12)),
          ),
        SizedBox(
          height: 340,
          width: double.infinity,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(14),
            child: SelectableText.rich(TextSpan(
              children: [
                for (final line in diff.split('\n'))
                  TextSpan(
                    text: '$line\n',
                    style: TextStyle(
                      color: line.startsWith('+') && !line.startsWith('+++')
                          ? AppColors.mint
                          : line.startsWith('-') && !line.startsWith('---')
                              ? AppColors.coral
                              : line.startsWith('@@')
                                  ? AppColors.blue
                                  : AppColors.foreground,
                      fontFamily: 'monospace',
                      fontSize: 12,
                      height: 1.45,
                    ),
                  ),
              ],
            )),
          ),
        ),
      ]),
    );
  }
}

class _CommentRow extends StatelessWidget {
  const _CommentRow({required this.comment});
  final Map<String, dynamic> comment;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('@${comment['authorLogin'] ?? comment['user']?['login'] ?? 'github-user'}',
                style: const TextStyle(color: AppColors.blue, fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            SelectableText(comment['body']?.toString() ?? '', style: const TextStyle(height: 1.45)),
          ]),
        ),
      );
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.text, this.color = AppColors.muted});
  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.stroke),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 7),
          Text(text, style: TextStyle(color: color, fontSize: 11)),
        ]),
      );
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 10),
          OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh_rounded), label: const Text('Odśwież')),
        ]),
      );
}