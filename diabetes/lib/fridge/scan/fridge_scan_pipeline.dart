import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

import '../../ai/ai_retry.dart';
import 'fridge_scan_service.dart';
import 'photo_prep.dart';
import 'scan_merge.dart';
import 'scan_models.dart';
import 'tile_planner.dart';

/// How [FridgeScanPipeline] splits a photo across model calls.
enum ScanPlan {
  /// One call on the overview.
  overviewOnly,

  /// Overlapping native-resolution tiles in parallel; no overview call.
  grid,

  /// The grid tiles and the overview, all in parallel; the overview is the
  /// merge base.
  gridPlusOverview,

  /// Overview first, then tiles around where it found food.
  zones,

  /// Overview first, then one call with close-ups of what it was unsure of.
  zoom,

  /// Grid, then one call with close-ups of what the merged grid was unsure of.
  gridPlusZoom,
}

/// Prompt note for a tile of a larger photo.
const tileContextNote =
    'This image is one part of a larger fridge photo; list only what is in '
    'this part, including items cut off at its edges.';

/// Prompt note for the single multi-image zoom call.
const zoomContextNote =
    'These are close-ups of parts of one fridge photo; image i has photoIndex '
    'i (the first image is photoIndex 0). List only what is in the close-ups, '
    'including items cut off at their edges. Give each item the photoIndex of '
    'the image it is in, and a box on the 0 to 1000 grid of that image.';

/// What a multi-call scan found. Item boxes are on the 0–1000 grid of the
/// photo (the straightened one when a zones/zoom plan levelled it).
class PipelineResult {
  const PipelineResult({
    required this.items,
    required this.zones,
    required this.tiltDegrees,
    required this.droppedNonFood,
    required this.usage,
    required this.calls,
    required this.callTimings,
    required this.droppedTiles,
    required this.perCallItems,
    required this.callIds,
  });

  final List<ScannedItem> items;
  final List<ScanZone> zones;

  /// From the overview call, or 0 when the plan has none.
  final double tiltDegrees;
  final int droppedNonFood;

  /// Summed over every call that returned.
  final FridgeScanUsage usage;

  /// Calls started (cancelled and failed ones included).
  final int calls;

  /// How long each started call ran, in the order they finished.
  final List<Duration> callTimings;

  /// Ids of tiles/crops that missed the deadline, failed or were never sent.
  final List<String> droppedTiles;

  /// The lists the final merge started from, boxes in photo space and before
  /// merging, in call order (the overview first when it is the merge base).
  /// A zoom stage is not included. Feeding them to [mergeScans] (first as
  /// base, the rest as extra) redoes the merge offline.
  final List<List<ScannedItem>> perCallItems;

  /// Call ids ("overview" or tile ids) matching [perCallItems].
  final List<String> callIds;
}

/// How far a streamed scan has got, across all of its calls.
class ScanProgress {
  const ScanProgress({
    required this.itemsSoFar,
    required this.latestNames,
    required this.callsDone,
    required this.callsTotal,
  });

  /// Items streamed so far, summed over every call and before merging, so a
  /// food seen in two overlapping tiles counts twice.
  final int itemsSoFar;

  /// The names of the last (up to three) items streamed, oldest first.
  final List<String> latestNames;

  /// Calls that have finished (returned, failed or been dropped).
  final int callsDone;

  /// Calls the scan has planned so far; it can grow as later stages start.
  final int callsTotal;
}

typedef _Stage = ({
  List<ScannedItem> items,
  List<ScanZone> zones,
  List<String> ids,
  List<List<ScannedItem>> lists,
});

