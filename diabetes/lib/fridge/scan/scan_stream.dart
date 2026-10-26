import 'dart:convert';

/// Finds the finished item objects in a scan reply that is still arriving.
///
/// Feed it the text slices of a streamed Gemini reply with [add]. It walks the
/// JSON once, tracking nesting depth and string/escape state, so braces and
/// quotes inside strings are never mistaken for structure. Each time an object
/// directly inside the top-level `"items"` array closes, [add] returns it
/// decoded. A bare top-level array is read as the items array too, and text
/// outside the JSON (a Markdown fence) is ignored.
///
/// It only finds items early. The authoritative result is still the parse of
/// the complete text, so an object this scanner cannot decode is skipped.
class ScanItemScanner {
  String _text = '';
  var _pos = 0;
  var _depth = 0;
  var _started = false;
  var _done = false;
  var _inString = false;
  var _escaped = false;
  var _stringStart = 0;

  /// The last string seen directly inside the root object (a key or a value),
  /// and the last non-space character before the current one. Together they
  /// recognise `"items": [`.
  String? _lastRootString;
  var _prev = '';

  /// Depth just inside the items array, or -1 outside it.
  var _itemsDepth = -1;
  var _itemStart = -1;

  /// Items completed so far, including ones that failed to decode.
  var itemCount = 0;

  /// Appends [slice] and returns the item objects it completed, in order.
  List<Map<String, dynamic>> add(String slice) {
    _text += slice;
    final found = <Map<String, dynamic>>[];
    for (; _pos < _text.length; _pos++) {
      final c = _text[_pos];
      if (_done) continue;

      if (_inString) {
        if (_escaped) {
          _escaped = false;
        } else if (c == r'\') {
          _escaped = true;
        } else if (c == '"') {
          _inString = false;
          if (_depth == 1) {
            _lastRootString = _text.substring(_stringStart + 1, _pos);
          }
          _prev = '"';
        }
        continue;
      }

      switch (c) {
        case '"':
          if (!_started) break;
          _inString = true;
          _stringStart = _pos;
        case '{' || '[':
          if (_depth == 0) {
            if (_started) break;
            _started = true;
            if (c == '[') _itemsDepth = 1;
          } else if (c == '[' &&
              _depth == 1 &&
              _lastRootString == 'items' &&
              _prev == ':') {
            _itemsDepth = 2;
          } else if (c == '{' && _depth == _itemsDepth) {
            _itemStart = _pos;
          }
          if (_started) _depth++;
          _prev = c;
        case '}' || ']':
          if (!_started) break;
          _depth--;
          if (c == '}' && _itemStart >= 0 && _depth == _itemsDepth) {
            final item = _decode(_text.substring(_itemStart, _pos + 1));
            _itemStart = -1;
            itemCount++;
            if (item != null) found.add(item);
          } else if (c == ']' && _depth == _itemsDepth - 1) {
            _itemsDepth = -1;
          }
          if (_depth == 0) _done = true;
          _prev = c;
        case ' ' || '\n' || '\r' || '\t':
          break;
        default:
          if (_started) _prev = c;
      }
    }
    return found;
  }

  static Map<String, dynamic>? _decode(String source) {
    try {
      final decoded = jsonDecode(source);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }
}
