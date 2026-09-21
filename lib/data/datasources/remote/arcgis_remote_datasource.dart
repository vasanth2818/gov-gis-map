import 'package:arcgis_maps/arcgis_maps.dart';
import 'package:gov_gis_map/domain/entities/gis_feature.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'dart:developer';

class ArcGISRemoteDataSource {
  final Map<String, ServiceFeatureTable> _tableCache = {};

  Future<ServiceFeatureTable> getFeatureTable(String url) async {
    final trimmedUrl = url.trim();
    if (trimmedUrl.isEmpty || !Uri.parse(trimmedUrl).isAbsolute) {
      throw ArgumentError('Invalid URL provided to FeatureTable: "$trimmedUrl"');
    }

    final cached = _tableCache[trimmedUrl];
    if (cached != null) {
      log('Returning cached FeatureTable for: $trimmedUrl');
      return cached;
    }

    try {
      log('Attempting to load FeatureTable from: $trimmedUrl');
      final credentials = ArcGISEnvironment
          .authenticationManager
          .arcGISCredentialStore
          .getCredentials();

      log('========== SERVICE AUTH DEBUG ==========');
      log('Credential count = ${credentials.length}');

      for (final credential in credentials) {
        log(
          'Credential type = ${credential.runtimeType}',
        );

        if (credential is OAuthUserCredential) {
          log(
            'OAuth username = ${credential.username}',
          );
        }
      }

      log('========================================');

      final serviceUri = Uri.parse(trimmedUrl);

      final matchedCredential = ArcGISEnvironment
          .authenticationManager
          .arcGISCredentialStore
          .getCredential(
        uri: serviceUri,
      );

      log('========== SERVICE CREDENTIAL MATCH ==========');
      log('Service URI       = $serviceUri');
      log('Matched credential = ${matchedCredential?.runtimeType}');
      if (matchedCredential is OAuthUserCredential) {
        log('Matched username  = ${matchedCredential.username}');
      }
      log('==============================================');

      final table = ServiceFeatureTable.withUri(Uri.parse(trimmedUrl));
      await table.load();
      log('SERVICE TABLE USERNAME = ${table.username}');
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

  Future<GisFeature> addFeature(
      String url,
      GisFeature feature, {
        FeatureTable? table,
      }) async {
    try {
      final effectiveTable = await _resolveFeatureTable(url, table);

      if (effectiveTable.loadStatus != LoadStatus.loaded) {
        await effectiveTable.load();
      }

      log('==========================================');;
      log('FEATURE TABLE URL       = $url');
      log('FEATURE TABLE NAME      = ${effectiveTable.tableName}');
      log('FEATURE TABLE USERNAME  = ${effectiveTable.username}');
      log('FEATURE TABLE TYPE      = ${effectiveTable.runtimeType}');('==========================================');

      debugPrint(
        'Creating new ArcGIS feature in ${effectiveTable.runtimeType}...',
      );

// ============================================================
// CREATE FEATURE DEBUG
// ============================================================
      debugPrint('========== CREATE FEATURE DEBUG ==========');
      debugPrint('Table type : ${effectiveTable.runtimeType}');
      debugPrint('Table hase application manifest');
      debugPrint('Table hasM : ${effectiveTable.hasM}');
      debugPrint('Geometry type : ${feature.geometry.runtimeType}');

      if (feature.geometry is ArcGISPoint) {
        final point = feature.geometry as ArcGISPoint;

        debugPrint('X / Longitude : ${point.x}');
        debugPrint('Y / Latitude  : ${point.y}');
        debugPrint('Z             : ${point.z}');
      }

      debugPrint('==========================================');

      Geometry? geometry = feature.geometry;

      debugPrint('========== GEOMETRY NORMALIZATION ==========');
      debugPrint('Table hasZ : ${effectiveTable.hasZ}');
      debugPrint('Geometry hasZ : ${geometry?.hasZ}');
      debugPrint('Geometry type : ${geometry.runtimeType}');

      if (!(effectiveTable?.hasZ ?? false) && (geometry?.hasZ ?? false)) {
        debugPrint('Removing Z because target table is 2D.');

        if (geometry is ArcGISPoint) {
          final point = geometry;

          geometry = ArcGISPoint(
            x: point.x,
            y: point.y,
            spatialReference: point.spatialReference,
          );
        }
      }

      debugPrint('Final geometry hasZ : ${geometry?.hasZ}');
      debugPrint('============================================');

      final arcgisFeature = effectiveTable.createFeature(
        attributes: feature.attributes,
        geometry: geometry,
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

        final editResults = await effectiveTable.applyEdits();

        if (editResults.isEmpty) {
          throw Exception(
            'ArcGIS did not return an edit result after adding the feature.',
          );
        }

        final editResult = editResults.first;

        debugPrint('========== ADD FEATURE RESULT ==========');
        debugPrint('Object ID: ${editResult.objectId}');
        debugPrint('Global ID: ${editResult.globalId}');
        debugPrint('Has errors: ${editResult.completedWithErrors}');
        debugPrint('========================================');

        if (editResult.completedWithErrors) {
          throw editResult.error ??
              Exception('ArcGIS failed to add the feature.');
        }

        if (editResult.objectId < 0) {
          throw Exception(
            'Invalid OBJECTID returned by ArcGIS: ${editResult.objectId}',
          );
        }

        return GisFeature(
          id: editResult.objectId.toString(),
          geometry: feature.geometry,
          attributes: Map<String, dynamic>.from(feature.attributes),
          attachments: List<File>.from(feature.attachments),
        );
      } else if (effectiveTable is GeodatabaseFeatureTable) {
        debugPrint('Feature added to local geodatabase table.');

        return feature;
      }

      return feature;
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
