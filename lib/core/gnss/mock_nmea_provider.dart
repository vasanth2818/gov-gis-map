import 'dart:async';
import 'package:arcgis_maps/arcgis_maps.dart';
import 'package:flutter/foundation.dart';

class MockNmeaProvider implements NmeaDataProvider {
  final StreamController<String> _nmeaStreamController =
  StreamController<String>.broadcast();

  Timer? _timer;

  double _lat = 34.0560;
  double _lon = -118.2440;

  @override
  Stream<String> get nmeaData => _nmeaStreamController.stream;

  void startSimulation() {
    // Prevent multiple timers from running at the same time.
    if (_timer != null && _timer!.isActive) {
      debugPrint('MOCK NMEA: Simulation already running');
      return;
    }

    debugPrint('MOCK NMEA: Simulation started');

    _timer = Timer.periodic(
      const Duration(seconds: 1),
          (timer) {
        // ---------------------------------------------------------
        // 1. Move simulated position
        // ---------------------------------------------------------
        _lat += 0.0001;
        _lon += 0.0001;

        final now = DateTime.now().toUtc();

        final timeStr =
            '${now.hour.toString().padLeft(2, '0')}'
            '${now.minute.toString().padLeft(2, '0')}'
            '${now.second.toString().padLeft(2, '0')}.000';

        // ---------------------------------------------------------
        // 2. Convert latitude to DDMM.MMMM
        // ---------------------------------------------------------
        final latAbs = _lat.abs();
        final latDeg = latAbs.truncate();
        final latMin = (latAbs - latDeg) * 60;

        final latStr =
            '${latDeg.toString().padLeft(2, '0')}'
            '${latMin.toStringAsFixed(4).padLeft(7, '0')}';

        final latDir = _lat >= 0 ? 'N' : 'S';

        // ---------------------------------------------------------
        // 3. Convert longitude to DDDMM.MMMM
        // ---------------------------------------------------------
        final lonAbs = _lon.abs();
        final lonDeg = lonAbs.truncate();
        final lonMin = (lonAbs - lonDeg) * 60;

        final lonStr =
            '${lonDeg.toString().padLeft(3, '0')}'
            '${lonMin.toStringAsFixed(4).padLeft(7, '0')}';

        final lonDir = _lon >= 0 ? 'E' : 'W';

        // ---------------------------------------------------------
        // 4. GPGGA
        //
        // Fix quality:
        // 1 = GPS fix
        //
        // Keep normal GPS for now.
        // We will change this to RTK Fixed later.
        // ---------------------------------------------------------
        final ggaBody =
            'GPGGA,'
            '$timeStr,'
            '$latStr,'
            '$latDir,'
            '$lonStr,'
            '$lonDir,'
            '1,'
            '08,'
            '0.9,'
            '100.0,'
            'M,'
            '0.0,'
            'M,,';

        final ggaSentence = _withChecksum(ggaBody);

        _nmeaStreamController.add(ggaSentence);

        // ---------------------------------------------------------
        // 5. GPGSA
        //
        // 8 ACTIVE satellites:
        // 01 02 03 04 05 06 07 08
        // ---------------------------------------------------------
        final gsaBody =
            'GPGSA,A,3,'
            '01,'
            '02,'
            '03,'
            '04,'
            '05,'
            '06,'
            '07,'
            '08,'
            ',,,,'
            '1.5,'
            '0.9,'
            '1.2';

        final gsaSentence = _withChecksum(gsaBody);

        _nmeaStreamController.add(gsaSentence);

        // ---------------------------------------------------------
        // Debug logs
        // ---------------------------------------------------------
        debugPrint('MOCK NMEA: GGA => $ggaSentence');
        debugPrint('MOCK NMEA: GSA => $gsaSentence');
      },
    );
  }

  void stopSimulation() {
    debugPrint('MOCK NMEA: Simulation stopped');

    _timer?.cancel();
    _timer = null;
  }

  String _withChecksum(String body) {
    int checksum = 0;

    for (int i = 0; i < body.length; i++) {
      checksum ^= body.codeUnitAt(i);
    }

    final hexChecksum =
    checksum.toRadixString(16).toUpperCase().padLeft(2, '0');

    return '\$$body*$hexChecksum\r\n';
  }

  void dispose() {
    stopSimulation();
    _nmeaStreamController.close();
  }
}