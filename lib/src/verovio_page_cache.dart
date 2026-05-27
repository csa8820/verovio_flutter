import 'dart:collection';

class VerovioPageCache {
  VerovioPageCache({int capacity = 32}) : assert(capacity > 0) {
    if (capacity <= 0) {
      throw ArgumentError.value(capacity, 'capacity', 'must be greater than 0');
    }
    _capacity = capacity;
  }

  late final int _capacity;
  final LinkedHashMap<String, String> _entries = LinkedHashMap<String, String>();

  Future<String> getOrRender({
    required String data,
    required String optionsJson,
    required int pageNo,
    required Future<String> Function() render,
  }) async {
    final key = _cacheKey(data, optionsJson, pageNo);
    final cached = _entries.remove(key);
    if (cached != null) {
      _entries[key] = cached;
      return cached;
    }

    final svg = await render();
    _entries[key] = svg;
    while (_entries.length > _capacity) {
      _entries.remove(_entries.keys.first);
    }
    return svg;
  }

  void invalidateAll() {
    _entries.clear();
  }

  int get length => _entries.length;

  int _fnv1a64(String s) {
    var h = 0xcbf29ce484222325;
    for (final c in s.codeUnits) {
      h = (h ^ c) * 0x100000001b3;
      h &= 0xffffffffffffffff;
    }
    return h;
  }

  String _cacheKey(String data, String options, int page) =>
      '${_fnv1a64(data).toRadixString(16)}:'
      '${_fnv1a64(options).toRadixString(16)}:$page';
}
