import 'dart:io';

import 'package:arcgis_maps/arcgis_maps.dart';
import 'package:flutter/foundation.dart';

class OfflineMapDataSource {
  Future<GenerateOfflineMapJob> generateOfflineMap({
    required ArcGISMap onlineMap,
    required Envelope areaOfInterest,
    required String downloadPath,
  }) async {
    try {
      final offlineMapTask = OfflineMapTask.withOnlineMap(onlineMap);

      final parameters =
      await offlineMapTask.createDefaultGenerateOfflineMapParameters(
        areaOfInterest: areaOfInterest,
      );

      // The offline map must be backed by sync-enabled geodatabases
      // because the app supports offline editing and manual synchronization.
      parameters.updateMode =
          GenerateOfflineMapUpdateMode.syncWithFeatureServices;
      parameters.includeBasemap = true; // Enable basemap download for offline usability

      // Include attachments for editable layers and upload newly-created
      // attachments when the offline edits are synchronized.
      parameters.returnLayerAttachmentOption =
          ReturnLayerAttachmentOption.editableLayers;
      parameters.attachmentSyncDirection = AttachmentSyncDirection.upload;

      final capabilities = await offlineMapTask.getOfflineMapCapabilities(
        parameters: parameters,
      );

      if (capabilities.hasErrors) {
        final errors = <String>[
          ...capabilities.layerCapabilities.entries.map(
                (entry) =>
            'Layer "${entry.key.name}": ${entry.value.error?.message ?? entry.value}',
          ),
          ...capabilities.tableCapabilities.entries.map(
                (entry) =>
            'Table "${entry.key.tableName}": ${entry.value.error?.message ?? entry.value}',
          ),
        ];

        throw Exception(
          errors.isEmpty
              ? 'Some map content cannot be taken offline.'
              : 'Some map content cannot be taken offline:\n${errors.join('\n')}',
        );
      }

      final directory = Directory(downloadPath);

      // GenerateOfflineMapJob requires the final download directory to be
      // empty. Remove an old download before starting a new one.
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
      await directory.create(recursive: true);
      return offlineMapTask.generateOfflineMap(
        parameters: parameters,
        downloadDirectoryUri: directory.uri,
      );
    } catch (e) {
      debugPrint('Error initiating offline map download: $e');
      rethrow;
    }
  }

  Future<OfflineMapSyncJob> syncOfflineMap(String offlineMapPath) async {
    try {
      final mobileMapPackage =
      MobileMapPackage.withFileUri(Uri.file(offlineMapPath));
      await mobileMapPackage.load();

      if (mobileMapPackage.maps.isEmpty) {
        throw Exception('No maps found in the offline package.');
      }

      final map = mobileMapPackage.maps.first;
      final syncTask = OfflineMapSyncTask.withMap(map);
      final parameters =
      await syncTask.createDefaultOfflineMapSyncParameters();

      // Bidirectional is the SDK default and allows both local uploads and
      // server-side updates to be applied.
      parameters.syncDirection = SyncDirection.bidirectional;

      return syncTask.syncOfflineMap(parameters: parameters);
    } catch (e) {
      debugPrint('Error initiating offline sync: $e');
      rethrow;
    }
  }

  Future<ArcGISMap> openOfflineMap(String path) async {
    final mobileMapPackage = MobileMapPackage.withFileUri(Uri.file(path));
    await mobileMapPackage.load();

    if (mobileMapPackage.maps.isEmpty) {
      throw Exception('No maps found in the offline package.');
    }

    final map = mobileMapPackage.maps.first;
    await map.load();
    return map;
  }

  Future<void> removeOfflineMap(String path) async {
    final directory = Directory(path);
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }
}
