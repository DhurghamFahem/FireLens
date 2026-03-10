import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/schema_model.dart';
import '../providers/firebase_provider.dart';
import '../services/firestore_service.dart';
import 'document_form_screen.dart';

class CollectionScreen extends StatefulWidget {
  final SchemaModel schema;

  const CollectionScreen({super.key, required this.schema});

  @override
  State<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends State<CollectionScreen> {
  late Future<List<Map<String, dynamic>>> _docsFuture;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final app = context.read<FirebaseProvider>().app;
    _docsFuture =
        FirestoreService(app).getDocuments(widget.schema.collectionName);
  }

  Future<void> _refresh() async => setState(_load);

  Future<void> _deleteDoc(String docId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Document'),
        content: Text('Delete document "$docId"? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final app = context.read<FirebaseProvider>().app;
    await FirestoreService(app)
        .deleteDocument(widget.schema.collectionName, docId);
    _refresh();
  }

  Future<void> _openForm({Map<String, dynamic>? initialData}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DocumentFormScreen(
          schema: widget.schema,
          initialData: initialData,
          onSaved: _refresh,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.schema.collectionName),
        actions: [
          IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh),
              onPressed: _refresh),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text('New Document'),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _docsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 12),
                  Text(snapshot.error.toString(), textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  FilledButton(
                      onPressed: _refresh, child: const Text('Retry')),
                ],
              ),
            );
          }

          final docs = snapshot.data ?? [];
          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.inbox_outlined,
                      size: 64,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(height: 16),
                  const Text('No documents yet'),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                      onPressed: () => _openForm(),
                      icon: const Icon(Icons.add),
                      label: const Text('New Document')),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: docs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final doc = docs[index];
                final docId = doc['__id'] as String;
                // Show defined fields as subtitle chips
                final preview = widget.schema.fields
                    .take(3)
                    .map((f) => '${f.label}: ${_preview(doc[f.name])}')
                    .join('  •  ');

                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor:
                          Theme.of(context).colorScheme.secondaryContainer,
                      child: Text(
                        (index + 1).toString(),
                        style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSecondaryContainer),
                      ),
                    ),
                    title: Text(docId,
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 13)),
                    subtitle: preview.isNotEmpty ? Text(preview) : null,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Edit',
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => _openForm(initialData: doc),
                        ),
                        IconButton(
                          tooltip: 'Delete',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _deleteDoc(docId),
                        ),
                      ],
                    ),
                    onTap: () => _openForm(initialData: doc),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  String _preview(dynamic value) {
    if (value == null) return '—';
    final s = value.toString();
    return s.length > 30 ? '${s.substring(0, 30)}…' : s;
  }
}
