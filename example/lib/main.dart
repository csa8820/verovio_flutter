import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:verovio_flutter/verovio_flutter.dart';

void main() {
  runApp(const VerovioFlutterDemo());
}

class VerovioFlutterDemo extends StatelessWidget {
  const VerovioFlutterDemo({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Verovio Flutter - Web Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const VerovioWebDemoPage(),
    );
  }
}

class VerovioWebDemoPage extends StatefulWidget {
  const VerovioWebDemoPage({super.key});

  @override
  State<VerovioWebDemoPage> createState() => _VerovioWebDemoPageState();
}

class _VerovioWebDemoPageState extends State<VerovioWebDemoPage> {
  static const String meiData = '''<?xml version="1.0" encoding="UTF-8"?>
<mei xmlns="http://www.music-encoding.org/ns/mei" meiversion="5.0">
  <meiHead/>
  <music>
    <body>
      <mdiv>
        <score>
          <scoreDef meter.count="4" meter.unit="4" key.sig="0"/>
          <section>
            <measure n="1">
              <staff n="1">
                <layer n="1">
                  <note pname="c" oct="4" dur="4"/>
                  <note pname="d" oct="4" dur="4"/>
                  <note pname="e" oct="4" dur="4"/>
                  <note pname="f" oct="4" dur="4"/>
                </layer>
              </staff>
            </measure>
            <measure n="2">
              <staff n="1">
                <layer n="1">
                  <note pname="g" oct="4" dur="4"/>
                  <note pname="a" oct="4" dur="4"/>
                  <note pname="b" oct="4" dur="4"/>
                  <note pname="c" oct="5" dur="4"/>
                </layer>
              </staff>
            </measure>
          </section>
        </score>
      </mdiv>
    </body>
  </music>
</mei>''';

