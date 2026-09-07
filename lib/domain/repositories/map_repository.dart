import 'package:arcgis_maps/arcgis_maps.dart';
import 'package:gov_gis_map/domain/entities/gis_feature.dart';

abstract class MapRepository {
  Future<List<GisFeature>> getFeatures(String layerUrl);
  Future<void> addFeature(String layerUrl, GisFeature feature);
  Future<void> updateFeature(String layerUrl, GisFeature feature);
  Future<void> deleteFeature(String layerUrl, String featureId);
  
  // Offline workflows
  Future<Job> downloadOfflineMap(Envelope areaOfInterest, String downloadPath);
}
