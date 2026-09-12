import 'package:arcgis_maps/arcgis_maps.dart';
import 'package:gov_gis_map/domain/entities/gis_feature.dart';
import 'package:flutter/foundation.dart';

class ArcGISRemoteDataSource {
  final Map<String, ServiceFeatureTable> _tableCache = {};

  Future<ServiceFeatureTable> getFeatureTable(String url) async {
    final trimmedUrl = url.trim();
    if (trimmedUrl.isEmpty || !Uri.parse(trimmedUrl).isAbsolute) {
      throw ArgumentError('Invalid URL provided to FeatureTable: "$trimmedUrl"');
    }

    final cached = _tableCache[trimmedUrl];
    if (cached != null) {
      debugPrint('Returning cached FeatureTable for: $trimmedUrl');
      return cached;
    }

    try {
      debugPrint('Attempting to load FeatureTable from: $trimmedUrl');
      final table = ServiceFeatureTable.withUri(Uri.parse(trimmedUrl));
      await table.load();
      _tableCache[trimmedUrl] = table;
      return table;
    } catch (e) {
      debugPrint('Error loading feature table at $url: $e');
      rethrow;
    }
  }

  Future<ArcGISFeatureTable> _resolveFeatureTable(
      String url,
      FeatureTable? table,
      ) async {
    if (table is ArcGISFeatureTable) {
      return table;
    }

    if (table != null) {
      throw ArgumentError(
        'Unsupported feature table type: ${table.runtimeType}',
      );
    }

    return getFeatureTable(url);
  }

  Future<void> addFeature(
      String url,
      GisFeature feature, {
        FeatureTable? table,
      }) async {
    try {
      final effectiveTable = await _resolveFeatureTable(url, table);

      if (effectiveTable.loadStatus != LoadStatus.loaded) {
        await effectiveTable.load();
      }

      debugPrint(
        'Creating new ArcGIS feature in ${effectiveTable.runtimeType}...',
      );

      final arcgisFeature = effectiveTable.createFeature(
        attributes: feature.attributes,
        geometry: feature.geometry,
      ) as ArcGISFeature;

      await effectiveTable.addFeature(arcgisFeature);

      if (feature.attachments.isNotEmpty &&
          effectiveTable.hasAttachments &&
          arcgisFeature.canEditAttachments) {
        for (final file in feature.attachments) {
          final bytes = await file.readAsBytes();
          final extension = file.path.split('.').last.toLowerCase();

          final contentType = switch (extension) {
            'jpg' || 'jpeg' => 'image/jpeg',
            'png' => 'image/png',
            'pdf' => 'application/pdf',
            _ => 'application/octet-stream',
          };

          await arcgisFeature.addAttachment(
            name: file.path.split('/').last,
            contentType: contentType,
            data: bytes,
          );
        }
      }

      if (effectiveTable is ServiceFeatureTable) {
        debugPrint('Applying edits to ArcGIS Online...');
        await effectiveTable.applyEdits();
        debugPrint('Feature successfully saved to ArcGIS Online.');
      } else if (effectiveTable is GeodatabaseFeatureTable) {
        debugPrint('Feature added to local geodatabase table.');
      }
    } catch (e, stackTrace) {
      debugPrint('Error adding feature: $e');
      debugPrint('$stackTrace');
      rethrow;
    }
  }

  Future<void> updateFeature(
      String url,
      GisFeature feature, {
        FeatureTable? table,
      }) async {
    try {
      final effectiveTable = await _resolveFeatureTable(url, table);

      if (effectiveTable.loadStatus != LoadStatus.loaded) {
        await effectiveTable.load();
      }

      final objectIdField = effectiveTable.objectIdField;
      final queryParameters = QueryParameters()
        ..whereClause = "$objectIdField = ${feature.id}";

      final result = await effectiveTable.queryFeatures(queryParameters);
      final features = result.features();

      if (features.isEmpty) {
        throw Exception(
          'Feature not found for $objectIdField = ${feature.id}',
        );
      }

      final arcgisFeature = features.first as ArcGISFeature;

      // queryFeatures can return minimally loaded service features.
      // This API exists on ServiceFeatureTable, not on generic FeatureTable.
      if (effectiveTable is ServiceFeatureTable) {
        await effectiveTable.loadOrRefreshFeatures([arcgisFeature]);
      }

      if (feature.geometry != null) {
        arcgisFeature.geometry = feature.geometry;
      }

      final excludedNames = <String>{
        objectIdField,
        effectiveTable.globalIdField,
        'CreationDate',
        'Creator',
        'EditDate',
        'Editor',
        'Shape__Area',
        'Shape__Length',
      };

      final updateAttributes = Map<String, dynamic>.from(feature.attributes);
      updateAttributes.removeWhere(
            (key, value) =>
        excludedNames.contains(key) ||
            key.startsWith('esrignss_') ||
            key.startsWith('esrisnsr_'),
      );

      arcgisFeature.attributes.addAll(updateAttributes);
      await effectiveTable.updateFeature(arcgisFeature);

      if (effectiveTable is ServiceFeatureTable) {
        await effectiveTable.applyEdits();
      } else if (effectiveTable is GeodatabaseFeatureTable) {
        debugPrint('Feature updated in local geodatabase table.');
      }
    } catch (e) {
      debugPrint('Error updating feature: $e');
      rethrow;
    }
  }

  Future<void> deleteFeature(
      String url,
      String featureId, {
        FeatureTable? table,
      }) async {
    try {
      final effectiveTable = await _resolveFeatureTable(url, table);

      if (effectiveTable.loadStatus != LoadStatus.loaded) {
        await effectiveTable.load();
      }

      final objectIdField = effectiveTable.objectIdField;
      final queryParameters = QueryParameters()
        ..whereClause = "$objectIdField = $featureId";

      final result = await effectiveTable.queryFeatures(queryParameters);
      final features = result.features();

      if (features.isEmpty) {
        return;
      }

      await effectiveTable.deleteFeature(features.first);

      if (effectiveTable is ServiceFeatureTable) {
        await effectiveTable.applyEdits();
      } else if (effectiveTable is GeodatabaseFeatureTable) {
        debugPrint('Feature deleted from local geodatabase table.');
      }
    } catch (e) {
      debugPrint('Error deleting feature: $e');
      rethrow;
    }
  }
}
