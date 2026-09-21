import 'package:arcgis_maps/arcgis_maps.dart';
import 'package:gov_gis_map/data/datasources/local/offline_map_datasource.dart';
import 'package:gov_gis_map/data/datasources/remote/arcgis_remote_datasource.dart';
import 'package:gov_gis_map/domain/entities/gis_feature.dart';
import 'package:gov_gis_map/domain/repositories/map_repository.dart';

class MapRepositoryImpl implements MapRepository {
  final ArcGISRemoteDataSource remoteDataSource;
  final OfflineMapDataSource offlineDataSource;

  MapRepositoryImpl(this.remoteDataSource, this.offlineDataSource);

  @override
  Future<List<GisFeature>> getFeatures(String layerUrl) async {
    final table = await remoteDataSource.getFeatureTable(layerUrl);

    final queryParams = QueryParameters()..whereClause = '1=1';

    final result = await table.queryFeatures(queryParams);

    return result.features().map((f) {
      return GisFeature(
        id: f.attributes['OBJECTID']?.toString() ?? '',
        geometry: f.geometry,
        attributes: Map<String, dynamic>.from(f.attributes),
      );
    }).toList();
  }

  @override
  Future<ServiceFeatureTable> getServiceFeatureTable(String layerUrl) {
    return remoteDataSource.getFeatureTable(layerUrl);
  }

  @override
  Future<GisFeature> addFeature(
    String layerUrl,
    GisFeature feature, {
    FeatureTable? table,
  }) async {
    return await remoteDataSource.addFeature(layerUrl, feature, table: table);
  }

  @override
  Future<void> updateFeature(
    String layerUrl,
    GisFeature feature, {
    FeatureTable? table,
  }) {
    return remoteDataSource.updateFeature(layerUrl, feature, table: table);
  }

  @override
  Future<void> deleteFeature(
    String layerUrl,
    String featureId, {
    FeatureTable? table,
  }) {
    return remoteDataSource.deleteFeature(layerUrl, featureId, table: table);
  }

  @override
  Future<GenerateOfflineMapJob> generateOfflineMap({
    required ArcGISMap onlineMap,
    required Envelope areaOfInterest,
    required String downloadPath,
    double? currentScale,
  }) {
    return offlineDataSource.generateOfflineMap(
      onlineMap: onlineMap,
      areaOfInterest: areaOfInterest,
      downloadPath: downloadPath,
      currentScale: currentScale,
    );
  }

  @override
  Future<OfflineMapSyncJob> syncOfflineMap(String offlineMapPath) {
    return offlineDataSource.syncOfflineMap(offlineMapPath);
  }

  @override
  Future<ArcGISMap> openOfflineMap(String offlineMapPath) {
    return offlineDataSource.openOfflineMap(offlineMapPath);
  }

  @override
  Future<void> removeOfflineMap(String offlineMapPath) {
    return offlineDataSource.removeOfflineMap(offlineMapPath);
  }
}
