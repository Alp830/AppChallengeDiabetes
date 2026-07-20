import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/meal_repository.dart';
import '../models/meal_balance_models.dart';
import '../models/meal_models.dart';
import '../services/meal_balance_calculator.dart';
import 'meal_balance_input_form.dart';

enum BalancePageMode { savedMeals, calculator }

enum BalanceVisualization { breakdown, ring, plate }

class MealBalancePage extends StatefulWidget {
  const MealBalancePage({
    super.key,
    required this.userId,
    this.repository,
    this.mealsStream,
    this.onUpdateBalance,
  });

  final String userId;
  final MealRepository? repository;
  final Stream<List<MealEvent>>? mealsStream;
  final Future<void> Function(String mealId, MealBalanceInput? input)?
  onUpdateBalance;

  @override
  State<MealBalancePage> createState() => _MealBalancePageState();
}

class _MealBalancePageState extends State<MealBalancePage> {
  static const _calculator = MealBalanceCalculator();
  late final MealRepository? _repository =
      widget.mealsStream == null || widget.onUpdateBalance == null
      ? widget.repository ?? MealRepository()
      : widget.repository;
  late final Stream<List<MealEvent>> _meals =
      widget.mealsStream ?? _repository!.watchMeals(widget.userId);

  BalancePageMode _mode = BalancePageMode.savedMeals;
  BalanceVisualization _visualization = BalanceVisualization.breakdown;
  MealBalanceInput _calculatorInput = const MealBalanceInput();
  String? _selectedMealId;

  Future<void> _editMeal(MealEvent meal) async {
    final formKey = GlobalKey<FormState>();
    var input = meal.balanceInput ?? const MealBalanceInput();
    final updated = await showModalBottomSheet<MealBalanceInput>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Balance details for ${meal.name}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                MealBalanceInputForm(
                  initialValue: input,
                  onChanged: (value) => input = value,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  key: const Key('saveMealBalanceButton'),
                  onPressed: () {
                    if (formKey.currentState!.validate()) {
                      Navigator.of(context).pop(input);
                    }
                  },
                  child: const Text('Save balance details'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (updated == null) return;
    final callback = widget.onUpdateBalance;
    if (callback != null) {
      await callback(meal.id, updated.isEmpty ? null : updated);
    } else {
      await _repository!.updateMealBalance(
        widget.userId,
        meal.id,
        updated.isEmpty ? null : updated,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const Key('mealBalancePage'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        const Text(
          'Build more balanced meals',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        const Text(
          'This wellness score highlights protein, fiber, produce, hydration, and portion structure. It is not medical advice.',
        ),
        const SizedBox(height: 16),
        SegmentedButton<BalancePageMode>(
          segments: const [
            ButtonSegment(
              value: BalancePageMode.savedMeals,
              icon: Icon(Icons.history),
              label: Text('Saved meals'),
            ),
            ButtonSegment(
              value: BalancePageMode.calculator,
              icon: Icon(Icons.calculate_outlined),
              label: Text('Calculator'),
            ),
          ],
          selected: {_mode},
          onSelectionChanged: (selection) =>
              setState(() => _mode = selection.first),
        ),
        const SizedBox(height: 16),
        if (_mode == BalancePageMode.savedMeals)
          _buildSavedMeals()
        else
          _buildCalculator(),
      ],
    );
  }

  Widget _buildSavedMeals() {
    return StreamBuilder<List<MealEvent>>(
      stream: _meals,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('Could not load saved meals.'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final meals = snapshot.data!;
        if (meals.isEmpty) {
          return const _MessageCard(
            icon: Icons.restaurant_outlined,
            message: 'Log a meal to begin building your balance history.',
          );
        }
        final selected = meals
            .where((meal) => meal.id == _selectedMealId)
            .firstOrNull;
        final activeMeal = selected ?? meals.first;
        final result = activeMeal.balanceInput == null
            ? null
            : _calculator.calculate(activeMeal.balanceInput!);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              activeMeal.name,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            if (result == null)
              _MessageCard(
                icon: Icons.edit_note,
                message:
                    'This meal does not have balance details yet. Existing meal tags are not guessed into numeric scores.',
                actionLabel: 'Add balance details',
                onAction: () => _editMeal(activeMeal),
              )
            else ...[
              _VisualizationPicker(
                value: _visualization,
                onChanged: (value) => setState(() => _visualization = value),
              ),
              const SizedBox(height: 12),
              _BalanceResultView(
                result: result,
                input: activeMeal.balanceInput!,
                visualization: _visualization,
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => _editMeal(activeMeal),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit balance details'),
                ),
              ),
            ],
            const SizedBox(height: 20),
            Text(
              'Recent meals',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            for (final meal in meals.take(20))
              _SavedMealTile(
                meal: meal,
                selected: meal.id == activeMeal.id,
                result: meal.balanceInput == null
                    ? null
                    : _calculator.calculate(meal.balanceInput!),
                onTap: () => setState(() => _selectedMealId = meal.id),
                onEdit: () => _editMeal(meal),
              ),
          ],
        );
      },
    );
  }

  Widget _buildCalculator() {
    final result = _calculator.calculate(_calculatorInput);
    return Form(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: MealBalanceInputForm(
                onChanged: (value) => setState(() => _calculatorInput = value),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (result == null)
            const _MessageCard(
              icon: Icons.tune,
              message:
                  'Enter any detail to calculate a score. Missing components will not count against the meal.',
            )
          else ...[
            _VisualizationPicker(
              value: _visualization,
              onChanged: (value) => setState(() => _visualization = value),
            ),
            const SizedBox(height: 12),
            _BalanceResultView(
              result: result,
              input: _calculatorInput,
              visualization: _visualization,
            ),
          ],
        ],
      ),
    );
  }
}

class _VisualizationPicker extends StatelessWidget {
  const _VisualizationPicker({required this.value, required this.onChanged});

