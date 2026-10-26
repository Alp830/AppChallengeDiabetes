// FoodItem and FoodType still live in main.dart; the import is circular,
// which Dart allows.
import '../../main.dart';

/// How sure the model is about one scanned item. v1 only returned the items it
/// was sure of; v2 lists everything and says how much to trust each entry.
enum ScanConfidence {
  /// Label read, or unmistakable.
  sure('sure'),

  /// Probably right, but could be a lookalike.
  likely('likely'),

  /// Best guess; the alternatives may be the right answer.
  guess('guess');

  const ScanConfidence(this.label);

  final String label;

  /// Unknown or missing labels read as [likely]: neither trusted blindly nor
  /// treated as a guess the user must review.
  static ScanConfidence fromLabel(Object? label) {
    final normalized = (label ?? '').toString().toLowerCase().trim();
    return ScanConfidence.values.firstWhere(
      (confidence) => confidence.label == normalized,
      orElse: () => ScanConfidence.likely,
    );
  }
}

/// One food or drink the v2 scan saw.
class ScannedItem {
  const ScannedItem({
    required this.name,
    required this.foodType,
    this.confidence = ScanConfidence.likely,
    this.alternatives = const [],
    this.location = '',
    this.box2d,
    this.photoIndex = 0,
    this.isFood = true,
    this.amount = '',
    this.description,
    this.expiryEstimateDays,
  });

  final String name;
  final FoodType foodType;
  final ScanConfidence confidence;

  /// Up to two other names this item could be, best first.
  final List<String> alternatives;

  /// The zone it sits in, as named in [ScanResponse.zones].
  final String location;

  /// `[ymin, xmin, ymax, xmax]` on a 0–1000 grid over the photo, or null when
  /// the model gave no usable box.
  final List<int>? box2d;

  /// Which uploaded photo the item is in (0 for a single-photo scan).
  final int photoIndex;

  /// False for medicine, supplements, skincare, household items and plants.
  /// The parser drops those, so items it returns are always food.
  final bool isFood;

  /// Empty when the model gave none; [toFoodItem] then uses `"1 <name>"`.
  final String amount;
  final String? description;
  final int? expiryEstimateDays;

  ScannedItem copyWith({List<int>? box2d}) {
    return ScannedItem(
      name: name,
      foodType: foodType,
      confidence: confidence,
      alternatives: alternatives,
      location: location,
      box2d: box2d ?? this.box2d,
      photoIndex: photoIndex,
      isFood: isFood,
      amount: amount,
      description: description,
      expiryEstimateDays: expiryEstimateDays,
    );
  }

  /// The fridge-grid item. Confidence is ignored until the review step reads it.
  FoodItem toFoodItem() {
    final days = expiryEstimateDays;
    return FoodItem(
      name: name,
      amount: amount.isEmpty ? '1 $name' : amount,
      foodType: foodType,
      description: description,
      expiryDate: days == null || days < 0
          ? null
          : DateTime.now().add(Duration(days: days)),
    );
  }
}

/// A region of the fridge (a shelf, drawer or door bin) and how many items the
/// model counted there. The model states the count before listing the items.
class ScanZone {
  const ScanZone({required this.name, required this.count});

  final String name;
  final int count;
}

/// Everything one v2 scan call returned.
class ScanResponse {
  const ScanResponse({
    required this.zones,
    required this.items,
    required this.tiltDegrees,
    required this.droppedNonFood,
    required this.usage,
  });

  final List<ScanZone> zones;
  final List<ScannedItem> items;

  /// Clockwise rotation, in degrees, the photo needs to be level.
  final double tiltDegrees;

  /// How many `isFood: false` entries the parser removed.
  final int droppedNonFood;
  final FridgeScanUsage usage;
}

