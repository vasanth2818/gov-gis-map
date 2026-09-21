import 'package:arcgis_maps/arcgis_maps.dart';
import 'package:gov_gis_map/domain/entities/gis_feature.dart';

abstract class MapRepository {
  Future<List<GisFeature>> getFeatures(String layerUrl);

  Future<ServiceFeatureTable> getServiceFeatureTable(String layerUrl);

  Future<GisFeature> addFeature(
      String layerUrl,
      GisFeature feature, {
        FeatureTable? table,
      });

  Future<void> updateFeature(
      String layerUrl,
      GisFeature feature, {
        FeatureTable? table,
      });

  Future<void> deleteFeature(
      String layerUrl,
      String featureId, {
        FeatureTable? table,
      });

  // Offline workflows
  Future<GenerateOfflineMapJob> generateOfflineMap({
    required ArcGISMap onlineMap,
    required Envelope areaOfInterest,
    required String downloadPath,
    double? currentScale,
  });

  Future<OfflineMapSyncJob> syncOfflineMap(String offlineMapPath);

  Future<ArcGISMap> openOfflineMap(String offlineMapPath);

  Future<void> removeOfflineMap(String offlineMapPath);
}