import 'dart:async';
import 'package:arcgis_maps/arcgis_maps.dart';

class MockNmeaProvider implements NmeaDataProvider {
  final StreamController<String> _nmeaStreamController = StreamController<String>.broadcast();
  Timer? _timer;
  double _lat = 34.0560;
  double _lon = -118.2440;

  @override
  Stream<String> get nmeaData => _nmeaStreamController.stream;

  void startSimulation() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      // Walk slightly to simulate motion
      _lat += 0.0001;
      _lon += 0.0001;

      final now = DateTime.now().toUtc();
      final timeStr = '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}.000';

      // Convert decimal degrees to DDMM.MMMM format
      final latDeg = _lat.abs().truncate();
      final latMin = (_lat.abs() - latDeg) * 60;
      final latStr = '${latDeg.toString().padLeft(2, '0')}${latMin.toStringAsFixed(4)}';
      final latDir = _lat >= 0 ? 'N' : 'S';

      final lonDeg = _lon.abs().truncate();
      final lonMin = (_lon.abs() - lonDeg) * 60;
      final lonStr = '${lonDeg.toString().padLeft(3, '0')}${lonMin.toStringAsFixed(4)}';
      final lonDir = _lon >= 0 ? 'E' : 'W';

      // 1. GPGGA sentence: Fix data
      final ggaBody = 'GPGGA,$timeStr,$latStr,$latDir,$lonStr,$lonDir,1,08,0.9,100.0,M,0.0,M,,';
      _nmeaStreamController.add(_withChecksum(ggaBody));

      // 2. GPGSA sentence: Active satellites and DOP values
      final gsaBody = 'GPGSA,A,3,01,02,03,04,05,07,08,09,,,,,1.5,0.9,1.2';
      _nmeaStreamController.add(_withChecksum(gsaBody));
    });
  }

  void stopSimulation() {
    _timer?.cancel();
    _timer = null;
  }

  String _withChecksum(String body) {
    int checksum = 0;
    for (int i = 0; i < body.length; i++) {
      checksum ^= body.codeUnitAt(i);
    }
    final hexChecksum = checksum.toRadixString(16).toUpperCase().padLeft(2, '0');
    return '\$$body*$hexChecksum\r\n';
  }
}
