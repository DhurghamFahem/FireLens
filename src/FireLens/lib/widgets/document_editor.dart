import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/schema_model.dart';

// ─── Stable ID generation ──────────────────────────────────────────────────

int _idSeq = 0;
String _genId() => 'n${_idSeq++}';

// ─── Models ────────────────────────────────────────────────────────────────

/// A single field in the document tree (can nest Maps/Arrays).
class FieldNode {
  final String id; // stable across rebuilds — used as widget key
  String name;
  FieldType type;
  dynamic value; // String | bool | DateTime | GeoPoint | List<FieldNode> | List<ArrayItem> | null

  FieldNode({
    String? id,
    required this.name,
    required this.type,
    required this.value,
  }) : id = id ?? _genId();
}

/// One element inside an Array field.
class ArrayItem {
  final String id;
  FieldType subtype;
  dynamic value;

  ArrayItem({
    String? id,
    required this.subtype,
    required this.value,
  }) : id = id ?? _genId();
}

// ─── Default values per type ───────────────────────────────────────────────

dynamic _defaultValue(FieldType t) => switch (t) {
      FieldType.string => '',
      FieldType.number => '',
      FieldType.boolean => false,
      FieldType.timestamp => DateTime.now(),
      FieldType.map => <FieldNode>[],
      FieldType.array => <ArrayItem>[],
      FieldType.geopoint => const GeoPoint(0, 0),
      FieldType.reference => '',
      FieldType.nullValue => null,
    };

// ─── Firestore serialisation ───────────────────────────────────────────────

/// Converts a list of [FieldNode]s into a Firestore-ready map.
Map<String, dynamic> fieldNodesToFirestoreMap(List<FieldNode> nodes) {
  final result = <String, dynamic>{};
  for (final node in nodes) {
    final name = node.name.trim();
    if (name.isEmpty) continue;
    result[name] = _nodeToFirestore(node.type, node.value);
  }
  return result;
}

dynamic _nodeToFirestore(FieldType type, dynamic value) => switch (type) {
      FieldType.string => value?.toString() ?? '',
      FieldType.number => num.tryParse(value?.toString() ?? '') ?? 0,
      FieldType.boolean => value is bool ? value : false,
      FieldType.timestamp =>
        value is DateTime ? Timestamp.fromDate(value) : Timestamp.now(),
      FieldType.map => fieldNodesToFirestoreMap(
          value is List ? value.cast<FieldNode>() : <FieldNode>[]),
      FieldType.array => value is List
          ? (value as List<ArrayItem>)
              .map((item) => _nodeToFirestore(item.subtype, item.value))
              .toList()
          : <dynamic>[],
      FieldType.geopoint =>
        value is GeoPoint ? value : const GeoPoint(0, 0),
      FieldType.reference => value?.toString() ?? '',
      FieldType.nullValue => null,
    };

// ─── Firestore deserialisation ─────────────────────────────────────────────

/// Converts an existing Firestore document map into a [FieldNode] list.
List<FieldNode> firestoreMapToFieldNodes(Map<String, dynamic> data) =>
    data.entries.map((e) => _entryToNode(e.key, e.value)).toList();

FieldNode _entryToNode(String name, dynamic value) {
  if (value == null) {
    return FieldNode(name: name, type: FieldType.nullValue, value: null);
  }
  if (value is bool) {
    return FieldNode(name: name, type: FieldType.boolean, value: value);
  }
  if (value is num) {
    return FieldNode(
        name: name, type: FieldType.number, value: value.toString());
  }
  if (value is String) {
    return FieldNode(name: name, type: FieldType.string, value: value);
  }
  if (value is Timestamp) {
    return FieldNode(
        name: name, type: FieldType.timestamp, value: value.toDate());
  }
  if (value is GeoPoint) {
    return FieldNode(name: name, type: FieldType.geopoint, value: value);
  }
  if (value is DocumentReference) {
    return FieldNode(
        name: name, type: FieldType.reference, value: value.path);
  }
  if (value is Map<String, dynamic>) {
    return FieldNode(
      name: name,
      type: FieldType.map,
      value: firestoreMapToFieldNodes(value),
    );
  }
  if (value is List) {
    final items = value.map((item) {
      final probe = _entryToNode('_', item);
      return ArrayItem(subtype: probe.type, value: probe.value);
    }).toList();
    return FieldNode(name: name, type: FieldType.array, value: items);
  }
  return FieldNode(
      name: name, type: FieldType.string, value: value.toString());
}