  final BalanceVisualization value;
  final ValueChanged<BalanceVisualization> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SegmentedButton<BalanceVisualization>(
        key: const Key('balanceVisualizationPicker'),
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(
            value: BalanceVisualization.breakdown,
            icon: Icon(Icons.percent),
            label: Text('Breakdown'),
          ),
          ButtonSegment(
            value: BalanceVisualization.ring,
            icon: Icon(Icons.donut_large),
            label: Text('Ring'),
          ),
          ButtonSegment(
            value: BalanceVisualization.plate,
            icon: Icon(Icons.pie_chart_outline),
            label: Text('Plate'),
          ),
        ],
        selected: {value},
        onSelectionChanged: (selection) => onChanged(selection.first),
      ),
    );
  }
}

class _BalanceResultView extends StatelessWidget {
  const _BalanceResultView({
    required this.result,
    required this.input,
    required this.visualization,
  });

  final MealBalanceResult result;
  final MealBalanceInput input;
  final BalanceVisualization visualization;

  @override
  Widget build(BuildContext context) {
    final visual = switch (visualization) {
      BalanceVisualization.breakdown => _BreakdownView(result: result),
      BalanceVisualization.ring => _RingView(result: result),
      BalanceVisualization.plate => _PlateView(input: input),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        visual,
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'What\'s working',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(result.whatsWorking),
                const SizedBox(height: 14),
                Text(
                  'One optional improvement',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(result.optionalImprovement),
                if (result.fiberStretch) ...[
                  const SizedBox(height: 12),
                  const Chip(
                    avatar: Icon(Icons.stars_outlined),
                    label: Text('Fiber stretch: 10 g+'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _BreakdownView extends StatelessWidget {
  const _BreakdownView({required this.result});

  final MealBalanceResult result;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const Key('balanceBreakdownView'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ScoreHeading(result: result),
            const SizedBox(height: 16),
            for (final component in MealBalanceComponent.values) ...[
              _ComponentProgress(
                component: component,
                score: result.componentScores[component],
                contribution: result.weightedContributions[component],
              ),
              if (component != MealBalanceComponent.values.last)
                const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}

class _ScoreHeading extends StatelessWidget {
  const _ScoreHeading({required this.result});

  final MealBalanceResult result;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          '${result.overallScore.round()}%',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(width: 12),
        Expanded(child: Text('${result.confidence.label} confidence')),
      ],
    );
  }
}

class _ComponentProgress extends StatelessWidget {
  const _ComponentProgress({
    required this.component,
    required this.score,
    required this.contribution,
  });

  final MealBalanceComponent component;
  final double? score;
  final double? contribution;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${component.label} (${(component.weight * 100).round()}% weight)',
              ),
            ),
            Text(
              score == null
                  ? 'Missing'
                  : '${score!.round()}% · +${contribution!.toStringAsFixed(1)}',
            ),
          ],
        ),
        const SizedBox(height: 5),
        LinearProgressIndicator(value: (score ?? 0) / 100),
      ],
    );
  }
}

class _RingView extends StatelessWidget {
  const _RingView({required this.result});

