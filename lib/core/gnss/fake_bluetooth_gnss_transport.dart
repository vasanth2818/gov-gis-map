import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

class FakeBluetoothGnssTransport {
  final StreamController<Uint8List> _nmeaStreamController =
      StreamController<Uint8List>.broadcast();

  Stream<Uint8List> get nmeaStream => _nmeaStreamController.stream;

  void start() {
    if (kDebugMode) {
      Timer.periodic(Duration(seconds: 1), (timer) {
        final nmeaSentence = _generateFakeNmeaSentence();
        _nmeaStreamController.add(Uint8List.fromList(nmeaSentence.codeUnits));
      });
    }
  }

  void stop() {
    _nmeaStreamController.close();
  }

  String _generateFakeNmeaSentence() {
    return 'GPGGA,123519,4807.038,N,01131.000,E,1,08,0.9,545.4,M,46.9,M,,*47\r\n';
  }
}
