import 'package:cloud_firestore/cloud_firestore.dart';

import 'meal_balance_models.dart';

enum MealPortion { smaller, usual, larger }

enum MealOrder {
  together,
  vegetablesFirst,
  proteinFirst,
  carbohydratesFirst,
  custom,
}

enum MealPreparation { fresh, leftover, reheated }

enum CarbBand { unknown, low, medium, high }

class MealEvent {
  const MealEvent({
    required this.id,
    required this.name,
    required this.timestamp,
    required this.mealType,
    required this.portion,
    required this.carbBand,
    required this.mealOrder,
    required this.preparation,
    this.restaurant,
    this.carbohydrateGrams,
    this.hasProtein = false,
    this.hasFat = false,
    this.hasFiber = false,
    this.components = const [],
    this.nearbyMovement,
    this.notes,
    this.photoUrl,
    this.groupId,
    this.groupConfidence,
    this.groupConfirmed = false,
    this.balanceInput,
  });

  final String id;
  final String name;
  final DateTime timestamp;
  final String mealType;
  final MealPortion portion;
  final CarbBand carbBand;
  final MealOrder mealOrder;
  final MealPreparation preparation;
  final String? restaurant;
  final double? carbohydrateGrams;
  final bool hasProtein;
  final bool hasFat;
  final bool hasFiber;
  final List<String> components;
  final String? nearbyMovement;
  final String? notes;
  final String? photoUrl;
  final String? groupId;
  final double? groupConfidence;
  final bool groupConfirmed;
  final MealBalanceInput? balanceInput;

  MealEvent copyWith({
    String? id,
    String? groupId,
    double? groupConfidence,
    bool? groupConfirmed,
    MealBalanceInput? balanceInput,
  }) => MealEvent(
    id: id ?? this.id,
    name: name,
    timestamp: timestamp,
    mealType: mealType,
    portion: portion,
    carbBand: carbBand,
    mealOrder: mealOrder,
    preparation: preparation,
    restaurant: restaurant,
    carbohydrateGrams: carbohydrateGrams,
    hasProtein: hasProtein,
    hasFat: hasFat,
    hasFiber: hasFiber,
    components: components,
    nearbyMovement: nearbyMovement,
    notes: notes,
    photoUrl: photoUrl,
    groupId: groupId ?? this.groupId,
    groupConfidence: groupConfidence ?? this.groupConfidence,
    groupConfirmed: groupConfirmed ?? this.groupConfirmed,
    balanceInput: balanceInput ?? this.balanceInput,
  );

  Map<String, dynamic> toFirestore() => {
    'schemaVersion': 2,
    'name': name,
    'timestamp': Timestamp.fromDate(timestamp),
    'mealType': mealType,
    'portion': portion.name,
    'carbBand': carbBand.name,
    'mealOrder': mealOrder.name,
    'preparation': preparation.name,
    if (restaurant != null) 'restaurant': restaurant,
    if (carbohydrateGrams != null) 'carbohydrateGrams': carbohydrateGrams,
    'hasProtein': hasProtein,
    'hasFat': hasFat,
    'hasFiber': hasFiber,
    'components': components,
    if (nearbyMovement != null) 'nearbyMovement': nearbyMovement,
    if (notes != null) 'notes': notes,
    if (photoUrl != null) 'photoUrl': photoUrl,
    if (groupId != null) 'groupId': groupId,
    if (groupConfidence != null) 'groupConfidence': groupConfidence,
    'groupConfirmed': groupConfirmed,
    if (balanceInput != null && !balanceInput!.isEmpty)
      'mealBalance': balanceInput!.toFirestore(),
    'updatedAt': FieldValue.serverTimestamp(),
  };

