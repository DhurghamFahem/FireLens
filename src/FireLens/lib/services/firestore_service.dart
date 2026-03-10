import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import '../models/schema_model.dart';

const _metadataCollection = '_app_metadata';

class FirestoreService {
  final FirebaseApp _app;
  late final FirebaseFirestore _db;

  FirestoreService(this._app) {
    _db = FirebaseFirestore.instanceFor(app: _app);
  }

  // ─── Schema Methods ────────────────────────────────────────────────────────

  /// Saves (or overwrites) a schema into `_app_metadata/{collectionName}`
  Future<void> saveSchema(SchemaModel schema) async {
    await _db
        .collection(_metadataCollection)
        .doc(schema.collectionName)
        .set(schema.toFirestore());
  }

  /// Deletes a schema document from _app_metadata
  Future<void> deleteSchema(String collectionName) async {
    await _db
        .collection(_metadataCollection)
        .doc(collectionName)
        .delete();
  }

  /// Fetches all schemas from _app_metadata
  Future<List<SchemaModel>> getSchemas() async {
    final snapshot = await _db.collection(_metadataCollection).get();
    return snapshot.docs
        .map((doc) => SchemaModel.fromFirestore(doc.id, doc.data()))
        .toList();
  }

  // ─── Document Methods ──────────────────────────────────────────────────────

  /// Fetches all documents from [collectionName], returning each doc
  /// as a map with its Firestore document ID included under the key '__id'.
  Future<List<Map<String, dynamic>>> getDocuments(
      String collectionName) async {
    final snapshot = await _db.collection(collectionName).get();
    return snapshot.docs.map((doc) {
      return {'__id': doc.id, ...doc.data()};
    }).toList();
  }

  /// Creates a new document in [collectionName] with an auto-generated ID.
  /// Returns the new document ID.
  Future<String> addDocument(
      String collectionName, Map<String, dynamic> data) async {
    final ref = await _db.collection(collectionName).add(data);
    return ref.id;
  }

  /// Overwrites (or creates) a document at [collectionName]/[docId] with [data].
  Future<void> setDocument(
      String collectionName, String docId, Map<String, dynamic> data) async {
    await _db.collection(collectionName).doc(docId).set(data);
  }

  /// Merges [data] into an existing document at [collectionName]/[docId].
  Future<void> updateDocument(
      String collectionName, String docId, Map<String, dynamic> data) async {
    await _db.collection(collectionName).doc(docId).update(data);
  }

  /// Deletes the document at [collectionName]/[docId].
  Future<void> deleteDocument(String collectionName, String docId) async {
    await _db.collection(collectionName).doc(docId).delete();
  }
}
