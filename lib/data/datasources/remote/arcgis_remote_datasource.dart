import 'package:arcgis_maps/arcgis_maps.dart';
import 'package:gov_gis_map/domain/entities/gis_feature.dart';
import 'package:flutter/foundation.dart';

class ArcGISRemoteDataSource {
  Future<ServiceFeatureTable> getFeatureTable(String url) async {
    try {
      final trimmedUrl = url.trim();
      if (trimmedUrl.isEmpty || !Uri.parse(trimmedUrl).isAbsolute) {
        throw ArgumentError('Invalid URL provided to FeatureTable: "$trimmedUrl"');
      }
      debugPrint('Attempting to load FeatureTable from: $trimmedUrl');
      final table = ServiceFeatureTable.withUri(Uri.parse(trimmedUrl));
      await table.load();
      return table;
    } catch (e) {
      debugPrint('Error loading feature table at $url: $e');
      rethrow;
    }
  }

  Future<void> addFeature(String url, GisFeature feature) async {
    try {
      final table = await getFeatureTable(url);
      final arcgisFeature = table.createFeature(
        attributes: feature.attributes,
        geometry: feature.geometry,
      ) as ArcGISFeature;

      // Add attachments if any
      for (var file in feature.attachments) {
        final bytes = await file.readAsBytes();
        await arcgisFeature.addAttachment(
          name: file.path.split('/').last,
          contentType: 'image/jpeg', // Defaulting to jpeg for simplicity
          data: bytes,
        );
      }

      // Apply edits to persist to server
      if (table is ServiceFeatureTable) {
        await table.applyEdits();
      }
    } catch (e) {
      debugPrint('Error adding feature: $e');
      rethrow;
    }
  }

  Future<void> updateFeature(String url, GisFeature feature) async {
    final table = await getFeatureTable(url);
    final queryParameters = QueryParameters()..whereClause = "OBJECTID = ${feature.id}";
    final result = await table.queryFeatures(queryParameters);

    if (result.features().isNotEmpty) {
      final arcgisFeature = result.features().first;
      arcgisFeature.geometry = feature.geometry;
      feature.attributes.forEach((key, value) {
        arcgisFeature.attributes[key] = value;
      });
      await table.updateFeature(arcgisFeature);

      await table.applyEdits();
    }
  }

  Future<void> deleteFeature(String url, String featureId) async {
    final table = await getFeatureTable(url);
    final queryParameters = QueryParameters()..whereClause = "OBJECTID = $featureId";
    final result = await table.queryFeatures(queryParameters);

    if (result.features().isNotEmpty) {
      await table.deleteFeature(result.features().first);
      await table.applyEdits();
    }
  }
}
