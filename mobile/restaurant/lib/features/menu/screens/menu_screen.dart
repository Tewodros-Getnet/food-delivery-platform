import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
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
  String? _selectedCategory;

  static const _brandColor = Color(0xFF2E7D32);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items =
          await ref.read(menuServiceProvider).getItems(widget.restaurantId);
      if (mounted) {
        setState(() {
          _items = items;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
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

  Future<void> _toggleAvailability(int realIndex) async {
    final item = _items[realIndex] as Map<String, dynamic>;
    final id = item['id'] as String;
    final originalValue = item['available'] as bool? ?? true;

    setState(() {
      _togglingIds.add(id);
      (_items[realIndex] as Map<String, dynamic>)['available'] = !originalValue;
    });

    try {
      final updated =
          await ref.read(menuServiceProvider).toggleAvailability(id);
      if (!mounted) return;
      setState(() => _items[realIndex] = updated);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        (_items[realIndex] as Map<String, dynamic>)['available'] =
            originalValue;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to update availability')),
      );
    } finally {
      if (mounted) setState(() => _togglingIds.remove(id));
    }
  }

  Future<void> _deleteItem(String id, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Item'),
        content: Text('Remove "$name" from your menu?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(menuServiceProvider).deleteItem(id);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Item deleted')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to delete: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showAddSheet({Map<String, dynamic>? existing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _ItemSheet(
        restaurantId: widget.restaurantId,
        existing: existing,
        onSaved: _load,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Menu Management'),
        backgroundColor: _brandColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddSheet(),
        backgroundColor: _brandColor,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Add Item', style: TextStyle(color: Colors.white)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.restaurant_menu,
                          size: 72, color: Colors.grey[300]),
                      const SizedBox(height: 16),
                      const Text('No menu items yet',
                          style: TextStyle(fontSize: 17, color: Colors.grey)),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        onPressed: () => _showAddSheet(),
                        icon: const Icon(Icons.add),
                        label: const Text('Add your first item'),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: _brandColor,
                            foregroundColor: Colors.white),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: Column(
                    children: [
                      // Category filter chips
                      if (_categories.isNotEmpty)
                        Container(
                          color: Colors.white,
                          child: SizedBox(
                            height: 48,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: FilterChip(
                                    label: const Text('All'),
                                    selected: _selectedCategory == null,
                                    onSelected: (_) => setState(
                                        () => _selectedCategory = null),
                                    selectedColor:
                                        _brandColor.withValues(alpha: 0.15),
                                    checkmarkColor: _brandColor,
                                    labelStyle: TextStyle(
                                      color: _selectedCategory == null
                                          ? _brandColor
                                          : Colors.black87,
                                      fontWeight: _selectedCategory == null
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                  ),
                                ),
                                ..._categories.map(
                                  (cat) => Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: FilterChip(
                                      label: Text(cat),
                                      selected: _selectedCategory == cat,
                                      onSelected: (_) => setState(
                                          () => _selectedCategory = cat),
                                      selectedColor:
                                          _brandColor.withValues(alpha: 0.15),
                                      checkmarkColor: _brandColor,
                                      labelStyle: TextStyle(
                                        color: _selectedCategory == cat
                                            ? _brandColor
                                            : Colors.black87,
                                        fontWeight: _selectedCategory == cat
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 100),
                          itemCount: _filteredItems.length,
                          itemBuilder: (ctx, i) {
                            final item =
                                _filteredItems[i] as Map<String, dynamic>;
                            final itemId = item['id'] as String;
                            final isAvailable =
                                item['available'] as bool? ?? true;
                            final isToggling = _togglingIds.contains(itemId);
                            final realIndex = _items.indexWhere((e) =>
                                (e as Map<String, dynamic>)['id'] == itemId);

                            return _MenuItemCard(
                              item: item,
                              isAvailable: isAvailable,
                              isToggling: isToggling,
                              onToggle: realIndex >= 0
                                  ? () => _toggleAvailability(realIndex)
                                  : null,
                              onEdit: () => _showAddSheet(existing: item),
                              onDelete: () =>
                                  _deleteItem(itemId, item['name'] as String),
                              onModifiers: () => context.push(
                                '/menu-item/$itemId/modifiers?name=${Uri.encodeComponent(item['name'] as String)}',
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
}

// ── Menu item card ────────────────────────────────────────────────────────────

class _MenuItemCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final bool isAvailable;
  final bool isToggling;
  final VoidCallback? onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onModifiers;

  const _MenuItemCard({
    required this.item,
    required this.isAvailable,
    required this.isToggling,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
    required this.onModifiers,
  });

  @override
  Widget build(BuildContext context) {
    final imageUrl = item['image_url'] as String?;
    final name = item['name'] as String;
    final price = item['price'];
    final category = item['category'] as String?;
    final description = item['description'] as String?;
    final hasModifiers = (item['modifiers'] as List?)?.isNotEmpty == true;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Opacity(
        opacity: isAvailable ? 1.0 : 0.6,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Image
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: imageUrl != null && imageUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: imageUrl,
                        width: 72,
                        height: 72,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => _placeholder(),
                      )
                    : _placeholder(),
              ),
              const SizedBox(width: 12),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                        child: Text(name,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 14)),
                      ),
                      if (!isAvailable)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.red.shade200),
                          ),
                          child: Text('Unavailable',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.red.shade700,
                                  fontWeight: FontWeight.w600)),
                        ),
                    ]),
                    if (description != null && description.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              TextStyle(fontSize: 12, color: Colors.grey[600])),
                    ],
                    const SizedBox(height: 4),
                    Row(children: [
                      Text('ETB ${price.toString()}',
                          style: const TextStyle(
                              color: Color(0xFF2E7D32),
                              fontWeight: FontWeight.bold,
                              fontSize: 13)),
                      if (category != null && category.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(category,
                              style: TextStyle(
                                  fontSize: 10, color: Colors.grey[600])),
                        ),
                      ],
                      if (hasModifiers) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('Customisable',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.orange,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ]),
                    const SizedBox(height: 8),
                    // Action row
                    Row(children: [
                      // Availability toggle
                      isToggling
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Color(0xFF2E7D32)))
                          : Transform.scale(
                              scale: 0.8,
                              child: Switch(
                                value: isAvailable,
                                activeColor: const Color(0xFF2E7D32),
                                onChanged: onToggle != null
                                    ? (_) => onToggle!()
                                    : null,
                              ),
                            ),
                      const Spacer(),
                      // Modifiers
                      _ActionChip(
                        icon: Icons.tune,
                        label: 'Modifiers',
                        color: Colors.orange,
                        onTap: onModifiers,
                      ),
                      const SizedBox(width: 6),
                      // Edit
                      _ActionChip(
                        icon: Icons.edit_outlined,
                        label: 'Edit',
                        color: const Color(0xFF2E7D32),
                        onTap: onEdit,
                      ),
                      const SizedBox(width: 6),
                      // Delete
                      GestureDetector(
                        onTap: onDelete,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Icon(Icons.delete_outline,
                              size: 16, color: Colors.red.shade600),
                        ),
                      ),
                    ]),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _placeholder() => Container(
        width: 72,
        height: 72,
        color: Colors.grey[200],
        child: const Icon(Icons.fastfood, color: Colors.grey, size: 28),
      );
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11, color: color, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