  final MealBalanceResult result;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const Key('balanceRingView'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Semantics(
              label:
                  'Meal balance ${result.overallScore.round()} percent, ${result.confidence.label.toLowerCase()} confidence',
              child: SizedBox(
                width: 220,
                height: 220,
                child: CustomPaint(
                  painter: _BalanceRingPainter(
                    scores: result.componentScores,
                    background: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                  ),
                  child: Center(
                    child: Text(
                      '${result.overallScore.round()}%',
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (final component in MealBalanceComponent.values)
                  _LegendItem(
                    color: _componentColor(component),
                    label:
                        '${component.label}: ${result.componentScores[component]?.round() ?? 0}%',
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BalanceRingPainter extends CustomPainter {
  const _BalanceRingPainter({required this.scores, required this.background});

  final Map<MealBalanceComponent, double> scores;
  final Color background;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    const gap = 0.035;
    var start = -math.pi / 2;
    for (final component in MealBalanceComponent.values) {
      final sweep = math.pi * 2 * component.weight;
      final trackSweep = sweep - gap;
      final track = Paint()
        ..color = background
        ..style = PaintingStyle.stroke
        ..strokeWidth = 22;
      final fill = Paint()
        ..color = _componentColor(component)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 22;
      canvas.drawArc(rect.deflate(18), start, trackSweep, false, track);
      canvas.drawArc(
        rect.deflate(18),
        start,
        trackSweep * ((scores[component] ?? 0) / 100),
        false,
        fill,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _BalanceRingPainter oldDelegate) =>
      oldDelegate.scores != scores || oldDelegate.background != background;
}

class _PlateView extends StatelessWidget {
  const _PlateView({required this.input});

  final MealBalanceInput input;

  @override
  Widget build(BuildContext context) {
    final actual = input.hasCompletePlateSplit && (input.plateTotal ?? 0) > 0
        ? [
            input.producePlatePercent!,
            input.proteinPlatePercent!,
            input.qualityCarbPlatePercent!,
          ]
        : null;
    return Card(
      key: const Key('balancePlateView'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Wrap(
              spacing: 24,
              runSpacing: 20,
              alignment: WrapAlignment.center,
              children: [
                const _PlateChart(title: 'Target', values: [50, 25, 25]),
                if (actual != null)
                  _PlateChart(title: 'Your meal', values: actual),
              ],
            ),
            if (actual == null) ...[
              const SizedBox(height: 16),
              const Text(
                'Add all three plate percentages to compare your meal with the target.',
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 16),
            const Wrap(
              spacing: 12,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _LegendItem(color: Color(0xff43a047), label: 'Produce'),
                _LegendItem(color: Color(0xff1e88e5), label: 'Protein'),
                _LegendItem(color: Color(0xffffa000), label: 'Quality carbs'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PlateChart extends StatelessWidget {
  const _PlateChart({required this.title, required this.values});

  final String title;
  final List<double> values;

  @override
  Widget build(BuildContext context) {
    final total = values.fold<double>(0, (a, b) => a + b);
    final labels = values
        .map((value) => '${(value / total * 100).round()}%')
        .join(', ');
    return Semantics(
      label: '$title plate split: $labels',
      child: Column(
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SizedBox(
            width: 160,
            height: 160,
            child: CustomPaint(painter: _PlatePainter(values)),
          ),
        ],
      ),
    );
  }
}

class _PlatePainter extends CustomPainter {
  const _PlatePainter(this.values);

  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<double>(0, (a, b) => a + b);
    final colors = const [
      Color(0xff43a047),
      Color(0xff1e88e5),
      Color(0xffffa000),
    ];
    final rect = Offset.zero & size;
    var start = -math.pi / 2;
    for (var index = 0; index < values.length; index++) {
      final sweep = math.pi * 2 * values[index] / total;
      canvas.drawArc(
        rect.deflate(4),
        start,
        sweep,
        true,
        Paint()..color = colors[index],
      );
      start += sweep;
    }
    canvas.drawCircle(
      rect.center,
      size.shortestSide / 2 - 4,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(covariant _PlatePainter oldDelegate) =>
      oldDelegate.values != values;
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 12, height: 12, color: color),
        const SizedBox(width: 5),
        Text(label),
      ],
    );
  }
}

class _SavedMealTile extends StatelessWidget {
  const _SavedMealTile({
    required this.meal,
    required this.selected,
    required this.result,
    required this.onTap,
    required this.onEdit,
  });

  final MealEvent meal;
  final bool selected;
  final MealBalanceResult? result;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: selected ? Theme.of(context).colorScheme.secondaryContainer : null,
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          child: Text(
            result == null ? '--' : result!.overallScore.round().toString(),
          ),
        ),
        title: Text(meal.name),
        subtitle: Text(
          result == null
              ? 'Balance details not added'
              : '${result!.overallScore.round()}% · ${result!.confidence.label} confidence',
        ),
        trailing: IconButton(
          tooltip: result == null
              ? 'Add balance details'
              : 'Edit balance details',
          onPressed: onEdit,
          icon: const Icon(Icons.edit_outlined),
        ),
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(icon, size: 36),
            const SizedBox(height: 10),
            Text(message, textAlign: TextAlign.center),
            if (actionLabel != null) ...[
              const SizedBox(height: 12),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

Color _componentColor(MealBalanceComponent component) => switch (component) {
  MealBalanceComponent.protein => const Color(0xff1e88e5),
  MealBalanceComponent.fiber => const Color(0xff7b1fa2),
  MealBalanceComponent.produce => const Color(0xff43a047),
  MealBalanceComponent.hydration => const Color(0xff00acc1),
  MealBalanceComponent.portionBalance => const Color(0xffffa000),
};
