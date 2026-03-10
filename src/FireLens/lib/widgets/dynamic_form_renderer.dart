import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/schema_model.dart';
import 'document_editor.dart';

/// Mutable holder for a GeoPoint's lat/lng while the form is being edited.
class _GeoPointDraft {
  double lat;
  double lng;
  _GeoPointDraft(this.lat, this.lng);
}

/// Renders a dynamic form from a [SchemaModel].
///
/// Each field shows its label + type badge side-by-side, with a
/// type-aware value editor below.  Map fields render a recursive
/// key/value tree; Array fields render per-index item editors;
/// Boolean fields use a true/false dropdown, etc.
///
/// [initialData] pre-populates the form (used during editing).
/// [firestore] is required to resolve Reference paths to [DocumentReference]s.
/// [onSubmit] receives the final Map ready to be written to Firestore.
class DynamicFormRenderer extends StatefulWidget {
  final SchemaModel schema;
  final Map<String, dynamic> initialData;
  final FirebaseFirestore? firestore;
  final Future<void> Function(Map<String, dynamic> data) onSubmit;

  const DynamicFormRenderer({
    super.key,
    required this.schema,
    required this.onSubmit,
    this.initialData = const {},
    this.firestore,
  });

  @override
  State<DynamicFormRenderer> createState() => _DynamicFormRendererState();
}

