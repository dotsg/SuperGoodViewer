import 'dart:io';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sogoodviewer/controllers/reader_controller.dart';
import 'package:sogoodviewer/services/preferences_service.dart';
import 'package:sogoodviewer/views/workspace_view.dart';

void main() {
  late Directory tempDir;

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('sgv_drag_drop_test_');
    PreferencesService.setConfigFileForTesting(
      File(p.join(tempDir.path, 'preferences.json')),
    );
  });

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    const windowChannel = MethodChannel('com.sogoodviewer.window');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      windowChannel,
      (call) async {
        if (call.method == 'isFullScreen') return false;
        return null;
      },
    );
  });

  tearDown(() {
    const windowChannel = MethodChannel('com.sogoodviewer.window');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      windowChannel,
      null,
    );
  });

  tearDownAll(() {
    PreferencesService.setConfigFileForTesting(null);
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  group('Drag and Drop File to Open Tests', () {
    testWidgets('Drag hover triggers visual overlay and exit dismisses it', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = ReaderController(autoRestorePreferences: false);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: WorkspaceView(controller: controller),
        ),
      );
      await tester.pump();

      // Overlay should not be visible initially
      expect(find.text('释放以在此窗口打开文档'), findsNothing);

      // Find DropTarget
      final dropFinder = find.byType(DropTarget);
      expect(dropFinder, findsOneWidget);
      final dropTarget = tester.widget<DropTarget>(dropFinder);

      // Trigger drag enter
      dropTarget.onDragEntered?.call(
        DropEventDetails(localPosition: Offset.zero, globalPosition: Offset.zero),
      );
      await tester.pump();

      // Overlay should now be displayed
      expect(find.text('释放以在此窗口打开文档'), findsOneWidget);
      expect(find.byIcon(Icons.file_download_outlined), findsOneWidget);

      // Trigger drag exit
      dropTarget.onDragExited?.call(
        DropEventDetails(localPosition: Offset.zero, globalPosition: Offset.zero),
      );
      await tester.pump();

      // Overlay should disappear
      expect(find.text('释放以在此窗口打开文档'), findsNothing);
    });

    testWidgets('Dropping a markdown file opens it in ReaderController', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final sampleMd = File(p.join(tempDir.path, 'dragged_doc.md'));
      sampleMd.writeAsStringSync('# Drag and Drop Success\n\nThis document was dropped into the window.');

      final controller = ReaderController(autoRestorePreferences: false);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: WorkspaceView(controller: controller),
        ),
      );
      await tester.pump();

      final dropTarget = tester.widget<DropTarget>(find.byType(DropTarget));

      // Drag in then drop file
      dropTarget.onDragEntered?.call(
        DropEventDetails(localPosition: Offset.zero, globalPosition: Offset.zero),
      );
      await tester.pump();
      expect(find.text('释放以在此窗口打开文档'), findsOneWidget);

      await tester.runAsync(() async {
        dropTarget.onDragDone?.call(
          DropDoneDetails(
            files: [DropItemFile(sampleMd.path)],
            localPosition: Offset.zero,
            globalPosition: Offset.zero,
          ),
        );
        await Future.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Overlay dismissed
      expect(find.text('释放以在此窗口打开文档'), findsNothing);

      // Document was opened
      expect(controller.currentFilePath, sampleMd.path);
      expect(controller.documentTitle, 'dragged_doc');
      expect(controller.currentMarkdown, contains('Drag and Drop Success'));
    });

    testWidgets('Dropping a directory opens README.md inside it', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final subDir = Directory(p.join(tempDir.path, 'project_folder'));
      subDir.createSync(recursive: true);
      final readme = File(p.join(subDir.path, 'README.md'));
      readme.writeAsStringSync('# Project Readme\n\nAuto-discovered inside dropped directory.');

      final controller = ReaderController(autoRestorePreferences: false);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: WorkspaceView(controller: controller),
        ),
      );
      await tester.pump();

      final dropTarget = tester.widget<DropTarget>(find.byType(DropTarget));

      // Drop directory
      await tester.runAsync(() async {
        dropTarget.onDragDone?.call(
          DropDoneDetails(
            files: [DropItemFile(subDir.path)],
            localPosition: Offset.zero,
            globalPosition: Offset.zero,
          ),
        );
        await Future.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(controller.currentFilePath, readme.path);
      expect(controller.currentMarkdown, contains('Project Readme'));
    });

    testWidgets('Dropping directory with multiple files deterministically opens first alphabetically', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final multiDir = Directory(p.join(tempDir.path, 'multi_folder'));
      multiDir.createSync(recursive: true);
      final fileZ = File(p.join(multiDir.path, 'zeta.md'));
      fileZ.writeAsStringSync('# Zeta Document');
      final fileA = File(p.join(multiDir.path, 'alpha.md'));
      fileA.writeAsStringSync('# Alpha Document');
      final fileM = File(p.join(multiDir.path, 'middle.md'));
      fileM.writeAsStringSync('# Middle Document');

      final controller = ReaderController(autoRestorePreferences: false);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: WorkspaceView(controller: controller),
        ),
      );
      await tester.pump();

      final dropTarget = tester.widget<DropTarget>(find.byType(DropTarget));

      await tester.runAsync(() async {
        dropTarget.onDragDone?.call(
          DropDoneDetails(
            files: [DropItemFile(multiDir.path)],
            localPosition: Offset.zero,
            globalPosition: Offset.zero,
          ),
        );
        await Future.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(controller.currentFilePath, fileA.path);
      expect(controller.currentMarkdown, contains('Alpha Document'));
    });

    testWidgets('Dropping empty directory shows specific snackbar', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final emptyDir = Directory(p.join(tempDir.path, 'empty_dir'));
      emptyDir.createSync(recursive: true);

      final controller = ReaderController(autoRestorePreferences: false);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: WorkspaceView(controller: controller),
        ),
      );
      await tester.pump();

      final dropTarget = tester.widget<DropTarget>(find.byType(DropTarget));

      await tester.runAsync(() async {
        dropTarget.onDragDone?.call(
          DropDoneDetails(
            files: [DropItemFile(emptyDir.path)],
            localPosition: Offset.zero,
            globalPosition: Offset.zero,
          ),
        );
        await Future.delayed(const Duration(milliseconds: 500));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('所选文件夹中未找到可打开的 Markdown 或 PDF 文档'), findsOneWidget);
    });

    testWidgets('Dropping unsupported binary file (e.g. .png) shows specific format error', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final pngFile = File(p.join(tempDir.path, 'image.png'));
      pngFile.writeAsBytesSync([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);

      final controller = ReaderController(autoRestorePreferences: false);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: WorkspaceView(controller: controller),
        ),
      );
      await tester.pump();

      final dropTarget = tester.widget<DropTarget>(find.byType(DropTarget));

      await tester.runAsync(() async {
        dropTarget.onDragDone?.call(
          DropDoneDetails(
            files: [DropItemFile(pngFile.path)],
            localPosition: Offset.zero,
            globalPosition: Offset.zero,
          ),
        );
        await Future.delayed(const Duration(milliseconds: 500));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('暂不支持打开 .png 格式文件，请拖入 Markdown (.md) 或 PDF (.pdf)'), findsOneWidget);
    });
  });
}
