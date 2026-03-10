import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/schema_model.dart';
import '../providers/firebase_provider.dart';
import '../services/firestore_service.dart';
import '../widgets/dynamic_form_renderer.dart';

class DocumentFormScreen extends StatelessWidget {
  final SchemaModel schema;
  final Map<String, dynamic>? initialData;
  final VoidCallback onSaved;

  const DocumentFormScreen({
    super.key,
    required this.schema,
    required this.onSaved,
    this.initialData,
  });

  bool get _isEditing =>
      initialData != null && (initialData!['__id'] as String?)?.isNotEmpty == true;

  String? get _docId => initialData?['__id'] as String?;

  Future<void> _handleSubmit(
      BuildContext context, Map<String, dynamic> data) async {
    final app = context.read<FirebaseProvider>().app;
    final service = FirestoreService(app);

    if (_isEditing) {
      // Update: merge changed fields into existing document
      await service.updateDocument(schema.collectionName, _docId!, data);
    } else {
      // Create: let Firestore auto-generate an ID
      await service.addDocument(schema.collectionName, data);
    }

    onSaved();
    if (context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    // Strip the internal __id key before passing to the form
    final formData = Map<String, dynamic>.from(initialData ?? {})
      ..remove('__id');

    final app = context.read<FirebaseProvider>().app;
    final firestore = FirebaseFirestore.instanceFor(app: app);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_isEditing ? 'Edit Document' : 'New Document'),
            if (_isEditing)
              Text(
                _docId!,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: DynamicFormRenderer(
          schema: schema,
          initialData: formData,
          firestore: firestore,
          onSubmit: (data) => _handleSubmit(context, data),
        ),
      ),
    );
  }
}