  late Future<DemoRenderResult?> _renderFuture;
  int _currentPage = 1;
  int _totalPages = 1;
  Offset? _lastClickOffset;
  List<ElementHit>? _lastHitElements;
  bool _showHitInfo = true;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _renderFuture = _loadAndRender();
  }

  Future<DemoRenderResult?> _loadAndRender() async {
    try {
      final service = await VerovioAsyncService.spawn(
        resourcePath: '/verovio',
      );

      final optionsMap = {
        'pageHeight': 2970,
        'pageWidth': 2100,
        'scale': 40,
      };
      await service.setOptionsJson(jsonEncode(optionsMap));

      // Try to load MXL file
      try {
        final zipBytes = await rootBundle.load('assets/testdata/test_score.mxl');
        final uint8list = zipBytes.buffer.asUint8List(
          zipBytes.offsetInBytes,
          zipBytes.lengthInBytes,
        );
        await service.loadZipDataBuffer(uint8list);
        debugPrint('✓ Loaded test score from MXL');
      } catch (e) {
        debugPrint('Note: MXL loading failed, using MEI instead: $e');
        await service.loadData(meiData);
      }

      final pageCount = await service.pageCount;
      setState(() => _totalPages = pageCount);

      // Render first page with hit_map
      final result = await service.renderPageWithHitMap(_currentPage);
      final svg = result.svg;
      final hitMap = result.hitMap;

      await service.dispose();

      return DemoRenderResult(
        svg: svg,
        hitMap: hitMap,
        pageIndex: _currentPage,
      );
    } catch (e) {
      debugPrint('Error in demo: $e');
      return null;
    }
  }

  Future<void> _goToPage(int pageNum) async {
    if (pageNum < 1 || pageNum > _totalPages) return;

    setState(() {
      _currentPage = pageNum;
      _lastClickOffset = null;
      _lastHitElements = null;
      _isLoading = true;
      _renderFuture = _loadAndRender();
    });

    await _renderFuture;
    setState(() => _isLoading = false);
  }

  void _onSvgTap(Offset offset) async {
    setState(() => _lastClickOffset = offset);

    try {
      final result = await _renderFuture;
      if (result?.hitMap == null) {
        debugPrint('No hit map available');
        return;
      }

      final hits = hitTestPointAll(
        result!.hitMap!,
        offset,
      );

      setState(() => _lastHitElements = hits);

      if (hits.isNotEmpty) {
        final ids = hits.map((h) => h.id).join(', ');
        debugPrint('✓ Hit ${hits.length} element(s) at (${offset.dx.toStringAsFixed(1)}, ${offset.dy.toStringAsFixed(1)}): $ids');
      } else {
        debugPrint('○ No hits at (${offset.dx.toStringAsFixed(1)}, ${offset.dy.toStringAsFixed(1)})');
      }
    } catch (e) {
      debugPrint('Error in hit test: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Verovio Flutter - Web Demo'),
        centerTitle: false,
      ),
      body: Column(
        children: [
          // Status bar
          Container(
            color: Colors.blue[50],
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Page $_currentPage of $_totalPages'),
                if (_lastClickOffset != null)
                  Text(
                    'Last click: (${_lastClickOffset!.dx.toStringAsFixed(0)}, ${_lastClickOffset!.dy.toStringAsFixed(0)})',
                    style: const TextStyle(fontSize: 12),
                  ),
              ],
            ),
          ),
          // Control panel
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Page navigation
                Row(
                  children: [
                    Expanded(
                      child: Slider(
                        value: _currentPage.toDouble(),
                        min: 1,
                        max: _totalPages.toDouble(),
                        divisions: _totalPages > 1 ? _totalPages - 1 : 1,
                        label: 'Page $_currentPage',
                        onChanged: (value) {
                          _goToPage(value.toInt());
                        },
                      ),
                    ),
                    ElevatedButton(
                      onPressed: _currentPage > 1 ? () => _goToPage(_currentPage - 1) : null,
                      child: const Text('Prev'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _currentPage < _totalPages ? () => _goToPage(_currentPage + 1) : null,
                      child: const Text('Next'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Hit info toggle
                Row(
                  children: [
                    Checkbox(
                      value: _showHitInfo,
                      onChanged: (value) {
                        setState(() => _showHitInfo = value ?? true);
                      },
                    ),
                    const Text('Show hit info'),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 0),
          // Render area with click detection
          Expanded(
            child: FutureBuilder<DemoRenderResult?>(
              future: _renderFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting || _isLoading) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                } else if (snapshot.hasError || snapshot.data == null) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text(
                        'Error: ${snapshot.error ?? "Failed to load"}',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                final result = snapshot.data!;
                final viewBoxSize = result.hitMap?.viewBox;
                final width = viewBoxSize?.width ?? 2100.0;
                final height = viewBoxSize?.height ?? 2970.0;

                return SingleChildScrollView(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: GestureDetector(
                      onTapDown: (details) {
                        _onSvgTap(details.globalPosition);
                      },
                      child: Stack(
                        children: [
                          SvgPicture.string(
                            result.svg,
                            width: width,
                            height: height,
                          ),
                          // Hit highlight overlay
                          if (_showHitInfo && _lastHitElements != null && _lastHitElements!.isNotEmpty)
                            Positioned(
                              child: SizedBox(
                                width: width,
                                height: height,
                                child: CustomPaint(
                                  painter: HitHighlightPainter(
                                    hits: _lastHitElements!,
                                    lastClick: _lastClickOffset,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          // Hit info panel
          if (_showHitInfo)
            Container(
              color: Colors.grey[100],
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_lastHitElements != null && _lastHitElements!.isNotEmpty) ...[
                    Text(
                      'Hit elements: ${_lastHitElements!.length}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    ..._lastHitElements!.take(5).map((hit) {
                      final bbox = hit.bbox;
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '• ${hit.id} (${hit.type}) bbox=(${bbox.left.toStringAsFixed(0)},${bbox.top.toStringAsFixed(0)},${bbox.width.toStringAsFixed(0)},${bbox.height.toStringAsFixed(0)})',
                          style: const TextStyle(fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }),
                    if (_lastHitElements!.length > 5)
                      Text(
                        '... and ${_lastHitElements!.length - 5} more',
                        style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                      ),
                  ] else if (_lastClickOffset != null)
                    const Text(
                      'No hits at this location',
                      style: TextStyle(color: Colors.grey),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class DemoRenderResult {
  final String svg;
  final PageHitMap? hitMap;
  final int pageIndex;

  DemoRenderResult({
    required this.svg,
    required this.hitMap,
    required this.pageIndex,
  });
}

class HitHighlightPainter extends CustomPainter {
  final List<ElementHit> hits;
  final Offset? lastClick;

  HitHighlightPainter({
    required this.hits,
    required this.lastClick,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.blue.withAlpha(50)
      ..style = PaintingStyle.fill;

    final strokePaint = Paint()
      ..color = Colors.blue
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    for (final hit in hits) {
      final rect = hit.bbox;
      canvas.drawRect(rect, paint);
      canvas.drawRect(rect, strokePaint);
    }

    // Draw click point
    if (lastClick != null) {
      final clickPaint = Paint()
        ..color = Colors.red
        ..style = PaintingStyle.fill;
      canvas.drawCircle(lastClick!, 8, clickPaint);
    }
  }

  @override
  bool shouldRepaint(HitHighlightPainter oldDelegate) {
    return true;
  }
}