/// Scan v2 split over several model calls. Makes no retries of its own.
class FridgeScanPipeline {
  /// [deadline] (from the start of the scan) drops tiles and crops that are
  /// not done in time; the overview call is never dropped. The scan throws
  /// the first error only when every call failed. [abortTrigger] cancels all
  /// in-flight calls. At most [maxParallel] tile calls run at once.
  ///
  /// With [onProgress] the calls stream their replies and report each item as
  /// it completes; without it they use the plain request.
  static Future<PipelineResult> scan(
    PreparedPhoto photo, {
    required ScanPlan plan,
    ScanStyle style = ScanStyle.lean,
    String thinkingLevel = 'low',
    Duration? deadline,
    http.Client? client,
    String? apiKey,
    Future<void>? abortTrigger,
    int maxParallel = 4,
    void Function(ScanProgress progress)? onProgress,
  }) async {
    final run = _Run(
      onProgress: onProgress,
      style: style,
      thinkingLevel: thinkingLevel,
      deadline: deadline,
      client: client,
      apiKey: apiKey,
      abortTrigger: abortTrigger,
      maxParallel: math.max(1, maxParallel),
    );
    switch (plan) {
      case ScanPlan.overviewOnly:
        return _overviewOnly(run, photo);
      case ScanPlan.grid:
        final grid = await _grid(run, photo);
        if (grid == null) return _overviewOnly(run, photo);
        return run.result(grid.items, grid.zones, 0, grid.ids, grid.lists);
      case ScanPlan.gridPlusOverview:
        return _gridPlusOverview(run, photo);
      case ScanPlan.zones:
        return _zones(run, photo);
      case ScanPlan.zoom:
        return _zoom(run, photo);
      case ScanPlan.gridPlusZoom:
        return _gridPlusZoom(run, photo);
    }
  }

  /// Scans several photos of the same fridge. Each photo runs its own plan
  /// (a grid, or one overview call when it is too small to tile), all calls in
  /// parallel and at most [maxParallel] at once. Items get the photoIndex of
  /// the photo they were seen in. Within a photo the box-based merge applies;
  /// across photos items merge by normalized name and zone only, because boxes
  /// don't line up between photos (see [mergePhotos]). The progress covers
  /// every call of every photo.
  static Future<PipelineResult> scanPhotos(
    List<PreparedPhoto> photos, {
    ScanStyle style = ScanStyle.lean,
    String thinkingLevel = 'low',
    Duration? deadline,
    http.Client? client,
    String? apiKey,
    Future<void>? abortTrigger,
    int maxParallel = 4,
    void Function(ScanProgress progress)? onProgress,
  }) async {
    final run = _Run(
      onProgress: onProgress,
      style: style,
      thinkingLevel: thinkingLevel,
      deadline: deadline,
      client: client,
      apiKey: apiKey,
      abortTrigger: abortTrigger,
      maxParallel: math.max(1, maxParallel),
    );
    final rectsOf = [
      for (final photo in photos)
        planGridTiles(
          photo.original.width,
          photo.original.height,
          overviewMaxSide: overviewMaxSide,
        ),
    ];

    // One job per call, across all photos, so the limit is shared.
    final jobs = <Future<ScanResponse?> Function()>[];
    final jobPhoto = <int>[];
    final jobRect = <TileRect?>[];
    for (var p = 0; p < photos.length; p++) {
      final photo = photos[p];
      final rects = rectsOf[p];
      if (rects.isEmpty) {
        jobs.add(
          () => run.call('p$p:overview', () => [photo.overviewJpeg],
              droppable: false),
        );
        jobPhoto.add(p);
        jobRect.add(null);
        continue;
      }
      for (final rect in rects) {
        jobs.add(
          () => run.call(
            'p$p:${rect.id}',
            () => [encodeTile(cutTile(photo.original, rect))],
            note: tileContextNote,
          ),
        );
        jobPhoto.add(p);
        jobRect.add(rect);
      }
    }
    run.plan(jobs.length);

    final responses = List<ScanResponse?>.filled(jobs.length, null);
    var next = 0;
    Future<void> worker() async {
      while (next < jobs.length) {
        final i = next++;
        responses[i] = await jobs[i]();
      }
    }

    await Future.wait([
      for (var w = 0; w < math.min(run.maxParallel, jobs.length); w++) worker(),
    ]);

    final perPhoto = <List<ScannedItem>>[];
    final zoneCounts = <String, int>{};
    final callIds = <String>[];
    final perCall = <List<ScannedItem>>[];
    for (var p = 0; p < photos.length; p++) {
      final source = photos[p].original;
      final lists = <List<ScannedItem>>[];
      for (var j = 0; j < jobs.length; j++) {
        final response = responses[j];
        if (jobPhoto[j] != p || response == null) continue;
        final rect = jobRect[j];
        final items = [
          for (final item in response.items)
            _withPhotoIndex(
              rect == null
                  ? item
                  : _toPhotoSpace(item, rect, source.width, source.height),
              p,
            ),
        ];
        lists.add(items);
        perCall.add(items);
        callIds.add(
          rect == null ? 'p$p:overview' : 'p$p:${rect.id}',
        );
        for (final zone in response.zones) {
          zoneCounts[zone.name] = math.max(
            zoneCounts[zone.name] ?? 0,
            zone.count,
          );
        }
      }
      perPhoto.add(mergeScans(const [], lists));
    }
    return run.result(
      mergePhotos(perPhoto),
      [
        for (final e in zoneCounts.entries)
          ScanZone(name: e.key, count: e.value),
      ],
      0,
      callIds,
      perCall,
    );
  }

