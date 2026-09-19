import 'package:flutter/material.dart';
import '../i18n/app_strings.dart';
import '../services/native_cli_service.dart';

/// Displays feedback SnackBar after a CLI install/uninstall operation.
void showCliOperationFeedback(
  BuildContext context, {
  required CliOperationResult result,
  required AppStrings strings,
  required bool isInstall,
}) {
  if (result.isSuccess) {
    final warnMsg = result.localizedWarning(strings);
    if (warnMsg != null && warnMsg.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('⚠️ $warnMsg'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.orange.shade800,
          duration: const Duration(seconds: 4),
        ),
      );
    } else {
      final customMsg = result.localizedMessage(strings);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            (customMsg != null && customMsg.isNotEmpty)
                ? customMsg
                : (isInstall ? strings.cliInstallSuccess : strings.cliUninstallSuccess),
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: isInstall ? const Color(0xFF10B981) : null,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  } else if (result.isCancelled) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(strings.cliAuthCancelled),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  } else {
    final detail = result.localizedMessage(strings) ?? '';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isInstall
              ? strings.cliInstallFailed(detail)
              : strings.cliUninstallFailed(detail),
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.redAccent,
        duration: const Duration(seconds: 4),
      ),
    );
  }
}
