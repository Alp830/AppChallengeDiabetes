import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../app_features.dart';
import '../../cgm/data/glucose_repository.dart';
import '../../cgm/models/glucose_models.dart';
import '../data/meal_repository.dart';
import '../models/meal_models.dart';
import '../models/meal_balance_models.dart';
import '../services/meal_grouping_service.dart';
import 'meal_balance_input_form.dart';

class MealLogPage extends StatefulWidget {
  const MealLogPage({
    super.key,
    required this.userId,
    required this.geminiApiKey,
    this.initialName,
    this.diabetesEnabled = AppFeatures.diabetesEnabled,
  });
  final String userId;
  final String geminiApiKey;
  final String? initialName;
  final bool diabetesEnabled;

  @override
  State<MealLogPage> createState() => _MealLogPageState();
}

class _MealLogPageState extends State<MealLogPage> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initialName);
  final _restaurant = TextEditingController();
  final _carbs = TextEditingController();
  final _components = TextEditingController();
  final _movement = TextEditingController();
  final _notes = TextEditingController();
  final _repository = MealRepository();
  late final GlucoseRepository? _glucoseRepository = widget.diabetesEnabled
      ? GlucoseRepository()
      : null;
  Uint8List? _photo;
  DateTime _timestamp = DateTime.now();
  String _mealType = 'Meal';
  MealPortion _portion = MealPortion.usual;
  CarbBand _carbBand = CarbBand.unknown;
  MealOrder _order = MealOrder.together;
  MealPreparation _preparation = MealPreparation.fresh;
  bool _protein = false;
  bool _fat = false;
  bool _fiber = false;
  bool _saving = false;
  MealBalanceInput _balanceInput = const MealBalanceInput();
  int _balanceFormRevision = 0;

  @override
  void dispose() {
    for (final controller in [
      _name,
      _restaurant,
      _carbs,
      _components,
      _movement,
      _notes,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 72,
      maxWidth: 1280,
    );
    if (file != null) {
      final bytes = await file.readAsBytes();
      if (mounted) setState(() => _photo = Uint8List.fromList(bytes));
    }
  }

  Future<void> _chooseTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _timestamp,
      firstDate: DateTime.now().subtract(const Duration(days: 3650)),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_timestamp),
    );
    if (time != null) {
      setState(
        () => _timestamp = DateTime(
          date.year,
          date.month,
          date.day,
          time.hour,
          time.minute,
        ),
      );
    }
  }

  MealEvent _event() => MealEvent(
    id: '',
    name: _name.text.trim(),
    timestamp: _timestamp,
    mealType: _mealType,
    portion: _portion,
    carbBand: _carbBand,
    mealOrder: _order,
    preparation: _preparation,
    restaurant: _emptyToNull(_restaurant.text),
    carbohydrateGrams: double.tryParse(_carbs.text),
    hasProtein: _protein,
    hasFat: _fat,
    hasFiber: _fiber,
    components: _components.text
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(),
    nearbyMovement: _emptyToNull(_movement.text),
    notes: _emptyToNull(_notes.text),
    balanceInput: _balanceInput.isEmpty ? null : _balanceInput,
  );

  void _applyTemplate(MealTemplate template) {
    setState(() {
      _name.text = template.name;
      _restaurant.text = template.restaurant ?? '';
      _components.text = template.components.join(', ');
      _mealType = template.mealType;
      _portion = template.portion;
      _carbBand = template.carbBand;
      _order = template.mealOrder;
      _preparation = template.preparation;
      _protein = template.hasProtein;
      _fat = template.hasFat;
      _fiber = template.hasFiber;
      _balanceInput = template.balanceInput ?? const MealBalanceInput();
      _balanceFormRevision++;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final meal = _event();
      final id = await _repository.saveMeal(widget.userId, meal, photo: _photo);
      if (widget.diabetesEnabled) {
        final settings = await _glucoseRepository!
            .watchSettings(widget.userId)
            .first;
        if (settings.aiMealGroupingConsent) {
          await _groupMeal(meal.copyWith(id: id), settings);
        }
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save this meal. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _groupMeal(MealEvent meal, GlucoseSettings settings) async {
    try {
      final groups = await _repository.watchGroups(widget.userId).first;
      final proposal = await GeminiMealGroupingService(
        apiKey: widget.geminiApiKey,
      ).propose(meal, groups, photo: _photo);
      var accepted = proposal.confidence >= .85;
      if (!accepted && mounted) {
        accepted =
            await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Group this meal?'),
                content: Text(
                  '${proposal.canonicalName}\n\n${proposal.explanation}'
                  '${proposal.differences.isEmpty ? '' : '\n\nDifferent: ${proposal.differences.join(', ')}'}',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Leave ungrouped'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Use group'),
                  ),
                ],
              ),
            ) ??
            false;
      }
      if (!accepted) return;
      final groupId =
          proposal.groupId ??
          await _repository.createGroup(
            widget.userId,
            proposal.canonicalName,
            '${meal.name}: ${meal.components.join(', ')}',
          );
      await _repository.assignGroup(
        widget.userId,
        meal.id,
        groupId,
        proposal.confidence,
        confirmed: proposal.confidence < .85,
      );
      if (mounted && proposal.confidence >= .85) {
        final undo =
            await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: Text('Grouped as ${proposal.canonicalName}'),
                content: Text(
                  '${proposal.explanation}\n\nGemini confidence: ${(proposal.confidence * 100).round()}%',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Undo'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Keep group'),
                  ),
                ],
              ),
            ) ??
            false;
        if (undo) await _repository.unassignGroup(widget.userId, meal.id);
      }
    } catch (_) {
      // Grouping is optional and never prevents the meal from being saved.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Log meal')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            StreamBuilder<List<MealTemplate>>(
              stream: _repository.watchTemplates(widget.userId),
              builder: (context, snapshot) {
                final templates = snapshot.data ?? const <MealTemplate>[];
                if (templates.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Quick log',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final template in templates.take(6))
                          ActionChip(
                            avatar: const Icon(Icons.bolt, size: 18),
                            label: Text(template.name),
                            onPressed: () => _applyTemplate(template),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                );
              },
            ),
            OutlinedButton.icon(
              onPressed: _pickPhoto,
              icon: const Icon(Icons.add_a_photo),
              label: Text(
                _photo == null ? 'Add meal photo' : 'Change meal photo',
              ),
            ),
            if (_photo != null) ...[
              const SizedBox(height: 8),
              Image.memory(_photo!, height: 180, fit: BoxFit.cover),
            ],
            const SizedBox(height: 16),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Meal or dish name',
                border: OutlineInputBorder(),
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Enter a meal name'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _restaurant,
              decoration: const InputDecoration(
                labelText: 'Restaurant (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule),
              title: const Text('Meal time'),
              subtitle: Text(_timestamp.toString()),
              onTap: _chooseTime,
            ),
            DropdownButtonFormField<String>(
              initialValue: _mealType,
              decoration: const InputDecoration(labelText: 'Meal type'),
              items:
                  const [
                        'Meal',
                        'Breakfast',
                        'Lunch',
                        'Dinner',
                        'Snack',
                        'Drink',
                      ]
                      .map(
                        (value) =>
                            DropdownMenuItem(value: value, child: Text(value)),
                      )
                      .toList(),
              onChanged: (value) => setState(() => _mealType = value ?? 'Meal'),
            ),
            DropdownButtonFormField<MealPortion>(
              initialValue: _portion,
              decoration: const InputDecoration(labelText: 'Portion'),
              items: MealPortion.values
                  .map(
                    (value) =>
                        DropdownMenuItem(value: value, child: Text(value.name)),
                  )
                  .toList(),
              onChanged: (value) =>
                  setState(() => _portion = value ?? MealPortion.usual),
            ),
            TextFormField(
              controller: _carbs,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Carbohydrate grams (optional)',
              ),
            ),
            DropdownButtonFormField<CarbBand>(
              initialValue: _carbBand,
              decoration: const InputDecoration(labelText: 'Carbohydrate band'),
              items: CarbBand.values
                  .map(
                    (value) =>
                        DropdownMenuItem(value: value, child: Text(value.name)),
                  )
                  .toList(),
              onChanged: (value) =>
                  setState(() => _carbBand = value ?? CarbBand.unknown),
            ),
            CheckboxListTile(
              value: _protein,
              onChanged: (value) => setState(() => _protein = value ?? false),
              title: const Text('Contains protein'),
            ),
            CheckboxListTile(
              value: _fat,
              onChanged: (value) => setState(() => _fat = value ?? false),
              title: const Text('Contains substantial fat'),
            ),
            CheckboxListTile(
              value: _fiber,
              onChanged: (value) => setState(() => _fiber = value ?? false),
              title: const Text('Contains fiber'),
            ),
            Card(
              margin: const EdgeInsets.symmetric(vertical: 8),
              child: ExpansionTile(
                key: const Key('mealBalanceDetailsTile'),
                leading: const Icon(Icons.donut_large),
                title: const Text('Meal balance details'),
                subtitle: const Text('Optional scoring details'),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  MealBalanceInputForm(
                    key: ValueKey(_balanceFormRevision),
                    initialValue: _balanceInput,
                    onChanged: (value) => _balanceInput = value,
                  ),
                ],
              ),
            ),
            TextFormField(
              controller: _components,
              decoration: const InputDecoration(
                labelText: 'Ingredients, sides, accompaniments',
                hintText: 'fruit, nuts, milk',
              ),
            ),
            DropdownButtonFormField<MealOrder>(
              initialValue: _order,
              decoration: const InputDecoration(labelText: 'Meal order'),
              items: MealOrder.values
                  .map(
                    (value) =>
                        DropdownMenuItem(value: value, child: Text(value.name)),
                  )
                  .toList(),
              onChanged: (value) =>
                  setState(() => _order = value ?? MealOrder.together),
            ),
            DropdownButtonFormField<MealPreparation>(
              initialValue: _preparation,
              decoration: const InputDecoration(labelText: 'Preparation'),
              items: MealPreparation.values
                  .map(
                    (value) =>
                        DropdownMenuItem(value: value, child: Text(value.name)),
                  )
                  .toList(),
              onChanged: (value) =>
                  setState(() => _preparation = value ?? MealPreparation.fresh),
            ),
            TextFormField(
              controller: _movement,
              decoration: const InputDecoration(
                labelText: 'Nearby movement (optional)',
              ),
            ),
            TextFormField(
              controller: _notes,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save),
              label: Text(_saving ? 'Saving...' : 'Save meal'),
            ),
          ],
        ),
      ),
    );
  }
}

String? _emptyToNull(String value) =>
    value.trim().isEmpty ? null : value.trim();
