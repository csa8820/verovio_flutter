import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:verovio_flutter/verovio_flutter.dart';

class TestdataViewerApp extends StatelessWidget {
  const TestdataViewerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Verovio Testdata Viewer',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const TestdataViewerPage(),
    );
  }
}

class TestFile {
  final String name;
  final String path;
  final bool isMxl;

  TestFile({
    required this.name,
    required this.path,
    required this.isMxl,
  });
}

class TestdataViewerPage extends StatefulWidget {
  const TestdataViewerPage({super.key});

  @override
  State<TestdataViewerPage> createState() => _TestdataViewerPageState();
}

class _TestdataViewerPageState extends State<TestdataViewerPage> {
  static const String _optionsJson = '''
{"adjustPageHeight":false,"breaks":"auto","pageHeight":420,"pageWidth":1200,"header":"none","footer":"none","scale":40,"spacingStaff":4}
''';

  late List<TestFile> _testFiles;
  TestFile? _selectedFile;
  VerovioService? _service;
  String? _error;
  bool _loading = true;
  int _pageCount = 0;
  int _currentPage = 1;
  String _svg = '';
  int _renderTime = 0;
  int _activePane = 0;

  @override
  void initState() {
    super.initState();
    _initializeTestFiles();
    _bootstrap();
  }

  void _initializeTestFiles() {
    _testFiles = [
      TestFile(
        name: 'Melody Of The Night 5.xml',
        path: 'assets/testdata/Melody Of The Night 5.xml',
        isMxl: false,
      ),
      TestFile(
        name: 'Melody Of The Night 5-new.mxl',
        path: 'assets/testdata/Melody Of The Night 5-new.mxl',
        isMxl: true,
      ),
      TestFile(
        name: '花之舞 C调完美简易版 好弹好听.xml',
        path: 'assets/testdata/花之舞 C调完美简易版 好弹好听.xml',
        isMxl: true,
      ),
      TestFile(
        name: 'importer.mei',
        path: 'assets/testdata/importer.mei',
        isMxl: false,
      ),
      TestFile(
        name: 'minimal.mei',
        path: 'assets/testdata/minimal.mei',
        isMxl: false,
      ),
    ];
  }

