import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../models/product.dart';
import '../../products/product_photo_service.dart';
import '../../repository/bakery_repository.dart';
import '../../utils/guarded_action.dart';
import '../../utils/segment_label.dart';
import '../widgets/product_avatar.dart';
import 'browse_photos_dialog.dart';
import 'media_manager_screen.dart';

class ProductsListScreen extends StatefulWidget {
  const ProductsListScreen({super.key});

  @override
  State<ProductsListScreen> createState() => _ProductsListScreenState();
}

enum _CategoryFilter { all, bakery, merchandise }

IconData _categoryIcon(ProductCategory category) => switch (category) {
  ProductCategory.bakery => Icons.bakery_dining_outlined,
  ProductCategory.merchandise => Icons.shopping_bag_outlined,
};

class _ProductsListScreenState extends State<ProductsListScreen> {
  String _search = '';
  _CategoryFilter _filter = _CategoryFilter.all;
  bool _showArchived = false;
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final products =
        appState.products
            .where((p) => p.title.toLowerCase().contains(_search.toLowerCase()))
            .where((p) => p.isArchived == _showArchived)
            .where(
              (p) => switch (_filter) {
                _CategoryFilter.all => true,
                _CategoryFilter.bakery => p.category == ProductCategory.bakery,
                _CategoryFilter.merchandise =>
                  p.category == ProductCategory.merchandise,
              },
            )
            .toList()
          ..sort(
            (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
          );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Products'),
        actions: [
          IconButton(
            icon: Icon(
              _showArchived ? Icons.unarchive_outlined : Icons.archive_outlined,
            ),
            tooltip: _showArchived
                ? 'Show active products'
                : 'Show archived products',
            onPressed: () => setState(() => _showArchived = !_showArchived),
          ),
          IconButton(
            icon: const Icon(Icons.photo_library_outlined),
            tooltip: 'Media manager',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const MediaManagerScreen()),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddProductDialog(context),
        tooltip: 'New product',
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Search products...',
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: _search.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(() {
                          _search = '';
                          _searchController.clear();
                        }),
                      ),
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SegmentedButton<_CategoryFilter>(
                segments: [
                  ButtonSegment(
                    value: _CategoryFilter.all,
                    icon: const Icon(Icons.apps),
                    label: compactLabel('All'),
                    tooltip: 'All',
                  ),
                  ButtonSegment(
                    value: _CategoryFilter.bakery,
                    icon: Icon(_categoryIcon(ProductCategory.bakery)),
                    label: compactLabel('Bakery'),
                    tooltip: 'Bakery',
                  ),
                  ButtonSegment(
                    value: _CategoryFilter.merchandise,
                    icon: Icon(_categoryIcon(ProductCategory.merchandise)),
                    label: compactLabel('Merchandise'),
                    tooltip: 'Merchandise',
                  ),
                ],
                selected: {_filter},
                onSelectionChanged: (s) => setState(() => _filter = s.first),
              ),
            ),
          ),
          if (_showArchived)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Viewing archived products - hidden from batch creation.',
                style: TextStyle(fontSize: 12),
              ),
            ),
          const SizedBox(height: 8),
          Expanded(
            child: products.isEmpty
                ? Center(
                    child: Text(
                      _showArchived
                          ? 'No archived products.'
                          : switch (_filter) {
                              _CategoryFilter.all => 'No products yet.',
                              _CategoryFilter.bakery =>
                                'No bakery products yet.',
                              _CategoryFilter.merchandise =>
                                'No merchandise products yet.',
                            },
                    ),
                  )
                : ListView.builder(
                    itemCount: products.length,
                    itemBuilder: (context, index) {
                      final product = products[index];
                      return ListTile(
                        leading: ProductAvatar(imageUrl: product.imageUrl),
                        title: Text(product.title),
                        subtitle: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(_categoryIcon(product.category), size: 14),
                            const SizedBox(width: 4),
                            Text(
                              product.category == ProductCategory.merchandise
                                  ? 'Merchandise'
                                  : 'Bakery',
                            ),
                          ],
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _editProduct(context, product),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddProductDialog(BuildContext context) async {
    final titleController = TextEditingController();
    var category = ProductCategory.bakery;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('New product'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(labelText: 'Product name'),
                autofocus: true,
              ),
              const SizedBox(height: 16),
              SegmentedButton<ProductCategory>(
                segments: const [
                  ButtonSegment(
                    value: ProductCategory.bakery,
                    label: Text('Bakery'),
                  ),
                  ButtonSegment(
                    value: ProductCategory.merchandise,
                    label: Text('Merchandise'),
                  ),
                ],
                selected: {category},
                onSelectionChanged: (s) =>
                    setDialogState(() => category = s.first),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
    final title = titleController.text.trim();
    if (result != true || title.isEmpty || !context.mounted) return;
    await runGuarded(
      context,
      () => context.read<BakeryRepository>().createProduct(
        Product(
          id: 0,
          title: title,
          category: category,
          updatedAt: DateTime.now(),
        ),
      ),
    );
  }

  Future<void> _editProduct(BuildContext context, Product product) async {
    final titleController = TextEditingController(text: product.title);
    var imageUrl = product.imageUrl;
    var category = product.category;
    var isArchived = product.isArchived;
    var uploading = false;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> pickPhoto() async {
            if (product.remoteId == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'This product hasn\'t synced yet - try again shortly.',
                  ),
                ),
              );
              return;
            }
            final picked = await ImagePicker().pickImage(
              source: ImageSource.gallery,
              imageQuality: 82,
              maxWidth: 1600,
              maxHeight: 1600,
            );
            if (picked == null) return;
            setDialogState(() => uploading = true);
            try {
              final url = await uploadProductPhoto(
                stableId: product.remoteId!,
                file: picked,
              );
              setDialogState(() {
                imageUrl = url;
                uploading = false;
              });
            } catch (e) {
              setDialogState(() => uploading = false);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Photo upload failed: $e')),
                );
              }
            }
          }

          Future<void> browseExisting() async {
            final picked = await showBrowsePhotosDialog(context);
            if (picked != null) setDialogState(() => imageUrl = picked);
          }

          return AlertDialog(
            title: const Text('Edit product'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    if (uploading)
                      const CircleAvatar(
                        radius: 40,
                        child: CircularProgressIndicator(),
                      )
                    else
                      ProductAvatar(imageUrl: imageUrl, radius: 40),
                    IconButton.filled(
                      icon: const Icon(Icons.camera_alt, size: 18),
                      tooltip: 'Upload a new photo',
                      onPressed: uploading ? null : pickPhoto,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: uploading ? null : browseExisting,
                  icon: const Icon(Icons.photo_library_outlined, size: 18),
                  label: const Text('Browse existing images'),
                ),
                if (imageUrl != null)
                  TextButton.icon(
                    onPressed: uploading
                        ? null
                        : () => setDialogState(() => imageUrl = null),
                    icon: const Icon(Icons.no_photography_outlined, size: 18),
                    label: const Text('Remove photo'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.red.shade700,
                    ),
                  ),
                const SizedBox(height: 16),
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(labelText: 'Product name'),
                  autofocus: true,
                ),
                const SizedBox(height: 16),
                SegmentedButton<ProductCategory>(
                  segments: const [
                    ButtonSegment(
                      value: ProductCategory.bakery,
                      label: Text('Bakery'),
                    ),
                    ButtonSegment(
                      value: ProductCategory.merchandise,
                      label: Text('Merchandise'),
                    ),
                  ],
                  selected: {category},
                  onSelectionChanged: (s) =>
                      setDialogState(() => category = s.first),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Archived'),
                  subtitle: const Text(
                    'Hides it from batch creation and the active product list - '
                    'existing batches keep working',
                  ),
                  value: isArchived,
                  onChanged: (v) => setDialogState(() => isArchived = v),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
    if (result != true || titleController.text.trim().isEmpty) return;
    if (!context.mounted) return;
    await runGuarded(
      context,
      () => context.read<BakeryRepository>().updateProduct(
        Product(
          id: product.id,
          remoteId: product.remoteId,
          title: titleController.text.trim(),
          imageUrl: imageUrl,
          category: category,
          isArchived: isArchived,
          updatedAt: DateTime.now(),
          isDeleted: product.isDeleted,
        ),
      ),
    );
  }
}