class _DynamicFormRendererState extends State<DynamicFormRenderer> {
  final _formKey = GlobalKey<FormState>();
  late final Map<String, dynamic> _values;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _values = _buildInitialValues();
  }

  Map<String, dynamic> _buildInitialValues() {
    final result = <String, dynamic>{};
    for (final field in widget.schema.fields) {
      final raw = widget.initialData[field.name];
      result[field.name] = switch (field.type) {
        FieldType.string    => raw?.toString() ?? '',
        FieldType.number    => raw?.toString() ?? '0',
        FieldType.boolean   => raw is bool ? raw : false,
        FieldType.timestamp => raw is Timestamp
            ? raw.toDate()
            : DateTime.now(),
        FieldType.map => raw is Map<String, dynamic>
            ? firestoreMapToFieldNodes(raw)
            : <FieldNode>[],
        FieldType.array => raw is List
            ? _rawListToArrayItems(raw)
            : <ArrayItem>[],
        FieldType.geopoint => raw is GeoPoint
            ? _GeoPointDraft(raw.latitude, raw.longitude)
            : _GeoPointDraft(0, 0),
        FieldType.reference => raw is DocumentReference ? raw.path : '',
        FieldType.nullValue => null,
      };
    }
    return result;
  }

  List<ArrayItem> _rawListToArrayItems(List<dynamic> raw) {
    return raw.map<ArrayItem>((item) {
      if (item == null)               return ArrayItem(subtype: FieldType.nullValue, value: null);
      if (item is bool)               return ArrayItem(subtype: FieldType.boolean, value: item);
      if (item is num)                return ArrayItem(subtype: FieldType.number, value: item.toString());
      if (item is String)             return ArrayItem(subtype: FieldType.string, value: item);
      if (item is Timestamp)          return ArrayItem(subtype: FieldType.timestamp, value: item.toDate());
      if (item is GeoPoint)           return ArrayItem(subtype: FieldType.geopoint, value: item);
      if (item is DocumentReference)  return ArrayItem(subtype: FieldType.reference, value: item.path);
      if (item is Map<String, dynamic>) {
        return ArrayItem(subtype: FieldType.map, value: firestoreMapToFieldNodes(item));
      }
      return ArrayItem(subtype: FieldType.string, value: item.toString());
    }).toList();
  }

  /// Converts the live [_values] map into Firestore-compatible types.
  Map<String, dynamic> _buildFirestoreMap() {
    final result = <String, dynamic>{};
    for (final field in widget.schema.fields) {
      final raw = _values[field.name];
      result[field.name] = switch (field.type) {
        FieldType.string    => raw?.toString() ?? '',
        FieldType.number    => num.tryParse(raw?.toString() ?? '0') ?? 0,
        FieldType.boolean   => raw is bool ? raw : false,
        FieldType.timestamp =>
          raw is DateTime ? Timestamp.fromDate(raw) : Timestamp.now(),
        FieldType.map => fieldNodesToFirestoreMap(
            raw is List<FieldNode> ? raw : <FieldNode>[]),
        FieldType.array => _arrayItemsToFirestore(
            raw is List<ArrayItem> ? raw : <ArrayItem>[]),
        FieldType.geopoint => raw is _GeoPointDraft
            ? GeoPoint(raw.lat, raw.lng)
            : const GeoPoint(0, 0),
        FieldType.reference =>
          widget.firestore != null && raw is String && raw.isNotEmpty
              ? widget.firestore!.doc(raw)
              : raw,
        FieldType.nullValue => null,
      };
    }
    return result;
  }

  List<dynamic> _arrayItemsToFirestore(List<ArrayItem> items) =>
      items.map<dynamic>(_arrayItemToFirestore).toList();

  dynamic _arrayItemToFirestore(ArrayItem item) => switch (item.subtype) {
        FieldType.string    => item.value?.toString() ?? '',
        FieldType.number    => num.tryParse(item.value?.toString() ?? '') ?? 0,
        FieldType.boolean   => item.value is bool ? item.value : false,
        FieldType.timestamp => item.value is DateTime
            ? Timestamp.fromDate(item.value as DateTime)
            : Timestamp.now(),
        FieldType.map => fieldNodesToFirestoreMap(
            item.value is List<FieldNode>
                ? item.value as List<FieldNode>
                : <FieldNode>[]),
        FieldType.array => _arrayItemsToFirestore(
            item.value is List<ArrayItem>
                ? item.value as List<ArrayItem>
                : <ArrayItem>[]),
        FieldType.geopoint =>
          item.value is GeoPoint ? item.value : const GeoPoint(0, 0),
        FieldType.reference => item.value?.toString() ?? '',
        FieldType.nullValue => null,
      };

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    _formKey.currentState!.save();
    setState(() => _submitting = true);
    try {
      await widget.onSubmit(_buildFirestoreMap());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...widget.schema.fields.map(_buildFieldWidget),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save Document'),
          ),
        ],
      ),
    );
  }

  // ─── Field Widget ─────────────────────────────────────────────────────────

  Widget _buildFieldWidget(FieldDefinition field) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header: label + type badge side-by-side ───────────────────
          Row(
            children: [
              Expanded(
                child: Text(
                  field.label,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  field.type.displayName,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color:
                        Theme.of(context).colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // ── Value widget — changes based on type ──────────────────────
          _buildValueWidget(field),
        ],
      ),
    );
  }

  Widget _buildValueWidget(FieldDefinition field) => switch (field.type) {
        FieldType.string => _StringValueField(
            initialValue: _values[field.name] as String?,
            onSaved: (v) => _values[field.name] = v ?? '',
          ),
        FieldType.number => _NumberValueField(
            initialValue: _values[field.name]?.toString(),
            onSaved: (v) => _values[field.name] = v ?? '0',
          ),
        FieldType.boolean => _BoolValueField(
            value: _values[field.name] as bool? ?? false,
            onChanged: (v) => setState(() => _values[field.name] = v),
          ),
        FieldType.timestamp => _TimestampValueField(
            value: _values[field.name] is DateTime
                ? _values[field.name] as DateTime
                : DateTime.now(),
            onChanged: (v) => setState(() => _values[field.name] = v),
          ),
        FieldType.map => _MapValueField(
            nodes: _values[field.name] is List<FieldNode>
                ? _values[field.name] as List<FieldNode>
                : <FieldNode>[],
            onChanged: (nodes) =>
                setState(() => _values[field.name] = nodes),
          ),
        FieldType.array => _ArrayValueField(
            items: _values[field.name] is List<ArrayItem>
                ? _values[field.name] as List<ArrayItem>
                : <ArrayItem>[],
            onChanged: (items) =>
                setState(() => _values[field.name] = items),
          ),
        FieldType.geopoint => _GeoPointValueField(
            draft: _values[field.name] is _GeoPointDraft
                ? _values[field.name] as _GeoPointDraft
                : _GeoPointDraft(0, 0),
          ),
        FieldType.reference => _ReferenceValueField(
            initialValue: _values[field.name] as String?,
            onSaved: (v) => _values[field.name] = v ?? '',
          ),
        FieldType.nullValue => const _NullValueField(),
      };
}

// ─── Value Widgets ────────────────────────────────────────────────────────────

class _StringValueField extends StatelessWidget {
  final String? initialValue;
  final FormFieldSetter<String> onSaved;

