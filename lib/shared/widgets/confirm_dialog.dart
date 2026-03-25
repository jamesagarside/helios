import 'package:flutter/material.dart';
import '../theme/helios_colors.dart';

/// Shows a confirmation dialog for critical vehicle commands.
///
/// Returns `true` if user confirmed, `false` if cancelled.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool isDangerous = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      backgroundColor: HeliosColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: HeliosColors.border),
      ),
      title: Row(
        children: [
          Icon(
            isDangerous ? Icons.warning_amber_rounded : Icons.info_outline,
            color: isDangerous ? HeliosColors.warning : HeliosColors.accent,
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              color: HeliosColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      content: Text(
        message,
        style: const TextStyle(
          color: HeliosColors.textSecondary,
          fontSize: 14,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(
            cancelLabel,
            style: const TextStyle(color: HeliosColors.textSecondary),
          ),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          style: ElevatedButton.styleFrom(
            backgroundColor:
                isDangerous ? HeliosColors.dangerDim : HeliosColors.accentDim,
            foregroundColor: HeliosColors.textPrimary,
          ),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Confirm arm/disarm action.
Future<bool> confirmArm(BuildContext context, {required bool arm}) {
  return showConfirmDialog(
    context,
    title: arm ? 'Arm Vehicle' : 'Disarm Vehicle',
    message: arm
        ? 'Are you sure you want to arm the vehicle? Motors will spin.'
        : 'Are you sure you want to disarm? Vehicle will lose thrust.',
    confirmLabel: arm ? 'Arm' : 'Disarm',
    isDangerous: true,
  );
}

/// Confirm flight mode change.
Future<bool> confirmModeChange(BuildContext context, String modeName) {
  return showConfirmDialog(
    context,
    title: 'Change Mode',
    message: 'Switch flight mode to $modeName?',
    confirmLabel: 'Change',
  );
}

/// Confirm mission upload.
Future<bool> confirmMissionUpload(BuildContext context, int waypointCount) {
  return showConfirmDialog(
    context,
    title: 'Upload Mission',
    message: 'Upload $waypointCount waypoints to the vehicle?',
    confirmLabel: 'Upload',
  );
}

/// Confirm mission clear.
Future<bool> confirmMissionClear(BuildContext context) {
  return showConfirmDialog(
    context,
    title: 'Clear Mission',
    message: 'Remove all waypoints from the vehicle?',
    confirmLabel: 'Clear',
    isDangerous: true,
  );
}