  factory MealEvent.fromFirestore(
    String id,
    Map<String, dynamic> data,
  ) => MealEvent(
    id: id,
    name: data['name'] as String? ?? 'Meal',
    timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
    mealType: data['mealType'] as String? ?? 'Meal',
    portion: _enumValue(MealPortion.values, data['portion'], MealPortion.usual),
    carbBand: _enumValue(CarbBand.values, data['carbBand'], CarbBand.unknown),
    mealOrder: _enumValue(
      MealOrder.values,
      data['mealOrder'],
      MealOrder.together,
    ),
    preparation: _enumValue(
      MealPreparation.values,
      data['preparation'],
      MealPreparation.fresh,
    ),
    restaurant: data['restaurant'] as String?,
    carbohydrateGrams: (data['carbohydrateGrams'] as num?)?.toDouble(),
    hasProtein: data['hasProtein'] as bool? ?? false,
    hasFat: data['hasFat'] as bool? ?? false,
    hasFiber: data['hasFiber'] as bool? ?? false,
    components: (data['components'] as List? ?? const [])
        .whereType<String>()
        .toList(),
    nearbyMovement: data['nearbyMovement'] as String?,
    notes: data['notes'] as String?,
    photoUrl: data['photoUrl'] as String?,
    groupId: data['groupId'] as String?,
    groupConfidence: (data['groupConfidence'] as num?)?.toDouble(),
    groupConfirmed: data['groupConfirmed'] as bool? ?? false,
    balanceInput: data['mealBalance'] is Map
        ? MealBalanceInput.fromFirestore(
            Map<String, dynamic>.from(data['mealBalance'] as Map),
          )
        : null,
  );
}

class MealGroup {
  const MealGroup({
    required this.id,
    required this.name,
    this.summary = '',
    this.correctionExamples = const [],
  });
  final String id;
  final String name;
  final String summary;
  final List<String> correctionExamples;

  factory MealGroup.fromFirestore(String id, Map<String, dynamic> data) =>
      MealGroup(
        id: id,
        name: data['name'] as String? ?? 'Meal group',
        summary: data['summary'] as String? ?? '',
        correctionExamples: (data['correctionExamples'] as List? ?? const [])
            .whereType<String>()
            .toList(),
      );
}

class MealTemplate {
  const MealTemplate({
    required this.id,
    required this.name,
    required this.mealType,
    required this.portion,
    required this.carbBand,
    required this.mealOrder,
    required this.preparation,
    this.restaurant,
    this.components = const [],
    this.hasProtein = false,
    this.hasFat = false,
    this.hasFiber = false,
    this.favorite = false,
    this.balanceInput,
  });
  final String id;
  final String name;
  final String mealType;
  final MealPortion portion;
  final CarbBand carbBand;
  final MealOrder mealOrder;
  final MealPreparation preparation;
  final String? restaurant;
  final List<String> components;
  final bool hasProtein;
  final bool hasFat;
  final bool hasFiber;
  final bool favorite;
  final MealBalanceInput? balanceInput;

  factory MealTemplate.fromFirestore(
    String id,
    Map<String, dynamic> data,
  ) => MealTemplate(
    id: id,
    name: data['name'] as String? ?? 'Meal',
    mealType: data['mealType'] as String? ?? 'Meal',
    portion: _enumValue(MealPortion.values, data['portion'], MealPortion.usual),
    carbBand: _enumValue(CarbBand.values, data['carbBand'], CarbBand.unknown),
    mealOrder: _enumValue(
      MealOrder.values,
      data['mealOrder'],
      MealOrder.together,
    ),
    preparation: _enumValue(
      MealPreparation.values,
      data['preparation'],
      MealPreparation.fresh,
    ),
    restaurant: data['restaurant'] as String?,
    components: (data['components'] as List? ?? const [])
        .whereType<String>()
        .toList(),
    hasProtein: data['hasProtein'] as bool? ?? false,
    hasFat: data['hasFat'] as bool? ?? false,
    hasFiber: data['hasFiber'] as bool? ?? false,
    favorite: data['favorite'] as bool? ?? false,
    balanceInput: data['mealBalance'] is Map
        ? MealBalanceInput.fromFirestore(
            Map<String, dynamic>.from(data['mealBalance'] as Map),
          )
        : null,
  );
}

T _enumValue<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  return fallback;
}