  static ScannedItem _withPhotoIndex(ScannedItem item, int index) {
    return ScannedItem(
      name: item.name,
      foodType: item.foodType,
      confidence: item.confidence,
      alternatives: item.alternatives,
      location: item.location,
      box2d: item.box2d,
      photoIndex: index,
      isFood: item.isFood,
      amount: item.amount,
      description: item.description,
      expiryEstimateDays: item.expiryEstimateDays,
    );
  }

  static Future<PipelineResult> _overviewOnly(
    _Run run,
    PreparedPhoto photo,
  ) async {
    final overview = await run.overview(photo);
    if (overview == null) run.rethrowFirst();
    return run.result(
      overview.items,
      overview.zones,
      overview.tiltDegrees,
      const ['overview'],
      [overview.items],
    );
  }

  static Future<_Stage?> _grid(_Run run, PreparedPhoto photo) async {
    final rects = planGridTiles(
      photo.original.width,
      photo.original.height,
      overviewMaxSide: overviewMaxSide,
    );
    if (rects.isEmpty) return null;
    final outcomes = await run.tiles(rects, photo.original);
    return _mergeTiles(null, const [], outcomes, photo.original);
  }

  static Future<PipelineResult> _gridPlusOverview(
    _Run run,
    PreparedPhoto photo,
  ) async {
    final rects = planGridTiles(
      photo.original.width,
      photo.original.height,
      overviewMaxSide: overviewMaxSide,
    );
    if (rects.isEmpty) return _overviewOnly(run, photo);
    final overviewFuture = run.overview(photo);
    final outcomes = await run.tiles(rects, photo.original);
    final overview = await overviewFuture;
    final merged = _mergeTiles(
      overview?.items,
      overview?.zones ?? const [],
      outcomes,
      photo.original,
    );
    return run.result(
      merged.items,
      merged.zones,
      overview?.tiltDegrees ?? 0,
      merged.ids,
      merged.lists,
    );
  }

