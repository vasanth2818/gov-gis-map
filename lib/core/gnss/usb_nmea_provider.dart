import 'dart:async';
import 'dart:typed_data';

import 'package:arcgis_maps/arcgis_maps.dart';
import 'package:flutter/foundation.dart';
import 'package:usb_serial/usb_serial.dart';

import 'usb_gnss_transport.dart';

/// Adapts USB serial data to ArcGIS NmeaDataProvider.
class UsbNmeaProvider implements NmeaDataProvider {
  final UsbGnssTransport _transport;

  final StreamController<String> _nmeaStreamController =
      StreamController<String>.broadcast();

  StreamSubscription<Uint8List>? _dataSubscription;

  bool _started = false;
  bool _disposed = false;

  UsbNmeaProvider(this._transport);

  @override
  Stream<String> get nmeaData => _nmeaStreamController.stream;

  bool get isStarted => _started;

  Future<bool> start(UsbDevice device) async {
    if (_disposed) {
      return false;
    }

    try {
      await stop();

      // First subscribe to the transport.
      _dataSubscription = _transport.dataStream.listen(
        (Uint8List data) {
          if (_disposed || _nmeaStreamController.isClosed) {
            return;
          }

          final nmeaData = String.fromCharCodes(data);
          debugPrint('USB GNSS NMEA: $nmeaData');
          _nmeaStreamController.add(nmeaData);
        },
        onError: (error) {
          debugPrint('USB GNSS: NMEA stream error: $error');
        },
        onDone: () {
          debugPrint('USB GNSS: NMEA stream closed');
        },
      );

      final connected = await _transport.connect(device);

      if (!connected) {
        await _dataSubscription?.cancel();
        _dataSubscription = null;
        return false;
      }

      _started = true;
      debugPrint('USB GNSS: NMEA provider started');

      return true;
    } catch (e, stackTrace) {
      debugPrint('USB GNSS: Error starting NMEA provider: $e');
      debugPrint('$stackTrace');

      await _dataSubscription?.cancel();
      _dataSubscription = null;
      _started = false;

      return false;
    }
  }

  Future<void> stop() async {
    try {
      await _dataSubscription?.cancel();
      _dataSubscription = null;

      await _transport.disconnect();

      _started = false;
      debugPrint('USB GNSS: NMEA provider stopped');
    } catch (e) {
      debugPrint('USB GNSS: Error stopping NMEA provider: $e');
    }
  }

  void dispose() {
    if (_disposed) {
      return;
    }

    _disposed = true;
    unawaited(stop());
    _nmeaStreamController.close();
  }
}
