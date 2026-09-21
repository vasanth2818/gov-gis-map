import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:usb_serial/usb_serial.dart';

class UsbGnssTransport {
  final StreamController<Uint8List> _dataStreamController =
      StreamController<Uint8List>.broadcast();

  UsbPort? _usbPort;
  StreamSubscription<Uint8List>? _usbSubscription;
  bool _connected = false;
  bool _disposed = false;

  Stream<Uint8List> get dataStream => _dataStreamController.stream;

  bool get isConnected => _connected;

  Future<List<UsbDevice>> listDevices() async {
    if (_disposed) {
      return <UsbDevice>[];
    }

    try {
      final devices = await UsbSerial.listDevices();

      debugPrint('USB GNSS: ${devices.length} USB device(s) detected');

      for (final device in devices) {
        debugPrint(
          'USB GNSS DEVICE: '
          '${device.productName ?? device.deviceName} '
          'VID=${device.vid} PID=${device.pid} ID=${device.deviceId}',
        );
      }

      return devices;
    } catch (e, stackTrace) {
      debugPrint('USB GNSS: Device enumeration error: $e');
      debugPrint('$stackTrace');
      return <UsbDevice>[];
    }
  }

  Future<bool> connect(UsbDevice device) async {
    if (_disposed) {
      return false;
    }

    try {
      await disconnect();

      debugPrint(
        'USB GNSS: Connecting to '
        '${device.productName ?? device.deviceName}',
      );

      // usb_serial requests Android USB permission when create() is called
      // if permission has not already been granted.
      final port = await device.create();

      if (port == null) {
        debugPrint('USB GNSS: Could not create USB serial port');
        return false;
      }

      final opened = await port.open();

      if (!opened) {
        debugPrint('USB GNSS: Failed to open USB serial port');
        return false;
      }

      _usbPort = port;

      await port.setDTR(true);
      await port.setRTS(true);

      // Default NMEA serial configuration.
      // Change only the baud rate if the actual receiver requires another one.
      await port.setPortParameters(
        9600,
        UsbPort.DATABITS_8,
        UsbPort.STOPBITS_1,
        UsbPort.PARITY_NONE,
      );

      final inputStream = port.inputStream;

      if (inputStream == null) {
        debugPrint('USB GNSS: USB input stream is null');
        await port.close();
        _usbPort = null;
        return false;
      }

      // Listen before marking the connection ready.
      _usbSubscription = inputStream.listen(
        (Uint8List data) {
          if (_disposed || _dataStreamController.isClosed) {
            return;
          }

          debugPrint('USB GNSS RX: ${String.fromCharCodes(data)}');
          _dataStreamController.add(data);
        },
        onError: (error) {
          debugPrint('USB GNSS: Receive error: $error');
        },
        onDone: () {
          debugPrint('USB GNSS: USB input stream closed');
          _connected = false;
        },
      );

      _connected = true;

      debugPrint(
        'USB GNSS: Connected to '
        '${device.productName ?? device.deviceName}',
      );

      return true;
    } catch (e, stackTrace) {
      debugPrint('USB GNSS: Connection error: $e');
      debugPrint('$stackTrace');

      try {
        await _usbSubscription?.cancel();
        await _usbPort?.close();
      } catch (_) {}

      _usbSubscription = null;
      _usbPort = null;
      _connected = false;

      return false;
    }
  }

  Future<void> disconnect() async {
    try {
      await _usbSubscription?.cancel();
      _usbSubscription = null;

      if (_usbPort != null) {
        await _usbPort!.close();
      }

      _usbPort = null;
      _connected = false;

      debugPrint('USB GNSS: Disconnected');
    } catch (e) {
      debugPrint('USB GNSS: Disconnection error: $e');
    }
  }

  void dispose() {
    if (_disposed) {
      return;
    }

    _disposed = true;
    unawaited(disconnect());
    _dataStreamController.close();
  }
}
