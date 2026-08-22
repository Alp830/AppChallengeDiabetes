import 'package:diabetes/meals/models/meal_balance_models.dart';
import 'package:diabetes/main.dart';
import 'package:diabetes/meals/screens/meal_balance_input_form.dart';
import 'package:diabetes/meals/screens/meal_balance_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('calculator updates and switches between all visualizations', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MealBalancePage(
            userId: 'test-user',
            mealsStream: Stream.value(const []),
            onUpdateBalance: (_, _) async {},
          ),
        ),
      ),
    );
    await tester.tap(find.text('Calculator'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('balanceProteinField')), '25');
    await tester.enterText(find.byKey(const Key('balanceFiberField')), '8');
    await tester.enterText(find.byKey(const Key('balanceProduceField')), '1.5');
    await tester.enterText(
      find.byKey(const Key('balanceHydrationField')),
      '250',
    );
    await tester.pump();

    expect(find.byKey(const Key('balanceBreakdownView')), findsOneWidget);
    expect(find.text('100%'), findsWidgets);

    await tester.ensureVisible(find.text('Ring'));
    await tester.tap(find.text('Ring'));
    await tester.pump();
    expect(find.byKey(const Key('balanceRingView')), findsOneWidget);

    await tester.tap(find.text('Plate'));
    await tester.pump();
    expect(find.byKey(const Key('balancePlateView')), findsOneWidget);
    expect(
      find.text(
        'Add all three plate percentages to compare your meal with the target.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('two MVP navigation buttons fit a narrow phone', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (var index = 0; index < 2; index++)
                CirclePageButton(
                  icon: Icons.circle,
                  label: 'Tab $index',
                  isSelected: index == 0,
                  onTap: () {},
                  compact: true,
                ),
            ],
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(CirclePageButton), findsNWidgets(2));
  });

  testWidgets('plate percentages must be complete and total 100', (
    tester,
  ) async {
    final formKey = GlobalKey<FormState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: MealBalanceInputForm(onChanged: (_) {}),
            ),
          ),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('balanceProducePercentField')),
      '40',
    );
    await tester.enterText(
      find.byKey(const Key('balanceProteinPercentField')),
      '30',
    );
    await tester.enterText(
      find.byKey(const Key('balanceCarbPercentField')),
      '20',
    );
    expect(formKey.currentState!.validate(), isFalse);
    await tester.pump();
    expect(find.text('Plate percentages must total 100'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('balanceCarbPercentField')),
      '30',
    );
    expect(formKey.currentState!.validate(), isTrue);
  });

  test('empty balance input remains empty for legacy meals', () {
    expect(const MealBalanceInput().isEmpty, isTrue);
  });
}
