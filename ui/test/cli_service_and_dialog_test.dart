import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sogoodviewer/i18n/app_localizations.dart';
import 'package:sogoodviewer/i18n/strings_en.dart';
import 'package:sogoodviewer/i18n/strings_zh_hans.dart';
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

    test('install handles partial success with warning field', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'installCli') {
          return {
            'status': 'success',
            'path': '/usr/local/bin/sgv',
            'warning': 'sgv 安装成功，但未能创建 sgv-cli 快捷方式',
          };
        }
        return null;
      });

      final res = await NativeCliService.install();
      expect(res.isSuccess, isTrue);
      expect(res.isCancelled, isFalse);
      expect(res.path, equals('/usr/local/bin/sgv'));
      expect(res.warning, equals('sgv 安装成功，但未能创建 sgv-cli 快捷方式'));
    });

    test('checkStatus parses response correctly when partially installed', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'checkCliStatus') {
          return {
            'isInstalled': false,
            'isPartial': true,
            'path': '/usr/local/bin/sgv',
            'target': '/Applications/SuperGoodViewer.app/Contents/Resources/bin/sgv',
            'isCurrentApp': false,
          };
        }
        return null;
      });

      final status = await NativeCliService.checkStatus();
      expect(status.isInstalled, isFalse);
      expect(status.isPartial, isTrue);
      expect(status.path, equals('/usr/local/bin/sgv'));
      expect(status.warning, isNull);
    });

    test('checkStatus parses response correctly when partially installed with custom warning', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'checkCliStatus') {
          return {
            'isInstalled': false,
            'isPartial': true,
            'path': r'C:\Users\test\AppData\Local\SuperGoodViewer\bin\sgv.cmd',
            'target': r'C:\Program Files\SuperGoodViewer\sgv.exe',
            'isCurrentApp': true,
            'warning': '安装不完整 (未添加到系统 PATH)',
          };
        }
        return null;
      });

      final status = await NativeCliService.checkStatus();
      expect(status.isInstalled, isFalse);
      expect(status.isPartial, isTrue);
      expect(status.path, equals(r'C:\Users\test\AppData\Local\SuperGoodViewer\bin\sgv.cmd'));
      expect(status.warning, equals('安装不完整 (未添加到系统 PATH)'));
    });

    test('checkStatus parses warningCode and produces localizedWarning in different languages', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'checkCliStatus') {
          return {
            'isInstalled': false,
            'isPartial': true,
            'path': r'C:\Users\test\AppData\Local\SuperGoodViewer\bin\sgv.cmd',
            'target': r'C:\Program Files\SuperGoodViewer\sgv.exe',
            'isCurrentApp': true,
            'warningCode': 'missing_path',
            'warning': '安装不完整 (未添加到系统 PATH)',
          };
        }
        return null;
      });

      final status = await NativeCliService.checkStatus();
      expect(status.isInstalled, isFalse);
      expect(status.isPartial, isTrue);
      expect(status.warningCode, equals('missing_path'));
      expect(status.localizedWarning(const ZhHansStrings()), equals('安装不完整 (未添加到系统 PATH)'));
      expect(status.localizedWarning(const EnStrings()), equals('Incomplete installation (Not added to system PATH)'));
    });

    test('install parses warningCodes and formats localized warning', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'installCli') {
          return {
            'status': 'success',
            'path': r'C:\Users\test\AppData\Local\SuperGoodViewer\bin\sgv.cmd',
            'warningCodes': ['path_failed', 'ps1_update_failed'],
            'warning': '脚本已生成，但未能将安装目录添加到环境变量 PATH（注册表受限），命令行可能无法直接调用；且 sgv.ps1 未能更新（可能被占用），PowerShell 下可能仍指向旧版本',
          };
        }
        return null;
      });

      final res = await NativeCliService.install();
      expect(res.isSuccess, isTrue);
      expect(res.warningCodes, equals(['path_failed', 'ps1_update_failed']));
      expect(res.localizedWarning(const EnStrings()), contains('Scripts generated, but '));
      expect(res.localizedWarning(const EnStrings()), contains('registry restricted'));
      expect(res.localizedWarning(const EnStrings()), contains('PowerShell may still point to older version'));
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
      expect(res.message, isNull);
    });

    test('uninstall handles success with custom message', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'uninstallCli') {
          return {
            'status': 'success',
            'message': '已成功卸载',
          };
        }
        return null;
      });

      final res = await NativeCliService.uninstall();
      expect(res.isSuccess, isTrue);
      expect(res.isCancelled, isFalse);
      expect(res.message, equals('已成功卸载'));
    });
  });

  group('CliToolsDialog Widget Tests', () {
    Widget buildTestApp(Widget child, [String language = 'zhHans']) {
      return MaterialApp(
        localizationsDelegates: [
          AppLocalizationsDelegate(language),
        ],
        home: Scaffold(body: child),
      );
    }

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
        buildTestApp(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showCliToolsDialog(context),
              child: const Text('Open Dialog'),
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

    testWidgets('renders dialog in partially installed state with repair and cleanup buttons', (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'checkCliStatus') {
          return {
            'isInstalled': false,
            'isPartial': true,
            'path': '/usr/local/bin/sgv',
            'target': '/Applications/SuperGoodViewer.app/Contents/Resources/bin/sgv',
            'isCurrentApp': false,
          };
        }
        return null;
      });

      await tester.pumpWidget(
        buildTestApp(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showCliToolsDialog(context),
              child: const Text('Open Dialog'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('安装不完整 (部分工具未就绪)'), findsOneWidget);
      expect(find.text('重新安装 / 修复'), findsOneWidget);
      expect(find.text('卸载清理'), findsOneWidget);
      expect(find.text('软链接路径: /usr/local/bin/sgv'), findsOneWidget);
    });

    testWidgets('renders dialog in partially installed state with custom warning message', (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'checkCliStatus') {
          return {
            'isInstalled': false,
            'isPartial': true,
            'path': r'C:\Users\test\AppData\Local\SuperGoodViewer\bin\sgv.cmd',
            'target': r'C:\Program Files\SuperGoodViewer\sgv.exe',
            'isCurrentApp': true,
            'warning': '安装不完整 (未添加到系统 PATH)',
          };
        }
        return null;
      });

      await tester.pumpWidget(
        buildTestApp(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showCliToolsDialog(context),
              child: const Text('Open Dialog'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('安装不完整 (未添加到系统 PATH)'), findsOneWidget);
      expect(find.text('重新安装 / 修复'), findsOneWidget);
      expect(find.text('卸载清理'), findsOneWidget);
    });

    testWidgets('renders dialog localized in English with custom warning message', (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'checkCliStatus') {
          return {
            'isInstalled': false,
            'isPartial': true,
            'path': r'C:\Users\test\AppData\Local\SuperGoodViewer\bin\sgv.cmd',
            'target': r'C:\Program Files\SuperGoodViewer\sgv.exe',
            'isCurrentApp': true,
            'warningCode': 'missing_path',
            'warning': '安装不完整 (未添加到系统 PATH)',
          };
        }
        return null;
      });

      await tester.pumpWidget(
        buildTestApp(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showCliToolsDialog(context),
              child: const Text('Open Dialog'),
            ),
          ),
          'en',
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('CLI Command Tool (sgv)'), findsOneWidget);
      expect(find.text('Incomplete installation (Not added to system PATH)'), findsOneWidget);
      expect(find.text('Reinstall / Repair'), findsOneWidget);
      expect(find.text('Clean Uninstall'), findsOneWidget);
      expect(find.text('Usage Examples'), findsOneWidget);
    });

    testWidgets('shows warning snackbar when install partially succeeds with warning', (tester) async {
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
        if (call.method == 'installCli') {
          return {
            'status': 'success',
            'path': '/usr/local/bin/sgv',
            'warningCode': 'cli_tool_failed',
            'warning': 'sgv 安装成功，但未能创建 sgv-cli 快捷方式',
          };
        }
        return null;
      });

      await tester.pumpWidget(
        buildTestApp(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showCliToolsDialog(context),
              child: const Text('Open Dialog'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('一键安装到终端'));
      await tester.pump();

      expect(find.text('⚠️ 脚本已生成，但未能创建 sgv-cli 快捷方式'), findsOneWidget);
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
        buildTestApp(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showCliToolsDialog(context),
              child: const Text('Open Dialog'),
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

    testWidgets('shows default snackbar when uninstall succeeds without message', (tester) async {
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
        if (call.method == 'uninstallCli') {
          return {
            'status': 'success',
          };
        }
        return null;
      });

      await tester.pumpWidget(
        buildTestApp(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showCliToolsDialog(context),
              child: const Text('Open Dialog'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('卸载'));
      await tester.pump();

      expect(find.text('已成功卸载 \'sgv\' 命令行工具'), findsOneWidget);
    });

    testWidgets('shows custom message when uninstall returns message', (tester) async {
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
        if (call.method == 'uninstallCli') {
          return {
            'status': 'success',
            'message': '未安装',
          };
        }
        return null;
      });

      await tester.pumpWidget(
        buildTestApp(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showCliToolsDialog(context),
              child: const Text('Open Dialog'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('卸载'));
      await tester.pump();

      expect(find.text('未安装'), findsOneWidget);
    });
  });
}
