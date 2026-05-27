import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:verovio_flutter/verovio_flutter.dart';
import 'testdata_viewer.dart';

void main() {
  runApp(const AppLauncher());
}

class AppLauncher extends StatelessWidget {
  const AppLauncher({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Verovio Apps',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const AppSelectionPage(),
    );
  }
}

class AppSelectionPage extends StatelessWidget {
  const AppSelectionPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Application'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const VerovioSpikeApp(),
                  ),
                );
              },
              icon: const Icon(Icons.music_note),
              label: const Text('Verovio Demo'),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const TestdataViewerApp(),
                  ),
                );
              },
              icon: const Icon(Icons.preview),
              label: const Text('Testdata Viewer'),
            ),
          ],
        ),
      ),
    );
  }
}

class VerovioSpikeApp extends StatelessWidget {
  const VerovioSpikeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Verovio FFI Spike',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const VerovioSpikePage(),
    );
  }
}

class VerovioSpikePage extends StatefulWidget {
  const VerovioSpikePage({super.key});

  @override
  State<VerovioSpikePage> createState() => _VerovioSpikePageState();
}

class _VerovioSpikePageState extends State<VerovioSpikePage> {
  static const String _sampleAssetPath = 'assets/testdata/importer.mei';
  static const String _optionsJson = '''
{"adjustPageHeight":false,"breaks":"auto","pageHeight":420,"pageWidth":1200,"header":"none","footer":"none","scale":40,"spacingStaff":4}
''';

  VerovioService? _service;
  final VerovioPageCache _cache = VerovioPageCache();

