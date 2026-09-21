import 'package:flutter_test/flutter_test.dart';
import 'package:arcgis_maps/arcgis_maps.dart';
import 'package:gov_gis_map/core/gnss/real_nmea_provider.dart';

void main() {
  test('NmeaLocationDataSource processes injected NMEA sentences', () async {
    final realNmeaProvider = RealNmeaProvider();

    final nmeaLocationDataSource = NmeaLocationDataSource.withProvider(
      realNmeaProvider,
    );

    final nmeaTestInjector = NmeaTestInjector(realNmeaProvider);

    final locationUpdates = <Location>[];
    final satelliteUpdates = <SatelliteInfo>[];
    final receivedSentences = <String>[];

    nmeaLocationDataSource.onLocationChanged.listen(locationUpdates.add);

    nmeaLocationDataSource.onSatellitesChanged.listen(satelliteUpdates.add);

    nmeaLocationDataSource.onSentenceReceived.listen(receivedSentences.add);

    await nmeaLocationDataSource.start();

    nmeaTestInjector.injectTestNmeaData();

    await Future.delayed(const Duration(seconds: 1));

    expect(
      receivedSentences,
      isNotEmpty,
      reason: 'ArcGIS should receive the injected NMEA sentences.',
    );

    expect(
      locationUpdates,
      isNotEmpty,
      reason: 'ArcGIS should generate a location from GGA.',
    );

    expect(
      satelliteUpdates,
      isNotEmpty,
      reason: 'ArcGIS should generate satellite information from GSA.',
    );

    final location = locationUpdates.last;
    final satellites = satelliteUpdates.last;

    print('TEST LOCATION: $location');
    print('TEST SATELLITES: $satellites');
    print('TEST SENTENCES: $receivedSentences');

    nmeaLocationDataSource.stop();
    realNmeaProvider.dispose();
  });
}
