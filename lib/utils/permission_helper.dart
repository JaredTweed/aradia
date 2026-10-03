import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/material.dart';

import '../resources/designs/app_colors.dart';

@immutable
class PermissionHelper {
  const PermissionHelper._();

  static Future<bool> requestStorageAndMediaPermissions() async {
    PermissionStatus storageStatus;
    PermissionStatus photoStatus;

    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      if (androidInfo.version.sdkInt >= 33) {
        photoStatus = await Permission.photos.status;
        if (!photoStatus.isGranted) {
          photoStatus = await Permission.photos.request();
        }

        return photoStatus.isGranted;
      } else {
        storageStatus = await Permission.storage.status;
        if (!storageStatus.isGranted) {
          storageStatus = await Permission.storage.request();
        }
        return storageStatus.isGranted;
      }
    } else if (Platform.isIOS) {
      photoStatus = await Permission.photos.status;
      if (!photoStatus.isGranted) {
        photoStatus = await Permission.photos.request();
      }

      return photoStatus.isGranted;
    }
    return true;
  }

  static Future<bool> openAppSettingsPage() async {
    return await openAppSettings();
  }

  /// Download permission handler - only requests notification permission for Android 13+
  /// Since we're downloading to app's external storage, no storage permissions needed
  /// Returns true if all required permissions are granted
  static Future<bool> requestDownloadPermissions() async {
    final androidInfo = await DeviceInfoPlugin().androidInfo;
    final sdkInt = androidInfo.version.sdkInt;

    if (sdkInt >= 33) {
      // Android 13+ - Only request notification permission for download notifications
      final notification = await Permission.notification.status;
      if (notification.isDenied) {
        final result = await Permission.notification.request();
        return result.isGranted;
      }
      return notification.isGranted;
    }
    // Android 12 and below - No permissions needed for app external storage
    return true;
  }

  /// Shows a user-friendly permission dialog for download permissions
  /// Returns true if user grants permission, false otherwise
  static Future<bool> handleDownloadPermissionWithDialog(
      BuildContext context) async {
    final hasPermission = await requestDownloadPermissions();

    if (hasPermission) {
      return true;
    }

    // Show dialog to explain why we need notification permissions (Android 13+ only)
    if (!context.mounted) return false;

    final androidInfo = await DeviceInfoPlugin().androidInfo;
    final sdkInt = androidInfo.version.sdkInt;

    if (!context.mounted) return false;
    if (sdkInt >= 33) {
      final shouldOpenSettings = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(
                Icons.notifications_rounded,
                color: AppColors.primaryColor,
                size: 28,
              ),
              const SizedBox(width: 12),
              const Text('Notification Permission Required'),
            ],
          ),
          content: const Text(
            'To show download progress notifications, we need notification permission.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryColor,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Open Settings'),
            ),
          ],
        ),
      );

      if (shouldOpenSettings == true) {
        await openAppSettings();
      }

      return false;
    }

    // For Android 12 and below, no permissions needed
    return true;
  }
}
