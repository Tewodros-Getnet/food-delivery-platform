import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'dart:io';
import '../services/menu_service.dart';

class MenuScreen extends ConsumerStatefulWidget {
  final String restaurantId;
  const MenuScreen({super.key, required this.restaurantId});
  @override
  ConsumerState<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends ConsumerState<MenuScreen> {
  List<dynamic> _items = [];
  bool _loading = true;
  final Set<String> _togglingIds = {};
  String? _selectedCategory; // null = show all

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items =
          await ref.read(menuServiceProvider).getItems(widget.restaurantId);
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  List<String> get _categories {
    final cats = <String>{};
    for (final item in _items) {
      final cat = (item as Map<String, dynamic>)['category'] as String?;
      if (cat != null && cat.isNotEmpty) cats.add(cat);
    }
    return cats.toList()..sort();
  }

  List<dynamic> get _filteredItems {
    if (_selectedCategory == null) return _items;
    return _items.where((item) {
      final cat = (item as Map<String, dynamic>)['category'] as String?;
      return cat == _selectedCategory;
    }).toList();
  }

  Future<void> _toggleAvailability(int index) async {
    final item = _items[index] as Map<String, dynamic>;
    final id = item['id'] as String;
    final originalValue = item['available'] as bool? ?? true;

    // Optimistic update — flip immediately
    setState(() {
      _togglingIds.add(id);
      (_items[index] as Map<String, dynamic>)['available'] = !originalValue;
    });

    try {
      final updated =
          await ref.read(menuServiceProvider).toggleAvailability(id);
      if (!mounted) return;
      setState(() {
        _items[index] = updated; // use server-confirmed value
      });
    } catch (_) {
      // Revert on error
      if (!mounted) return;
      setState(() {
        (_items[index] as Map<String, dynamic>)['available'] = originalValue;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to update availability')),
      );
    } finally {
      if (mounted) setState(() => _togglingIds.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Menu Management'),
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddSheet(),
        backgroundColor: const Color(0xFF2E7D32),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? const Center(child: Text('No menu items yet. Tap + to add.'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: Column(
                    children: [
                      // Category filter chips
                      if (_categories.isNotEmpty)
                        SizedBox(
                          height: 44,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: FilterChip(
                                  label: const Text('All'),
                                  selected: _selectedCategory == null,
                                  onSelected: (_) =>
                                      setState(() => _selectedCategory = null),
                                  selectedColor:
                                      const Color(0xFF2E7D32).withAlpha(40),
                                  checkmarkColor: const Color(0xFF2E7D32),
                                ),
                              ),
                              ..._categories.map(
                                (cat) => Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: FilterChip(
                                    label: Text(cat),
                                    selected: _selectedCategory == cat,
                                    onSelected: (_) =>
                                        setState(() => _selectedCategory = cat),
                                    selectedColor:
                                        const Color(0xFF2E7D32).withAlpha(40),
                                    checkmarkColor: const Color(0xFF2E7D32),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      Expanded(
                        child: ListView.builder(
                          itemCount: _filteredItems.length,
                          itemBuilder: (ctx, i) {
                            final filtered = _filteredItems;
                            final item = filtered[i] as Map<String, dynamic>;
                            final itemId = item['id'] as String;
                            final isAvailable =
                                item['available'] as bool? ?? true;
                            final isToggling = _togglingIds.contains(itemId);
                            // Find the real index in _items for toggle
                            final realIndex = _items.indexWhere((e) =>
                                (e as Map<String, dynamic>)['id'] == itemId);

                            return ListTile(
                              leading: isAvailable
                                  ? null
                                  : const Icon(Icons.block,
                                      color: Colors.red, size: 18),
                              title: Text(
                                item['name'] as String,
                                style: TextStyle(
                                  color: isAvailable ? null : Colors.grey,
                                ),
                              ),
                              subtitle: Text(
                                'ETB ${item['price']} • ${item['category'] ?? ''}'
                                '${isAvailable ? '' : ' • Sold Out'}',
                                style: TextStyle(
                                  color: isAvailable ? null : Colors.grey,
                                ),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  isToggling
                                      ? const SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2),
                                        )
                                      : Switch(
                                          value: isAvailable,
                                          activeThumbColor:
                                              const Color(0xFF2E7D32),
                                          onChanged: realIndex >= 0
                                              ? (_) =>
                                                  _toggleAvailability(realIndex)
                                              : null,
                                        ),
                                  IconButton(
                                    icon: const Icon(Icons.delete,
                                        color: Colors.red),
                                    onPressed: () async {
                                      await ref
                                          .read(menuServiceProvider)
                                          .deleteItem(itemId);
                                      await _load();
                                    },
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  void _showAddSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) =>
          _AddItemSheet(restaurantId: widget.restaurantId, onAdded: _load),
    );
  }
}

class _AddItemSheet extends ConsumerStatefulWidget {
  final String restaurantId;
  final VoidCallback onAdded;
  const _AddItemSheet({required this.restaurantId, required this.onAdded});
  @override
  ConsumerState<_AddItemSheet> createState() => _AddItemSheetState();
}

class _AddItemSheetState extends ConsumerState<_AddItemSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _catCtrl = TextEditingController();
  File? _image;
  bool _loading = false;

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
      maxWidth: 1024,
      maxHeight: 1024,
    );
    if (picked != null) setState(() => _image = File(picked.path));
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _image == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill all fields and pick an image'),
        ),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final bytes = await _image!.readAsBytes();
      await ref.read(menuServiceProvider).createItem(widget.restaurantId, {
        'name': _nameCtrl.text,
        'description': _descCtrl.text,
        'price': double.parse(_priceCtrl.text),
        'category': _catCtrl.text,
        'imageBase64': 'data:image/jpeg;base64,${base64Encode(bytes)}',
      });
      widget.onAdded();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Add Menu Item',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => v!.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _descCtrl,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _priceCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Price (ETB)',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => v!.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _catCtrl,
                decoration: const InputDecoration(
                  labelText: 'Category',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => v!.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _pickImage,
                icon: const Icon(Icons.image),
                label: Text(
                  _image == null ? 'Pick Image *' : 'Image Selected ✓',
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2E7D32),
                ),
                child: _loading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                        'Add Item',
                        style: TextStyle(color: Colors.white),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