  bool _loading = true;
  String? _resourcePath;
  String? _error;
  String _log = '';
  String _svg = '';
  String _svgHead = '';
  int _svgLength = 0;
  int _pageCount = 0;
  int _currentPage = 0;
  int _firstScreenMs = 0;
  int _lastFetchMs = 0;
  bool _lastFetchHit = false;
  String _lastFetchLabel = '';
  String _mei = '';
  int _renderToken = 0;
  bool _autoDemoStarted = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final stopwatch = Stopwatch()..start();
    VerovioService? service;
    try {
      final resourcePath =
          await VerovioResourceManager.ensureVerovioAssetsReady();
      final mei = await rootBundle.loadString(_sampleAssetPath);
      service = await VerovioService.spawn(resourcePath: resourcePath);
      service.setOptionsJson(_optionsJson);
      service.loadData(mei);
      final pageCount = service.pageCount;
      if (pageCount < 1) {
        throw StateError('pageCount < 1 after loadData');
      }

      _mei = mei;
      _resourcePath = resourcePath;
      _service = service;
      _pageCount = pageCount;
      _currentPage = 1;
      _log = service.getLog();

      final firstPage = await _loadPage(pageNo: 1, applyState: false);
      stopwatch.stop();

      if (!mounted) {
        await service.dispose();
        return;
      }

      setState(() {
        _svg = firstPage.svg;
        _svgHead = firstPage.svg.length <= 200
            ? firstPage.svg
            : firstPage.svg.substring(0, 200);
        _svgLength = firstPage.svg.length;
        _firstScreenMs = stopwatch.elapsedMilliseconds;
        _lastFetchMs = firstPage.elapsedMs;
        _lastFetchHit = firstPage.hit;
        _lastFetchLabel = firstPage.hit ? 'hit' : 'miss';
        _loading = false;
      });

      debugPrint('VEROVIO_RESOURCE_PATH=$resourcePath');
      debugPrint('VEROVIO_FIRST_SCREEN_MS=${stopwatch.elapsedMilliseconds}');
      debugPrint('VEROVIO_PAGE_COUNT=$pageCount');
      debugPrint('VEROVIO_SVG_LENGTH=${firstPage.svg.length}');
      debugPrint('VEROVIO_SVG_HEAD=${_svgHead.replaceAll('\n', r'\n')}');
      debugPrint('VEROVIO_FETCH=${firstPage.hit ? 'hit' : 'miss'} '
          '${firstPage.elapsedMs}ms');
      debugPrint('VEROVIO_LOG_START');
      if (_log.isEmpty) {
        debugPrint('(empty)');
      } else {
        for (final line in _log.split('\n').take(30)) {
          debugPrint(line);
        }
      }
      debugPrint('VEROVIO_LOG_END');
      _schedulePrefetch(pageNo: 1);
      _scheduleAutoDemo();
    } catch (error) {
      stopwatch.stop();
      final log = service == null ? '' : service.getLog();
      if (service != null) {
        try {
          await service.dispose();
        } catch (_) {}
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
        _log = log;
        _firstScreenMs = stopwatch.elapsedMilliseconds;
        _loading = false;
      });
    }
  }

  void _scheduleAutoDemo() {
    if (_autoDemoStarted || _pageCount < 3 || !mounted) {
      return;
    }
    _autoDemoStarted = true;
    scheduleMicrotask(() {
      unawaited(_runFivePageDemo());
    });
  }

  Future<void> _runFivePageDemo() async {
    if (_service == null || _pageCount < 3) {
      return;
    }
    final sequence = <int>[2, 3, 2, 1];
    final measurements = <String>[];
    var hits = _lastFetchHit ? 1 : 0;

    await _warmPages(<int>[2, 3]);

    for (final pageNo in sequence) {
      if (!mounted) {
        return;
      }
      _renderToken++;
      try {
        final result = await _loadPage(pageNo: pageNo, applyState: true);
        hits += result.hit ? 1 : 0;
        measurements.add(
          'page=$pageNo ${result.hit ? 'hit' : 'miss'} ${result.elapsedMs}ms',
        );
        _schedulePrefetch(pageNo: pageNo);
      } on _RenderCancelled {
        return;
      }
    }

    final total = sequence.length + 1;
    debugPrint('VEROVIO_PAGE_DEMO_START');
    debugPrint('VEROVIO_PAGE_DEMO_INITIAL page=1 '
        '${_lastFetchHit ? 'hit' : 'miss'} ${_lastFetchMs}ms');
    for (final line in measurements) {
      debugPrint('VEROVIO_PAGE_DEMO $line');
    }
    debugPrint('VEROVIO_PAGE_DEMO_SUMMARY hits=$hits total=$total '
        'misses=${total - hits}');
    debugPrint('VEROVIO_PAGE_DEMO_END');
  }

  Future<void> _warmPages(Iterable<int> pageNos) async {
    final service = _service;
    if (service == null) {
      return;
    }
    for (final pageNo in pageNos) {
      if (pageNo < 1 || pageNo > _pageCount) {
        continue;
      }
      try {
        await _cache.getOrRender(
          data: _mei,
          optionsJson: _optionsJson,
          pageNo: pageNo,
          render: () => Future.value(service.renderToSvg(pageNo)),
        );
      } catch (_) {
        return;
      }
    }
  }

  Future<
      ({
        String svg,
        bool hit,
        int elapsedMs,
      })> _loadPage({
    required int pageNo,
    required bool applyState,
  }) async {
    final service = _service;
    if (service == null) {
      throw StateError('VerovioService is not ready');
    }
    final token = _renderToken;
    final stopwatch = Stopwatch()..start();
    var cacheMiss = false;
    final svg = await _cache.getOrRender(
      data: _mei,
      optionsJson: _optionsJson,
      pageNo: pageNo,
      render: () async {
        cacheMiss = true;
        return service.renderToSvg(pageNo);
      },
    );
    stopwatch.stop();
    if (token != _renderToken) {
      throw const _RenderCancelled();
    }

    if (applyState && mounted) {
      setState(() {
        _currentPage = pageNo;
        _svg = svg;
        _svgHead = svg.length <= 200 ? svg : svg.substring(0, 200);
        _svgLength = svg.length;
        _lastFetchMs = stopwatch.elapsedMilliseconds;
        _lastFetchHit = !cacheMiss;
        _lastFetchLabel = cacheMiss ? 'miss' : 'hit';
      });
    }
    return (
      svg: svg,
      hit: !cacheMiss,
      elapsedMs: stopwatch.elapsedMilliseconds
    );
  }

  void _schedulePrefetch({required int pageNo}) {
    final token = ++_renderToken;
    scheduleMicrotask(() {
      unawaited(_prefetchAdjacentPages(pageNo: pageNo, token: token));
    });
  }

  Future<void> _prefetchAdjacentPages({
    required int pageNo,
    required int token,
  }) async {
    final service = _service;
    if (service == null || _mei.isEmpty || _pageCount < 2) {
      return;
    }

    final candidates = <int>[
      if (pageNo > 1) pageNo - 1,
      if (pageNo < _pageCount) pageNo + 1,
    ];

    for (final candidate in candidates) {
      if (token != _renderToken || !mounted) {
        return;
      }
      try {
        await _cache.getOrRender(
          data: _mei,
          optionsJson: _optionsJson,
          pageNo: candidate,
          render: () => Future.value(service.renderToSvg(candidate)),
        );
      } on _RenderCancelled {
        return;
      } catch (_) {
        return;
      }
    }
  }

  Future<void> _goToPage(int pageNo) async {
    if (_service == null || pageNo < 1 || pageNo > _pageCount) {
      return;
    }
    _renderToken++;
    try {
      await _loadPage(pageNo: pageNo, applyState: true);
      if (!mounted) {
        return;
      }
      _schedulePrefetch(pageNo: pageNo);
    } on _RenderCancelled {
      // A newer navigation superseded this request.
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
      });
    }
  }

  @override
  void dispose() {
    unawaited(_service?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusText = _loading
        ? 'Loading Verovio spike...'
        : _error == null
            ? 'Spike complete'
            : 'Spike failed';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Verovio FFI Spike'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: DefaultTextStyle(
            style: theme.textTheme.bodyMedium ?? const TextStyle(fontSize: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(statusText, style: theme.textTheme.headlineSmall),
                const SizedBox(height: 12),
                if (_resourcePath != null) ...[
                  const Text('resourcePath'),
                  SelectableText(_resourcePath!),
                  const SizedBox(height: 12),
                ],
                Text('currentPage: $_currentPage / $_pageCount'),
                Text('firstScreenMs: $_firstScreenMs'),
                Text(
                  'lastFetch: $_lastFetchLabel $_lastFetchMs ms '
                  '(hit=$_lastFetchHit)',
                ),
                Text('cacheLength: ${_cache.length}'),
                Text('svgLength: $_svgLength'),
                Text('svg contains <svg: ${_svg.contains('<svg')}'),
                const SizedBox(height: 12),
                Row(
                  children: [
                    OutlinedButton(
                      onPressed: _currentPage > 1
                          ? () => _goToPage(_currentPage - 1)
                          : null,
                      child: const Text('上一页'),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton(
                      onPressed: _currentPage < _pageCount
                          ? () => _goToPage(_currentPage + 1)
                          : null,
                      child: const Text('下一页'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text('SVG head (first 200 chars)'),
                SelectableText(_svgHead.isEmpty ? '(empty)' : _svgHead),
                const SizedBox(height: 12),
                const Text('Verovio log'),
                SelectableText(_log.isEmpty ? '(empty)' : _log),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  const Text('Error'),
                  SelectableText(_error!),
                ],
                const SizedBox(height: 12),
                const Text('This spike keeps the full SVG in memory only.'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RenderCancelled implements Exception {
  const _RenderCancelled();
}