  const _StringValueField(
      {required this.initialValue, required this.onSaved});

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: initialValue,
      decoration: const InputDecoration(
        hintText: 'value…',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
      onSaved: onSaved,
    );
  }
}

class _NumberValueField extends StatelessWidget {
  final String? initialValue;
  final FormFieldSetter<String> onSaved;

  const _NumberValueField(
      {required this.initialValue, required this.onSaved});

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: initialValue,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: const InputDecoration(
        hintText: '0',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      validator: (v) {
        if (v == null || v.isEmpty) return 'Required';
        if (num.tryParse(v) == null) return 'Enter a valid number';
        return null;
      },
      onSaved: onSaved,
    );
  }
}

/// Boolean field — true/false dropdown (no switch toggle).
class _BoolValueField extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _BoolValueField({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<bool>(
      initialValue: value,
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
      onChanged: (v) => onChanged(v ?? false),
    );
  }
}

class _TimestampValueField extends StatelessWidget {
  final DateTime value;
  final ValueChanged<DateTime> onChanged;

  const _TimestampValueField(
      {required this.value, required this.onChanged});

  Future<void> _pick(BuildContext context) async {
    final date = await showDatePicker(
      context: context,
      initialDate: value,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null || !context.mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(value),
    );
    if (time == null) return;
    onChanged(
        DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  @override
  Widget build(BuildContext context) {
    final formatted = DateFormat('yyyy-MM-dd  HH:mm').format(value);
    return InkWell(
      onTap: () => _pick(context),
      child: InputDecorator(
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          isDense: true,
          contentPadding:
              EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          suffixIcon: Icon(Icons.calendar_today, size: 18),
        ),
        child: Text(formatted),
      ),
    );
  }
}

/// Map field — renders a recursive key/value tree editor.
class _MapValueField extends StatelessWidget {
  final List<FieldNode> nodes;
  final ValueChanged<List<FieldNode>> onChanged;

  const _MapValueField({required this.nodes, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return NestedContainer(
      depth: 0,
      child: FieldListEditor(
        fields: nodes,
        depth: 1,
        onChanged: onChanged,
      ),
    );
  }
}

/// Array field — renders per-index item editors with type selector.
class _ArrayValueField extends StatelessWidget {
  final List<ArrayItem> items;
  final ValueChanged<List<ArrayItem>> onChanged;

  const _ArrayValueField({required this.items, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return ArrayEditorWidget(
      items: items,
      depth: 0,
      onChanged: onChanged,
    );
  }
}

class _GeoPointValueField extends StatelessWidget {
  final _GeoPointDraft draft;

  const _GeoPointValueField({required this.draft});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextFormField(
            initialValue: draft.lat.toString(),
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Latitude',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            validator: (v) {
              if (v == null || v.isEmpty) return 'Required';
              final d = double.tryParse(v);
              if (d == null) return 'Invalid';
              if (d < -90 || d > 90) return '-90 to 90';
              return null;
            },
            onSaved: (v) => draft.lat = double.tryParse(v ?? '') ?? 0,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextFormField(
            initialValue: draft.lng.toString(),
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Longitude',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            validator: (v) {
              if (v == null || v.isEmpty) return 'Required';
              final d = double.tryParse(v);
              if (d == null) return 'Invalid';
              if (d < -180 || d > 180) return '-180 to 180';
              return null;
            },
            onSaved: (v) => draft.lng = double.tryParse(v ?? '') ?? 0,
          ),
        ),
      ],
    );
  }
}

class _ReferenceValueField extends StatelessWidget {
  final String? initialValue;
  final FormFieldSetter<String> onSaved;

  const _ReferenceValueField(
      {required this.initialValue, required this.onSaved});

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: initialValue,
      decoration: const InputDecoration(
        hintText: 'collection/documentId',
        border: OutlineInputBorder(),
        isDense: true,
        suffixIcon: Tooltip(
          message: 'Firestore document path',
          child: Icon(Icons.link, size: 18),
        ),
      ),
      validator: (v) {
        if (v == null || v.trim().isEmpty) return 'Required';
        final parts = v.trim().split('/');
        if (parts.length < 2 || parts.length.isOdd) {
          return 'Must be an even-segment path: col/doc or col/doc/col/doc';
        }
        return null;
      },
      onSaved: onSaved,
    );
  }
}

class _NullValueField extends StatelessWidget {
  const _NullValueField();

  @override
  Widget build(BuildContext context) {
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
}
