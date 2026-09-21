import 'package:flutter_test/flutter_test.dart';
import 'package:gov_gis_map/core/gnss/real_nmea_provider.dart';

import 'nmea_test_data.dart';

void main() {
  test('Inject NMEA data into RealNmeaProvider', () async {
    final realNmeaProvider = RealNmeaProvider();

    final received = <String>[];

    final subscription = realNmeaProvider.nmeaData.listen((nmeaSentence) {
      received.add(nmeaSentence);
    });

    realNmeaProvider.injectTestNmeaData(nmeaTestData);

    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(received, equals(nmeaTestData));

    await subscription.cancel();
    realNmeaProvider.dispose();
  });

  test(
    'NmeaTestInjector injects NMEA sentences into RealNmeaProvider',
    () async {
      final realNmeaProvider = RealNmeaProvider();
      final injector = NmeaTestInjector(realNmeaProvider);

      // Listen to NMEA data stream
      final nmeaData = <String>[];
      final subscription = realNmeaProvider.nmeaData.listen(nmeaData.add);

      // Inject test NMEA data
      injector.injectTestNmeaData();

      // Wait for data to propagate
      await Future.delayed(const Duration(seconds: 1));

      // Verify injected data
      expect(
        nmeaData,
        contains(
          'GPGGA,123519,4807.038,N,01131.000,E,1,08,0.9,545.4,M,46.9,M,,*47',
        ),
      );
      expect(
        nmeaData,
        contains(
          'GPGSA,A,3,04,05,..,..,..,..,..,..,..,..,..,..,1.8,1.0,1.5*33',
        ),
      );

      // Clean up
      await subscription.cancel();
    },
  );
}
