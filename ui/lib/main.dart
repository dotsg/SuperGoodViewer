import 'package:flutter/material.dart';
import 'controllers/reader_controller.dart';
import 'views/workspace_view.dart';

void main(List<String> args) {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(SoGoodViewerApp(initialFile: args.isNotEmpty ? args.first : null));
}

class SoGoodViewerApp extends StatefulWidget {
  final String? initialFile;
  const SoGoodViewerApp({super.key, this.initialFile});

  @override
  State<SoGoodViewerApp> createState() => _SoGoodViewerAppState();
}

class _SoGoodViewerAppState extends State<SoGoodViewerApp> {
  late final ReaderController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ReaderController(initialFilePath: widget.initialFile);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final isDark = _controller.renderOptions.isDark;

        return MaterialApp(
          title: 'SoGoodViewer',
          debugShowCheckedModeBanner: false,
          themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF2563EB), // Premium Royal Blue
              brightness: Brightness.light,
            ),
            scaffoldBackgroundColor: const Color(0xFFF9F9F9),
            fontFamily: '-apple-system',
            dividerTheme: const DividerThemeData(
              color: Color(0xFFE5E5E5),
              thickness: 1,
            ),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF3B82F6),
              brightness: Brightness.dark,
              surface: const Color(0xFF1E1E1E),
            ),
            scaffoldBackgroundColor: const Color(0xFF141414),
            fontFamily: '-apple-system',
            dividerTheme: const DividerThemeData(
              color: Color(0xFF2E2E2E),
              thickness: 1,
            ),
          ),
          home: WorkspaceView(controller: _controller),
        );
      },
    );
  }
}
