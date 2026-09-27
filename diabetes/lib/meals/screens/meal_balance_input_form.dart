import 'package:flutter/material.dart';

import '../models/meal_balance_models.dart';

class MealBalanceInputForm extends StatefulWidget {
  const MealBalanceInputForm({
    super.key,
    required this.onChanged,
    this.initialValue = const MealBalanceInput(),
  });

  final MealBalanceInput initialValue;
  final ValueChanged<MealBalanceInput> onChanged;

  @override
  State<MealBalanceInputForm> createState() => _MealBalanceInputFormState();
}

class _MealBalanceInputFormState extends State<MealBalanceInputForm> {
  late final TextEditingController _protein;
  late final TextEditingController _fiber;
  late final TextEditingController _produceCups;
  late final TextEditingController _hydration;
  late final TextEditingController _producePercent;
  late final TextEditingController _proteinPercent;
  late final TextEditingController _qualityCarbPercent;

  @override
  void initState() {
    super.initState();
    _protein = _controller(widget.initialValue.proteinGrams);
    _fiber = _controller(widget.initialValue.fiberGrams);
    _produceCups = _controller(widget.initialValue.produceCupEquivalents);
    _hydration = _controller(widget.initialValue.hydrationMilliliters);
    _producePercent = _controller(widget.initialValue.producePlatePercent);
    _proteinPercent = _controller(widget.initialValue.proteinPlatePercent);
    _qualityCarbPercent = _controller(
      widget.initialValue.qualityCarbPlatePercent,
    );
  }

  @override
  void dispose() {
    for (final controller in [
      _protein,
      _fiber,
      _produceCups,
      _hydration,
      _producePercent,
      _proteinPercent,
      _qualityCarbPercent,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  TextEditingController _controller(double? value) =>
      TextEditingController(text: value == null ? '' : _formatNumber(value));

  String _formatNumber(double value) => value == value.roundToDouble()
      ? value.round().toString()
      : value.toString();

  MealBalanceInput _value() => MealBalanceInput(
    proteinGrams: _number(_protein.text),
    fiberGrams: _number(_fiber.text),
    produceCupEquivalents: _number(_produceCups.text),
    hydrationMilliliters: _number(_hydration.text),
    producePlatePercent: _number(_producePercent.text),
    proteinPlatePercent: _number(_proteinPercent.text),
    qualityCarbPlatePercent: _number(_qualityCarbPercent.text),
  );

  double? _number(String value) => double.tryParse(value.trim());

  void _notify(_) => widget.onChanged(_value());

  String? _nonNegative(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final number = double.tryParse(value.trim());
    if (number == null || number < 0) return 'Enter 0 or more';
    return null;
  }

  String? _plateValidation(String? _) {
    final values = [
      _producePercent.text.trim(),
      _proteinPercent.text.trim(),
      _qualityCarbPercent.text.trim(),
    ];
    if (values.every((value) => value.isEmpty)) return null;
    final parsed = values.map(double.tryParse).toList();
    if (parsed.any((value) => value == null || value < 0 || value > 100)) {
      return 'Enter all three percentages from 0 to 100';
    }
    final total = parsed.whereType<double>().fold<double>(0, (a, b) => a + b);
    if ((total - 100).abs() > 0.5) return 'Plate percentages must total 100';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    const numberKeyboard = TextInputType.numberWithOptions(decimal: true);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'All fields are optional. More details improve score confidence.',
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                key: const Key('balanceProteinField'),
                controller: _protein,
                keyboardType: numberKeyboard,
                decoration: const InputDecoration(
                  labelText: 'Protein',
                  suffixText: 'g',
                ),
                validator: _nonNegative,
                onChanged: _notify,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                key: const Key('balanceFiberField'),
                controller: _fiber,
                keyboardType: numberKeyboard,
                decoration: const InputDecoration(
                  labelText: 'Fiber',
                  suffixText: 'g',
                ),
                validator: _nonNegative,
                onChanged: _notify,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                key: const Key('balanceProduceField'),
                controller: _produceCups,
                keyboardType: numberKeyboard,
                decoration: const InputDecoration(
                  labelText: 'Produce',
                  suffixText: 'cups',
                ),
                validator: _nonNegative,
                onChanged: _notify,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                key: const Key('balanceHydrationField'),
                controller: _hydration,
                keyboardType: numberKeyboard,
                decoration: const InputDecoration(
                  labelText: 'Unsweetened drink',
                  suffixText: 'mL',
                ),
                validator: _nonNegative,
                onChanged: _notify,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text('Plate split', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        const Text('Target: 50% produce, 25% protein, 25% quality carbs.'),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                key: const Key('balanceProducePercentField'),
                controller: _producePercent,
                keyboardType: numberKeyboard,
                decoration: const InputDecoration(
                  labelText: 'Produce',
                  suffixText: '%',
                ),
                validator: _nonNegative,
                onChanged: _notify,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                key: const Key('balanceProteinPercentField'),
                controller: _proteinPercent,
                keyboardType: numberKeyboard,
                decoration: const InputDecoration(
                  labelText: 'Protein',
                  suffixText: '%',
                ),
                validator: _nonNegative,
                onChanged: _notify,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                key: const Key('balanceCarbPercentField'),
                controller: _qualityCarbPercent,
                keyboardType: numberKeyboard,
                decoration: const InputDecoration(
                  labelText: 'Quality carbs',
                  suffixText: '%',
                ),
                validator: _plateValidation,
                onChanged: _notify,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
