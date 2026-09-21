import 'dart:async';
import 'dart:typed_data';

import 'package:arcgis_maps/arcgis_maps.dart';
import 'package:bluetooth_classic/bluetooth_classic.dart';
import 'package:bluetooth_classic/models/device.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class RealNmeaProvider implements NmeaDataProvider {
  final BluetoothClassic _bluetooth = BluetoothClassic();

  static const MethodChannel _platformChannel =
  MethodChannel('com.example.gov_gis_map/location_settings');

  final StreamController<String> _nmeaStreamController =
  StreamController<String>.broadcast();

  StreamSubscription<Uint8List>? _dataSubscription;
  StreamSubscription<int>? _statusSubscription;

  final StringBuffer _buffer = StringBuffer();

  bool _connected = false;
  bool _disposed = false;

  Future<bool>? _bluetoothInitialization;


  StreamSubscription<Device>? _discoveredDeviceSubscription;

  final StreamController<Device> _discoveredDeviceController =
  StreamController<Device>.broadcast();

  Stream<Device> get discoveredDevices =>
      _discoveredDeviceController.stream;

  bool _discoveryStarted = false;
  /// Standard Bluetooth Classic Serial Port Profile UUID.
  static const String serialPortServiceUuid =
      '00001101-0000-1000-8000-00805f9b34fb';

  @override
  Stream<String> get nmeaData => _nmeaStreamController.stream;

  bool get isConnected => _connected;

  /// Inject NMEA manually for testing.
  void addNmeaSentence(String sentence) {
    if (_disposed || _nmeaStreamController.isClosed) {
      return;
    }

    final value = sentence.trim();

    if (value.isEmpty) {
      return;
    }

    _nmeaStreamController.add(value);
  }

  /// Test helper.
  void injectTestNmeaData(List<String> nmeaSentences) {
    for (final sentence in nmeaSentences) {
      addNmeaSentence(sentence);
    }
  }

  /// Returns true only when the Android Bluetooth adapter is ON.
  Future<bool> isBluetoothEnabled() async {
    if (_disposed) {
      return false;
    }

    try {
      final enabled = await _platformChannel.invokeMethod<bool>(
        'isBluetoothEnabled',
      );

      debugPrint(
        'GNSS Bluetooth enabled: $enabled',
      );

      return enabled ?? false;
    } on PlatformException catch (e) {
      debugPrint(
        'GNSS Bluetooth state error: '
            '${e.code} - ${e.message}',
      );

      return false;
    } catch (e) {
      debugPrint(
        'GNSS Bluetooth state unexpected error: $e',
      );

      return false;
    }
  }

  /// Initialize Bluetooth permissions.
  Future<bool> initializeBluetooth() {
    if (_disposed) {
      return Future.value(false);
    }

    // If initialization is already running, wait for the same operation.
    if (_bluetoothInitialization != null) {
      return _bluetoothInitialization!;
    }

    _bluetoothInitialization = _initializeBluetoothInternal();

    return _bluetoothInitialization!;
  }

  Future<bool> _initializeBluetoothInternal() async {
    try {
      final result = await _bluetooth.initPermissions();

      debugPrint(
        'GNSS Bluetooth initialization result: $result',
      );

      return result;
    } catch (e) {
      debugPrint(
        'GNSS Bluetooth permission error: $e',
      );

      return false;
    } finally {
      _bluetoothInitialization = null;
    }
  }

  /// Get already paired Bluetooth devices.
  Future<List<Device>> getPairedDevices() async {
    if (_disposed) {
      return <Device>[];
    }

    try {
      return await _bluetooth.getPairedDevices();
    } catch (e) {
      debugPrint('GNSS get paired devices error: $e');
      return <Device>[];
    }
  }

  /// Connect to external GNSS receiver.
  Future<bool> connectToDevice(Device device) async {
    if (_disposed) {
      return false;
    }

    try {
      await disconnect();

      debugPrint(
        'GNSS: Connecting to '
            '${device.name ?? 'Unknown device'} '
            '(${device.address})',
      );

      // Start listening before the receiver is connected.
      _startListening();

      final connected = await _bluetooth.connect(
        device.address,
        serialPortServiceUuid,
      );

      if (!connected) {
        debugPrint('GNSS: Bluetooth connection failed');

        //await _stopListening();

        return false;
      }

      _connected = true;

      debugPrint(
        'GNSS: Connected to '
            '${device.name ?? 'Unknown device'}',
      );

      return true;
    } catch (e) {
      debugPrint('GNSS: Connection error: $e');

      _connected = false;

     // await _stopListening();

      return false;
    }
  }

  Future<void> _stopListening() async {
    // Do NOT cancel the Bluetooth plugin streams here.
    //
    // These subscriptions are kept alive for the lifetime
    // of RealNmeaProvider to avoid:
    //
    // Bad state: Stream has already been listened to.

    return;
  }

  // Future<void> _stopListening() async {
  //   await _dataSubscription?.cancel();
  //   _dataSubscription = null;
  //
  //   await _statusSubscription?.cancel();
  //   _statusSubscription = null;
  // }

  void _startListening() {
    // IMPORTANT:
    // bluetooth_classic streams should not be listened to repeatedly.
    // Keep the existing subscriptions if they are already active.

    if (_dataSubscription == null) {
      _dataSubscription = _bluetooth.onDeviceDataReceived().listen(
        _handleBluetoothData,
        onError: (error) {
          debugPrint('GNSS Bluetooth data error: $error');
          _connected = false;
        },
        onDone: () {
          debugPrint('GNSS Bluetooth data stream closed');
          _connected = false;
        },
      );
    }

    if (_statusSubscription == null) {
      _statusSubscription = _bluetooth.onDeviceStatusChanged().listen(
            (status) {
          debugPrint('GNSS Bluetooth status: $status');

          if (status == Device.disconnected) {
            _connected = false;
          } else if (status == Device.connected) {
            _connected = true;
          }
        },
        onError: (error) {
          debugPrint('GNSS Bluetooth status error: $error');
        },
      );
    }
  }

  // void _startListening() {
  //   _dataSubscription?.cancel();
  //
  //   _dataSubscription = _bluetooth.onDeviceDataReceived().listen(
  //     _handleBluetoothData,
  //     onError: (error) {
  //       debugPrint('GNSS Bluetooth data error: $error');
  //       _connected = false;
  //     },
  //     onDone: () {
  //       debugPrint('GNSS Bluetooth data stream closed');
  //       _connected = false;
  //     },
  //   );
  //
  //   _statusSubscription?.cancel();
  //
  //   _statusSubscription = _bluetooth.onDeviceStatusChanged().listen(
  //         (status) {
  //       debugPrint('GNSS Bluetooth status: $status');
  //
  //       if (status == Device.disconnected) {
  //         _connected = false;
  //       } else if (status == Device.connected) {
  //         _connected = true;
  //       }
  //     },
  //     onError: (error) {
  //       debugPrint('GNSS Bluetooth status error: $error');
  //     },
  //   );
  // }

  /// Bluetooth packets can contain:
  ///
  /// 1. One complete NMEA sentence
  /// 2. Multiple sentences
  /// 3. Half of a sentence
  ///
  /// Therefore we MUST buffer the incoming bytes.
  void _handleBluetoothData(Uint8List data) {
    if (_disposed || data.isEmpty) {
      return;
    }

    final chunk = String.fromCharCodes(data);

    debugPrint(
      'GNSS RX: '
          '${chunk.replaceAll('\r', '\\r').replaceAll('\n', '\\n')}',
    );

    _buffer.write(chunk);

    final buffered = _buffer.toString();

    final parts = buffered.split('\n');

    _buffer
      ..clear()
      ..write(parts.removeLast());

    for (final part in parts) {
      final sentence = part.trim();

      if (sentence.isEmpty) {
        continue;
      }

      _emitNmeaSentence(sentence);
    }
  }

  void _emitNmeaSentence(String sentence) {
    if (_nmeaStreamController.isClosed) {
      return;
    }

    debugPrint('GNSS NMEA: $sentence');

    _nmeaStreamController.add(sentence);
  }

  Future<void> disconnect() async {
    try {
      if (_connected) {
        await _bluetooth.disconnect();
      }
    } catch (e) {
      debugPrint('GNSS disconnect error: $e');
    } finally {
      _connected = false;
      _buffer.clear();
    }
  }

  // Future<void> disconnect() async {
  //   try {
  //     await _stopListening();
  //
  //     if (_connected) {
  //       await _bluetooth.disconnect();
  //     }
  //   } catch (e) {
  //     debugPrint('GNSS disconnect error: $e');
  //   } finally {
  //     _connected = false;
  //     _buffer.clear();
  //   }
  // }
  void dispose() {
    if (_disposed) {
      return;
    }

    _disposed = true;

    _disposeAsync();
  }

  void initializeDiscoveryListener() {
    if (_discoveryStarted || _disposed) {
      return;
    }

    _discoveryStarted = true;

    _discoveredDeviceSubscription =
        _bluetooth.onDeviceDiscovered().listen(
              (device) {
            debugPrint(
              'GNSS Bluetooth discovered: '
                  '${device.name ?? 'Unknown'} (${device.address})',
            );

            if (!_discoveredDeviceController.isClosed) {
              _discoveredDeviceController.add(device);
            }
          },
          onError: (error) {
            debugPrint(
              'GNSS Bluetooth discovery error: $error',
            );
          },
        );
  }

  Future<bool> startDeviceScan() async {
    if (_disposed) return false;

    try {
      initializeDiscoveryListener();

      debugPrint('GNSS: Starting Bluetooth device scan');

      final result = await _bluetooth.startScan();

      debugPrint(
        'GNSS: Bluetooth scan started: $result',
      );

      return result;
    } catch (e) {
      debugPrint(
        'GNSS: Bluetooth scan failed: $e',
      );
      return false;
    }
  }
  Future<void> stopDeviceScan() async {
    try {
      await _bluetooth.stopScan();
      debugPrint('GNSS: Bluetooth scan stopped');
    } catch (e) {
      debugPrint(
        'GNSS: Bluetooth stop scan error: $e',
      );
    }
  }

  Future<void> _disposeAsync() async {
    try {
      await _dataSubscription?.cancel();
      await _statusSubscription?.cancel();

      _dataSubscription = null;
      _statusSubscription = null;

      if (_connected) {
        await _bluetooth.disconnect();
      }
    } catch (e) {
      debugPrint('GNSS dispose error: $e');
    } finally {
      _connected = false;
      _buffer.clear();

      if (!_nmeaStreamController.isClosed) {
        await _nmeaStreamController.close();
      }
    }
  }
}

class NmeaTestInjector {
  final RealNmeaProvider realNmeaProvider;

  NmeaTestInjector(this.realNmeaProvider);

  void injectTestNmeaData() {
    final testNmeaSentences = [
      // Valid NMEA 0183 sentences for ArcGIS NMEA pipeline testing.
      r'$GPGGA,123519,4807.038,N,01131.000,E,1,08,0.9,545.4,M,46.9,M,,*47',
      r'$GPGSA,A,3,04,05,09,12,24,25,29,31,,,,,1.8,1.0,1.5*3D',
    ];

    for (final sentence in testNmeaSentences) {
      realNmeaProvider.addNmeaSentence(sentence);
    }
  }
}
