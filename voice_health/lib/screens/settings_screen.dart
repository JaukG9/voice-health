import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_service.dart';
import '../services/app_store.dart';
import '../services/report_builder.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _api = ApiService();
  late final TextEditingController _nameController;
  late final TextEditingController _serverController;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    final store = AppStore.instance;
    _nameController = TextEditingController(text: store.displayName);
    _serverController = TextEditingController(text: store.serverUrl);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _serverController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppStore.instance,
      builder: (context, _) => _buildSettings(context),
    );
  }

  Widget _buildSettings(BuildContext context) {
    final store = AppStore.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionTitle(context, 'Profile'),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Display name (optional)',
              border: OutlineInputBorder(),
            ),
            onChanged: store.setDisplayName,
          ),
          const SizedBox(height: 24),
          _sectionTitle(context, 'Analysis'),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'device', label: Text('This phone')),
              ButtonSegment(value: 'server', label: Text('My computer')),
            ],
            selected: {store.analysisMode},
            onSelectionChanged: (selection) =>
                store.setAnalysisMode(selection.first),
          ),
          const SizedBox(height: 8),
          Text(
            store.analysisMode == 'device'
                ? 'Everything runs on this phone — no PC needed and nothing '
                    'ever leaves the device. The speech model is included '
                    'with the app.'
                : 'Recordings are sent to the NeuroVoice backend running on '
                    'your own computer for analysis.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (store.analysisMode == 'server') ...[
            const SizedBox(height: 16),
            TextField(
              controller: _serverController,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Server address',
                helperText: 'Android emulator: http://10.0.2.2:8000 — '
                    'physical phone: http://<your PC\'s LAN IP>:8000',
                helperMaxLines: 2,
                border: OutlineInputBorder(),
              ),
              onChanged: store.setServerUrl,
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _testing ? null : _testConnection,
              icon: const Icon(Icons.wifi_tethering),
              label: Text(_testing ? 'Testing…' : 'Test connection'),
            ),
          ],
          const SizedBox(height: 24),
          _sectionTitle(context, 'Data'),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.description_outlined),
            title: const Text('Export report for clinician'),
            subtitle: const Text('Copies a plain-text report to the clipboard'),
            onTap: _exportReport,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.delete_outline,
                color: Theme.of(context).colorScheme.error),
            title: const Text('Delete all data'),
            subtitle: const Text('Removes history on this device and server'),
            onTap: _confirmDelete,
          ),
          const SizedBox(height: 24),
          _sectionTitle(context, 'About'),
          Text(
            'NeuroVoice AI monitors changes in your speech over time by '
            'comparing new recordings to your own earlier ones. It is a '
            'monitoring aid, not a medical device, and it does not diagnose '
            'any condition. Recordings stay on your device and your own '
            'computer.\n\nAnonymous ID: ${store.userId.substring(0, 8)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }

  Future<void> _testConnection() async {
    setState(() => _testing = true);
    final ok = await _api.ping();
    setState(() => _testing = false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? 'Connected to the analysis server.'
          : 'Could not reach the server. Is the backend running, and are '
              'phone and PC on the same Wi-Fi?'),
    ));
  }

  Future<void> _exportReport() async {
    final report = buildClinicianReport(AppStore.instance);
    await Clipboard.setData(ClipboardData(text: report));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Report copied to clipboard — paste it into an email '
          'or document.'),
    ));
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete all data?'),
        content: const Text(
            'This permanently removes your recording history from this '
            'device and the analysis server.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (AppStore.instance.analysisMode == 'server') {
      await _api.deleteServerHistory();
    }
    await AppStore.instance.clearHistory();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('All data deleted.')),
    );
  }
}
