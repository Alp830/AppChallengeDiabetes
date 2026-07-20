import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../app_features.dart';
import '../data/demo_cgm_importer.dart';
import '../data/glucose_repository.dart';
import '../data/libreview_csv_importer.dart';
import '../models/glucose_models.dart';

class GlucoseSettingsPage extends StatefulWidget {
  const GlucoseSettingsPage({
    super.key,
    required this.userId,
    this.diabetesEnabled = AppFeatures.diabetesEnabled,
    this.repositoryFactory,
  });

  final String userId;
  final bool diabetesEnabled;
  final GlucoseRepository Function()? repositoryFactory;

  @override
  State<GlucoseSettingsPage> createState() => _GlucoseSettingsPageState();
}

class _GlucoseSettingsPageState extends State<GlucoseSettingsPage> {
  late final GlucoseRepository? _repository;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _repository = widget.diabetesEnabled
        ? (widget.repositoryFactory?.call() ?? GlucoseRepository())
        : null;
  }

  Future<void> _importLibreView() async {
    final repository = _repository;
    if (repository == null) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv', 'txt'],
      withData: true,
    );
    final bytes = result?.files.single.bytes;
    if (bytes == null) return;
    setState(() => _busy = true);
    try {
      final preview = await const LibreViewCsvImporter().parse(
        utf8.decode(bytes, allowMalformed: true),
      );
      if (!mounted) return;
      final confirmed = await _showPreview(preview);
      if (confirmed) {
        await repository.saveImport(widget.userId, preview);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${preview.readings.length} readings imported.'),
            ),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not read that LibreView export. Check the file and try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadDemo() async {
    final repository = _repository;
    if (repository == null) return;
    setState(() => _busy = true);
    try {
      final preview = await const DemoCgmImporter().parse('');
      await repository.saveImport(widget.userId, preview);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Seven days of demo readings added.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _showPreview(CgmImportPreview preview) async {
    var timezoneConfirmed = preview.timezoneWasInferred;
    return await showDialog<bool>(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              title: const Text('Review LibreView import'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${preview.readings.length} valid readings'),
                  Text('${preview.rejectedRows} rejected rows'),
                  Text('${preview.duplicateRows} duplicates in this file'),
                  Text('Detected unit: ${preview.detectedUnit}'),
                  if (preview.deviceId != null)
                    Text('Device: ${preview.deviceId}'),
                  if (preview.startedAt != null && preview.endedAt != null)
                    Text(
                      'Range: ${preview.startedAt!.toLocal()} through ${preview.endedAt!.toLocal()}',
                    ),
                  const SizedBox(height: 12),
                  const Text(
                    'The export does not identify a timezone. Times will use this device’s current timezone.',
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: timezoneConfirmed,
                    onChanged: (value) => setDialogState(
                      () => timezoneConfirmed = value ?? false,
                    ),
                    title: const Text(
                      'The displayed date and time range looks correct',
                    ),
                  ),
                  const Text('Imported data is historical and may be delayed.'),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: timezoneConfirmed
                      ? () => Navigator.of(context).pop(true)
                      : null,
                  child: const Text('Import'),
                ),
              ],
            ),
          ),
        ) ??
        false;
  }

  Future<void> _editRange(GlucoseSettings settings) async {
    final repository = _repository;
    if (repository == null) return;
    var unit = settings.displayUnit;
    var low = glucoseForDisplay(settings.lowMgDl, unit).round().toString();
    var high = glucoseForDisplay(settings.highMgDl, unit).round().toString();
    final updated = await showDialog<GlucoseSettings>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Personal glucose range'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: unit,
                items: const [
                  DropdownMenuItem(value: 'mg/dL', child: Text('mg/dL')),
                  DropdownMenuItem(value: 'mmol/L', child: Text('mmol/L')),
                ],
                onChanged: (value) {
                  if (value != null) setDialogState(() => unit = value);
                },
                decoration: const InputDecoration(labelText: 'Display unit'),
              ),
              TextFormField(
                initialValue: low,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Lower bound'),
                onChanged: (value) => low = value,
              ),
              TextFormField(
                initialValue: high,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Upper bound'),
                onChanged: (value) => high = value,
              ),
              const SizedBox(height: 12),
              const Text(
                'Confirm a range agreed on with your diabetes care team.',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final lowValue = double.tryParse(low);
                final highValue = double.tryParse(high);
                if (lowValue == null ||
                    highValue == null ||
                    lowValue >= highValue) {
                  return;
                }
                final multiplier = unit == 'mmol/L' ? 18.0182 : 1.0;
                Navigator.of(context).pop(
                  settings.copyWith(
                    displayUnit: unit,
                    lowMgDl: lowValue * multiplier,
                    highMgDl: highValue * multiplier,
                    rangeConfirmed: true,
                  ),
                );
              },
              child: const Text('Confirm'),
            ),
          ],
        ),
      ),
    );
    if (updated != null) await repository.saveSettings(widget.userId, updated);
  }

  @override
  Widget build(BuildContext context) {
    final repository = _repository;
    if (repository == null) {
      return const SizedBox.shrink(key: Key('diabetesFeatureDisabled'));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Glucose & data sources')),
      body: StreamBuilder<GlucoseSettings>(
        stream: repository.watchSettings(widget.userId),
        builder: (context, snapshot) {
          final settings = snapshot.data ?? const GlucoseSettings();
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: ListTile(
                  leading: const Icon(Icons.monitor_heart),
                  title: const Text('LibreView Import'),
                  subtitle: const Text(
                    'Import a CSV downloaded from LibreView.',
                  ),
                  trailing: FilledButton(
                    onPressed: _busy ? null : _importLibreView,
                    child: const Text('Choose file'),
                  ),
                ),
              ),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.science_outlined),
                  title: const Text('Demo data'),
                  subtitle: const Text(
                    'Synthetic readings are kept separate from real imports.',
                  ),
                  trailing: TextButton(
                    onPressed: _busy ? null : _loadDemo,
                    child: const Text('Add demo'),
                  ),
                ),
              ),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.tune),
                  title: const Text('Display unit and personal range'),
                  subtitle: Text(
                    settings.rangeConfirmed
                        ? '${settings.displayUnit}: ${glucoseForDisplay(settings.lowMgDl, settings.displayUnit).toStringAsFixed(settings.displayUnit == 'mmol/L' ? 1 : 0)}–${glucoseForDisplay(settings.highMgDl, settings.displayUnit).toStringAsFixed(settings.displayUnit == 'mmol/L' ? 1 : 0)}'
                        : 'Range not confirmed',
                  ),
                  onTap: () => _editRange(settings),
                ),
              ),
              SwitchListTile(
                title: const Text('AI meal grouping'),
                subtitle: const Text(
                  'Gemini receives meal details, but never glucose readings or your identity.',
                ),
                value: settings.aiMealGroupingConsent,
                onChanged: (value) => repository.saveSettings(
                  widget.userId,
                  settings.copyWith(aiMealGroupingConsent: value),
                ),
              ),
              const Divider(),
              const ListTile(
                enabled: false,
                leading: Icon(Icons.bluetooth_disabled),
                title: Text('Approved live Libre connection'),
                subtitle: Text(
                  'Not available until an authorized integration exists.',
                ),
              ),
              const ListTile(
                enabled: false,
                leading: Icon(Icons.devices_other),
                title: Text('Other CGM sources'),
                subtitle: Text(
                  'Provider adapters are planned for a future release.',
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Import history',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: repository.watchImports(widget.userId),
                builder: (context, importSnapshot) {
                  if (!importSnapshot.hasData) {
                    return const ListTile(title: Text('No imports yet.'));
                  }
                  final documents = importSnapshot.data!.docs;
                  if (documents.isEmpty) {
                    return const ListTile(title: Text('No imports yet.'));
                  }
                  return Column(
                    children: [
                      for (final document in documents.take(5))
                        ListTile(
                          leading: Icon(
                            document.data()['source'] == GlucoseSource.demo.name
                                ? Icons.science_outlined
                                : Icons.upload_file,
                          ),
                          title: Text(
                            document.data()['source'] == GlucoseSource.demo.name
                                ? 'Demo data'
                                : 'LibreView CSV',
                          ),
                          subtitle: Text(
                            '${document.data()['readingCount'] ?? 0} readings • '
                            '${document.data()['rejectedRows'] ?? 0} rejected rows',
                          ),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 20),
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => repository.deleteSource(
                        widget.userId,
                        GlucoseSource.demo,
                      ),
                child: const Text('Remove demo readings'),
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => repository.deleteSource(
                        widget.userId,
                        GlucoseSource.libreView,
                      ),
                child: const Text('Delete all imported glucose data'),
              ),
              const SizedBox(height: 16),
              const Text(
                'Imported readings may be delayed. Continue using the official Libre app for alarms and treatment decisions.',
                textAlign: TextAlign.center,
              ),
            ],
          );
        },
      ),
    );
  }
}