// ── Add / Edit item bottom sheet ──────────────────────────────────────────────

class _ItemSheet extends ConsumerStatefulWidget {
  final String restaurantId;
  final Map<String, dynamic>? existing; // null = add mode
  final VoidCallback onSaved;

  const _ItemSheet({
    required this.restaurantId,
    this.existing,
    required this.onSaved,
  });

  @override
  ConsumerState<_ItemSheet> createState() => _ItemSheetState();
}

class _ItemSheetState extends ConsumerState<_ItemSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _catCtrl;
  File? _image;
  bool _loading = false;

  bool get _isEdit => widget.existing != null;

  static const _brandColor = Color(0xFF2E7D32);

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?['name'] as String? ?? '');
    _descCtrl = TextEditingController(text: e?['description'] as String? ?? '');
    _priceCtrl =
        TextEditingController(text: e != null ? e['price'].toString() : '');
    _catCtrl = TextEditingController(text: e?['category'] as String? ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    _catCtrl.dispose();
    super.dispose();
  }

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
    if (!_formKey.currentState!.validate()) return;
    if (!_isEdit && _image == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please pick an image')),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final data = <String, dynamic>{
        'name': _nameCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'price': double.parse(_priceCtrl.text.trim()),
        'category': _catCtrl.text.trim(),
      };
      if (_image != null) {
        final bytes = await _image!.readAsBytes();
        data['imageBase64'] = 'data:image/jpeg;base64,${base64Encode(bytes)}';
      }

      if (_isEdit) {
        await ref
            .read(menuServiceProvider)
            .updateItem(widget.existing!['id'] as String, data);
      } else {
        await ref
            .read(menuServiceProvider)
            .createItem(widget.restaurantId, data);
      }

      widget.onSaved();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  InputDecoration _field(String label, {IconData? icon}) => InputDecoration(
        labelText: label,
        prefixIcon: icon != null ? Icon(icon, size: 18) : null,
        filled: true,
        fillColor: Colors.grey[50],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _brandColor, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.red),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.red, width: 1.5),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final existingImageUrl = widget.existing?['image_url'] as String?;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _isEdit ? 'Edit Menu Item' : 'Add Menu Item',
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              // Image picker
              GestureDetector(
                onTap: _pickImage,
                child: Container(
                  height: 120,
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: Colors.grey.shade300, style: BorderStyle.solid),
                  ),
                  child: _image != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.file(_image!,
                              fit: BoxFit.cover, width: double.infinity),
                        )
                      : existingImageUrl != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Stack(children: [
                                CachedNetworkImage(
                                  imageUrl: existingImageUrl,
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  height: 120,
                                ),
                                Positioned.fill(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.black.withValues(alpha: 0.3),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.camera_alt,
                                            color: Colors.white, size: 28),
                                        SizedBox(height: 4),
                                        Text('Tap to change',
                                            style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 12)),
                                      ],
                                    ),
                                  ),
                                ),
                              ]),
                            )
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add_photo_alternate_outlined,
                                    size: 36, color: Colors.grey[400]),
                                const SizedBox(height: 6),
                                Text('Tap to add image',
                                    style: TextStyle(
                                        color: Colors.grey[500], fontSize: 13)),
                              ],
                            ),
                ),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _nameCtrl,
                decoration: _field('Item name', icon: Icons.fastfood_outlined),
                textCapitalization: TextCapitalization.words,
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _descCtrl,
                decoration: _field('Description (optional)',
                    icon: Icons.notes_outlined),
                maxLines: 2,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _priceCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration:
                    _field('Price (ETB)', icon: Icons.attach_money_outlined),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Required';
                  if (double.tryParse(v.trim()) == null) return 'Invalid price';
                  return null;
                },
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _catCtrl,
                decoration: _field('Category (e.g. Mains, Drinks)',
                    icon: Icons.category_outlined),
                textCapitalization: TextCapitalization.words,
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: _loading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _brandColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Text(
                          _isEdit ? 'Save Changes' : 'Add to Menu',
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
