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

    if (_tableCache.containsKey(trimmedUrl)) {
      debugPrint('Returning cached FeatureTable for: $trimmedUrl');
      return _tableCache[trimmedUrl]!;
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

  Future<void> addFeature(String url, GisFeature feature) async {
    try {
      final table = await getFeatureTable(url);

      debugPrint('Creating new ArcGIS feature...');

      final arcgisFeature = table.createFeature(
        attributes: feature.attributes,
        geometry: feature.geometry,
      ) as ArcGISFeature;

      debugPrint('Adding feature to local ServiceFeatureTable...');

      // IMPORTANT:
      // createFeature() only creates the feature in memory.
      // addFeature() adds it to the table's local edit cache.
      await table.addFeature(arcgisFeature);

      debugPrint('Feature added locally.');

      // Add attachments after the feature has been added
      // to the table.
      for (final file in feature.attachments) {
        final bytes = await file.readAsBytes();

        final extension = file.path.split('.').last.toLowerCase();

        String contentType;

        switch (extension) {
          case 'jpg':
          case 'jpeg':
            contentType = 'image/jpeg';
            break;
          case 'png':
            contentType = 'image/png';
            break;
          case 'pdf':
            contentType = 'application/pdf';
            break;
          default:
            contentType = 'application/octet-stream';
        }

        debugPrint(
          'Adding attachment: ${file.path.split('/').last} '
              '($contentType)',
        );

        await arcgisFeature.addAttachment(
          name: file.path.split('/').last,
          contentType: contentType,
          data: bytes,
        );
      }

      debugPrint('Applying edits to ArcGIS Online...');

      final editResults = await table.applyEdits();

      debugPrint(
        'Apply edits completed. Result count: ${editResults.length}',
      );

      debugPrint('Feature successfully saved to ArcGIS Online.');
    } catch (e, stackTrace) {
      debugPrint('Error adding feature: $e');
      debugPrint('$stackTrace');
      rethrow;
    }
  }

  Future<void> updateFeature(String url, GisFeature feature) async {
    final table = await getFeatureTable(url);

    final objectIdField = table.objectIdField;

    final queryParameters = QueryParameters()
      ..whereClause = "$objectIdField = ${feature.id}";

    final result = await table.queryFeatures(queryParameters);

    final features = result.features();

    if (features.isEmpty) {
      throw Exception(
        'Feature not found for $objectIdField = ${feature.id}',
      );
    }

    final arcgisFeature = features.first;

    // IMPORTANT:
    // queryFeatures() can return a minimally loaded feature.
    // Load all attributes and geometry before editing.
    await table.loadOrRefreshFeatures([arcgisFeature]);

    // Update geometry.
    if (feature.geometry != null) {
      arcgisFeature.geometry = feature.geometry;
    }

    // Update only editable application fields.
    final excludedNames = [
      objectIdField,
      table.globalIdField,
      'CreationDate',
      'Creator',
      'EditDate',
      'Editor',
      'Shape__Area',
      'Shape__Length',
    ];

    final updateAttributes =
    Map<String, dynamic>.from(feature.attributes);

    updateAttributes.removeWhere(
          (key, value) =>
      excludedNames.contains(key) ||
          key.startsWith('esrignss_') ||
          key.startsWith('esrisnsr_'),
    );

    arcgisFeature.attributes.addAll(updateAttributes);

    debugPrint('Updating feature ${feature.id}...');
    debugPrint('Attributes: ${arcgisFeature.attributes}');

    await table.updateFeature(arcgisFeature);

    final editResults = await table.applyEdits();

    debugPrint(
      'Feature update completed. Result count: ${editResults.length}',
    );
  }

  Future<void> deleteFeature(String url, String featureId) async {
    final table = await getFeatureTable(url);
    final objectIdField = table.objectIdField;
    final queryParameters = QueryParameters()
      ..whereClause = "$objectIdField = $featureId";
    final result = await table.queryFeatures(queryParameters);

    if (result.features().isNotEmpty) {
      await table.deleteFeature(result.features().first);
      await table.applyEdits();
    }
  }
}