  static Future<PipelineResult> _zones(_Run run, PreparedPhoto photo) async {
    final overview = await run.overview(photo);
    if (overview == null) run.rethrowFirst();
    final straightened = straightenIfTilted(
      photo,
      overview.tiltDegrees,
      items: overview.items,
    );
    final working = straightened.photo.original;
    final rects = planZoneTiles(
      working.width,
      working.height,
      straightened.items,
      overviewMaxSide: overviewMaxSide,
    );
    if (rects.isEmpty) {
      return run.result(
        straightened.items,
        overview.zones,
        overview.tiltDegrees,
        const ['overview'],
        [straightened.items],
      );
    }
    final outcomes = await run.tiles(rects, working);
    final merged = _mergeTiles(
      straightened.items,
      overview.zones,
      outcomes,
      working,
    );
    return run.result(
      merged.items,
      merged.zones,
      overview.tiltDegrees,
      merged.ids,
      merged.lists,
    );
  }

  static Future<PipelineResult> _zoom(_Run run, PreparedPhoto photo) async {
    final overview = await run.overview(photo);
    if (overview == null) run.rethrowFirst();
    final straightened = straightenIfTilted(
      photo,
      overview.tiltDegrees,
      items: overview.items,
    );
    final items = await _zoomStage(
      run,
      straightened.photo.original,
      straightened.items,
      overview.zones,
    );
    return run.result(
      items,
      overview.zones,
      overview.tiltDegrees,
      const ['overview'],
      [straightened.items],
    );
  }

  static Future<PipelineResult> _gridPlusZoom(
    _Run run,
    PreparedPhoto photo,
  ) async {
    final grid = await _grid(run, photo);
    if (grid == null) return _overviewOnly(run, photo);
    // Tile-local zone counts don't describe the merged items, so only the
    // guesses decide what to zoom on.
    final items = await _zoomStage(run, photo.original, grid.items, const []);
    return run.result(items, grid.zones, 0, grid.ids, grid.lists);
  }

  /// Plans close-ups on [source], scans them in ONE multi-image call and folds
  /// the result into [base]. Returns [base] when there is nothing to zoom on
  /// or the call is dropped or fails.
  static Future<List<ScannedItem>> _zoomStage(
    _Run run,
    img.Image source,
    List<ScannedItem> base,
    List<ScanZone> zones,
  ) async {
    final crops = planZoomCrops(source.width, source.height, base, zones);
    if (crops.isEmpty) return base;
    run.plan(1);
    final response = await run.call(
      'zoom',
      () => [for (final crop in crops) encodeTile(cutTile(source, crop))],
      note: zoomContextNote,
      droppable: true,
    );
    if (response == null) return base;
    final zoomed = <ScannedItem>[];
    for (final item in response.items) {
      if (item.photoIndex < 0 || item.photoIndex >= crops.length) continue;
      zoomed.add(
        _toPhotoSpace(item, crops[item.photoIndex], source.width, source.height),
      );
    }
    return applyZoom(base, zoomed);
  }

  /// [base] is the overview's items, or null when the plan has no overview
  /// (or it failed).
  static _Stage _mergeTiles(
    List<ScannedItem>? base,
    List<ScanZone> baseZones,
    List<({TileRect rect, ScanResponse response})> outcomes,
    img.Image source,
  ) {
    final tileLists = [
      for (final o in outcomes)
        [
          for (final item in o.response.items)
            _toPhotoSpace(item, o.rect, source.width, source.height),
        ],
    ];
    final items = mergeScans(base ?? const [], tileLists);
    final ids = [
      if (base != null) 'overview',
      for (final o in outcomes) o.rect.id,
    ];
    final lists = [?base, ...tileLists];
    if (baseZones.isNotEmpty) {
      return (items: items, zones: baseZones, ids: ids, lists: lists);
    }
    // No overview: the tiles' zones, by name, keeping the largest count.
    final counts = <String, int>{};
    for (final o in outcomes) {
      for (final zone in o.response.zones) {
        counts[zone.name] = math.max(counts[zone.name] ?? 0, zone.count);
      }
    }
    return (
      items: items,
      zones: [
        for (final e in counts.entries) ScanZone(name: e.key, count: e.value),
      ],
      ids: ids,
      lists: lists,
    );
  }

