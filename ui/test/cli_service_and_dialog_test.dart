import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sogoodviewer/services/native_cli_service.dart';
import 'package:sogoodviewer/views/cli_tools_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.sogoodviewer.app');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('NativeCliService Tests', () {
    test('checkStatus parses response correctly when installed', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'checkCliStatus') {
          return {
            'isInstalled': true,
            'path': '/usr/local/bin/sgv',
            'target': '/Applications/SuperGoodViewer.app/Contents/Resources/bin/sgv',
            'isCurrentApp': true,
          };
        }
        return null;
      });

      final status = await NativeCliService.checkStatus();
      expect(status.isInstalled, isTrue);
      expect(status.path, equals('/usr/local/bin/sgv'));
      expect(status.isCurrentApp, isTrue);
    });

    test('install handles success and cancelled states', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'installCli') {
          return {
            'status': 'success',
            'path': '/usr/local/bin/sgv',
          };
        }
        return null;
      });

      final res = await NativeCliService.install();
      expect(res.isSuccess, isTrue);
      expect(res.isCancelled, isFalse);
      expect(res.path, equals('/usr/local/bin/sgv'));
    });

    test('uninstall handles success and cancelled states', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'uninstallCli') {
          return {
            'status': 'success',
          };
        }
        return null;
      });

      final res = await NativeCliService.uninstall();
      expect(res.isSuccess, isTrue);
      expect(res.isCancelled, isFalse);
    });
  });

  group('CliToolsDialog Widget Tests', () {
    testWidgets('renders dialog in uninstalled state with install button', (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'checkCliStatus') {
          return {
            'isInstalled': false,
            'path': '/usr/local/bin/sgv',
            'target': '',
            'isCurrentApp': false,
          };
        }
        return null;
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showCliToolsDialog(context),
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('命令行工具 (sgv)'), findsOneWidget);
      expect(find.text('尚未安装到系统终端'), findsOneWidget);
      expect(find.text('一键安装到终端'), findsOneWidget);
      expect(find.text('sgv README.md'), findsOneWidget);
    });

    testWidgets('renders dialog in installed state with repair and uninstall buttons', (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'checkCliStatus') {
          return {
            'isInstalled': true,
            'path': '/usr/local/bin/sgv',
            'target': '/Applications/SuperGoodViewer.app/Contents/Resources/bin/sgv',
            'isCurrentApp': true,
          };
        }
        return null;
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showCliToolsDialog(context),
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('已就绪 (已安装在系统 PATH)'), findsOneWidget);
      expect(find.text('重新链接 / 修复'), findsOneWidget);
      expect(find.text('卸载'), findsOneWidget);
    });
  });
}
