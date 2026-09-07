import 'package:arcgis_maps/arcgis_maps.dart';
import 'package:gov_gis_map/core/utils/arcgis_extensions.dart';
import 'package:gov_gis_map/data/datasources/remote/arcgis_remote_datasource.dart';
import 'package:gov_gis_map/domain/entities/gis_feature.dart';
import 'package:gov_gis_map/domain/repositories/map_repository.dart';

class MapRepositoryImpl implements MapRepository {
  final ArcGISRemoteDataSource remoteDataSource;

  MapRepositoryImpl(this.remoteDataSource);

  @override
  Future<List<GisFeature>> getFeatures(String layerUrl) async {
    final table = await remoteDataSource.getFeatureTable(layerUrl);
    final queryParams = QueryParameters()..whereClause = "1=1";
    // Fix: Positional argument for queryFeatures
    final result = await table.queryFeatures(queryParams);
    
    return result.features().map((f) => GisFeature(
      id: f.attributes['OBJECTID']?.toString() ?? '',
      geometry: f.geometry,
      attributes: Map<String, dynamic>.from(f.attributes),
    )).toList();
  }

  @override
  Future<ServiceFeatureTable> getServiceFeatureTable(String layerUrl) {
    return remoteDataSource.getFeatureTable(layerUrl);
  }

  @override
  Future<void> addFeature(String layerUrl, GisFeature feature) {
    return remoteDataSource.addFeature(layerUrl, feature);
  }

  @override
  Future<void> updateFeature(String layerUrl, GisFeature feature) {
    return remoteDataSource.updateFeature(layerUrl, feature);
  }

  @override
  Future<void> deleteFeature(String layerUrl, String featureId) {
    return remoteDataSource.deleteFeature(layerUrl, featureId);
  }

  @override
  Future<Job> downloadOfflineMap(Envelope areaOfInterest, String downloadPath) async {
    // Rectification: OfflineMapTask.create (via extension)
    // Using extension name to call static method
    final offlineMapTask = await OfflineMapTaskExtension.create(
      map: ArcGISMap.withBasemapStyle(BasemapStyle.arcGISImageryStandard),
    );
    
    final parameters = await offlineMapTask.createDefaultGenerateOfflineMapParameters(
      areaOfInterest: areaOfInterest,
    );
    
    final job = offlineMapTask.generateOfflineMap(
      parameters: parameters,
      downloadDirectoryUri: Uri.file(downloadPath),
    );
    
    return job;
  }
}