/// Structured-output schema for the v2 scan. Zones come first so the model
/// counts a zone before it lists the items in it.
Map<String, dynamic> scanResponseSchema() => {
  'type': 'OBJECT',
  'properties': {
    'zones': {
      'type': 'ARRAY',
      'items': {
        'type': 'OBJECT',
        'properties': {
          'name': {'type': 'STRING'},
          'count': {'type': 'INTEGER'},
        },
        'required': ['name', 'count'],
        'propertyOrdering': ['name', 'count'],
      },
    },
    'items': {
      'type': 'ARRAY',
      'items': {
        'type': 'OBJECT',
        'properties': {
          'name': {'type': 'STRING'},
          'amount': {'type': 'STRING'},
          'foodType': {
            'type': 'STRING',
            'enum': [for (final foodType in FoodType.values) foodType.label],
          },
          'confidence': {
            'type': 'STRING',
            'enum': [
              for (final confidence in ScanConfidence.values) confidence.label,
            ],
          },
          'alternatives': {
            'type': 'ARRAY',
            'items': {'type': 'STRING'},
          },
          'location': {'type': 'STRING'},
          'box_2d': {
            'type': 'ARRAY',
            'items': {'type': 'INTEGER'},
          },
          'photoIndex': {'type': 'INTEGER'},
          'isFood': {'type': 'BOOLEAN'},
          'description': {'type': 'STRING'},
          'expiryEstimateDays': {'type': 'INTEGER', 'nullable': true},
        },
        'required': [
          'name',
          'foodType',
          'confidence',
          'alternatives',
          'location',
          'box_2d',
          'photoIndex',
          'isFood',
        ],
        'propertyOrdering': [
          'name',
          'amount',
          'foodType',
          'confidence',
          'alternatives',
          'location',
          'box_2d',
          'photoIndex',
          'isFood',
          'description',
          'expiryEstimateDays',
        ],
      },
    },
    'tiltDegrees': {'type': 'NUMBER'},
  },
  'required': ['zones', 'items', 'tiltDegrees'],
  'propertyOrdering': ['zones', 'items', 'tiltDegrees'],
};

/// Which request shape [FridgeScanService] uses. [full] is the original
/// camelCase item with amount, description and photoIndex; [lean] drops those
/// and shortens the keys so Gemini writes fewer output tokens per item.
enum ScanStyle { full, lean }

/// Structured-output schema for [ScanStyle.lean]. Same layout as
/// [scanResponseSchema] with short keys and no amount, description or
/// photoIndex.
Map<String, dynamic> leanScanResponseSchema() => {
  'type': 'OBJECT',
  'properties': {
    'zones': {
      'type': 'ARRAY',
      'items': {
        'type': 'OBJECT',
        'properties': {
          'name': {'type': 'STRING'},
          'count': {'type': 'INTEGER'},
        },
        'required': ['name', 'count'],
        'propertyOrdering': ['name', 'count'],
      },
    },
    'items': {
      'type': 'ARRAY',
      'items': {
        'type': 'OBJECT',
        'properties': {
          'name': {'type': 'STRING'},
          'type': {
            'type': 'STRING',
            'enum': [for (final foodType in FoodType.values) foodType.label],
          },
          'conf': {
            'type': 'STRING',
            'enum': [
              for (final confidence in ScanConfidence.values) confidence.label,
            ],
          },
          'alts': {
            'type': 'ARRAY',
            'items': {'type': 'STRING'},
          },
          'zone': {'type': 'STRING'},
          'box': {
            'type': 'ARRAY',
            'items': {'type': 'INTEGER'},
          },
          'food': {'type': 'BOOLEAN'},
          'days': {'type': 'INTEGER', 'nullable': true},
        },
        'required': ['name', 'type', 'conf', 'alts', 'zone', 'box', 'food'],
        'propertyOrdering': [
          'name',
          'type',
          'conf',
          'alts',
          'zone',
          'box',
          'food',
          'days',
        ],
      },
    },
    'tilt': {'type': 'NUMBER'},
  },
  'required': ['zones', 'items', 'tilt'],
  'propertyOrdering': ['zones', 'items', 'tilt'],
};