  /// [item] with its box moved from [rect]'s grid to the whole photo's, and
  /// photoIndex reset to 0 (the photo itself).
  static ScannedItem _toPhotoSpace(
    ScannedItem item,
    TileRect rect,
    int w,
    int h,
  ) {
    final box = item.box2d;
    return ScannedItem(
      name: item.name,
      foodType: item.foodType,
      confidence: item.confidence,
      alternatives: item.alternatives,
      location: item.location,
      box2d: box == null || box.length != 4
          ? null
          : tileBoxToPhoto(box, rect, w, h),
      photoIndex: 0,
      isFood: item.isFood,
      amount: item.amount,
      description: item.description,
      expiryEstimateDays: item.expiryEstimateDays,
    );
  }
}

/// State shared by the calls of one scan.
class _Run {
  _Run({
    required this.style,
    required this.thinkingLevel,
    required this.deadline,
    required this.client,
    required this.apiKey,
    required this.maxParallel,
    this.onProgress,
    Future<void>? abortTrigger,
  }) {
    if (abortTrigger != null) {
      unawaited(
        abortTrigger.then<void>(
          (_) {
            _aborted = true;
            for (final cancel in _cancels.toList()) {
              if (!cancel.isCompleted) cancel.complete();
            }
          },
          onError: (Object _) {},
        ),
      );
    }
  }

  final ScanStyle style;
  final String thinkingLevel;
  final Duration? deadline;
  final http.Client? client;
  final String? apiKey;
  final int maxParallel;
  final void Function(ScanProgress progress)? onProgress;

  var _itemsSoFar = 0;
  var _callsDone = 0;
  var _callsTotal = 0;
  final _latestNames = <String>[];

  void _report() {
    onProgress?.call(
      ScanProgress(
        itemsSoFar: _itemsSoFar,
        latestNames: List.unmodifiable(_latestNames),
        callsDone: _callsDone,
        callsTotal: _callsTotal,
      ),
    );
  }

  void _onItem(ScannedItem item) {
    _itemsSoFar++;
    _latestNames.add(item.name);
    if (_latestNames.length > 3) _latestNames.removeAt(0);
    _report();
  }

  /// Announces [count] more planned calls.
  void plan(int count) {
    _callsTotal += count;
    _report();
  }

  final _clock = Stopwatch()..start();
  final _cancels = <Completer<void>>[];
  final _responses = <ScanResponse>[];
  final _timings = <Duration>[];
  final _dropped = <String>[];
  var _calls = 0;
  var _aborted = false;
  (Object, StackTrace)? _firstError;

  /// The overview call. Never dropped by the deadline.
  Future<ScanResponse?> overview(PreparedPhoto photo) {
    plan(1);
    return call('overview', () => [photo.overviewJpeg], droppable: false);
  }

  /// One model call. [images] runs lazily, inside the guarded section, so
  /// cutting and encoding is skipped for a dropped call and a failure there
  /// counts as a failed call. The first image is the main one, the rest are
  /// sent as extra images. Returns null when the call was dropped or failed.
  Future<ScanResponse?> call(
    String id,
    List<Uint8List> Function() images, {
    String? note,
    bool droppable = true,
  }) async {
    try {
      return await _call(id, images, note: note, droppable: droppable);
    } finally {
      _callsDone++;
      _report();
    }
  }

