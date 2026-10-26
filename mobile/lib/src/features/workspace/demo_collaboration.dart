import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class DemoCollaboration extends StatelessWidget {
  const DemoCollaboration({
    required this.members,
    required this.parents,
    required this.onChanged,
    this.enabled = true,
    this.caption =
        'Hierarchia współpracy (demo). Strzałki prowadzą od koordynatora '
        'do wykonawcy. Kliknij bota, aby zmienić przełożonego. '
        'Relacje cykliczne są zablokowane.',
    super.key,
  });

  final List<({String id, String name, String role})> members;
  final Map<String, String> parents;
  final ValueChanged<Map<String, String>> onChanged;
  final bool enabled;
  final String caption;
  static const _coordinator = '__coordinator__';

  bool _wouldCycle(String child, String parent) {
    final visited = {child};
    String? cursor = parent;
    while (cursor != null) {
      if (!visited.add(cursor)) return true;
      cursor = parents[cursor];
    }
    return false;
  }

  Future<void> _edit(BuildContext context, String id) async {
    var parent = parents[id] ?? _coordinator;
    final options = members.where(
      (member) => member.id != id && !_wouldCycle(id, member.id),
    );
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Współpraca · ${members.firstWhere((m) => m.id == id).name}',
        ),
        content: SizedBox(
          width: 380,
          child: DropdownButtonFormField<String>(
            initialValue: parent,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Raportuje do'),
            items: [
              const DropdownMenuItem(
                value: _coordinator,
                child: Text('Koordynacja zespołu'),
              ),
              for (final option in options)
                DropdownMenuItem(value: option.id, child: Text(option.name)),
            ],
            onChanged: (value) {
              if (value != null) parent = value;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Anuluj'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, parent),
            child: const Text('Zapisz relację'),
          ),
        ],
      ),
    );
    if (selected == null || !context.mounted) return;
    final updated = {...parents};
    if (selected == _coordinator) {
      updated.remove(id);
    } else {
      updated[id] = selected;
    }
    onChanged(updated);
  }

  @override
  Widget build(BuildContext context) {
    final levels = <int, List<({String id, String name, String role})>>{};
    for (final member in members) {
      var depth = 1;
      var cursor = parents[member.id];
      final visited = {member.id};
      while (cursor != null && visited.add(cursor)) {
        depth++;
        cursor = parents[cursor];
      }
      levels.putIfAbsent(depth, () => []).add(member);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(caption),
        const SizedBox(height: 12),
        if (members.isEmpty) const Text('Dodaj boty do zespołu.'),
        if (members.isNotEmpty)
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = levels.values.fold<int>(
                1,
                (count, row) => math.max(count, row.length),
              );
              final width = math.max(constraints.maxWidth, columns * 210.0);
              final depth = levels.keys.fold<int>(0, math.max);
              final points = <String, Offset>{
                _coordinator: Offset(width / 2, 44),
              };
              for (final entry in levels.entries) {
                for (var i = 0; i < entry.value.length; i++) {
                  points[entry.value[i].id] = Offset(
                    width * (i + .5) / entry.value.length,
                    entry.key * 126.0 + 44,
                  );
                }
              }
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: width,
                  height: depth * 126.0 + 92,
                  child: CustomPaint(
                    painter: _HierarchyPainter(
                      points: points,
                      parents: {
                        for (final member in members)
                          member.id: parents[member.id] ?? _coordinator,
                      },
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    child: Stack(
                      children: [
                        Positioned(
                          left: width / 2 - 100,
                          top: 0,
                          width: 200,
                          height: 88,
                          child: const Card(
                            child: Center(
                              child: Text(
                                'Koordynacja zespołu',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ),
                        for (final member in members)
                          Positioned(
                            left: points[member.id]!.dx - 100,
                            top: points[member.id]!.dy - 44,
                            width: 200,
                            height: 88,
                            child: Card(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primaryContainer,
                              child: InkWell(
                                onTap: enabled
                                    ? () => _edit(context, member.id)
                                    : null,
                                borderRadius: BorderRadius.circular(18),
                                child: Padding(
                                  padding: const EdgeInsets.all(10),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        member.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        member.role,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const Icon(Icons.edit, size: 14),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

class _HierarchyPainter extends CustomPainter {
  const _HierarchyPainter({
    required this.points,
    required this.parents,
    required this.color,
  });
  final Map<String, Offset> points;
  final Map<String, String> parents;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    for (final entry in parents.entries) {
      final source = points[entry.value];
      final target = points[entry.key];
      if (source == null || target == null) continue;
      final start = source + const Offset(0, 44);
      final end = target - const Offset(0, 44);
      final middle = (start.dy + end.dy) / 2;
      canvas.drawPath(
        Path()
          ..moveTo(start.dx, start.dy)
          ..lineTo(start.dx, middle)
          ..lineTo(end.dx, middle)
          ..lineTo(end.dx, end.dy)
          ..moveTo(end.dx - 5, end.dy - 7)
          ..lineTo(end.dx, end.dy)
          ..lineTo(end.dx + 5, end.dy - 7),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_HierarchyPainter oldDelegate) =>
      color != oldDelegate.color ||
      !mapEquals(points, oldDelegate.points) ||
      !mapEquals(parents, oldDelegate.parents);
}