// ═══════════════════════════════════════════════════════════════════════════
//  DocumentEditorWidget — public entry point
// ═══════════════════════════════════════════════════════════════════════════

class DocumentEditorWidget extends StatefulWidget {
  /// Pre-populate from an existing Firestore document.
  final Map<String, dynamic>? initialData;

  /// Called with the final serialised map when the user taps "Save".
  final Future<void> Function(Map<String, dynamic> data) onSave;

  const DocumentEditorWidget({
    super.key,
    this.initialData,
    required this.onSave,
  });

  @override
  State<DocumentEditorWidget> createState() => _DocumentEditorWidgetState();
}

class _DocumentEditorWidgetState extends State<DocumentEditorWidget> {
  late List<FieldNode> _fields;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _fields = widget.initialData != null
        ? firestoreMapToFieldNodes(widget.initialData!)
        : [FieldNode(name: '', type: FieldType.string, value: '')];
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.onSave(fieldNodesToFirestoreMap(_fields));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FieldListEditor(
          fields: _fields,
          depth: 0,
          onChanged: (updated) => setState(() => _fields = updated),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save Document'),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  FieldListEditor — renders a flat list of FieldRows; used recursively
// ═══════════════════════════════════════════════════════════════════════════

class FieldListEditor extends StatelessWidget {
  final List<FieldNode> fields;
  final int depth;
  final ValueChanged<List<FieldNode>> onChanged;

  const FieldListEditor({
    required this.fields,
    required this.depth,
    required this.onChanged,
  });

  void _add() => onChanged([
        ...fields,
        FieldNode(name: '', type: FieldType.string, value: ''),
      ]);

  void _remove(int i) {
    final list = List<FieldNode>.from(fields)..removeAt(i);
    onChanged(list);
  }

  void _update(int i, FieldNode node) {
    final list = List<FieldNode>.from(fields)..[i] = node;
    onChanged(list);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < fields.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _FieldRowWidget(
              key: ValueKey(fields[i].id),
              node: fields[i],
              depth: depth,
              onChanged: (updated) => _update(i, updated),
              onDelete: () => _remove(i),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _add,
            icon: const Icon(Icons.add, size: 16),
            label: Text(depth == 0 ? 'Add Field' : 'Add Sub-field'),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  _FieldRowWidget — header row (name + type + delete) + value row below
// ═══════════════════════════════════════════════════════════════════════════

class _FieldRowWidget extends StatefulWidget {
  final FieldNode node;
  final int depth;
  final ValueChanged<FieldNode> onChanged;
  final VoidCallback onDelete;

  const _FieldRowWidget({
    super.key,
    required this.node,
    required this.depth,
    required this.onChanged,
    required this.onDelete,
  });

  @override
  State<_FieldRowWidget> createState() => _FieldRowWidgetState();
}

class _FieldRowWidgetState extends State<_FieldRowWidget> {
  // Persistent controllers — never recreated after initState
  late final TextEditingController _nameCtrl;
  late final TextEditingController _textValCtrl; // string / number
  late final TextEditingController _refCtrl;     // reference path
  late final TextEditingController _latCtrl;     // geopoint latitude
  late final TextEditingController _lngCtrl;     // geopoint longitude

  late FieldType _type;
  late dynamic _value; // authoritative live value for non-text types

  @override
  void initState() {
    super.initState();
    final n = widget.node;
    _type = n.type;
    _value = n.value;

    _nameCtrl = TextEditingController(text: n.name);

    _textValCtrl = TextEditingController(
      text: (_type == FieldType.string || _type == FieldType.number)
          ? n.value?.toString() ?? ''
          : '',
    );

    _refCtrl = TextEditingController(
      text: _type == FieldType.reference ? n.value?.toString() ?? '' : '',
    );

    final gp =
        n.type == FieldType.geopoint && n.value is GeoPoint
            ? n.value as GeoPoint
            : const GeoPoint(0, 0);
    _latCtrl = TextEditingController(text: gp.latitude.toString());
    _lngCtrl = TextEditingController(text: gp.longitude.toString());
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _textValCtrl.dispose();
    _refCtrl.dispose();
    _latCtrl.dispose();
    _lngCtrl.dispose();
    super.dispose();
  }

  void _emit() {
    widget.onChanged(FieldNode(
      id: widget.node.id,
      name: _nameCtrl.text,
      type: _type,
      value: _value,
    ));
  }

  void _onTypeChanged(FieldType? t) {
    if (t == null || t == _type) return;
    setState(() {
      _type = t;
      _value = _defaultValue(t);
      _textValCtrl.text = '';
      _refCtrl.text = '';
      _latCtrl.text = '0';
      _lngCtrl.text = '0';
    });
    _emit();
  }

  /// For non-text values (bool, DateTime, List children, GeoPoint).
  void _onValueChanged(dynamic v) {
    setState(() => _value = v);
    _emit();
  }

  // ─── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Header Row: name | type dropdown | delete ─────────────────────
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              flex: 5,
              child: TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Field name',
                  hintText: 'e.g. title',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (_) => _emit(),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 4,
              child: DropdownButtonFormField<FieldType>(
                initialValue: _type,
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
            const SizedBox(width: 4),
            IconButton(
              icon:
                  const Icon(Icons.delete_outline, color: Colors.redAccent),
              tooltip: 'Delete field',
              visualDensity: VisualDensity.compact,
              onPressed: widget.onDelete,
            ),
          ],
        ),
        const SizedBox(height: 6),
        // ── Value Row ─────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: _buildValueWidget(context),
        ),
      ],
    );
  }

