import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/schema_model.dart';
import '../providers/firebase_provider.dart';
import 'dashboard_screen.dart';

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({super.key});

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  final _formKey = GlobalKey<FormState>();

  final _apiKeyCtrl = TextEditingController();
  final _projectIdCtrl = TextEditingController();
  final _appIdCtrl = TextEditingController();
  final _senderIdCtrl = TextEditingController();
  final _bucketCtrl = TextEditingController();
  final _authDomainCtrl = TextEditingController();

  @override
  void dispose() {
    _apiKeyCtrl.dispose();
    _projectIdCtrl.dispose();
    _appIdCtrl.dispose();
    _senderIdCtrl.dispose();
    _bucketCtrl.dispose();
    _authDomainCtrl.dispose();
    super.dispose();
  }

  // ── google-services.json / web-config import ─────────────────────────────

  Future<void> _importFromFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final bytes = result.files.first.bytes;
    if (bytes == null) return;

    try {
      final json = jsonDecode(String.fromCharCodes(bytes)) as Map<String, dynamic>;
      _fillFromJson(json);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not parse file: $e'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Config imported — review and connect.')),
    );
  }

  /// Fills controllers from either a Firebase web-config JSON or a
  /// google-services.json (Android) file.
  void _fillFromJson(Map<String, dynamic> json) {
    // ── Web config: flat object with camelCase keys ───────────────────────
    if (json.containsKey('apiKey')) {
      _apiKeyCtrl.text    = (json['apiKey']             as String?) ?? '';
      _projectIdCtrl.text = (json['projectId']          as String?) ?? '';
      _appIdCtrl.text     = (json['appId']              as String?) ?? '';
      _senderIdCtrl.text  = (json['messagingSenderId']  as String?) ?? '';
      _bucketCtrl.text    = (json['storageBucket']      as String?) ?? '';
      _authDomainCtrl.text= (json['authDomain']         as String?) ?? '';
      return;
    }

    // ── google-services.json (Android) ───────────────────────────────────
    final projectInfo = json['project_info'] as Map<String, dynamic>?;
    if (projectInfo != null) {
      final projectId = (projectInfo['project_id']     as String?) ?? '';
      _projectIdCtrl.text = projectId;
      _senderIdCtrl.text  = (projectInfo['project_number']  as String?) ?? '';
      _bucketCtrl.text    = (projectInfo['storage_bucket']  as String?) ?? '';
      if (projectId.isNotEmpty) {
        _authDomainCtrl.text = '$projectId.firebaseapp.com';
      }
    }

    final clients = json['client'] as List<dynamic>?;
    if (clients != null && clients.isNotEmpty) {
      final client = clients.first as Map<String, dynamic>?;
      if (client != null) {
        final clientInfo = client['client_info'] as Map<String, dynamic>?;
        _appIdCtrl.text = (clientInfo?['mobilesdk_app_id'] as String?) ?? '';

        final apiKeys = client['api_key'] as List<dynamic>?;
        if (apiKeys != null && apiKeys.isNotEmpty) {
          final entry = apiKeys.first as Map<String, dynamic>?;
          _apiKeyCtrl.text = (entry?['current_key'] as String?) ?? '';
        }
      }
    }
  }

  Future<void> _connect(BuildContext context) async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final provider = context.read<FirebaseProvider>();
    final config = FirebaseConfig(
      apiKey: _apiKeyCtrl.text.trim(),
      projectId: _projectIdCtrl.text.trim(),
      appId: _appIdCtrl.text.trim(),
      messagingSenderId: _senderIdCtrl.text.trim(),
      storageBucket: _bucketCtrl.text.trim(),
      authDomain: _authDomainCtrl.text.trim().isNotEmpty
          ? _authDomainCtrl.text.trim()
          : null,
    );

    final success = await provider.connect(config);
    if (!context.mounted) return;

    if (success) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const DashboardScreen()),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Connection failed: ${provider.error}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<FirebaseProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('FireLens — Connect to Firebase')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _SectionHeader(
                    icon: Icons.cloud,
                    title: 'Firebase Configuration',
                    subtitle:
                        'Enter your Firebase project credentials. These are saved locally.',
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _importFromFile,
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Import google-services.json'),
                  ),
                  const SizedBox(height: 20),
                  _ConfigField(
                    controller: _apiKeyCtrl,
                    label: 'API Key',
                    hint: 'AIzaSy...',
                    required: true,
                  ),
                  _ConfigField(
                    controller: _projectIdCtrl,
                    label: 'Project ID',
                    hint: 'my-project-id',
                    required: true,
                  ),
                  _ConfigField(
                    controller: _appIdCtrl,
                    label: 'App ID',
                    hint: '1:123456789:web:abc...',
                    required: true,
                  ),
                  _ConfigField(
                    controller: _senderIdCtrl,
                    label: 'Messaging Sender ID',
                    hint: '123456789',
                    required: true,
                  ),
                  _ConfigField(
                    controller: _bucketCtrl,
                    label: 'Storage Bucket',
                    hint: 'my-project.appspot.com',
                    required: true,
                  ),
                  _ConfigField(
                    controller: _authDomainCtrl,
                    label: 'Auth Domain (optional)',
                    hint: 'my-project.firebaseapp.com',
                    required: false,
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: provider.isLoading ? null : () => _connect(context),
                    icon: provider.isLoading
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.link),
                    label: const Text('Connect'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 40, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ConfigField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final bool required;

  const _ConfigField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.required,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
        ),
        validator: required
            ? (v) => (v == null || v.trim().isEmpty) ? '$label is required' : null
            : null,
      ),
    );
  }
}
