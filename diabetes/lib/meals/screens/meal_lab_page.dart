import 'package:flutter/material.dart';

import '../../app_features.dart';
import '../../cgm/data/glucose_repository.dart';
import '../../cgm/models/glucose_models.dart';
import '../data/meal_repository.dart';
import '../models/meal_models.dart';
import '../services/meal_analysis_service.dart';

class MealLabPage extends StatefulWidget {
  const MealLabPage({
    super.key,
    required this.userId,
    this.diabetesEnabled = AppFeatures.diabetesEnabled,
  });
  final String userId;
  final bool diabetesEnabled;

  @override
  State<MealLabPage> createState() => _MealLabPageState();
}

class _MealLabPageState extends State<MealLabPage> {
  final _meals = MealRepository();
  late final GlucoseRepository? _glucose = widget.diabetesEnabled
      ? GlucoseRepository()
      : null;

  Future<_MealLabData> _analyze(
    List<MealEvent> meals,
    List<MealGroup> groups,
    GlucoseSettings settings,
  ) async {
    if (meals.isEmpty) {
      return _MealLabData(meals: meals, groups: groups, fingerprints: const []);
    }
    final ordered = List<MealEvent>.of(meals)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final start = ordered.first.timestamp.subtract(const Duration(minutes: 15));
    final end = ordered.last.timestamp.add(const Duration(hours: 4));
    final readings = await _glucose!.getRange(widget.userId, start, end);
    const service = MealAnalysisService();
    final fingerprints = <MealFingerprint>[];
    for (var index = 0; index < ordered.length; index++) {
      fingerprints.add(
        service.fingerprint(
          ordered[index],
          readings,
          nextMealAt: index + 1 < ordered.length
              ? ordered[index + 1].timestamp
              : null,
          settings: settings,
        ),
      );
    }
    return _MealLabData(
      meals: ordered.reversed.toList(),
      groups: groups,
      fingerprints: fingerprints,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Meal Lab'),
        actions: [
          IconButton(
            onPressed: _manageGroups,
            tooltip: 'Manage meal groups',
            icon: const Icon(Icons.folder_copy_outlined),
          ),
        ],
      ),
      body: StreamBuilder<List<MealEvent>>(
        stream: _meals.watchMeals(widget.userId),
        builder: (context, mealSnapshot) {
          if (mealSnapshot.hasError) {
            return const Center(child: Text('Could not load meals.'));
          }
          if (!mealSnapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return StreamBuilder<List<MealGroup>>(
            stream: _meals.watchGroups(widget.userId),
            builder: (context, groupSnapshot) {
              if (!groupSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              if (!widget.diabetesEnabled) {
                return _MealLabView(
                  data: _MealLabData(
                    meals: mealSnapshot.data!,
                    groups: groupSnapshot.data!,
                    fingerprints: const [],
                  ),
                  hasGlucose: false,
                  onDelete: (meal) => _meals.deleteMeal(widget.userId, meal),
                  onUngroup: (meal) =>
                      _meals.unassignGroup(widget.userId, meal.id),
                  onSaveTemplate: (meal) =>
                      _meals.saveTemplate(widget.userId, meal),
                  onChangeGroup: (meal) =>
                      _chooseGroup(meal, groupSnapshot.data!),
                );
              }
              final glucose = _glucose!;
              return StreamBuilder<GlucoseSettings>(
                stream: glucose.watchSettings(widget.userId),
                builder: (context, settingsSnapshot) =>
                    FutureBuilder<_MealLabData>(
                      future: _analyze(
                        mealSnapshot.data!,
                        groupSnapshot.data!,
                        settingsSnapshot.data ?? const GlucoseSettings(),
                      ),
                      builder: (context, dataSnapshot) {
                        if (!dataSnapshot.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        return StreamBuilder<bool>(
                          stream: glucose.watchHasGlucoseData(widget.userId),
                          builder: (context, glucoseSnapshot) => _MealLabView(
                            data: dataSnapshot.data!,
                            hasGlucose: glucoseSnapshot.data ?? false,
                            onDelete: (meal) =>
                                _meals.deleteMeal(widget.userId, meal),
                            onUngroup: (meal) =>
                                _meals.unassignGroup(widget.userId, meal.id),
                            onSaveTemplate: (meal) =>
                                _meals.saveTemplate(widget.userId, meal),
                            onChangeGroup: (meal) =>
                                _chooseGroup(meal, groupSnapshot.data!),
                          ),
                        );
                      },
                    ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _chooseGroup(MealEvent meal, List<MealGroup> groups) async {
    final group = await showDialog<MealGroup>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Move meal to group'),
        children: [
          for (final group in groups)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(group),
              child: Text(group.name),
            ),
        ],
      ),
    );
    if (group != null) {
      await _meals.assignGroup(
        widget.userId,
        meal.id,
        group.id,
        1,
        confirmed: true,
      );
    }
  }

  Future<void> _manageGroups() async {
    final groups = await _meals.watchGroups(widget.userId).first;
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Manage meal groups',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          if (groups.isEmpty) const Text('No AI meal groups yet.'),
          for (final group in groups)
            ListTile(
              title: Text(group.name),
              subtitle: Text(group.summary),
              trailing: Wrap(
                children: [
                  IconButton(
                    tooltip: 'Rename ${group.name}',
                    onPressed: () async {
                      Navigator.of(sheetContext).pop();
                      await _renameGroup(group);
                    },
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  if (groups.length > 1)
                    IconButton(
                      tooltip: 'Merge ${group.name}',
                      onPressed: () async {
                        Navigator.of(sheetContext).pop();
                        await _mergeGroup(group, groups);
                      },
                      icon: const Icon(Icons.merge),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _renameGroup(MealGroup group) async {
    var name = group.name;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename meal group'),
        content: TextFormField(
          initialValue: group.name,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Group name'),
          onChanged: (value) => name = value.trim(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (confirmed == true && name.isNotEmpty) {
      await _meals.renameGroup(widget.userId, group.id, name);
    }
  }

  Future<void> _mergeGroup(MealGroup source, List<MealGroup> groups) async {
    final destination = await showDialog<MealGroup>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('Merge ${source.name} into…'),
        children: [
          for (final group in groups.where((item) => item.id != source.id))
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(group),
              child: Text(group.name),
            ),
        ],
      ),
    );
    if (destination != null) {
      await _meals.mergeGroups(widget.userId, source.id, destination.id);
    }
  }
}

class _MealLabView extends StatelessWidget {
  const _MealLabView({
    required this.data,
    required this.hasGlucose,
    required this.onDelete,
    required this.onUngroup,
    required this.onSaveTemplate,
    required this.onChangeGroup,
  });
  final _MealLabData data;

  /// Whether the user has imported glucose data. Gates the CGM fingerprint and
  /// comparison sections; the meal library always shows.
  final bool hasGlucose;
  final Future<void> Function(MealEvent meal) onDelete;
  final Future<void> Function(MealEvent meal) onUngroup;
  final Future<void> Function(MealEvent meal) onSaveTemplate;
  final Future<void> Function(MealEvent meal) onChangeGroup;

  @override
  Widget build(BuildContext context) {
    final groupsById = {for (final group in data.groups) group.id: group};
    final fingerprintsByMeal = {
      for (final item in data.fingerprints) item.meal.id: item,
    };
    final grouped = <String, List<MealFingerprint>>{};
    for (final fingerprint in data.fingerprints.where(
      (item) => item.meal.groupId != null,
    )) {
      grouped.putIfAbsent(fingerprint.meal.groupId!, () => []).add(fingerprint);
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Meal Lab describes repeated records. It does not rate foods or recommend treatment changes.',
            ),
          ),
        ),
        Text('My Meal Library', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        if (data.meals.isEmpty)
          const Text('Log a meal to begin building your library.')
        else
          for (final meal in data.meals)
            Card(
              child: ListTile(
                leading: meal.photoUrl == null
                    ? const CircleAvatar(child: Icon(Icons.restaurant))
                    : CircleAvatar(
                        backgroundImage: NetworkImage(meal.photoUrl!),
                      ),
                title: Text(meal.name),
                subtitle: Text(
                  '${groupsById[meal.groupId]?.name ?? 'Ungrouped'} • ${meal.portion.name}'
                  '${!hasGlucose
                      ? ''
                      : fingerprintsByMeal[meal.id]?.hasCoverage == true
                      ? ' • CGM fingerprint ready'
                      : ' • incomplete CGM coverage'}',
                ),
                trailing: PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'ungroup') onUngroup(meal);
                    if (value == 'group') onChangeGroup(meal);
                    if (value == 'template') onSaveTemplate(meal);
                    if (value == 'delete') onDelete(meal);
                  },
                  itemBuilder: (context) => [
                    if (meal.groupId != null)
                      const PopupMenuItem(
                        value: 'ungroup',
                        child: Text('Move out of group'),
                      ),
                    if (data.groups.isNotEmpty)
                      const PopupMenuItem(
                        value: 'group',
                        child: Text('Change group'),
                      ),
                    const PopupMenuItem(
                      value: 'template',
                      child: Text('Save as quick-log template'),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('Delete meal'),
                    ),
                  ],
                ),
              ),
            ),
        // Fingerprints and comparisons are glucose-derived — only shown once
        // the user has imported glucose data.
        if (hasGlucose) ...[
          const SizedBox(height: 20),
          Text(
            'Meal Curve Fingerprints',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          for (final entry in grouped.entries)
            _GroupAnalysisCard(
              name: groupsById[entry.key]?.name ?? 'Meal group',
              fingerprints: entry.value,
            ),
          if (grouped.isEmpty)
            const Text(
              'AI-group at least one meal and import matching glucose data to see fingerprints.',
            ),
          const SizedBox(height: 20),
          Text('Comparisons', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          _CapabilityGrid(grouped: grouped),
        ],
      ],
    );
  }
}

class _GroupAnalysisCard extends StatelessWidget {
  const _GroupAnalysisCard({required this.name, required this.fingerprints});
  final String name;
  final List<MealFingerprint> fingerprints;

  @override
  Widget build(BuildContext context) {
    final covered = fingerprints.where((item) => item.hasCoverage).toList();
    final averageRise = covered.isEmpty
        ? null
        : covered.map((item) => item.riseMgDl!).reduce((a, b) => a + b) /
              covered.length;
    final delayed = covered.where((item) => item.delayedRise).length;
    final service = const MealAnalysisService();
    return Card(
      child: ExpansionTile(
        title: Text(name),
        subtitle: Text(
          '${service.evidenceLevel(covered.length)} • ${covered.length} supported events',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          if (averageRise == null)
            const Text('More glucose coverage is needed.')
          else ...[
            Text('Average recorded rise: ${averageRise.round()} mg/dL.'),
            Text('Delayed largest rise: $delayed of ${covered.length} events.'),
            Text(
              'Response variability: ${service.consistency(covered).round()} mg/dL.',
            ),
            const SizedBox(height: 8),
            const Text(
              'Why am I seeing this? These values use the 15-minute baseline and up to four hours after each recorded meal.',
            ),
          ],
        ],
      ),
    );
  }
}

class _CapabilityGrid extends StatelessWidget {
  const _CapabilityGrid({required this.grouped});
  final Map<String, List<MealFingerprint>> grouped;

  @override
  Widget build(BuildContext context) {
    const features = [
      'Same Meal, Different Context',
      'Meal Twin Comparison',
      'Delayed-Rise Detector',
      'Restaurant Memory',
      'Leftover Comparison',
      'Meal Sequence Comparison',
      'Portion Comparison',
      'Combination Finder',
      'Recovery Pattern',
      'Meal Consistency',
    ];
    final covered = grouped.values
        .expand((items) => items)
        .where((item) => item.hasCoverage)
        .toList();
    return Column(
      children: [
        for (final feature in features)
          Card(
            child: ListTile(
              title: Text(feature),
              subtitle: Text(_comparisonSummary(feature, grouped, covered)),
              trailing: Icon(
                grouped.values.any((items) => items.length >= 3)
                    ? Icons.check_circle_outline
                    : Icons.hourglass_empty,
              ),
            ),
          ),
      ],
    );
  }
}

String _comparisonSummary(
  String feature,
  Map<String, List<MealFingerprint>> grouped,
  List<MealFingerprint> covered,
) {
  if (!grouped.values.any((items) => items.length >= 3)) {
    return 'Complete at least three comparable, AI-grouped meals.';
  }
  return switch (feature) {
    'Same Meal, Different Context' =>
      '${covered.map((item) => item.meal.portion).toSet().length} portion contexts and ${covered.map((item) => item.meal.mealOrder).toSet().length} meal-order contexts recorded.',
    'Meal Twin Comparison' =>
      '${grouped.length} meal groups are available for side-by-side review.',
    'Delayed-Rise Detector' =>
      '${covered.where((item) => item.delayedRise).length} supported events had their largest recorded rise after two hours.',
    'Restaurant Memory' =>
      '${covered.where((item) => item.meal.restaurant?.isNotEmpty == true).length} supported restaurant meals recorded.',
    'Leftover Comparison' =>
      '${covered.where((item) => item.meal.preparation == MealPreparation.fresh).length} fresh and ${covered.where((item) => item.meal.preparation != MealPreparation.fresh).length} leftover/reheated events.',
    'Meal Sequence Comparison' =>
      '${covered.map((item) => item.meal.mealOrder).toSet().length} recorded meal-order contexts.',
    'Portion Comparison' =>
      '${covered.map((item) => item.meal.portion).toSet().length} recorded portion bands.',
    'Combination Finder' =>
      '${covered.expand((item) => item.meal.components).toSet().length} distinct meal components recorded.',
    'Recovery Pattern' =>
      '${covered.where((item) => item.minutesToRecovery != null).length} events returned near baseline within the measured window.',
    'Meal Consistency' =>
      'Recorded rise variability is ${const MealAnalysisService().consistency(covered).round()} mg/dL across supported events.',
    _ => 'Uses repeated events and shows supporting records.',
  };
}

class _MealLabData {
  const _MealLabData({
    required this.meals,
    required this.groups,
    required this.fingerprints,
  });
  final List<MealEvent> meals;
  final List<MealGroup> groups;
  final List<MealFingerprint> fingerprints;
}