  // ─── Factory: FieldType → Widget ────────────────────────────────────────

  Widget _buildValueWidget(BuildContext context) => switch (_type) {
        FieldType.string => _textField(multiline: true),
        FieldType.number => _textField(multiline: false, numeric: true),
        FieldType.boolean => _boolDropdown(),
        FieldType.timestamp => _timestampButton(),
        FieldType.map => _mapEditor(context),
        FieldType.array => _arrayEditor(),
        FieldType.geopoint => _geopointFields(),
        FieldType.reference => _referenceField(),
        FieldType.nullValue => _nullBadge(context),
      };

  // ── Leaf widgets ─────────────────────────────────────────────────────────

  Widget _textField({required bool multiline, bool numeric = false}) {
    return TextField(
      controller: _textValCtrl,
      keyboardType: numeric
          ? const TextInputType.numberWithOptions(decimal: true)
          : (multiline ? TextInputType.multiline : TextInputType.text),
      maxLines: multiline ? null : 1,
      decoration: InputDecoration(
        hintText: numeric ? '0' : 'value…',
        border: const OutlineInputBorder(),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      onChanged: (v) {
        _value = v;
        _emit();
      },
    );
  }

  Widget _boolDropdown() {
    final val = _value is bool ? _value as bool : false;
    return DropdownButtonFormField<bool>(
      initialValue: val,
      isDense: true,
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      items: const [
        DropdownMenuItem(value: true, child: Text('true')),
        DropdownMenuItem(value: false, child: Text('false')),
      ],
      onChanged: (v) => _onValueChanged(v ?? false),
    );
  }

  Widget _timestampButton() {
    final dt = _value is DateTime ? _value as DateTime : DateTime.now();
    final formatted = DateFormat('yyyy-MM-dd  HH:mm').format(dt);
    return InkWell(
      onTap: () => _pickDateTime(dt),
      child: InputDecorator(
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          suffixIcon: Icon(Icons.calendar_today, size: 18),
        ),
        child: Text(formatted),
      ),
    );
  }