  Future<ScanResponse?> _call(
    String id,
    List<Uint8List> Function() images, {
    String? note,
    bool droppable = true,
  }) async {
    // Time left for a droppable call; null means no limit. Checked before and
    // after the images are cut, because encoding takes real time.
    Duration? remainingTime() {
      final limit = deadline;
      return droppable && limit != null ? limit - _clock.elapsed : null;
    }

    bool outOfTime() {
      if (!droppable) return false;
      if (_aborted) return true;
      final left = remainingTime();
      return left != null && left <= Duration.zero;
    }

    if (outOfTime()) {
      _dropped.add(id);
      return null;
    }

    final cancel = Completer<void>();
    if (_aborted) cancel.complete();
    _cancels.add(cancel);
    final watch = Stopwatch()..start();
    var started = false;
    try {
      final jpegs = images();
      if (outOfTime()) {
        _dropped.add(id);
        return null;
      }
      final remaining = remainingTime();
      started = true;
      _calls++;
      final future = onProgress == null
          ? FridgeScanService.scanV2(
              jpegs.first,
              client: client,
              apiKey: apiKey,
              abortTrigger: cancel.future,
              thinkingLevel: thinkingLevel,
              style: style,
              contextNote: note,
              extraImages: jpegs.skip(1).toList(),
            )
          : FridgeScanService.scanV2Stream(
              jpegs.first,
              client: client,
              apiKey: apiKey,
              abortTrigger: cancel.future,
              thinkingLevel: thinkingLevel,
              style: style,
              contextNote: note,
              extraImages: jpegs.skip(1).toList(),
              onItem: _onItem,
            );
      final response = remaining == null
          ? await future
          : await future.timeout(remaining);
      _responses.add(response);
      return response;
    } on TimeoutException {
      if (!cancel.isCompleted) cancel.complete();
      _dropped.add(id);
      return null;
    } catch (error, stack) {
      _firstError ??= (error, stack);
      _dropped.add(id);
      return null;
    } finally {
      if (started) _timings.add(watch.elapsed);
      _cancels.remove(cancel);
    }
  }

  /// Scans [rects] cut from [source], at most [maxParallel] at a time. Only
  /// the tiles that returned are in the result, in [rects] order.
  Future<List<({TileRect rect, ScanResponse response})>> tiles(
    List<TileRect> rects,
    img.Image source,
  ) async {
    plan(rects.length);
    final responses = List<ScanResponse?>.filled(rects.length, null);
    var next = 0;
    Future<void> worker() async {
      while (next < rects.length) {
        final i = next++;
        responses[i] = await call(
          rects[i].id,
          () => [encodeTile(cutTile(source, rects[i]))],
          note: tileContextNote,
        );
      }
    }

    await Future.wait([
      for (var w = 0; w < math.min(maxParallel, rects.length); w++) worker(),
    ]);
    return [
      for (var i = 0; i < rects.length; i++)
        if (responses[i] != null) (rect: rects[i], response: responses[i]!),
    ];
  }

  Never rethrowFirst() {
    final error = _firstError;
    if (error != null) Error.throwWithStackTrace(error.$1, error.$2);
    throw const AiRequestException('Scan was cancelled', retryable: false);
  }

  /// The final result, or the first error when no call returned.
  PipelineResult result(
    List<ScannedItem> items,
    List<ScanZone> zones,
    double tiltDegrees,
    List<String> callIds,
    List<List<ScannedItem>> perCallItems,
  ) {
    if (_responses.isEmpty) rethrowFirst();
    var prompt = 0, candidates = 0, thoughts = 0, total = 0, nonFood = 0;
    for (final r in _responses) {
      prompt += r.usage.promptTokenCount;
      candidates += r.usage.candidatesTokenCount;
      thoughts += r.usage.thoughtsTokenCount;
      total += r.usage.totalTokenCount;
      nonFood += r.droppedNonFood;
    }
    return PipelineResult(
      items: items,
      zones: zones,
      tiltDegrees: tiltDegrees,
      droppedNonFood: nonFood,
      usage: FridgeScanUsage(
        promptTokenCount: prompt,
        candidatesTokenCount: candidates,
        thoughtsTokenCount: thoughts,
        totalTokenCount: total,
      ),
      calls: _calls,
      callTimings: List.unmodifiable(_timings),
      droppedTiles: List.unmodifiable(_dropped),
      perCallItems: List.unmodifiable(perCallItems),
      callIds: List.unmodifiable(callIds),
    );
  }
}
