import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:paperless_mobile/core/service/file_service.dart';
import 'package:path/path.dart' as p;

part 'receive_share_state.dart';

class ConsumptionChangeNotifier extends ChangeNotifier {
  List<File> pendingFiles = [];

  final Completer _restored = Completer();

  Future<void> get isInitialized => _restored.future;

  /// Sanitizes a file name by replacing directory separators and illegal characters (#437).
  static String sanitizeFileName(String fileName) {
    return fileName.replaceAll(RegExp(r'[/\\?%*:|"<>]+'), '_');
  }

  Future<void> loadFromConsumptionDirectory({required String userId}) async {
    pendingFiles = await _getCurrentFiles(userId);
    if (!_restored.isCompleted) {
      _restored.complete();
    }
    notifyListeners();
  }

  /// Creates a local copy of all shared files and reloads all files
  /// from the user's consumption directory. Returns the newly added files copied to the consumption directory.
  Future<List<File>> addFiles({
    required List<File> files,
    required String userId,
  }) async {
    if (files.isEmpty) {
      return [];
    }
    final consumptionDirectory = await FileService.instance
        .getConsumptionDirectory(userId: userId);
    if (!await consumptionDirectory.exists()) {
      await consumptionDirectory.create(recursive: true);
    }
    final List<File> localFiles = [];
    for (final file in files) {
      if (!file.path.startsWith(consumptionDirectory.path)) {
        try {
          final sanitizedName = sanitizeFileName(p.basename(file.path));
          final destinationPath = p.join(
            consumptionDirectory.path,
            sanitizedName,
          );
          final localFile = await file.copy(destinationPath);
          localFiles.add(localFile);
        } catch (_) {
          // If copy fails with sanitized basename, try ensuring parent and retry
          try {
            final fallbackFile = File(
              p.join(
                consumptionDirectory.path,
                'shared_${DateTime.now().millisecondsSinceEpoch}_${p.extension(file.path)}',
              ),
            );
            localFiles.add(await file.copy(fallbackFile.path));
          } catch (_) {}
        }
      } else {
        localFiles.add(file);
      }
    }
    await loadFromConsumptionDirectory(userId: userId);
    return localFiles;
  }

  /// Marks a file as processed by removing it from the queue and deleting the local copy of the file.
  Future<void> discardFile(File file, {required String userId}) async {
    final consumptionDirectory = await FileService.instance
        .getConsumptionDirectory(userId: userId);
    if (file.path.startsWith(consumptionDirectory.path)) {
      await file.delete();
    }
    return loadFromConsumptionDirectory(userId: userId);
  }

  /// Returns the next file to process of null if no file exists.
  Future<File?> getNextFile({required String userId}) async {
    final files = await _getCurrentFiles(userId);
    if (files.isEmpty) {
      return null;
    }
    return files.first;
  }

  Future<List<File>> _getCurrentFiles(String userId) async {
    final directory = await FileService.instance.getConsumptionDirectory(
      userId: userId,
    );
    return await FileService.instance.getAllFiles(directory);
  }
}
