enum FieldType {
  string,
  number,
  boolean,
  timestamp,
  map,
  array,
  geopoint,
  reference,
  nullValue;

  String get displayName => switch (this) {
        FieldType.string => 'String',
        FieldType.number => 'Number',
        FieldType.boolean => 'Boolean',
        FieldType.timestamp => 'Timestamp',
        FieldType.map => 'Map',
        FieldType.array => 'Array',
        FieldType.geopoint => 'GeoPoint',
        FieldType.reference => 'Reference',
        FieldType.nullValue => 'Null',
      };
}

class FieldDefinition {
  final String name;
  final String label;
  final FieldType type;
  final List<FieldDefinition> mapFields;
  final FieldType? arrayItemType;

  const FieldDefinition({
    required this.name,
    required this.label,
    required this.type,
    this.mapFields = const [],
    this.arrayItemType,
  });

  factory FieldDefinition.fromJson(Map<String, dynamic> json) {
    return FieldDefinition(
      name: json['name'] as String,
      label: json['label'] as String,
      type: FieldType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => FieldType.string,
      ),
      mapFields: (json['mapFields'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(FieldDefinition.fromJson)
          .toList(),
      arrayItemType: json['arrayItemType'] != null
          ? FieldType.values.firstWhere(
              (e) => e.name == json['arrayItemType'],
              orElse: () => FieldType.string,
            )
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'label': label,
        'type': type.name,
        if (mapFields.isNotEmpty)
          'mapFields': mapFields.map((f) => f.toJson()).toList(),
        if (arrayItemType != null) 'arrayItemType': arrayItemType!.name,
      };
}

class SchemaModel {
  final String collectionName;
  final List<FieldDefinition> fields;

  const SchemaModel({
    required this.collectionName,
    required this.fields,
  });

  factory SchemaModel.fromFirestore(
      String collectionName, Map<String, dynamic> data) {
    final rawFields = data['fields'] as List<dynamic>? ?? [];
    final fields = rawFields
        .whereType<Map<String, dynamic>>()
        .map(FieldDefinition.fromJson)
        .toList();
    return SchemaModel(collectionName: collectionName, fields: fields);
  }

  Map<String, dynamic> toFirestore() => {
        'fields': fields.map((f) => f.toJson()).toList(),
      };
}

class FirebaseConfig {
  final String apiKey;
  final String projectId;
  final String appId;
  final String messagingSenderId;
  final String storageBucket;
  final String? authDomain;

  const FirebaseConfig({
    required this.apiKey,
    required this.projectId,
    required this.appId,
    required this.messagingSenderId,
    required this.storageBucket,
    this.authDomain,
  });

  factory FirebaseConfig.fromMap(Map<String, String> map) {
    return FirebaseConfig(
      apiKey: map['apiKey'] ?? '',
      projectId: map['projectId'] ?? '',
      appId: map['appId'] ?? '',
      messagingSenderId: map['messagingSenderId'] ?? '',
      storageBucket: map['storageBucket'] ?? '',
      authDomain: map['authDomain'],
    );
  }

  Map<String, String> toMap() => {
        'apiKey': apiKey,
        'projectId': projectId,
        'appId': appId,
        'messagingSenderId': messagingSenderId,
        'storageBucket': storageBucket,
        if (authDomain != null) 'authDomain': authDomain!,
      };

  bool get isValid =>
      apiKey.isNotEmpty &&
      projectId.isNotEmpty &&
      appId.isNotEmpty &&
      messagingSenderId.isNotEmpty &&
      storageBucket.isNotEmpty;
}
