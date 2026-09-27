import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../design/app_radius.dart';
import '../design/spacing.dart';
import '../main.dart' show FoodItem;

/// Outcome of a fridge photo scan. The dialog returns null when cancelled.
class FridgeScanResult {
  const FridgeScanResult.success(this.foods) : error = null;
  const FridgeScanResult.failure(Object this.error) : foods = const [];

  final List<FoodItem> foods;
  final Object? error;
}

/// Blocks the fridge while the AI scan runs (5–15 s), so the user sees
/// progress, can cancel, and can't edit a grid that's about to change.
class FridgeScanDialog extends StatefulWidget {
  const FridgeScanDialog({
    super.key,
    required this.imageBytes,
    required this.detect,
  });

  final Uint8List imageBytes;
  final Future<List<FoodItem>> Function(Uint8List imageBytes) detect;

  @override
  State<FridgeScanDialog> createState() => _FridgeScanDialogState();
}

class _FridgeScanDialogState extends State<FridgeScanDialog> {
  bool _cancelled = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    FridgeScanResult result;
    try {
      result = FridgeScanResult.success(await widget.detect(widget.imageBytes));
    } catch (error) {
      result = FridgeScanResult.failure(error);
    }
    if (!mounted || _cancelled) return;
    Navigator.of(context).pop(result);
  }

  void _cancel() {
    _cancelled = true;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('Finding foods…'),
        content: SizedBox(
          width: 280,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: Opacity(
                  opacity: 0.6,
                  child: Image.memory(
                    widget.imageBytes,
                    height: 160,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        const SizedBox(height: 160),
                  ),
                ),
              ),
              const SizedBox(height: Spacing.s16),
              const LinearProgressIndicator(),
              const SizedBox(height: Spacing.s12),
              Text(
                'This usually takes 5–15 seconds.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            key: const Key('fridgeScanCancel'),
            onPressed: _cancel,
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}
