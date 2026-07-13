import 'package:cloud_firestore/cloud_firestore.dart';

class TodayTodo {
  const TodayTodo({
    required this.id,
    required this.name,
    this.isCompleted = false,
  });

  final String id;
  final String name;
  final bool isCompleted;

  TodayTodo copyWith({String? name, bool? isCompleted}) {
    return TodayTodo(
      id: id,
      name: name ?? this.name,
      isCompleted: isCompleted ?? this.isCompleted,
    );
  }

  Map<String, dynamic> toFirestore() => {
    'id': id,
    'name': name,
    'isCompleted': isCompleted,
  };

  factory TodayTodo.fromFirestore(Map<String, dynamic> data) {
    return TodayTodo(
      id: data['id'] as String? ?? '',
      name: data['name'] as String? ?? 'Untitled task',
      isCompleted: data['isCompleted'] as bool? ?? false,
    );
  }
}

class TodayTodoState {
  const TodayTodoState({required this.isInitialized, required this.items});

  final bool isInitialized;
  final List<TodayTodo> items;
}

class TodayTodoRepository {
  TodayTodoRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _document(
    String userId,
    DateTime localDay,
  ) {
    final dayId =
        '${localDay.year.toString().padLeft(4, '0')}-'
        '${localDay.month.toString().padLeft(2, '0')}-'
        '${localDay.day.toString().padLeft(2, '0')}';
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('dailyTodos')
        .doc(dayId);
  }

  Stream<TodayTodoState> watchTodos(String userId, DateTime localDay) {
    return _document(userId, localDay).snapshots().map((snapshot) {
      final data = snapshot.data();
      final rawItems = data?['items'] as List? ?? const [];
      return TodayTodoState(
        isInitialized: snapshot.exists,
        items: rawItems
            .whereType<Map>()
            .map(
              (item) => TodayTodo.fromFirestore(
                Map<String, dynamic>.from(item),
              ),
            )
            .where((item) => item.id.isNotEmpty)
            .toList(),
      );
    });
  }

  Future<void> saveTodos(
    String userId,
    DateTime localDay,
    List<TodayTodo> items,
  ) {
    return _document(userId, localDay).set({
      'date': Timestamp.fromDate(
        DateTime(localDay.year, localDay.month, localDay.day),
      ),
      'items': items.map((item) => item.toFirestore()).toList(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
