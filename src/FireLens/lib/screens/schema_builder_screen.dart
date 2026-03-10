import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/schema_model.dart';
import '../providers/firebase_provider.dart';
import '../services/firestore_service.dart';

class SchemaBuilderScreen extends StatefulWidget {
  final SchemaModel? existing;
  final VoidCallback onSaved;

  const SchemaBuilderScreen({
    super.key,
    this.existing,
    required this.onSaved,
  });

  @override
  State<SchemaBuilderScreen> createState() => _SchemaBuilderScreenState();
}

class _SchemaBuilderScreenState extends State<SchemaBuilderScreen> {
  final _formKey = GlobalKey<FormState>();
  final _collectionNameCtrl = TextEditingController();
  final List<_FieldEntry> _fields = [];
  bool _saving = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      _collectionNameCtrl.text = widget.existing!.collectionName;
      for (final f in widget.existing!.fields) {
        _fields.add(_FieldEntry(
          nameCtrl: TextEditingController(text: f.name),
          labelCtrl: TextEditingController(text: f.label),
          type: f.type,
        ));
      }
    }
    if (_fields.isEmpty) _addField();
  }

  @override
  void dispose() {
    _collectionNameCtrl.dispose();
    for (final f in _fields) {
      f.nameCtrl.dispose();
      f.labelCtrl.dispose();
    }
    super.dispose();
  }

  void _addField() {
    setState(() {
      _fields.add(_FieldEntry(
        nameCtrl: TextEditingController(),
        labelCtrl: TextEditingController(),
        type: FieldType.string,
      ));
    });
  }

  void _removeField(int index) {
    setState(() {
      _fields[index].nameCtrl.dispose();
      _fields[index].labelCtrl.dispose();
      _fields.removeAt(index);
    });
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final fields = _fields
        .map((e) => FieldDefinition(
              name: e.nameCtrl.text.trim(),
              label: e.labelCtrl.text.trim(),
              type: e.type,
            ))
        .toList();

    final schema = SchemaModel(
      collectionName: _collectionNameCtrl.text.trim(),
      fields: fields,
    );

    setState(() => _saving = true);
    try {
      final app = context.read<FirebaseProvider>().app;
      await FirestoreService(app).saveSchema(schema);
      widget.onSaved();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error saving schema: $e'),
              backgroundColor: Colors.red),
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
        title: Text(_isEditing ? 'Edit Schema' : 'New Schema'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _collectionNameCtrl,
              enabled: !_isEditing,
              decoration: const InputDecoration(
                labelText: 'Collection Name',
                hintText: 'e.g. products',
                border: OutlineInputBorder(),
                helperText:
                    'Matches an existing or new Firestore collection.',
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Text('Fields',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                TextButton.icon(
                  onPressed: _addField,
                  icon: const Icon(Icons.add),
                  label: const Text('Add Field'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _fields.length,
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (newIndex > oldIndex) newIndex--;
                  final item = _fields.removeAt(oldIndex);
                  _fields.insert(newIndex, item);
                });
              },
              itemBuilder: (context, index) {
                final entry = _fields[index];
                return _FieldRow(
                  key: ValueKey(entry),
                  entry: entry,
                  index: index,
                  canRemove: _fields.length > 1,
                  onRemove: () => _removeField(index),
                  onTypeChanged: (t) =>
                      setState(() => entry.type = t ?? FieldType.string),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldEntry {
  final TextEditingController nameCtrl;
  final TextEditingController labelCtrl;
  FieldType type;

  _FieldEntry({
    required this.nameCtrl,
    required this.labelCtrl,
    required this.type,
  });
}

class _FieldRow extends StatelessWidget {
  final _FieldEntry entry;
  final int index;
  final bool canRemove;
  final VoidCallback onRemove;
  final ValueChanged<FieldType?> onTypeChanged;

  const _FieldRow({
    super.key,
    required this.entry,
    required this.index,
    required this.canRemove,
    required this.onRemove,
    required this.onTypeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
        child: Column(
          children: [
            Row(
              children: [
                Text('Field ${index + 1}',
                    style: Theme.of(context).textTheme.labelLarge),
                const Spacer(),
                if (canRemove)
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    tooltip: 'Remove field',
                    onPressed: onRemove,
                  ),
                ReorderableDragStartListener(
                  index: index,
                  child: const Icon(Icons.drag_handle),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Row 1: name + label
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: entry.nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Field name',
                      hintText: 'e.g. title',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: entry.labelCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Label',
                      hintText: 'e.g. Product Title',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Row 2: type dropdown — full width, no overflow risk
            DropdownButtonFormField<FieldType>(
              initialValue: entry.type,
              isDense: true,
              decoration: const InputDecoration(
                labelText: 'Type',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: FieldType.values
                  .map((t) => DropdownMenuItem(
                        value: t,
                        child: Text(t.displayName),
                      ))
                  .toList(),
              onChanged: onTypeChanged,
            ),
          ],
        ),
      ),
    );
  }
}