  Future<void> _pickDateTime(DateTime current) async {
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (time == null) return;
    _onValueChanged(
        DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Widget _geopointFields() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _latCtrl,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Latitude',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (v) {
              _value = GeoPoint(
                double.tryParse(v) ?? 0,
                (_value is GeoPoint ? (_value as GeoPoint).longitude : 0),
              );
              _emit();
            },
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            controller: _lngCtrl,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Longitude',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (v) {
              _value = GeoPoint(
                (_value is GeoPoint ? (_value as GeoPoint).latitude : 0),
                double.tryParse(v) ?? 0,
              );
              _emit();
            },
          ),
        ),
      ],
    );
  }

  Widget _referenceField() {
    return TextField(
      controller: _refCtrl,
      decoration: const InputDecoration(
        hintText: 'collection/documentId',
        border: OutlineInputBorder(),
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        suffixIcon: Icon(Icons.link, size: 18),
      ),
      onChanged: (v) {
        _value = v;
        _emit();
      },
    );
  }

  Widget _nullBadge(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Chip(
        label: const Text('null',
            style: TextStyle(fontFamily: 'monospace', fontSize: 13)),
        backgroundColor: Theme.of(context).colorScheme.errorContainer,
        labelStyle: TextStyle(
            color: Theme.of(context).colorScheme.onErrorContainer),
        side: BorderSide.none,
        padding: const EdgeInsets.symmetric(horizontal: 4),
      ),
    );
  }

  // ── Composite / recursive widgets ──────────────────────────────────────

  Widget _mapEditor(BuildContext context) {
    final subFields = _value is List<FieldNode>
        ? _value as List<FieldNode>
        : <FieldNode>[];
    return NestedContainer(
      depth: widget.depth,
      child: FieldListEditor(
        fields: subFields,
        depth: widget.depth + 1,
        onChanged: _onValueChanged,
      ),
    );
  }

  Widget _arrayEditor() {
    final items = _value is List<ArrayItem>
        ? _value as List<ArrayItem>
        : <ArrayItem>[];
    return ArrayEditorWidget(
      items: items,
      depth: widget.depth,
      onChanged: _onValueChanged,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  ArrayEditorWidget — manages a list of ArrayItems
// ═══════════════════════════════════════════════════════════════════════════

class ArrayEditorWidget extends StatefulWidget {
  final List<ArrayItem> items;
  final int depth;
  final ValueChanged<List<ArrayItem>> onChanged;
  final FieldType? lockedItemType;

  const ArrayEditorWidget({
    required this.items,
    required this.depth,
    required this.onChanged,
    this.lockedItemType,
  });

  @override
  State<ArrayEditorWidget> createState() => ArrayEditorWidgetState();
}

class ArrayEditorWidgetState extends State<ArrayEditorWidget> {
  late List<ArrayItem> _items;

  @override
  void initState() {
    super.initState();
    _items = List.from(widget.items);
  }

  void _add() {
    final type = widget.lockedItemType ?? FieldType.string;
    final updated = [
      ..._items,
      ArrayItem(subtype: type, value: _defaultValue(type)),
    ];
    setState(() => _items = updated);
    widget.onChanged(updated);
  }

  void _remove(int i) {
    final updated = List<ArrayItem>.from(_items)..removeAt(i);
    setState(() => _items = updated);
    widget.onChanged(updated);
  }

  void _update(int i, ArrayItem item) {
    final updated = List<ArrayItem>.from(_items)..[i] = item;
    setState(() => _items = updated);
    widget.onChanged(updated);
  }

  @override
  Widget build(BuildContext context) {
    return NestedContainer(
      depth: widget.depth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < _items.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _ArrayItemWidget(
                key: ValueKey(_items[i].id),
                index: i,
                item: _items[i],
                depth: widget.depth + 1,
                lockedItemType: widget.lockedItemType,
                onChanged: (updated) => _update(i, updated),
                onDelete: () => _remove(i),
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _add,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add Item'),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  _ArrayItemWidget — one indexed item inside an Array
// ═══════════════════════════════════════════════════════════════════════════

class _ArrayItemWidget extends StatefulWidget {
  final int index;
  final ArrayItem item;
  final int depth;
  final FieldType? lockedItemType;
  final ValueChanged<ArrayItem> onChanged;
  final VoidCallback onDelete;

  const _ArrayItemWidget({
    super.key,
    required this.index,
    required this.item,
    required this.depth,
    this.lockedItemType,
    required this.onChanged,
    required this.onDelete,
  });

  @override
  State<_ArrayItemWidget> createState() => _ArrayItemWidgetState();
}

class _ArrayItemWidgetState extends State<_ArrayItemWidget> {
  late final TextEditingController _textCtrl;
  late final TextEditingController _refCtrl;
  late final TextEditingController _latCtrl;
  late final TextEditingController _lngCtrl;

  late FieldType _subtype;
  late dynamic _value;

  @override
  void initState() {
    super.initState();
    _subtype = widget.item.subtype;
    _value = widget.item.value;

    _textCtrl = TextEditingController(
      text: (_subtype == FieldType.string || _subtype == FieldType.number)
          ? _value?.toString() ?? ''
          : '',
    );
    _refCtrl = TextEditingController(
      text: _subtype == FieldType.reference ? _value?.toString() ?? '' : '',
    );
    final gp = _subtype == FieldType.geopoint && _value is GeoPoint
        ? _value as GeoPoint
        : const GeoPoint(0, 0);
    _latCtrl = TextEditingController(text: gp.latitude.toString());
    _lngCtrl = TextEditingController(text: gp.longitude.toString());
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _refCtrl.dispose();
    _latCtrl.dispose();
    _lngCtrl.dispose();
    super.dispose();
  }

  void _emit() =>
      widget.onChanged(ArrayItem(id: widget.item.id, subtype: _subtype, value: _value));

  void _onSubtypeChanged(FieldType? t) {
    if (t == null || t == _subtype) return;
    setState(() {
      _subtype = t;
      _value = _defaultValue(t);
      _textCtrl.text = '';
      _refCtrl.text = '';
      _latCtrl.text = '0';
      _lngCtrl.text = '0';
    });
    _emit();
  }

  void _onValueChanged(dynamic v) {
    setState(() => _value = v);
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Header Row: "Index N" label | subtype dropdown | delete ────
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'Index ${widget.index}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSecondaryContainer,
                ),
              ),
            ),
            if (widget.lockedItemType == null) ...[
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<FieldType>(
                  initialValue: _subtype,
                  isDense: true,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                    labelText: 'Type',
                  ),
                  items: FieldType.values
                      .map((t) => DropdownMenuItem(
                            value: t,
                            child: Text(t.displayName,
                                overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: _onSubtypeChanged,
                ),
              ),
            ] else
              const Spacer(),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              tooltip: 'Remove item',
              visualDensity: VisualDensity.compact,
              onPressed: widget.onDelete,
            ),
          ],
        ),
        const SizedBox(height: 6),
        // ── Value Row ────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: _buildValueWidget(context),
        ),
      ],
    );
  }

  Widget _buildValueWidget(BuildContext context) => switch (_subtype) {
        FieldType.string => _textField(multiline: true),
        FieldType.number => _textField(multiline: false, numeric: true),
        FieldType.boolean => _boolDropdown(),
        FieldType.timestamp => _timestampButton(),
        FieldType.map => _mapEditor(context),
        FieldType.array => _nestedArrayEditor(),
        FieldType.geopoint => _geopointFields(),
        FieldType.reference => _referenceField(),
        FieldType.nullValue => _nullBadge(context),
      };

  Widget _textField({required bool multiline, bool numeric = false}) =>
      TextField(
        controller: _textCtrl,
        keyboardType: numeric
            ? const TextInputType.numberWithOptions(decimal: true)
            : (multiline ? TextInputType.multiline : TextInputType.text),
        maxLines: multiline ? null : 1,
        decoration: InputDecoration(
          hintText: numeric ? '0' : 'value…',
          border: const OutlineInputBorder(),
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
        onChanged: (v) {
          _value = v;
          _emit();
        },
      );

  Widget _boolDropdown() {
    final val = _value is bool ? _value as bool : false;
    return DropdownButtonFormField<bool>(
      initialValue: val,
      isDense: true,
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      items: const [
        DropdownMenuItem(value: true, child: Text('true')),
        DropdownMenuItem(value: false, child: Text('false')),
      ],
      onChanged: (v) => _onValueChanged(v ?? false),
    );
  }

  Widget _timestampButton() {
    final dt = _value is DateTime ? _value as DateTime : DateTime.now();
    final formatted = DateFormat('yyyy-MM-dd  HH:mm').format(dt);
    return InkWell(
      onTap: () => _pickDateTime(dt),
      child: InputDecorator(
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          suffixIcon: Icon(Icons.calendar_today, size: 18),
        ),
        child: Text(formatted),
      ),
    );
  }

  Future<void> _pickDateTime(DateTime current) async {
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (time == null) return;
    _onValueChanged(
        DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Widget _geopointFields() => Row(
        children: [
          Expanded(
            child: TextField(
              controller: _latCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: 'Latitude',
                  border: OutlineInputBorder(),
                  isDense: true),
              onChanged: (v) {
                _value = GeoPoint(double.tryParse(v) ?? 0,
                    _value is GeoPoint ? (_value as GeoPoint).longitude : 0);
                _emit();
              },
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _lngCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: 'Longitude',
                  border: OutlineInputBorder(),
                  isDense: true),
              onChanged: (v) {
                _value = GeoPoint(
                    _value is GeoPoint ? (_value as GeoPoint).latitude : 0,
                    double.tryParse(v) ?? 0);
                _emit();
              },
            ),
          ),
        ],
      );

  Widget _referenceField() => TextField(
        controller: _refCtrl,
        decoration: const InputDecoration(
          hintText: 'collection/documentId',
          border: OutlineInputBorder(),
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          suffixIcon: Icon(Icons.link, size: 18),
        ),
        onChanged: (v) {
          _value = v;
          _emit();
        },
      );

  Widget _nullBadge(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: Chip(
          label: const Text('null',
              style: TextStyle(fontFamily: 'monospace', fontSize: 13)),
          backgroundColor: Theme.of(context).colorScheme.errorContainer,
          labelStyle: TextStyle(
              color: Theme.of(context).colorScheme.onErrorContainer),
          side: BorderSide.none,
          padding: const EdgeInsets.symmetric(horizontal: 4),
        ),
      );

  Widget _mapEditor(BuildContext context) {
    final subFields = _value is List<FieldNode>
        ? _value as List<FieldNode>
        : <FieldNode>[];
    return NestedContainer(
      depth: widget.depth,
      child: FieldListEditor(
        fields: subFields,
        depth: widget.depth + 1,
        onChanged: _onValueChanged,
      ),
    );
  }

  Widget _nestedArrayEditor() {
    final items = _value is List<ArrayItem>
        ? _value as List<ArrayItem>
        : <ArrayItem>[];
    return ArrayEditorWidget(
      items: items,
      depth: widget.depth,
      onChanged: _onValueChanged,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  NestedContainer — visual left-border tree indentation for Map/Array
// ═══════════════════════════════════════════════════════════════════════════

class NestedContainer extends StatelessWidget {
  final int depth;
  final Widget child;

  const NestedContainer({required this.depth, required this.child});

  // Cycles through distinct hues so each depth level is visually distinct.
  static const _borderHues = [
    Color(0xFF5C6BC0), // indigo
    Color(0xFF26A69A), // teal
    Color(0xFFEF6C00), // orange
    Color(0xFF8E24AA), // purple
    Color(0xFF1E88E5), // blue
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = _borderHues[depth % _borderHues.length];
    final bgColor = isDark
        ? Theme.of(context).colorScheme.surface.withValues(alpha: 0.6)
        : Theme.of(context).colorScheme.surfaceContainerLow;

    return Container(
      margin: const EdgeInsets.only(left: 12),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(
          left: BorderSide(color: borderColor, width: 3),
        ),
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(8),
          bottomRight: Radius.circular(8),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: child,
    );
  }
}
