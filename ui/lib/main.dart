import 'dart:io';
import 'package:flutter/material.dart';
import 'controllers/reader_controller.dart';
import 'views/workspace_view.dart';
import 'services/startup_metrics.dart';

void main(List<String> args) {
  StartupMetrics.begin();
  WidgetsFlutterBinding.ensureInitialized();
  String? targetFile;
  for (final arg in args) {
    if (arg != '--args' && !arg.startsWith('-')) {
      if (File(arg).existsSync() || Directory(arg).existsSync()) {
        targetFile = arg;
        break;
      }
    }
  }
  runApp(SuperGoodViewerApp(initialFile: targetFile));
}

class SuperGoodViewerApp extends StatefulWidget {
  final String? initialFile;
  const SuperGoodViewerApp({super.key, this.initialFile});

  @override
  State<SuperGoodViewerApp> createState() => _SuperGoodViewerAppState();
}

typedef SoGoodViewerApp = SuperGoodViewerApp;

class _SuperGoodViewerAppState extends State<SuperGoodViewerApp> {
  late final ReaderController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ReaderController(initialFilePath: widget.initialFile);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      StartupMetrics.markFirstFrame();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  static final ThemeData _lightTheme = ThemeData(
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
  );

  static final ThemeData _darkTheme = ThemeData(
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
  );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final isDark = _controller.renderOptions.isDark;

        return MaterialApp(
          title: '超好读',
          debugShowCheckedModeBanner: false,
          themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
          theme: _lightTheme,
          darkTheme: _darkTheme,
          home: WorkspaceView(controller: _controller),
        );
      },
    );
  }
}