  Future<void> _bootstrap() async {
    try {
      final resourcePath =
          await VerovioResourceManager.ensureVerovioAssetsReady();
      _service = await VerovioService.spawn(resourcePath: resourcePath);
      _service!.setOptionsJson(_optionsJson);

      setState(() {
        _loading = false;
        _selectedFile = _testFiles.first;
      });

      await _loadFile(_selectedFile!);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadFile(TestFile file) async {
    if (_service == null) return;

    try {
      setState(() => _loading = true);

      if (file.isMxl) {
        final ByteData bytes = await rootBundle.load(file.path);
        final Uint8List raw =
            bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
        final base64Data = base64Encode(raw);
        _service!.loadZipDataBase64(base64Data);
      } else {
        final data = await rootBundle.loadString(file.path);
        _service!.loadData(data);
      }

      final pageCount = _service!.pageCount;
      _currentPage = 1;
      _pageCount = pageCount;

      await _renderPage(1);

      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _renderPage(int pageNo) async {
    if (_service == null) return;

    try {
      final sw = Stopwatch()..start();
      final svg = _service!.renderToSvg(pageNo);
      sw.stop();

      setState(() {
        _svg = svg;
        _renderTime = sw.elapsedMilliseconds;
        _currentPage = pageNo;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  Widget _buildViewerPane(BuildContext context) {
    return _loading && _svg.isEmpty
        ? const Center(child: CircularProgressIndicator())
        : Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                color: Theme.of(context).colorScheme.surfaceContainer,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Select File',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    DropdownButton<TestFile>(
                      isExpanded: true,
                      value: _selectedFile,
                      items: _testFiles
                          .map((file) => DropdownMenuItem(
                                value: file,
                                child: Text(file.name),
                              ))
                          .toList(),
                      onChanged: (file) {
                        if (file != null && file != _selectedFile) {
                          setState(() => _selectedFile = file);
                          _loadFile(file);
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Text(
                          'Page $_currentPage / $_pageCount',
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.chevron_left),
                          onPressed: _currentPage > 1
                              ? () => _renderPage(_currentPage - 1)
                              : null,
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_right),
                          onPressed: _currentPage < _pageCount
                              ? () => _renderPage(_currentPage + 1)
                              : null,
                        ),
                      ],
                    ),
                    if (_renderTime > 0)
                      Text(
                        'Render time: ${_renderTime}ms',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.secondary,
                            ),
                      ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Error: $_error',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: _svg.isEmpty
                    ? const Center(child: Text('No SVG to display'))
                    : SvgPicture.string(
                        _svg,
                        fit: BoxFit.contain,
                      ),
              ),
            ],
          );
  }

  @override
  void dispose() {
    unawaited(_service?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Verovio Testdata Viewer'),
        elevation: 0,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SegmentedButton<int>(
                segments: const [
                  ButtonSegment<int>(
                    value: 0,
                    label: Text('Viewer'),
                    icon: Icon(Icons.preview),
                  ),
                  ButtonSegment<int>(
                    value: 1,
                    label: Text('Method browser'),
                    icon: Icon(Icons.view_list),
                  ),
                ],
                selected: <int>{_activePane},
                onSelectionChanged: (selection) {
                  setState(() => _activePane = selection.first);
                },
              ),
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: _activePane,
              children: [
                _buildViewerPane(context),
                _MethodBrowserPage(service: _service),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MethodBrowserPage extends StatefulWidget {
  const _MethodBrowserPage({required this.service});

  final VerovioService? service;

  @override
  State<_MethodBrowserPage> createState() => _MethodBrowserPageState();
}

class _MethodBrowserPageState extends State<_MethodBrowserPage> {
  String _result = 'Run a method to see the result here.';
  String _error = '';
  String? _runningMethod;
  late final List<_MethodEntry> _methods;

  @override
  void initState() {
    super.initState();
    _methods = _buildMethods();
  }

  @override
  void dispose() {
    for (final entry in _methods) {
      entry.controller?.dispose();
    }
    super.dispose();
  }

  List<_MethodEntry> _buildMethods() {
    const pageHint = 'Page number (int)';
    const jsonHint = 'JSON options / payload';
    const textHint = 'Text input';
    const base64Hint = 'Base64-encoded bytes';

    TextEditingController controller([String text = '']) =>
        TextEditingController(text: text);

    _MethodEntry noArg(
      String name,
      Future<String> Function(VerovioService service) run, {
      String hint = '',
    }) {
      return _MethodEntry(
        name: name,
        hint: hint,
        run: (service, _) => run(service),
      );
    }

    _MethodEntry withInput(
      String name,
      Future<String> Function(VerovioService service, String raw) run, {
      String hint = textHint,
      String inputLabel = 'Input',
      String initial = '',
      int maxLines = 1,
      TextInputType keyboardType = TextInputType.text,
    }) {
      return _MethodEntry(
        name: name,
        hint: hint,
        inputLabel: inputLabel,
        maxLines: maxLines,
        keyboardType: keyboardType,
        controller: controller(initial),
        run: run,
      );
    }

    return [
      noArg('getVersion', (service) async => service.getVersion()),
      noArg('getOptions', (service) async => service.getOptions()),
      noArg(
        'getAvailableOptions',
        (service) async => service.getAvailableOptions(),
      ),
      withInput(
        'setResourcePath',
        (service, raw) async => service.setResourcePath(raw).toString(),
        hint: 'Absolute resource directory path',
      ),
      withInput(
        'setOptionsJson',
        (service, raw) async {
          service.setOptionsJson(raw);
          return 'ok';
        },
        hint: jsonHint,
        inputLabel: 'JSON',
        maxLines: 4,
        keyboardType: TextInputType.multiline,
      ),
      withInput(
        'loadData',
        (service, raw) async {
          service.loadData(raw);
          return 'ok';
        },
        hint: 'Raw MEI / MusicXML text',
        inputLabel: 'Source data',
        maxLines: 6,
        keyboardType: TextInputType.multiline,
      ),
      withInput(
        'loadZipDataBase64',
        (service, raw) async {
          service.loadZipDataBase64(raw.trim());
          return 'ok';
        },
        hint: base64Hint,
        inputLabel: 'Base64 zip data',
        maxLines: 4,
        keyboardType: TextInputType.multiline,
      ),
      withInput(
        'loadZipDataBuffer',
        (service, raw) async {
          service.loadZipDataBuffer(base64Decode(raw.trim()));
          return 'ok';
        },
        hint: base64Hint,
        inputLabel: 'Base64 bytes',
        maxLines: 4,
        keyboardType: TextInputType.multiline,
      ),
      noArg('pageCount', (service) async => service.pageCount.toString()),
      withInput(
        'renderToSvg',
        (service, raw) async {
          final pageNo = int.parse(raw.trim());
          return service.renderToSvg(pageNo);
        },
        hint: pageHint,
        inputLabel: 'Page number',
        initial: '1',
        keyboardType: TextInputType.number,
      ),
      noArg('getLog', (service) async => service.getLog()),
      noArg(
        'getDefaultOptions',
        (service) async => service.getDefaultOptions(),
      ),
      noArg('getOptionUsageString',
          (service) async => service.getOptionUsageString()),
      withInput(
        'getDescriptiveFeatures',
        (service, raw) async => service.getDescriptiveFeatures(raw),
        hint: jsonHint,
        inputLabel: 'JSON options',
        maxLines: 4,
        keyboardType: TextInputType.multiline,
      ),
      withInput(
        'getElementAttr',
        (service, raw) async => service.getElementAttr(raw),
        hint: 'xml:id',
      ),
      withInput(
        'getElementsAtTime',
        (service, raw) async =>
            service.getElementsAtTime(int.parse(raw.trim())),
        hint: 'Milliseconds (int)',
        inputLabel: 'Milliseconds',
        initial: '0',
        keyboardType: TextInputType.number,
      ),
      withInput(
        'getExpansionIdsForElement',
        (service, raw) async => service.getExpansionIdsForElement(raw),
        hint: 'xml:id',
      ),
      withInput(
        'getMidiValuesForElement',
        (service, raw) async => service.getMidiValuesForElement(raw),
        hint: 'xml:id',
      ),
      withInput(
        'getNotatedIdForElement',
        (service, raw) async => service.getNotatedIdForElement(raw),
        hint: 'xml:id',
      ),
      withInput(
        'getTimesForElement',
        (service, raw) async => service.getTimesForElement(raw),
        hint: 'xml:id',
      ),
      noArg('getId', (service) async => service.getId()),
      noArg('getResourcePath', (service) async => service.getResourcePath()),
      noArg('getHumdrum', (service) async => service.getHumdrum()),
      withInput(
        'getMei',
        (service, raw) async => service.getMei(raw),
        hint: jsonHint,
        inputLabel: 'JSON options',
        maxLines: 4,
        keyboardType: TextInputType.multiline,
      ),
      withInput(
        'convertHumdrumToHumdrum',
        (service, raw) async => service.convertHumdrumToHumdrum(raw),
        hint: textHint,
        inputLabel: 'Humdrum source',
        maxLines: 6,
        keyboardType: TextInputType.multiline,
      ),
      withInput(
        'convertHumdrumToMidi',
        (service, raw) async => service.convertHumdrumToMidi(raw),
        hint: textHint,
        inputLabel: 'Humdrum source',
        maxLines: 6,
        keyboardType: TextInputType.multiline,
      ),
      withInput(
        'convertHumdrumToMidiBytes',
        (service, raw) async =>
            '<${service.convertHumdrumToMidiBytes(raw).length} bytes>',
        hint: textHint,
        inputLabel: 'Humdrum source',
        maxLines: 6,
        keyboardType: TextInputType.multiline,
      ),
      withInput(
        'convertMeiToHumdrum',
        (service, raw) async => service.convertMeiToHumdrum(raw),
        hint: textHint,
        inputLabel: 'MEI / XML source',
        maxLines: 6,
        keyboardType: TextInputType.multiline,
      ),
      noArg('editInfo', (service) async => service.editInfo()),
      withInput(
        'validatePae',
        (service, raw) async => service.validatePae(raw),
        hint: textHint,
        inputLabel: 'PAE text',
        maxLines: 4,
        keyboardType: TextInputType.multiline,
      ),
      withInput(
        'renderData',
        (service, raw) async {
          final trimmed = raw.trim();
          if (trimmed.isEmpty) {
            return service.renderData('', '');
          }
          try {
            final decoded = jsonDecode(trimmed);
            if (decoded is Map) {
              final data = decoded['data']?.toString() ?? '';
              final jsonOptions = decoded['jsonOptions']?.toString() ?? '';
              return service.renderData(data, jsonOptions);
            }
          } catch (_) {
            // Fall through to treating the input as raw data.
          }
          return service.renderData(raw, '');
        },
        hint: 'Raw data, or JSON object {"data":"...","jsonOptions":"..."}',
        inputLabel: 'Data / payload',
        maxLines: 6,
        keyboardType: TextInputType.multiline,
      ),
      noArg('renderToMidi', (service) async => service.renderToMidi()),
      noArg('renderToMidiBytes',
          (service) async => '<${service.renderToMidiBytes().length} bytes>'),
      noArg('renderToPae', (service) async => service.renderToPae()),
      withInput(
        'renderToTimemap',
        (service, raw) async => service.renderToTimemap(jsonOptions: raw),
        hint: jsonHint,
        inputLabel: 'JSON options',
        maxLines: 4,
        keyboardType: TextInputType.multiline,
      ),
      noArg('renderToExpansionMap',
          (service) async => service.renderToExpansionMap()),
      noArg('getScale', (service) async => service.getScale().toString()),
      withInput(
        'setScale',
        (service, raw) async =>
            service.setScale(int.parse(raw.trim())).toString(),
        hint: 'Scale (int)',
        inputLabel: 'Scale',
        initial: '40',
        keyboardType: TextInputType.number,
      ),
      withInput(
        'getPageWithElement',
        (service, raw) async => service.getPageWithElement(raw).toString(),
        hint: 'xml:id',
      ),
      withInput(
        'getTimeForElement',
        (service, raw) async => service.getTimeForElement(raw).toString(),
        hint: 'xml:id',
      ),
      withInput(
        'select',
        (service, raw) async => service.select(raw).toString(),
        hint: jsonHint,
        inputLabel: 'Selection JSON',
        maxLines: 4,
        keyboardType: TextInputType.multiline,
      ),
      withInput(
        'setInputFrom',
        (service, raw) async => service.setInputFrom(raw).toString(),
        hint: textHint,
      ),
      withInput(
        'setOutputTo',
        (service, raw) async => service.setOutputTo(raw).toString(),
        hint: textHint,
      ),
      withInput(
        'edit',
        (service, raw) async => service.edit(raw).toString(),
        hint: textHint,
      ),
      withInput(
        'redoLayout',
        (service, raw) async {
          service.redoLayout(jsonOptions: raw);
          return 'ok';
        },
        hint: jsonHint,
        inputLabel: 'JSON options',
        maxLines: 4,
        keyboardType: TextInputType.multiline,
      ),
      noArg('redoPagePitchPosLayout', (service) async {
        service.redoPagePitchPosLayout();
        return 'ok';
      }),
      noArg('resetOptions', (service) async {
        service.resetOptions();
        return 'ok';
      }),
      withInput(
        'resetXmlIdSeed',
        (service, raw) async {
          service.resetXmlIdSeed(int.parse(raw.trim()));
          return 'ok';
        },
        hint: 'Seed (int)',
        inputLabel: 'Seed',
        initial: '0',
        keyboardType: TextInputType.number,
      ),
    ];
  }

  Future<void> _runMethod(_MethodEntry entry) async {
    final service = widget.service;
    if (service == null) {
      setState(() {
        _error = 'VerovioService is not ready yet.';
      });
      return;
    }

    final raw = entry.controller?.text ?? '';
    setState(() {
      _runningMethod = entry.name;
      _error = '';
    });

    try {
      final result = await entry.run(service, raw);
      if (!mounted) {
        return;
      }
      setState(() {
        _result = result;
        _error = '';
        _runningMethod = null;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = e.toString();
        _runningMethod = null;
      });
    }
  }

  Widget _buildMethodCard(BuildContext context, _MethodEntry entry) {
    final serviceReady = widget.service != null;
    final isRunning = _runningMethod == entry.name;
    final buttonDisabled = !serviceReady || _runningMethod != null;
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.name,
                        style: theme.textTheme.titleMedium,
                      ),
                      if (entry.hint.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          entry.hint,
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.tonalIcon(
                  onPressed: buttonDisabled ? null : () => _runMethod(entry),
                  icon: isRunning
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow),
                  label: Text(isRunning ? 'Running' : 'Run'),
                ),
              ],
            ),
            if (entry.controller != null) ...[
              const SizedBox(height: 12),
              TextField(
                controller: entry.controller,
                enabled: serviceReady && !isRunning,
                maxLines: entry.maxLines,
                keyboardType: entry.keyboardType,
                decoration: InputDecoration(
                  labelText: entry.inputLabel,
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildOutputPanel(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 240),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Result',
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  if (_error.isNotEmpty)
                    Text(
                      'Error: $_error',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  if (_error.isNotEmpty) const SizedBox(height: 8),
                  SelectableText(
                    _result,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            service == null
                ? 'Waiting for VerovioService to finish bootstrapping…'
                : 'Manual method browser for the active toolkit instance. ${_methods.length} methods are listed below.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            itemCount: _methods.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              return _buildMethodCard(context, _methods[index]);
            },
          ),
        ),
        _buildOutputPanel(context),
      ],
    );
  }
}

class _MethodEntry {
  final String name;
  final String hint;
  final String inputLabel;
  final int maxLines;
  final TextInputType keyboardType;
  final TextEditingController? controller;
  final Future<String> Function(VerovioService service, String raw) run;

  _MethodEntry({
    required this.name,
    required this.run,
    this.hint = '',
    this.inputLabel = 'Input',
    this.maxLines = 1,
    this.keyboardType = TextInputType.text,
    this.controller,
  });
}
