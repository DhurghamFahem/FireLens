import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/schema_model.dart';
import '../providers/firebase_provider.dart';
import '../services/firestore_service.dart';
import 'connection_screen.dart';
import 'collection_screen.dart';
import 'schema_builder_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Future<List<SchemaModel>> _schemasFuture;

  @override
  void initState() {
    super.initState();
    _loadSchemas();
  }

  void _loadSchemas() {
    final app = context.read<FirebaseProvider>().app;
    _schemasFuture = FirestoreService(app).getSchemas();
  }

  Future<void> _refresh() async {
    setState(_loadSchemas);
  }

  Future<void> _deleteSchema(String collectionName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Schema'),
        content: Text(
            'Delete the schema for "$collectionName"? The Firestore collection is NOT deleted.'),
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
    await FirestoreService(app).deleteSchema(collectionName);
    _refresh();
  }

  Future<void> _disconnect() async {
    await context.read<FirebaseProvider>().disconnect();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const ConnectionScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final config = context.watch<FirebaseProvider>().config;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('FireLens Dashboard'),
            if (config != null)
              Text(
                config.projectId,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.onSurface),
              ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
          IconButton(
            tooltip: 'Disconnect',
            icon: const Icon(Icons.logout),
            onPressed: _disconnect,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => SchemaBuilderScreen(onSaved: _refresh),
            ),
          );
        },
        icon: const Icon(Icons.add),
        label: const Text('New Schema'),
      ),
      body: FutureBuilder<List<SchemaModel>>(
        future: _schemasFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorView(
                message: snapshot.error.toString(), onRetry: _refresh);
          }
          final schemas = snapshot.data ?? [];
          if (schemas.isEmpty) {
            return _EmptyState(onAdd: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SchemaBuilderScreen(onSaved: _refresh),
                ),
              );
            });
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: schemas.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final schema = schemas[index];
                return _SchemaCard(
                  schema: schema,
                  onOpen: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => CollectionScreen(schema: schema),
                    ),
                  ),
                  onEdit: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => SchemaBuilderScreen(
                          existing: schema,
                          onSaved: _refresh,
                        ),
                      ),
                    );
                  },
                  onDelete: () => _deleteSchema(schema.collectionName),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _SchemaCard extends StatelessWidget {
  final SchemaModel schema;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _SchemaCard({
    required this.schema,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Icon(Icons.folder,
              color: Theme.of(context).colorScheme.onPrimaryContainer),
        ),
        title: Text(schema.collectionName,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(
            '${schema.fields.length} field${schema.fields.length == 1 ? '' : 's'}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
                tooltip: 'Edit schema',
                icon: const Icon(Icons.edit_outlined),
                onPressed: onEdit),
            IconButton(
                tooltip: 'Delete schema',
                icon: const Icon(Icons.delete_outline),
                onPressed: onDelete),
          ],
        ),
        onTap: onOpen,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.schema_outlined,
              size: 72,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(height: 16),
          Text('No schemas yet',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text('Create a schema to start managing your Firestore data.'),
          const SizedBox(height: 24),
          FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('New Schema')),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
