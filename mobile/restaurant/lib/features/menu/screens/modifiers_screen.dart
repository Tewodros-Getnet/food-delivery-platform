import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/menu_service.dart';

class ModifiersScreen extends ConsumerStatefulWidget {
  final String menuItemId;
  final String menuItemName;

  const ModifiersScreen({
    super.key,
    required this.menuItemId,
    required this.menuItemName,
  });

  @override
  ConsumerState<ModifiersScreen> createState() => _ModifiersScreenState();
}

class _ModifiersScreenState extends ConsumerState<ModifiersScreen> {
  // Each group: { name, type, required, options: [{name, price}] }
  List<Map<String, dynamic>> _groups = [];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final item =
          await ref.read(menuServiceProvider).getItemById(widget.menuItemId);
      final modifiers = item['modifiers'] as List<dynamic>? ?? [];
      setState(() {
        _groups =
            modifiers.map((g) => Map<String, dynamic>.from(g as Map)).toList();
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  void _addGroup() {
    setState(() {
      _groups.add({
        'name': '',
        'type': 'single',
        'required': false,
        'options': <Map<String, dynamic>>[],
      });
    });
  }

  void _removeGroup(int i) => setState(() => _groups.removeAt(i));

  void _addOption(int groupIndex) {
    setState(() {
      (_groups[groupIndex]['options'] as List).add({'name': '', 'price': 0});
    });
  }

  void _removeOption(int groupIndex, int optIndex) {
    setState(() {
      (_groups[groupIndex]['options'] as List).removeAt(optIndex);
    });
  }

  Future<void> _save() async {
    // Validate
    for (final group in _groups) {
      if ((group['name'] as String).trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All modifier groups need a name')),
        );
        return;
      }
      final opts = group['options'] as List;
      for (final opt in opts) {
        if ((opt['name'] as String).trim().isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('All options need a name')),
          );
          return;
        }
      }
    }

    setState(() => _saving = true);
    try {
      await ref
          .read(menuServiceProvider)
          .updateModifiers(widget.menuItemId, _groups);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Modifiers saved!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Modifiers — ${widget.menuItemName}'),
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Save',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: _groups.isEmpty
                      ? const Center(
                          child: Text(
                            'No modifier groups yet.\nTap + to add one.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _groups.length,
                          itemBuilder: (ctx, gi) => _GroupCard(
                            group: _groups[gi],
                            onRemove: () => _removeGroup(gi),
                            onAddOption: () => _addOption(gi),
                            onRemoveOption: (oi) => _removeOption(gi, oi),
                            onChanged: () => setState(() {}),
                          ),
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _addGroup,
                      icon: const Icon(Icons.add),
                      label: const Text('Add Modifier Group'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF2E7D32),
                        side: const BorderSide(color: Color(0xFF2E7D32)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  final Map<String, dynamic> group;
  final VoidCallback onRemove;
  final VoidCallback onAddOption;
  final void Function(int) onRemoveOption;
  final VoidCallback onChanged;

  const _GroupCard({
    required this.group,
    required this.onRemove,
    required this.onAddOption,
    required this.onRemoveOption,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final options = group['options'] as List<dynamic>;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Group header
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: group['name'] as String,
                    decoration: const InputDecoration(
                      labelText: 'Group name (e.g. Size, Extras)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) {
                      group['name'] = v;
                      onChanged();
                    },
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: onRemove,
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Type + required row
            Row(
              children: [
                const Text('Type: '),
                DropdownButton<String>(
                  value: group['type'] as String,
                  items: const [
                    DropdownMenuItem(value: 'single', child: Text('Single')),
                    DropdownMenuItem(value: 'multi', child: Text('Multiple')),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      group['type'] = v;
                      onChanged();
                    }
                  },
                ),
                const SizedBox(width: 16),
                const Text('Required'),
                Switch(
                  value: group['required'] as bool,
                  activeThumbColor: const Color(0xFF2E7D32),
                  onChanged: (v) {
                    group['required'] = v;
                    onChanged();
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Options
            ...options.asMap().entries.map((e) {
              final oi = e.key;
              final opt = e.value as Map<String, dynamic>;
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        initialValue: opt['name'] as String,
                        decoration: const InputDecoration(
                          labelText: 'Option name',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (v) {
                          opt['name'] = v;
                          onChanged();
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        initialValue: (opt['price'] ?? 0).toString(),
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: '+Price',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (v) {
                          opt['price'] = double.tryParse(v) ?? 0;
                          onChanged();
                        },
                      ),
                    ),
                    IconButton(
                      icon:
                          const Icon(Icons.close, size: 18, color: Colors.red),
                      onPressed: () => onRemoveOption(oi),
                    ),
                  ],
                ),
              );
            }),
            TextButton.icon(
              onPressed: onAddOption,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add option'),
            ),
          ],
        ),
      ),
    );
  }
}
