import 'package:flutter/material.dart';

void main() {
  runApp(const SvgStringDemoApp());
}

class SvgStringDemoApp extends StatelessWidget {
  const SvgStringDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SVG String Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const SvgStringDemoPage(),
    );
  }
}

class SvgStringDemoPage extends StatelessWidget {
  const SvgStringDemoPage({super.key});

  static const String svgString = '''
<svg xmlns="http://www.w3.org/2000/svg" width="420" height="120" viewBox="0 0 420 120">
  <rect x="0" y="0" width="420" height="120" rx="16" fill="#EEF2FF"/>
  <rect x="18" y="18" width="384" height="84" rx="12" fill="#FFFFFF" stroke="#6366F1" stroke-width="2"/>
  <text x="210" y="58" text-anchor="middle" font-family="monospace" font-size="18" fill="#111827">
    &lt;svg&gt; string output only
  </text>
  <text x="210" y="82" text-anchor="middle" font-family="monospace" font-size="12" fill="#6B7280">
    verovio_flutter disabled for this test
  </text>
</svg>
''';

  @override
  Widget build(BuildContext context) {
    debugPrint('SVG_STRING_OUTPUT_START');
    debugPrint(svgString);
    debugPrint('SVG_STRING_OUTPUT_END');

    return Scaffold(
      appBar: AppBar(
        title: const Text('SVG String Demo'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Raw SVG string',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                child: const SingleChildScrollView(
                  padding: EdgeInsets.all(16),
                  child: SelectableText(
                    svgString,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
