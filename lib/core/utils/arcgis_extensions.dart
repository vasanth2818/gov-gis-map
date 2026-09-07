import 'package:arcgis_maps/arcgis_maps.dart';

extension FeatureLayerExtension on FeatureLayer {
  static FeatureLayer fromUrl(Uri uri) {
    return FeatureLayer.withFeatureTable(ServiceFeatureTable.withUri(uri));
  }
}

// Type alias for convenience to match prompt's "Point" naming
typedef Point = ArcGISPoint;

extension PointExtension on Point {
  static Point fromLatLng({
    required double latitude,
    required double longitude,
    SpatialReference? spatialReference,
  }) {
    return ArcGISPoint(
      x: longitude,
      y: latitude,
      spatialReference: spatialReference,
    );
  }
}

extension EnvelopeExtension on Envelope {
  static Envelope fromCoordinates({
    required double xmin,
    required double ymin,
    required double xmax,
    required double ymax,
    SpatialReference? spatialReference,
  }) {
    // Fix: Use fromXY instead of unnamed constructor
    return Envelope.fromXY(
      xMin: xmin,
      yMin: ymin,
      xMax: xmax,
      yMax: ymax,
      spatialReference: spatialReference,
    );
  }
}

extension OfflineMapTaskExtension on OfflineMapTask {
  static Future<OfflineMapTask> create({required ArcGISMap map}) async {
    return OfflineMapTask.withOnlineMap(map);
  }
}
