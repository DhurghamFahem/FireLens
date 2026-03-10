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
          mapSubFields: f.mapFields
              .map((sf) => _MapSubFieldEntry(
                    nameCtrl: TextEditingController(text: sf.name),
                    type: sf.type,
                  ))
              .toList(),
          arrayItemType: f.arrayItemType ?? FieldType.string,
        ));
      }
    }
    if (_fields.isEmpty) _addField();
  }

  @override
  void dispose() {
    _collectionNameCtrl.dispose();
    for (final f in _fields) {
      f.dispose();
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
      _fields[index].dispose();
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
              mapFields: e.type == FieldType.map
                  ? e.mapSubFields
                      .where((sf) => sf.nameCtrl.text.trim().isNotEmpty)
                      .map((sf) => FieldDefinition(
                            name: sf.nameCtrl.text.trim(),
                            label: sf.nameCtrl.text.trim(),
                            type: sf.type,
                          ))
                      .toList()
                  : const [],
              arrayItemType:
                  e.type == FieldType.array ? e.arrayItemType : null,
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
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Data classes ─────────────────────────────────────────────────────────────

class _MapSubFieldEntry {
  final TextEditingController nameCtrl;
  FieldType type;

  _MapSubFieldEntry({
    required this.nameCtrl,
    this.type = FieldType.string,
  });

  void dispose() => nameCtrl.dispose();
}

class _FieldEntry {
  final TextEditingController nameCtrl;
  final TextEditingController labelCtrl;
  FieldType type;
  List<_MapSubFieldEntry> mapSubFields;
  FieldType arrayItemType;

  _FieldEntry({
    required this.nameCtrl,
    required this.labelCtrl,
    this.type = FieldType.string,
    List<_MapSubFieldEntry>? mapSubFields,
    this.arrayItemType = FieldType.string,
  }) : mapSubFields = mapSubFields ?? [];

  void dispose() {
    nameCtrl.dispose();
    labelCtrl.dispose();
    for (final sf in mapSubFields) {
      sf.dispose();
    }
  }
}

// ─── Field Row (StatefulWidget) ───────────────────────────────────────────────

class _FieldRow extends StatefulWidget {
  final _FieldEntry entry;
  final int index;
  final bool canRemove;
  final VoidCallback onRemove;

  const _FieldRow({
    super.key,
    required this.entry,
    required this.index,
    required this.canRemove,
    required this.onRemove,
  });

  @override
  State<_FieldRow> createState() => _FieldRowState();
}

class _FieldRowState extends State<_FieldRow> {
  void _onTypeChanged(FieldType? t) {
    if (t == null || t == widget.entry.type) return;
    setState(() {
      if (t != FieldType.map) {
        for (final sf in widget.entry.mapSubFields) {
          sf.dispose();
        }
        widget.entry.mapSubFields.clear();
      }
      if (t != FieldType.array) {
        widget.entry.arrayItemType = FieldType.string;
      }
      widget.entry.type = t;
    });
  }

  void _addSubField() {
    setState(() {
      widget.entry.mapSubFields.add(
        _MapSubFieldEntry(nameCtrl: TextEditingController()),
      );
    });
  }

  void _removeSubField(int i) {
    setState(() {
      widget.entry.mapSubFields[i].dispose();
      widget.entry.mapSubFields.removeAt(i);
    });
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 10, 4, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Single row: index | name | label | type | delete | drag
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 14, right: 6),
                  child: Text(
                    '${widget.index + 1}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: entry.nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Name',
                      hintText: 'e.g. title',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  flex: 3,
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
                const SizedBox(width: 6),
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<FieldType>(
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
                              child: Text(t.displayName,
                                  overflow: TextOverflow.ellipsis),
                            ))
                        .toList(),
                    onChanged: _onTypeChanged,
                  ),
                ),
                if (widget.canRemove)
                  IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    tooltip: 'Remove field',
                    visualDensity: VisualDensity.compact,
                    onPressed: widget.onRemove,
                  ),
                ReorderableDragStartListener(
                  index: widget.index,
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.drag_handle, size: 20),
                  ),
                ),
              ],
            ),

            // Map sub-fields config
            if (entry.type == FieldType.map) ...[
              const SizedBox(height: 10),
              _buildMapSubFields(context),
            ],

            // Array item type config
            if (entry.type == FieldType.array) ...[
              const SizedBox(height: 10),
              _buildArrayConfig(context),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMapSubFields(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Map Sub-fields',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                )),
        const SizedBox(height: 6),
        for (var i = 0; i < widget.entry.mapSubFields.length; i++)
          _MapSubFieldRow(
            key: ObjectKey(widget.entry.mapSubFields[i]),
            entry: widget.entry.mapSubFields[i],
            onTypeChanged: (t) => setState(
                () => widget.entry.mapSubFields[i].type = t ?? FieldType.string),
            onRemove: () => _removeSubField(i),
          ),
        TextButton.icon(
          onPressed: _addSubField,
          icon: const Icon(Icons.add, size: 14),
          label: const Text('Add Sub-field'),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
            visualDensity: VisualDensity.compact,
          ),
        ),
      ],
    );
  }

  Widget _buildArrayConfig(BuildContext context) {
    return Row(
      children: [
        Text('Item Type:',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                )),
        const SizedBox(width: 10),
        Expanded(
          child: DropdownButtonFormField<FieldType>(
            initialValue: widget.entry.arrayItemType,
            isDense: true,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: FieldType.values
                .map((t) => DropdownMenuItem(
                      value: t,
                      child: Text(t.displayName),
                    ))
                .toList(),
            onChanged: (t) =>
                setState(() => widget.entry.arrayItemType = t ?? FieldType.string),
          ),
        ),
      ],
    );
  }
}

// ─── Map sub-field row ────────────────────────────────────────────────────────

class _MapSubFieldRow extends StatelessWidget {
  final _MapSubFieldEntry entry;
  final ValueChanged<FieldType?> onTypeChanged;
  final VoidCallback onRemove;

  const _MapSubFieldRow({
    super.key,
    required this.entry,
    required this.onTypeChanged,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, left: 12),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: TextField(
              controller: entry.nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Sub-field name',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 3,
            child: DropdownButtonFormField<FieldType>(
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
                        child:
                            Text(t.displayName, overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: onTypeChanged,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            visualDensity: VisualDensity.compact,
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}
