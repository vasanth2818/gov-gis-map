import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:arcgis_maps/arcgis_maps.dart';
import 'package:arcgis_maps_toolkit/arcgis_maps_toolkit.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:gov_gis_map/core/utils/arcgis_extensions.dart';
import 'package:gov_gis_map/features/map/domain/entities/gis_feature.dart';
import 'package:gov_gis_map/features/map/presentation/map/bloc/map_bloc.dart';
import 'package:gov_gis_map/core/gnss/mock_nmea_provider.dart';
import 'package:gov_gis_map/core/gnss/real_nmea_provider.dart';
import 'package:gov_gis_map/features/map/presentation/map/widgets/gnss_status_widget.dart';
import 'package:usb_serial/usb_serial.dart';
import 'package:gov_gis_map/core/gnss/usb_gnss_transport.dart';
import 'package:gov_gis_map/core/gnss/usb_nmea_provider.dart';

import 'dart:async';

import 'package:bluetooth_classic/bluetooth_classic.dart';
import 'package:bluetooth_classic/models/device.dart';

class MapPage extends StatefulWidget {
  final PortalItem? portalItem;
  const MapPage({super.key, this.portalItem});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  ArcGISMapViewController? _mapController;
  //final _mapController = ArcGISMapView.createController();

  StreamSubscription? _locationSubscription;
  StreamSubscription? _satellitesSubscription;
  StreamSubscription? _statusSubscription;

  final _locationDataSource = SystemLocationDataSource();
  NmeaLocationDataSource? _mockGnssDataSource;
  NmeaLocationDataSource? _realGnssDataSource;
  NmeaLocationDataSource? _usbGnssDataSource;
  final _mockNmeaProvider = MockNmeaProvider();
  late RealNmeaProvider _realNmeaProvider;
  bool _locationStarted = false;
  late ArcGISMap _map;
  late LocationDataSource _currentLocationDataSource;
  late UsbGnssTransport _usbGnssTransport;
  late UsbNmeaProvider _usbNmeaProvider;

  UsbDevice? _selectedUsbDevice;

  static final _locationChannel = MethodChannel(
    'com.example.gov_gis_map/location_settings',
  );

  String? _locationStatus = 'Initializing...';
  final String _layerUrl =
      'https://services8.arcgis.com/OFjCtQPTf3SnshL1/arcgis/rest/services/Pole/FeatureServer/0';

  ArcGISLocation? _lastKnownLocation;
  int _satelliteCount = 0;
  String _fixType = 'System GPS';
  double _accuracy = 0.0;
  String _gnssReceiverName = 'Device GPS';
  StreamSubscription<String>? _mockNmeaSubscription;

  @override
  void initState() {
    super.initState();

    debugPrint('Initializing MapPage');

    _currentLocationDataSource = _locationDataSource;

    _realNmeaProvider = RealNmeaProvider();

    _mockGnssDataSource = NmeaLocationDataSource.withProvider(
      () => _mockNmeaProvider,
    );

    _realGnssDataSource = NmeaLocationDataSource.withProvider(
      () => _realNmeaProvider,
    );
    _usbGnssTransport = UsbGnssTransport();

    _usbNmeaProvider = UsbNmeaProvider(_usbGnssTransport);

    _usbGnssDataSource = NmeaLocationDataSource.withProvider(
      () => _usbNmeaProvider,
    );

    _initMap();
  }

  void _initMap() {
    if (widget.portalItem != null) {
      _map = ArcGISMap.withItem(widget.portalItem!);
    } else {
      _map = ArcGISMap.withBasemapStyle(BasemapStyle.arcGISImageryStandard);
      final featureLayer = FeatureLayerExtension.fromUrl(Uri.parse(_layerUrl));
      _map.operationalLayers.add(featureLayer);
    }
    _loadMapResources();
  }

  Future<void> _loadMapResources() async {
    final bloc = context.read<MapBloc>();
    await _map.load();
    bloc.add(PageInitialized());

    // Ensure shared table instances are used if possible (only for online)
    for (final layer in _map.operationalLayers) {
      if (layer is FeatureLayer) {
        await layer.load();

        final table = layer.featureTable;

        if (table != null) {
          await table.load();
        }
      }
    }

    for (final layer in _map.operationalLayers) {
      if (layer is FeatureLayer) {
        await layer.load();
        final table = layer.featureTable;
        if (table != null) {
          await table.load();
        }
      }
    }
    setState(() {});
  }

  Future<void> _showGnssProviderDialog() async {
    if (!mounted) return;

    try {

      if (await Permission.bluetoothScan.isDenied) {
        final scanStatus = await Permission.bluetoothScan.request();

        if (!scanStatus.isGranted) {
          if (!mounted) return;

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Bluetooth permission is required to find GNSS receivers.',
              ),
            ),
          );

          return;
        }
      }

      if (await Permission.bluetoothConnect.isDenied) {
        final connectStatus = await Permission.bluetoothConnect.request();

        if (!connectStatus.isGranted) {
          if (!mounted) return;

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Bluetooth permission is required to connect to GNSS receiver.',
              ),
            ),
          );

          return;
        }
      }


      final bluetoothEnabled = await _locationChannel.invokeMethod<bool>(
        'isBluetoothEnabled',
      );

      debugPrint('GNSS BLUETOOTH ENABLED = $bluetoothEnabled');

      if (bluetoothEnabled != true) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Bluetooth is OFF. Please turn on Bluetooth and try again.',
            ),
            duration: Duration(seconds: 4),
          ),
        );

        return;
      }


      final initialized = await _realNmeaProvider.initializeBluetooth();

      if (!initialized) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Unable to initialize Bluetooth. Please check Bluetooth permissions.',
            ),
          ),
        );

        return;
      }


      final pairedDevices = await _realNmeaProvider.getPairedDevices();

      if (!mounted) return;

      // Continue with your existing bottom-sheet code...

      List<Device> discoveredDevices = [];
      StreamSubscription<Device>? discoverySubscription;
      bool scanStarted = false;

      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (sheetContext) {
          return StatefulBuilder(
            builder: (context, sheetSetState) {
              // Start listening only once.
              discoverySubscription ??= _realNmeaProvider.discoveredDevices
                  .listen((device) {
                    final alreadyExists = [
                      ...pairedDevices,
                      ...discoveredDevices,
                    ].any((existing) => existing.address == device.address);

                    if (alreadyExists) {
                      return;
                    }

                    sheetSetState(() {
                      discoveredDevices = [...discoveredDevices, device];
                    });

                    debugPrint(
                      'GNSS DISCOVERED: '
                      '${device.name ?? 'Unknown'} '
                      '${device.address}',
                    );
                  });

              // Start scanning after the listener is ready.
              if (!scanStarted) {
                scanStarted = true;

                _realNmeaProvider.startDeviceScan().then((started) {
                  debugPrint('GNSS Bluetooth scan started: $started');
                });
              }

              return SafeArea(
                child: SizedBox(
                  height: MediaQuery.of(context).size.height * 0.65,
                  child: Column(
                    children: [
                      const SizedBox(height: 12),

                      const Text(
                        'Select GNSS Receiver',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 8),

                      const Text(
                        'Bluetooth devices',
                        style: TextStyle(color: Colors.grey),
                      ),

                      const Divider(),

                      Expanded(
                        child: ListView(
                          children: [
                            // ==========================================
                            // PAIRED DEVICES
                            // ==========================================

                            if (pairedDevices.isNotEmpty) ...[
                              const Padding(
                                padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
                                child: Text(
                                  'PAIRED DEVICES',
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),

                              ...pairedDevices.map(
                                (device) => _buildGnssDeviceTile(device),
                              ),
                            ],

                            // ==========================================
                            // AVAILABLE DEVICES
                            // ==========================================
                            const Padding(
                              padding: EdgeInsets.fromLTRB(16, 20, 16, 8),
                              child: Text(
                                'AVAILABLE DEVICES',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),

                            if (discoveredDevices.isEmpty)
                              const Padding(
                                padding: EdgeInsets.all(24),
                                child: Center(
                                  child: Column(
                                    children: [
                                      CircularProgressIndicator(),
                                      SizedBox(height: 12),
                                      Text('Scanning for Bluetooth devices...'),
                                    ],
                                  ),
                                ),
                              )
                            else
                              ...discoveredDevices.map(
                                (device) => _buildGnssDeviceTile(device),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );

      // Stop scan when bottom sheet closes.
      try {
        await _realNmeaProvider.stopDeviceScan();
      } catch (_) {}

      await discoverySubscription?.cancel();
    } catch (e, stackTrace) {
      debugPrint('GNSS PROVIDER ERROR: $e');
      debugPrint('GNSS PROVIDER STACKTRACE: $stackTrace');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to open GNSS provider: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _connectGnssReceiver(Device device) async {
    if (!mounted) return;

    setState(() {
      _locationStatus = 'Connecting to ${device.name ?? 'GNSS receiver'}...';
      _fixType = 'Connecting...';
      _satelliteCount = 0;
      _accuracy = 0.0;
    });

    final connected = await _realNmeaProvider.connectToDevice(device);

    if (!mounted) return;

    if (!connected) {
      setState(() {
        _locationStatus = 'GNSS receiver connection failed';
        _fixType = 'NO CONNECTION';
        _gnssReceiverName = 'External GNSS Receiver';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not connect to ${device.name ?? device.address}',
          ),
        ),
      );

      return;
    }

    final receiverName = (device.name?.trim().isNotEmpty ?? false)
        ? device.name!.trim()
        : 'External GNSS Receiver';

    setState(() {
      _locationStatus = 'GNSS receiver connected';
      _fixType = 'WAITING FOR FIX';
      _gnssReceiverName = receiverName;
    });

    debugPrint('GNSS RECEIVER NAME: $_gnssReceiverName');

    debugPrint(
      'GNSS PROVIDER CONNECTED: '
      '${device.name ?? 'Unknown'} '
      '${device.address}',
    );
  }

  Future<void> _showGnssTransportDialog() async {
    if (!mounted) return;

    final selected = await showDialog<String>(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: const Text('Select GNSS Connection'),
          children: [
            SimpleDialogOption(
              onPressed: () {
                Navigator.pop(context, 'bluetooth');
              },
              child: const Text('Bluetooth GNSS'),
            ),
            SimpleDialogOption(
              onPressed: () {
                Navigator.pop(context, 'usb');
              },
              child: const Text('USB GNSS'),
            ),
          ],
        );
      },
    );

    if (!mounted || selected == null) {
      return;
    }

    if (selected == 'bluetooth') {
      // EXISTING BLUETOOTH FLOW
      await _showGnssProviderDialog();
    } else if (selected == 'usb') {
      await _showUsbGnssDialog();
    }
  }

  Future<void> _showUsbGnssDialog() async {
    if (!mounted) return;

    try {
      final devices = await _usbGnssTransport.listDevices();

      if (!mounted) return;

      if (devices.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No USB device detected. Connect the GNSS receiver and try again.',
            ),
          ),
        );
        return;
      }

      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (sheetContext) {
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.55,
              child: Column(
                children: [
                  const SizedBox(height: 16),

                  const Text(
                    'Select USB GNSS Receiver',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),

                  const SizedBox(height: 8),

                  const Text(
                    'USB serial devices',
                    style: TextStyle(color: Colors.grey),
                  ),

                  const Divider(),

                  Expanded(
                    child: ListView.builder(
                      itemCount: devices.length,
                      itemBuilder: (context, index) {
                        final device = devices[index];

                        final name =
                            device.productName?.trim().isNotEmpty == true
                            ? device.productName!.trim()
                            : device.deviceName;

                        final manufacturer =
                            device.manufacturerName?.trim().isNotEmpty == true
                            ? device.manufacturerName!.trim()
                            : 'Unknown manufacturer';

                        return ListTile(
                          leading: const Icon(Icons.usb, color: Colors.blue),
                          title: Text(name),
                          subtitle: Text(
                            '$manufacturer\n'
                            'VID: ${device.vid ?? '-'}  '
                            'PID: ${device.pid ?? '-'}',
                          ),
                          isThreeLine: true,
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () async {
                            Navigator.pop(sheetContext);
                            await _connectUsbGnssReceiver(device);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    } catch (e, stackTrace) {
      debugPrint('USB GNSS DIALOG ERROR: $e');
      debugPrint('$stackTrace');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to find USB GNSS device: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _connectUsbGnssReceiver(UsbDevice device) async {
    if (!mounted) return;

    final receiverName = device.productName?.trim().isNotEmpty == true
        ? device.productName!.trim()
        : device.deviceName;

    _selectedUsbDevice = device;

    setState(() {
      _locationStatus = 'Connecting to $receiverName...';
      _fixType = 'Connecting...';
      _satelliteCount = 0;
      _accuracy = 0.0;
      _gnssReceiverName = receiverName;
    });

    try {
      await _switchLocationProvider('USB GNSS');

      if (!mounted) return;

      if (!_usbNmeaProvider.isStarted) {
        setState(() {
          _locationStatus = 'USB GNSS connection failed';
          _fixType = 'NO CONNECTION';
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not connect to the USB GNSS receiver.'),
          ),
        );

        return;
      }

      setState(() {
        _locationStatus = 'USB GNSS receiver connected';
        _fixType = 'WAITING FOR FIX';
        _gnssReceiverName = receiverName;
      });

      debugPrint('USB GNSS RECEIVER: $receiverName');
    } catch (e, stackTrace) {
      debugPrint('USB GNSS CONNECTION ERROR: $e');
      debugPrint('$stackTrace');

      if (!mounted) return;

      setState(() {
        _locationStatus = 'USB GNSS connection failed';
        _fixType = 'NO CONNECTION';
      });
    }
  }

  Widget _buildGnssDeviceTile(Device device) {
    return ListTile(
      leading: const Icon(Icons.gps_fixed, color: Colors.blue),
      title: Text(device.name ?? 'Unknown Bluetooth Device'),
      subtitle: Text(device.address),
      trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        Navigator.pop(context);

        await _connectGnssReceiver(device);
      },
    );
  }

  @override
  void dispose() {
    _realNmeaProvider.dispose();
    _usbNmeaProvider.dispose();
    _locationSubscription?.cancel();
    _satellitesSubscription?.cancel();
    _statusSubscription?.cancel();
    _mockNmeaProvider.stopSimulation();
    _mapController?.dispose();
    _mockNmeaSubscription?.cancel();
    _mockNmeaSubscription = null;
    super.dispose();
  }

  Future<void> _onMapCreated() async {
    if (!mounted) return;

    await _map.load();

    if (!mounted) return;

    await _startUserLocation();
  }

  Future<bool> _checkLocationRequirements() async {
    if (!mounted) return false;

    // 1. Permission FIRST
    var status = await Permission.locationWhenInUse.status;

    if (!status.isGranted) {
      status = await Permission.locationWhenInUse.request();
    }

    if (!status.isGranted) {
      if (!mounted) return false;

      setState(() {
        _locationStatus = 'Location permission denied';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Location permission is required to show your position.',
          ),
        ),
      );

      return false;
    }

    // 2. Permission granted → now check Location Service
    final serviceStatus = await Permission.locationWhenInUse.serviceStatus;

    if (!serviceStatus.isEnabled) {
      if (!mounted) return false;

      setState(() {
        _locationStatus = 'Location service is OFF';
      });

      try {
        final result = await _locationChannel.invokeMethod<String>(
          'resolveLocationSettings',
        );
        if (result == 'enabled') {
          // If enabled, we should check again to be sure and continue
          return await _checkLocationRequirements();
        } else {
          if (!mounted) return false;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                result == 'cancelled'
                    ? 'Location service must be enabled to show your position.'
                    : 'Please turn on Location/GPS and return to the app.',
              ),
              duration: const Duration(seconds: 5),
            ),
          );
          return false;
        }
      } catch (e) {
        debugPrint('Location resolution error: $e');
        if (!mounted) return false;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please turn on Location/GPS and return to the app.'),
            duration: Duration(seconds: 5),
          ),
        );
        return false;
      }
    }

    return true;
  }

  Future<void> _startUserLocation() async {
    if (!mounted) return;

    final permissionGranted = await _checkLocationRequirements();

    if (!permissionGranted) {
      return;
    }

    final controller = _mapController;

    if (controller == null) {
      debugPrint('GPS ERROR: Map controller is NULL');
      return;
    }

    final locationDisplay = controller.locationDisplay;

    locationDisplay.dataSource = _currentLocationDataSource;

    try {
      await _currentLocationDataSource.start();

      setState(() {
        _locationStatus = 'Getting current location...';
      });
      bool cameraPositioned = false;
      debugPrint('LOCATION STARTED');
      _locationSubscription = _currentLocationDataSource.onLocationChanged
          .listen((location) async {
            debugPrint('LOCATION GETTING');
            final position = location.position;

            final latitude = position.y;

            final longitude = position.x;

            debugPrint(
              'CURRENT LOCATION => '
              'Lat: $latitude, '
              'Lng: $longitude',
            );
            setState(() {
              _lastKnownLocation = location;
              _accuracy = location.horizontalAccuracy;
              _locationStatus = 'Current location acquired';
            });

            if (!mounted) {
              return;
            }
            if (!cameraPositioned) {
              cameraPositioned = true;

              await _mapController?.setViewpointCenter(position, scale: 10000);
            }
            // Move map to user's current location
          });
    } catch (e) {
      debugPrint('LOCATION ERROR => $e');

      _locationStarted = false;
    }
  }

  FeatureLayer? get _firstEditableLayer {
    try {
      return _map.operationalLayers.whereType<FeatureLayer>().firstWhere((
        layer,
      ) {
        // Only allow adding to a layer that is currently visible.
        if (!layer.isVisible) {
          return false;
        }

        final table = layer.featureTable;

        return table != null && table.canAdd();
      });
    } catch (_) {
      return null;
    }
  }

  Future<void> _identifyFeature(Offset screenPoint) async {
    if (_mapController == null) return;

    final bloc = context.read<MapBloc>();

    debugPrint('MAP TAP: Offset $screenPoint');

    // Don't identify features while actively collecting/picking a location.
    if (bloc.state is CollectionState &&
        (bloc.state as CollectionState).mode != CollectionMode.idle &&
        (bloc.state as CollectionState).mode != CollectionMode.viewDetails) {
      debugPrint(
        'MAP TAP: Ignored due to active collection mode: '
        '${(bloc.state as CollectionState).mode}',
      );
      return;
    }

    try {
      final results = await _mapController!.identifyLayers(
        screenPoint: screenPoint,
        tolerance: 20,
        returnPopupsOnly: false,
      );

      debugPrint('MAP TAP: Identified ${results.length} layers');

      for (final layerResult in results) {
        debugPrint(
          'Layer: ${layerResult.layerContent.name}, '
          'Elements: ${layerResult.geoElements.length}, '
          'Popups: ${layerResult.popups.length}',
        );

        if (layerResult.geoElements.isNotEmpty) {
          final element = layerResult.geoElements.first;

          if (element is Feature && layerResult.layerContent is FeatureLayer) {
            final layer = layerResult.layerContent as FeatureLayer;
            final table = element.featureTable;

            debugPrint('Feature found: ${table?.tableName}');

            final attributes = Map<String, dynamic>.from(element.attributes);

            String objectId = '';

            if (table is ArcGISFeatureTable) {
              objectId =
                  element.attributes[table.objectIdField]?.toString() ?? '';
            } else {
              objectId =
                  element.attributes['OBJECTID']?.toString() ??
                  element.attributes['objectid']?.toString() ??
                  element.attributes['fid']?.toString() ??
                  '';
            }

            final gisFeature = GisFeature(
              id: objectId,
              geometry: element.geometry,
              attributes: attributes,
            );

            // Use the actual Web Map popup.

            Popup? popup;

            if (layerResult.popups.isNotEmpty) {
              popup = layerResult.popups.first;

              debugPrint('Using Web Map popup: ${popup.title}');
            } else {
              // Fallback if identify did not return a popup.
              final popupDefinition =
                  layer.popupDefinition ?? table?.popupDefinition;

              if (popupDefinition != null) {
                popup = Popup(
                  geoElement: element,
                  popupDefinition: popupDefinition,
                );

                debugPrint('Using layer/table popupDefinition fallback');
              }
            }

            if (popup != null) {
              _showFeaturePopup(
                popup: popup,
                feature: gisFeature,
                layer: layer,
              );
            } else {
              debugPrint('No popup definition available for ${layer.name}');
            }

            return;
          }
        }

        // ============================================================
        // 2. SUBLAYERS
        // ============================================================

        for (final subResult in layerResult.sublayerResults) {
          debugPrint(
            'Sublayer: ${subResult.layerContent.name}, '
            'Elements: ${subResult.geoElements.length}, '
            'Popups: ${subResult.popups.length}',
          );

          if (subResult.geoElements.isEmpty) {
            continue;
          }

          final element = subResult.geoElements.first;

          if (element is! Feature) {
            continue;
          }

          if (subResult.layerContent is! FeatureLayer) {
            continue;
          }

          final layer = subResult.layerContent as FeatureLayer;
          final table = element.featureTable;

          String objectId = '';

          if (table is ArcGISFeatureTable) {
            objectId =
                element.attributes[table.objectIdField]?.toString() ?? '';
          } else {
            objectId =
                element.attributes['OBJECTID']?.toString() ??
                element.attributes['objectid']?.toString() ??
                element.attributes['fid']?.toString() ??
                '';
          }

          final gisFeature = GisFeature(
            id: objectId,
            geometry: element.geometry,
            attributes: Map<String, dynamic>.from(element.attributes),
          );

          Popup? popup;

          if (subResult.popups.isNotEmpty) {
            popup = subResult.popups.first;

            debugPrint('Using Web Map sublayer popup: ${popup.title}');
          } else {
            final popupDefinition =
                layer.popupDefinition ?? table?.popupDefinition;

            if (popupDefinition != null) {
              popup = Popup(
                geoElement: element,
                popupDefinition: popupDefinition,
              );
            }
          }

          if (popup != null) {
            _showFeaturePopup(popup: popup, feature: gisFeature, layer: layer);
          }

          return;
        }
      }

      debugPrint('MAP TAP: No feature found at this location.');
    } catch (e, stackTrace) {
      debugPrint('MAP TAP ERROR: $e');
      debugPrint('MAP TAP STACKTRACE: $stackTrace');
    }
  }

  void _showPopup(Popup popup) {
    if (!mounted) return;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: false,
      builder: (_) => SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: PopupView(
          popup: popup,
          onClose: () {
            Navigator.of(context).pop();
          },
        ),
      ),
    );
  }

  void _startCollection() {
    final layer = _firstEditableLayer;

    if (layer != null) {
      context.read<MapBloc>().add(StartCollectionRequested(layer));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No editable layers found in this map.')),
      );
    }
  }

  Future<void> _exitOfflineMap() async {
    final hasInternet = await _hasInternetConnection();

    if (!hasInternet) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please turn on internet/data to go back online.'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 4),
        ),
      );

      return;
    }

    try {
      debugPrint('========== EXIT OFFLINE MAP ==========');

      // Create the ONLINE map again
      if (widget.portalItem != null) {
        _map = ArcGISMap.withItem(widget.portalItem!);
      } else {
        _map = ArcGISMap.withBasemapStyle(BasemapStyle.arcGISImageryStandard);

        final featureLayer = FeatureLayerExtension.fromUrl(
          Uri.parse(_layerUrl),
        );

        _map.operationalLayers.add(featureLayer);
      }

      // Load online map
      await _map.load();

      if (!mounted) return;

      // Existing MapView controller must receive the new online map.
      final controller = _mapController;

      if (controller != null) {
        controller.arcGISMap = _map;
      }

      // Load online layers
      for (final layer in _map.operationalLayers) {
        if (layer is FeatureLayer) {
          await layer.load();

          final table = layer.featureTable;

          if (table != null) {
            await table.load();
          }
        }
      }

      // Tell BLoC that we are now ONLINE
      context.read<MapBloc>().add(ExitOfflineMap());

      if (mounted) {
        setState(() {});
      }

      debugPrint('========== EXIT OFFLINE MAP SUCCESS ==========');
    } catch (e) {
      debugPrint('EXIT OFFLINE MAP ERROR => $e');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to exit offline map: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<bool> _hasInternetConnection() async {
    try {
      final result = await InternetAddress.lookup('www.arcgis.com');

      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } on SocketException {
      return false;
    }
  }

  Future<void> _goToMyLocation() async {
    if (!await _checkLocationRequirements()) {
      return;
    }

    final controller = _mapController;

    if (controller == null) {
      return;
    }

    try {
      controller.locationDisplay.dataSource = _currentLocationDataSource;

      await _currentLocationDataSource.start();

      final location = controller.locationDisplay.location;

      if (location?.position != null) {
        await controller.setViewpointCenter(location!.position, scale: 3000);

        controller.locationDisplay.autoPanMode =
            LocationDisplayAutoPanMode.recenter;
      }
    } catch (e) {
      debugPrint('MY LOCATION ERROR: $e');
    }
  }

  bool _returningToMapForLocationUpdate = false;

  void _beginLocationUpdate() {
    final bloc = context.read<MapBloc>();
    final state = bloc.state;

    if (state is! CollectionState ||
        !state.isNewFeature ||
        state.draftFeature?.geometry == null) {
      return;
    }

    _returningToMapForLocationUpdate = true;
    Navigator.of(context).pop();
    bloc.add(BeginLocationUpdate());
  }

  void _captureLocation() {
    final controller = _mapController;

    if (controller == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Map is not ready yet.')));
      return;
    }

    final extent = controller.visibleArea?.extent;
    final center = extent?.center;

    if (center == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to get map center.')),
      );
      return;
    }

    // Convert the selected map-center point to WGS84
    // before storing latitude/longitude attributes.
    final wgs84Geometry = GeometryEngine.project(
      center,
      outputSpatialReference: SpatialReference.wgs84,
    );

    if (wgs84Geometry is! ArcGISPoint) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to convert selected location to WGS84.'),
        ),
      );
      return;
    }

    final wgs84Point = wgs84Geometry;

    // Keep the latest GPS/GNSS information for:
    // accuracy, altitude, DOP, satellites, receiver, etc.
    final currentLocation = _lastKnownLocation;

    final attributes = currentLocation != null
        ? _buildAutomaticLocationAttributes(currentLocation)
        : <String, dynamic>{};

    // Store LAT/LONG in WGS84 decimal degrees,
    attributes['esrignss_latitude'] = wgs84Point.y;
    attributes['esrignss_longitude'] = wgs84Point.x;


    context.read<MapBloc>().add(
      LocationCaptured(center, attributes: attributes),
    );
  }

  void _captureCurrentLocation() {
    final controller = _mapController;

    if (controller == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Map is not ready yet.')));
      return;
    }

    // Get the latest location from the active location provider.
    //
    // This can be:
    // - Device GPS
    // - Mock GNSS
    // - Real external GNSS / DGPS
    final currentLocation =
        _lastKnownLocation ?? controller.locationDisplay.location;

    if (currentLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Current location is not available yet. Please wait for a location fix.',
          ),
        ),
      );

      debugPrint('CURRENT LOCATION CAPTURE FAILED: No location available.');

      return;
    }

    final position = currentLocation.position;

    debugPrint('========== CURRENT LOCATION CAPTURE ==========');
    debugPrint('Provider          : $_gnssReceiverName');
    debugPrint('Fix Type          : $_fixType');
    debugPrint('Original Position : $position');
    debugPrint('Source SR         : ${position.spatialReference}');
    debugPrint('Horizontal Accuracy: ${currentLocation.horizontalAccuracy}');
    debugPrint('Vertical Accuracy  : ${currentLocation.verticalAccuracy}');

    // Convert the GNSS/GPS position to WGS84.
    final wgs84Geometry = GeometryEngine.project(
      position,
      outputSpatialReference: SpatialReference.wgs84,
    );

    if (wgs84Geometry is! ArcGISPoint) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to convert current location to WGS84.'),
        ),
      );

      debugPrint('CURRENT LOCATION CAPTURE FAILED: WGS84 projection failed.');

      return;
    }

    final wgs84Point = wgs84Geometry;

    // Build the normal GNSS/GPS metadata.
    final attributes = _buildAutomaticLocationAttributes(currentLocation);

    // Make latitude/longitude match the feature geometry exactly.
    attributes['esrignss_latitude'] = wgs84Point.y;
    attributes['esrignss_longitude'] = wgs84Point.x;


    context.read<MapBloc>().add(
      LocationCaptured(wgs84Point, attributes: attributes),
    );
  }

  void _showLocationCaptureOptions() {
    if (!mounted) return;

    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),

                const SizedBox(height: 16),

                const Text(
                  'Select Location',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),

                const SizedBox(height: 16),

                // -------------------------------------------------
                // OPTION 1: MAP CENTER
                // -------------------------------------------------
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFE3F2FD),
                    child: Icon(Icons.add_location_alt, color: Colors.blue),
                  ),
                  title: const Text(
                    'Add Point',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text('Use the location selected on the map'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(sheetContext).pop();

                    // Existing behavior.
                    _captureLocation();
                  },
                ),

                const Divider(),

                // -------------------------------------------------
                // OPTION 2: CURRENT LOCATION
                // -------------------------------------------------
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFE8F5E9),
                    child: Icon(Icons.my_location, color: Colors.green),
                  ),
                  title: const Text(
                    'Use Current Location',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text('Use the latest GPS / GNSS position'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(sheetContext).pop();

                    _captureCurrentLocation();
                  },
                ),

                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  Map<String, dynamic> _buildAutomaticLocationAttributes(
    ArcGISLocation location,
  ) {
    final position = location.position;

    final attributes = <String, dynamic>{
      'esrignss_latitude': position.y,
      'esrignss_longitude': position.x,

      'esrignss_h_rms': _finiteOrNull(location.horizontalAccuracy),

      'esrignss_v_rms': _finiteOrNull(location.verticalAccuracy),

      'esrignss_speed': _finiteOrNull(location.speed * 3.6),

      'esrignss_direction': _finiteOrNull(location.course),

      'esrignss_fixdatetime': location.timestamp,

      'esrignss_positionsourcetype': location is NmeaLocation ? 3 : 2,

      // ---------------------------------------------------------
      // IMPORTANT:
      // Do NOT use:
      //
      // location is NmeaLocation ? 'Mock GNSS' : 'Device GPS'
      //
      // because both Mock GNSS and Real DGPS produce NmeaLocation.
      // ---------------------------------------------------------
      'esrignss_receiver': _gnssReceiverName,
    };

    // ---------------------------------------------------------
    // NMEA-specific metadata
    // ---------------------------------------------------------

    if (location is NmeaLocation) {
      attributes.addAll({
        // Altitude
        'esrignss_altitude': _finiteOrNull(location.heightAboveGeoid),

        // DOP
        'esrignss_pdop': _finiteOrNull(location.pdop),

        'esrignss_hdop': _finiteOrNull(location.hdop),

        'esrignss_vdop': _finiteOrNull(location.vdop),

        // DGPS correction information
        'esrignss_correctionage': _finiteOrNull(location.dgpsAge),

        // Reference station ID
        'esrignss_stationid': location.referenceStationId,

        // Satellites
        'esrignss_numsats': location.satellites.length,

        // NMEA fix type
        'esrignss_fixtype': _getNmeaFixTypeCode(location.fixType),
      });
    }

    attributes.removeWhere((key, value) => value == null);

    return attributes;
  }

  double? _finiteOrNull(double value) {
    return value.isFinite ? value : null;
  }

  int _getNmeaFixTypeCode(NmeaFixType fixType) {
    switch (fixType) {
      case NmeaFixType.invalid:
        return 0;

      case NmeaFixType.standard:
        return 1;

      case NmeaFixType.dgps:
        return 2;

      case NmeaFixType.rtk:
        return 4;

      case NmeaFixType.frtk:
        return 5;

      // These are not represented by the standard
      // ESRIGNSS_FIXTYPE domain.
      case NmeaFixType.pps:
      case NmeaFixType.estimated:
      case NmeaFixType.manual:
      case NmeaFixType.simulation:
        return 0;
    }
  }

  Future<void> _switchLocationProvider(String provider) async {
    try {
      if (_currentLocationDataSource == _usbGnssDataSource) {
        await _usbNmeaProvider.stop();
      }
      await _currentLocationDataSource.stop();
    } catch (_) {}

    await _locationSubscription?.cancel();
    await _satellitesSubscription?.cancel();
    await _statusSubscription?.cancel();
    await _mockNmeaSubscription?.cancel();

    _locationSubscription = null;
    _satellitesSubscription = null;
    _statusSubscription = null;
    _mockNmeaSubscription = null;

    setState(() {
      _lastKnownLocation = null;
      _accuracy = 0.0;
      _satelliteCount = 0;
      _locationStatus = 'Acquiring location...';

      switch (provider) {
        case 'Mock GNSS':
          _gnssReceiverName = 'Mock GNSS';
          _fixType = 'Acquiring Mock GNSS...';
          break;

        case 'Real GNSS':
          _gnssReceiverName = 'External GNSS Receiver';
          _fixType = 'Acquiring Real GNSS...';
          break;

        case 'USB GNSS':
          _gnssReceiverName =
              _selectedUsbDevice?.productName?.trim().isNotEmpty == true
              ? _selectedUsbDevice!.productName!.trim()
              : 'External USB GNSS';

          _fixType = 'Acquiring USB GNSS...';
          break;

        default:
          _gnssReceiverName = 'Device GPS';
          _fixType = 'Acquiring Device GPS...';
      }
    });

    if (provider == 'Mock GNSS') {
      if (_mockGnssDataSource == null) {
        _mockGnssDataSource = NmeaLocationDataSource.withProvider(
          () => _mockNmeaProvider,
        );
      }

      _currentLocationDataSource = _mockGnssDataSource!;

      _mockNmeaSubscription = _mockNmeaProvider.nmeaData.listen((sentence) {
        if (!sentence.startsWith('\$GPGSA')) {
          return;
        }

        final withoutChecksum = sentence.split('*').first;
        final fields = withoutChecksum.split(',');

        int count = 0;

        for (int i = 3; i <= 14 && i < fields.length; i++) {
          if (fields[i].trim().isNotEmpty) {
            count++;
          }
        }

        if (!mounted) return;

        setState(() {
          _satelliteCount = count;
        });
      });

      _mockNmeaProvider.startSimulation();

      setState(() {
        _fixType = 'SIMULATED GNSS';
        _gnssReceiverName = 'Mock GNSS';
      });
    } else if (provider == 'Real GNSS') {
      _mockNmeaProvider.stopSimulation();

      if (_realGnssDataSource == null) {
        _realGnssDataSource = NmeaLocationDataSource.withProvider(
          () => _realNmeaProvider,
        );
      }

      _currentLocationDataSource = _realGnssDataSource!;

      // Real GNSS satellite information comes from
      // NmeaLocationDataSource.
      _satellitesSubscription = _realGnssDataSource!.onSatellitesChanged.listen(
        (satelliteInfos) {
          if (!mounted) return;

          setState(() {
            _satelliteCount = satelliteInfos.length;
          });

          debugPrint('REAL GNSS SATELLITES: ${satelliteInfos.length}');
        },
      );

      setState(() {
        _fixType = 'REAL GNSS';

        // Keep the actual receiver name selected during Bluetooth connection.
        // If no receiver has been connected yet, use a generic name.
        if (_gnssReceiverName == 'Device GPS' ||
            _gnssReceiverName == 'Mock GNSS') {
          _gnssReceiverName = 'External GNSS Receiver';
        }
      });
    } else if (provider == 'USB GNSS') {
      _mockNmeaProvider.stopSimulation();

      if (_usbGnssDataSource == null) {
        _usbGnssDataSource = NmeaLocationDataSource.withProvider(
          () => _usbNmeaProvider,
        );
      }

      _currentLocationDataSource = _usbGnssDataSource!;

      _satellitesSubscription = _usbGnssDataSource!.onSatellitesChanged.listen((
        satelliteInfos,
      ) {
        if (!mounted) return;

        setState(() {
          _satelliteCount = satelliteInfos.length;
        });

        debugPrint('USB GNSS SATELLITES: ${satelliteInfos.length}');
      });

      setState(() {
        _fixType = 'USB GNSS';
      });
    } else {
      _mockNmeaProvider.stopSimulation();

      _currentLocationDataSource = _locationDataSource;

      setState(() {
        _fixType = 'Device GPS';
        _gnssReceiverName = 'Device GPS';
      });
    }

    _statusSubscription = _currentLocationDataSource.onStatusChanged.listen((
      status,
    ) {
      if (!mounted) return;

      setState(() {
        _locationStatus = status.toString().split('.').last;
      });
    });

    await _startUserLocation();
  }

  void _refreshLayers() async {
    for (final layer in _map.operationalLayers) {
      if (layer is FeatureLayer) {
        // Shared instances usually update.
      }
    }
  }

  void _showOfflineMapsMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => BlocBuilder<MapBloc, MapState>(
        builder: (context, state) {
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ListTile(
                  title: Text(
                    'Offline Maps',
                    style: TextStyle(
                      color: Colors.black87,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.download, color: Colors.blue),
                  title: const Text(
                    'Download Current Area',
                    style: TextStyle(color: Colors.black87),
                  ),
                  onTap: state.isDownloading
                      ? null
                      : () {
                          Navigator.pop(context);
                          final extent = _mapController?.visibleArea?.extent;
                          final scale = _mapController?.scale ?? 0.0;

                          if (scale > 100000) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Please zoom in further to download an offline map. The current area is too large.',
                                ),
                                backgroundColor: Colors.orange,
                              ),
                            );
                            return;
                          }

                          if (extent != null) {
                            context.read<MapBloc>().add(
                              DownloadOfflineMap(
                                _map,
                                extent,
                                currentScale: scale,
                              ),
                            );
                          }
                        },
                ),
                ListTile(
                  leading: Icon(
                    Icons.map,
                    color: state.isOfflineMode ? Colors.green : Colors.grey,
                  ),
                  title: Text(
                    state.isOfflineMode
                        ? 'Exit Offline Map'
                        : 'Open Offline Map',
                    style: const TextStyle(color: Colors.black87),
                  ),
                  onTap: state.offlineMapPath == null
                      ? null
                      : () {
                          Navigator.pop(context);
                          // if (state.isOfflineMode) {
                          //   _initMap();
                          //   context.read<MapBloc>().add(PageInitialized()); // Reset to online
                          // } else {
                          //   context.read<MapBloc>().add(OpenOfflineMap());
                          // }
                          if (state.isOfflineMode) {
                            _exitOfflineMap();
                          } else {
                            context.read<MapBloc>().add(OpenOfflineMap());
                          }
                        },
                ),
                ListTile(
                  leading: const Icon(Icons.sync, color: Colors.orange),
                  title: const Text(
                    'Sync Changes',
                    style: TextStyle(color: Colors.black87),
                  ),
                  onTap: (state.offlineMapPath == null || state.isSyncing)
                      ? null
                      : () {
                          Navigator.pop(context);
                          context.read<MapBloc>().add(SyncOfflineChanges());
                        },
                ),
                ListTile(
                  leading: const Icon(Icons.delete_forever, color: Colors.red),
                  title: const Text(
                    'Remove Offline Map',
                    style: TextStyle(color: Colors.black87),
                  ),
                  onTap: state.offlineMapPath == null
                      ? null
                      : () {
                          Navigator.pop(context);
                          context.read<MapBloc>().add(RemoveOfflineMap());
                        },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        title: BlocBuilder<MapBloc, MapState>(
          builder: (context, state) {
            final title = widget.portalItem?.title ?? '';
            final displayTitle = state.isOfflineMode
                ? '$title (Offline)'
                : title;

            return Tooltip(
              message: displayTitle,
              triggerMode: TooltipTriggerMode.longPress,
              child: Text(
                displayTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
              ),
            );
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync),
            tooltip: 'Sync',
            onPressed: () {
              context.read<MapBloc>().add(
                RefreshMapRequested(layerUrl: _layerUrl),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.layers),
            tooltip: 'Layers',
            onPressed: _showLayersSheet,
          ),

          PopupMenuButton<String>(
            offset: const Offset(0, 60),
            icon: const Icon(Icons.more_vert),
            tooltip: 'More',
            onSelected: (value) {
              switch (value) {
                case 'offline':
                  _showOfflineMapsMenu();
                  break;
                case 'basemap':
                  _showBasemapGallery();
                  break;
                case 'extent':
                  _goToDefaultMapExtent();
                  break;
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'offline', child: Text('Offline Maps')),
              PopupMenuItem(value: 'basemap', child: Text('Basemap')),
              PopupMenuItem(value: 'extent', child: Text('Default map extent')),
            ],
          ),
        ],
      ),

      body: BlocListener<MapBloc, MapState>(
        listenWhen: (previous, current) {
          if (current is MapError) return true;
          // Only trigger form if we transition TO fillingForm
          if (current is CollectionState &&
              current.mode == CollectionMode.fillingForm) {
            return previous is! CollectionState ||
                previous.mode != CollectionMode.fillingForm;
          }
          // Only trigger viewDetails if we transition TO viewDetails
          if (current is CollectionState &&
              current.mode == CollectionMode.viewDetails) {
            return previous is! CollectionState ||
                previous.mode != CollectionMode.viewDetails;
          }
          if (current.isOfflineMode != previous.isOfflineMode) return true;
          if (current.isDownloading != previous.isDownloading) return true;
          if (current.isSyncing != previous.isSyncing) return true;
          return false;
        },
        listener: (context, state) {
          if (state is MapError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: Colors.red,
              ),
            );
          }

          // Handle Download Notifications
          if (state.isDownloading && state.offlineDownloadProgress == 0.0) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Download started...'),
                duration: Duration(seconds: 2),
              ),
            );
          } else if (!state.isDownloading &&
              state.offlineDownloadProgress == 1.0) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Download completed successfully.'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 3),
              ),
            );
          }

          // Handle Sync Notifications
          if (state.isSyncing && state.offlineSyncProgress == 0.0) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Sync started...'),
                duration: Duration(seconds: 2),
              ),
            );
          } else if (!state.isSyncing && state.offlineSyncProgress == 1.0) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Sync completed successfully.'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 3),
              ),
            );
          }

          if (state is CollectionState &&
              state.mode == CollectionMode.fillingForm) {
            _showCollectionForm(context);
          }
          if (state is CollectionState &&
              state.mode == CollectionMode.viewDetails) {
            if (mounted) {
              Navigator.pop(context);

              _showCreatedFeaturePopup(
                feature: state.draftFeature!,
                layer: state.targetLayer!,
              );
            }
          }
          if (state.isOfflineMode && state.offlineMapPath != null) {
            context
                .read<MapBloc>()
                .mapRepository
                .openOfflineMap(state.offlineMapPath!)
                .then((offlineMap) {
                  setState(() {
                    _map = offlineMap;
                    _mapController?.arcGISMap = _map;
                  });
                });
          }
          if (state is MapInitial || state is MapLoaded) {
            _refreshLayers();
          }
        },
        child: Stack(
          children: [
            ArcGISMapView(
              controllerProvider: () {
                _mapController = ArcGISMapView.createController()
                  ..arcGISMap = _map;
                return _mapController!;
              },
              onMapViewReady: _onMapCreated,
              onTap: (offset) {
                final state = context.read<MapBloc>().state;

                if (state is CollectionState &&
                    state.mode == CollectionMode.pickingLocation) {
                  return;
                }

                _identifyFeature(offset);
              },
            ),

            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: GnssStatusWidget(
                onProviderSwitch: _switchLocationProvider,
                currentProvider:
                    _currentLocationDataSource == _realGnssDataSource
                    ? 'Real GNSS'
                    : _currentLocationDataSource == _mockGnssDataSource
                    ? 'Mock GNSS'
                    : _currentLocationDataSource == _usbGnssDataSource
                    ? 'USB GNSS'
                    : 'Device GPS',
                //currentProvider: _currentLocationDataSource is NmeaLocationDataSource ? 'Mock GNSS' : 'Device GPS',
                providerStatus: _locationStatus ?? 'Unknown',
                accuracy: _accuracy,
                satelliteCount: _satelliteCount,
                fixType: _fixType,
                // onAddProvider: _showGnssProviderDialog,
                onAddProvider: _showGnssTransportDialog,
              ),
            ),

            // Progress Indicators
            BlocBuilder<MapBloc, MapState>(
              builder: (context, state) {
                if (state.isDownloading) {
                  return Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: LinearProgressIndicator(
                      value: state.offlineDownloadProgress,
                      backgroundColor: Colors.white24,
                    ),
                  );
                }
                if (state.isSyncing) {
                  return Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: LinearProgressIndicator(
                      value: state.offlineSyncProgress,
                      backgroundColor: Colors.white24,
                      color: Colors.orange,
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),

            BlocBuilder<MapBloc, MapState>(
              builder: (context, state) {
                if (state is CollectionState &&
                    state.mode == CollectionMode.pickingLocation) {
                  return Center(
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.blue, width: 3),
                      ),
                      child: const Icon(
                        Icons.add,
                        color: Colors.blue,
                        size: 32,
                      ),
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),

            Positioned(
              bottom: 24,
              right: 24,
              child: BlocBuilder<MapBloc, MapState>(
                builder: (context, state) {
                  bool isPicking =
                      state is CollectionState &&
                      (state.mode == CollectionMode.pickingLocation ||
                          state.mode == CollectionMode.fillingForm);
                  return Column(
                    children: [
                      if (!isPicking)
                        FloatingActionButton(
                          heroTag: 'add_feature',
                          onPressed: _startCollection,
                          child: const Icon(Icons.add),
                        ),
                      const SizedBox(height: 16),
                      FloatingActionButton(
                        heroTag: 'my_location',
                        onPressed: _goToMyLocation,
                        child: const Icon(Icons.my_location),
                      ),
                    ],
                  );
                },
              ),
            ),

            BlocBuilder<MapBloc, MapState>(
              builder: (context, state) {
                if (state is CollectionState &&
                    state.mode == CollectionMode.pickingLocation) {
                  final hasLocation = state.draftFeature?.geometry != null;
                  return Positioned(
                    bottom: 80,
                    left: 20,
                    right: 20,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00A9E0),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      // onPressed: _captureLocation,
                      onPressed: _showLocationCaptureOptions,
                      child: Text(
                        hasLocation ? 'UPDATE POINT' : 'ADD POINT',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showBasemapGallery() {
    final portal = Portal.arcGISOnline(
      connection: PortalConnection.authenticated,
    );

    final controller = BasemapGalleryController.withPortal(
      portal,
      geoModel: _map,
    );

    controller.onBasemapChanged = (basemap) {
      if (mounted) {
        Navigator.of(context).pop();
      }
    };

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SizedBox(
          height: MediaQuery.of(sheetContext).size.height * 0.75,
          child: BasemapGallery(controller: controller),
        );
      },
    ).whenComplete(controller.dispose);
  }

  void _showLayersSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        final operationalLayers = _map.operationalLayers.toList();
        // final baseLayers = _map.basemap?.baseLayers.toList() ?? <Layer>[];
        // final referenceLayers =
        //     _map.basemap?.referenceLayers.toList() ?? <Layer>[];

        return StatefulBuilder(
          builder: (context, sheetSetState) {
            return SafeArea(
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.75,
                child: ListView(
                  padding: const EdgeInsets.only(top: 16, bottom: 24),
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20),
                      child: Text(
                        'Layers',
                        style: TextStyle(
                          color: Colors.black87,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    _buildLayerSectionTitle('Map layers'),

                    if (operationalLayers.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        child: Text(
                          'No map layers',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    else
                      ...operationalLayers.map(
                        (layer) =>
                            _buildOperationalLayerTile(layer, sheetSetState),
                      ),

                    const SizedBox(height: 12),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildLayerSectionTitle(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
    child: Text(
      title,
      style: const TextStyle(
        color: Colors.grey,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  Widget _buildOperationalLayerTile(
    Layer layer,
    void Function(VoidCallback) sheetSetState,
  ) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),

      leading: const Icon(
        Icons.layers_outlined,
        color: Colors.blueGrey,
        size: 30,
      ),

      title: Text(
        layer.name.isNotEmpty ? layer.name : 'Untitled layer',
        style: const TextStyle(color: Colors.black87, fontSize: 16),
      ),

      trailing: Checkbox(
        value: layer.isVisible,

        onChanged: (bool? value) {
          if (value == null) return;

          // Update ArcGIS layer
          layer.isVisible = value;

          sheetSetState(() {});
        },
      ),
    );
  }

  void _goToDefaultMapExtent() {
    final viewpoint = _map.initialViewpoint;
    if (viewpoint == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Default map extent is not available.')),
      );
      return;
    }
    _mapController?.setViewpoint(viewpoint);
  }

  void _showCollectionForm(BuildContext context) {
    final bloc = context.read<MapBloc>();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          _FeatureCollectionForm(onUpdatePoint: _beginLocationUpdate),
    ).then((_) {
      if (_returningToMapForLocationUpdate) {
        _returningToMapForLocationUpdate = false;
        return;
      }
      if (bloc.state is CollectionState &&
          (bloc.state as CollectionState).mode == CollectionMode.fillingForm) {
        bloc.add(CancelCollection());
      }
    });
  }

  Future<void> _showCreatedFeaturePopup({
    required GisFeature feature,
    required FeatureLayer layer,
  }) async {
    if (!mounted) return;

    final table = layer.featureTable;

    if (table == null) {
      debugPrint('Cannot show popup: FeatureTable is null');
      return;
    }

    try {
      ArcGISFeature? serverFeature;

      // GET THE ACTUAL FEATURE FROM ARCGIS SERVER

      if (feature.id.isNotEmpty) {
        if (table.loadStatus != LoadStatus.loaded) {
          await table.load();
        }

        if (table is! ArcGISFeatureTable) {
          debugPrint('CREATED POPUP: Table is not an ArcGISFeatureTable');
          return;
        }

        final objectIdField = table.objectIdField;

        final queryParameters = QueryParameters()
          ..whereClause = '$objectIdField = ${feature.id}';

        debugPrint(
          'CREATED POPUP: Querying server feature '
          '$objectIdField = ${feature.id}',
        );

        final result = await table.queryFeatures(queryParameters);

        final features = result.features();

        if (features.isNotEmpty && features.first is ArcGISFeature) {
          serverFeature = features.first as ArcGISFeature;

          debugPrint('CREATED POPUP: Server feature found: ${feature.id}');

          if (table is ServiceFeatureTable) {
            await table.loadOrRefreshFeatures([serverFeature]);

            debugPrint('CREATED POPUP: Server feature refreshed successfully');
          }
        } else {
          debugPrint(
            'CREATED POPUP: Server feature not found for ID ${feature.id}',
          );
        }
      }

      // USE SERVER FEATURE FOR POPUP

      if (serverFeature != null) {
        final popupDefinition =
            table.getPopupDefinitionWithFeature(serverFeature) ??
            layer.popupDefinition;

        if (popupDefinition == null) {
          debugPrint('CREATED POPUP: No popup definition available');
          return;
        }

        final popup = Popup(
          geoElement: serverFeature,
          popupDefinition: popupDefinition,
        );

        debugPrint('CREATED POPUP: Opening popup using SERVER feature');

        _showFeaturePopup(popup: popup, feature: feature, layer: layer);

        return;
      }

      // FALLBACK

      debugPrint('CREATED POPUP: Falling back to temporary feature');

      final arcFeature = table.createFeature(geometry: feature.geometry);

      for (final entry in feature.attributes.entries) {
        arcFeature.attributes[entry.key] = entry.value;
      }

      final popupDefinition =
          table.getPopupDefinitionWithFeature(arcFeature) ??
          layer.popupDefinition;

      if (popupDefinition == null) {
        debugPrint('CREATED POPUP: No popup definition available in fallback');
        return;
      }

      final popup = Popup(
        geoElement: arcFeature,
        popupDefinition: popupDefinition,
      );

      _showFeaturePopup(popup: popup, feature: feature, layer: layer);
    } catch (e, stackTrace) {
      debugPrint('CREATED FEATURE POPUP ERROR: $e');
      debugPrint('CREATED FEATURE POPUP STACKTRACE: $stackTrace');

      // FINAL FALLBACK

      try {
        final arcFeature = table.createFeature(geometry: feature.geometry);

        for (final entry in feature.attributes.entries) {
          arcFeature.attributes[entry.key] = entry.value;
        }

        final popupDefinition =
            table.getPopupDefinitionWithFeature(arcFeature) ??
            layer.popupDefinition;

        if (popupDefinition == null) return;

        final popup = Popup(
          geoElement: arcFeature,
          popupDefinition: popupDefinition,
        );

        _showFeaturePopup(popup: popup, feature: feature, layer: layer);
      } catch (fallbackError) {
        debugPrint('CREATED POPUP FALLBACK ERROR: $fallbackError');
      }
    }
  }

  void _showFeaturePopup({
    required Popup popup,
    required GisFeature feature,
    required FeatureLayer layer,
  }) {
    if (!mounted) return;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return _FeatureDetailsSheet(
          popup: popup,
          feature: feature,
          layer: layer,
        );
      },
    );
  }

}

class _FeatureCollectionForm extends StatefulWidget {
  final VoidCallback? onUpdatePoint;
  const _FeatureCollectionForm({this.onUpdatePoint});
  @override
  State<_FeatureCollectionForm> createState() => _FeatureCollectionFormState();
}

class _FeatureCollectionFormState extends State<_FeatureCollectionForm> {
  @override
  Widget build(BuildContext context) {
    return BlocBuilder<MapBloc, MapState>(
      builder: (context, state) {
        if (state is! CollectionState) return const SizedBox.shrink();
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
            left: 16,
            right: 16,
            top: 16,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      state.isEdit ? 'Edit Feature' : 'New Feature',
                      style: const TextStyle(
                        color: Colors.black87,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (state.mode == CollectionMode.submitting)
                      const CircularProgressIndicator()
                    else
                      IconButton(
                        icon: const Icon(Icons.check, color: Colors.black87),
                        onPressed: () =>
                            context.read<MapBloc>().add(SubmitDraftFeature()),
                      ),
                  ],
                ),
                if (state.errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      state.errorMessage!,
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ),
                const SizedBox(height: 16),
                ...state.editableFields.map(
                  (field) => _buildField(field, state.draftFeature!, context),
                ),
                if (state.isNewFeature &&
                    state.draftFeature?.geometry != null) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.blue,
                        side: const BorderSide(color: Colors.blue),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      icon: const Icon(Icons.location_on_outlined),
                      label: const Text(
                        'UPDATE POINT',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      onPressed: widget.onUpdatePoint,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                const Text(
                  'Attachments',
                  style: TextStyle(
                    color: Colors.black87,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.black87,
                          side: const BorderSide(color: Colors.grey),
                        ),
                        icon: const Icon(Icons.camera_alt),
                        label: const Text('TAKE PHOTO'),
                        onPressed: () => _takePhoto(context),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.black87,
                          side: const BorderSide(color: Colors.grey),
                        ),
                        icon: const Icon(Icons.attach_file),
                        label: const Text('ATTACH'),
                        onPressed: () => _attachFile(context),
                      ),
                    ),
                  ],
                ),
                if (state.draftFeature?.attachments.isNotEmpty ?? false)
                  Container(
                    height: 100,
                    margin: const EdgeInsets.only(top: 16),
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: state.draftFeature!.attachments.length,
                      itemBuilder: (context, index) {
                        final file = state.draftFeature!.attachments[index];
                        final extension = file.path
                            .split('.')
                            .last
                            .toLowerCase();

                        final isImage =
                            extension == 'jpg' ||
                            extension == 'jpeg' ||
                            extension == 'png';

                        return Stack(
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(right: 8.0),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: isImage
                                    ? Image.file(
                                        file,
                                        width: 100,
                                        height: 100,
                                        fit: BoxFit.cover,
                                      )
                                    : Container(
                                        width: 100,
                                        height: 100,
                                        color: Colors.grey.shade900,
                                        child: const Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.picture_as_pdf,
                                              color: Colors.red,
                                              size: 36,
                                            ),
                                            SizedBox(height: 4),
                                            Text(
                                              'PDF',
                                              style: TextStyle(
                                                color: Colors.black87,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                              ),
                            ),

                            Positioned(
                              top: 0,
                              right: 8,
                              child: IconButton(
                                icon: const Icon(
                                  Icons.remove_circle,
                                  color: Colors.red,
                                ),
                                onPressed: () => context.read<MapBloc>().add(
                                  RemoveDraftAttachment(index),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildField(Field field, GisFeature draft, BuildContext context) {
    final domain = field.domain;
    final label = field.alias.isNotEmpty ? field.alias : field.name;

    //  Dropdown
    if (domain is CodedValueDomain) {
      return _buildDropdownField(
        label: label,
        value: draft.attributes[field.name]?.toString(),
        options: domain.codedValues,
        onChanged: (value) {
          context.read<MapBloc>().add(
            UpdateDraftAttributes({field.name: value}),
          );
        },
        context: context,
      );
    }

    // 2. Date Only -> Date picker
    if (field.type == FieldType.dateOnly) {
      final value = draft.attributes[field.name];

      DateOnly? selectedDate;

      if (value is DateOnly) {
        selectedDate = value;
      }

      return Padding(
        padding: const EdgeInsets.only(bottom: 16.0),
        child: GestureDetector(
          onTap: () async {
            final bloc = context.read<MapBloc>();

            final pickedDate = await showDatePicker(
              context: context,
              initialDate: selectedDate != null
                  ? DateTime(
                      selectedDate.year,
                      selectedDate.month,
                      selectedDate.day,
                    )
                  : DateTime.now(),
              firstDate: DateTime(1900),
              lastDate: DateTime(2100),
            );

            if (pickedDate != null) {
              bloc.add(
                UpdateDraftAttributes({
                  field.name: DateOnly.withYearMonthDay(
                    year: pickedDate.year,
                    month: pickedDate.month,
                    day: pickedDate.day,
                  ),
                }),
              );
            }
          },
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: label,
              labelStyle: const TextStyle(color: Colors.grey),
              enabledBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.grey),
              ),

              focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.blue),
              ),
              suffixIcon: const Icon(Icons.calendar_today, color: Colors.grey),
            ),
            child: Text(
              selectedDate != null
                  ? '${selectedDate.day.toString().padLeft(2, '0')}/'
                        '${selectedDate.month.toString().padLeft(2, '0')}/'
                        '${selectedDate.year}'
                  : 'Select Date',
              style: const TextStyle(color: Colors.grey),
            ),
          ),
        ),
      );
    }

    // 3. Date + Time -> Date picker + Time picker
    if (field.type == FieldType.date) {
      final value = draft.attributes[field.name];

      DateTime? selectedDateTime;

      if (value is DateTime) {
        selectedDateTime = value;
      }

      return Padding(
        padding: const EdgeInsets.only(bottom: 16.0),
        child: GestureDetector(
          onTap: () async {
            final bloc = context.read<MapBloc>();

            final now = DateTime.now();

            // Step 1: Select date
            final pickedDate = await showDatePicker(
              context: context,
              initialDate: selectedDateTime ?? now,
              firstDate: DateTime(1900),
              lastDate: DateTime(2100),
            );

            if (pickedDate == null) {
              return;
            }

            if (!context.mounted) {
              return;
            }

            // Step 2: Select time
            final pickedTime = await showTimePicker(
              context: context,
              initialTime: selectedDateTime != null
                  ? TimeOfDay.fromDateTime(selectedDateTime)
                  : TimeOfDay.fromDateTime(now),
            );

            if (pickedTime == null) {
              return;
            }

            // Step 3: Combine date + time
            final selectedDateTimeValue = DateTime(
              pickedDate.year,
              pickedDate.month,
              pickedDate.day,
              pickedTime.hour,
              pickedTime.minute,
            );

            // Step 4: Store using the actual ArcGIS field name
            bloc.add(
              UpdateDraftAttributes({field.name: selectedDateTimeValue}),
            );
          },
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: label,
              labelStyle: const TextStyle(color: Colors.grey),
              enabledBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.grey),
              ),
              focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.blue),
              ),
              suffixIcon: const Icon(Icons.calendar_month, color: Colors.grey),
            ),
            child: Text(
              selectedDateTime != null
                  ? _formatDateTime(selectedDateTime)
                  : 'Select Date & Time',
              style: const TextStyle(color: Colors.grey),
            ),
          ),
        ),
      );
    }

    // 4. All other fields
    return _CollectionTextField(
      key: ValueKey(field.name),
      field: field,
      draft: draft,
    );
  }

  Widget _buildDropdownField({
    required String label,
    String? value,
    required List<CodedValue> options,
    required Function(dynamic) onChanged,
    required BuildContext context,
  }) {
    CodedValue? current;
    try {
      current = options.firstWhere((o) => o.code.toString() == value);
    } catch (_) {}
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          DropdownButton<dynamic>(
            value: current?.code,
            isExpanded: true,
            dropdownColor: Colors.white,
            style: const TextStyle(color: Colors.black87),
            hint: const Text('No value', style: TextStyle(color: Colors.grey)),
            underline: Container(height: 1, color: Colors.grey),
            items: options
                .map(
                  (e) => DropdownMenuItem(value: e.code, child: Text(e.name)),
                )
                .toList(),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  void _takePhoto(BuildContext context) async {
    final picker = ImagePicker();
    final photo = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 80,
    );
    if (photo != null)
      context.read<MapBloc>().add(AddDraftAttachment(File(photo.path)));
  }

  void _attachFile(BuildContext context) async {
    final result = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
    );

    if (result != null && result.path != null) {
      final file = File(result.path!);

      if (!context.mounted) return;

      context.read<MapBloc>().add(AddDraftAttachment(file));
    }
  }

  String _formatDateTime(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    final year = value.year.toString();

    final hour = value.hour == 0
        ? 12
        : value.hour > 12
        ? value.hour - 12
        : value.hour;

    final minute = value.minute.toString().padLeft(2, '0');

    final period = value.hour >= 12 ? 'PM' : 'AM';

    return '$day/$month/$year $hour:$minute $period';
  }
}

class _CollectionTextField extends StatefulWidget {
  final Field field;
  final GisFeature draft;
  const _CollectionTextField({
    super.key,
    required this.field,
    required this.draft,
  });
  @override
  State<_CollectionTextField> createState() => _CollectionTextFieldState();
}

class _CollectionTextFieldState extends State<_CollectionTextField> {
  late final TextEditingController _controller;

  @override
  @override
  void initState() {
    super.initState();

    _controller = TextEditingController(
      text: widget.draft.attributes[widget.field.name]?.toString() ?? '',
    );
  }

  // @override
  // void initState() { super.initState(); _controller = TextEditingController(text: widget.draft.attributes[widget.field.name]?.toString() ?? ''); }
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: TextField(
        controller: _controller,
        style: const TextStyle(color: Colors.black87),
        decoration: InputDecoration(
          labelText: widget.field.alias.isNotEmpty
              ? widget.field.alias
              : widget.field.name,
          labelStyle: const TextStyle(color: Colors.grey),
          enabledBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: Colors.grey),
          ),
          focusedBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: Colors.blue),
          ),
        ),
        onChanged: (val) => context.read<MapBloc>().add(
          UpdateDraftAttributes({widget.field.name: val}),
        ),
      ),
    );
  }
}

class _FeatureDetailsSheet extends StatelessWidget {
  final Popup popup;
  final GisFeature feature;
  final FeatureLayer layer;

  const _FeatureDetailsSheet({
    required this.popup,
    required this.feature,
    required this.layer,
  });

  static const Color _primaryColor = Color(0xFF0079C1);
  static const Color _backgroundColor = Color(0xFFF8F9FA);
  static const Color _borderColor = Color(0xFFE2E5E8);
  static const Color _textColor = Color(0xFF202124);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.sizeOf(context).height * 0.78,
      decoration: const BoxDecoration(
        color: _backgroundColor,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // ARCGIS WEB MAP POPUP
          Expanded(
            child: Container(
              color: _backgroundColor,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: PopupView(
                popup: popup,
                onClose: () {
                  Navigator.of(context).pop();
                },
              ),
            ),
          ),

          // ACTION BAR
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: _borderColor, width: 1)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: _FeatureActionButton(
                        icon: Icons.edit_outlined,
                        label: 'Edit',
                        onTap: () {
                          Navigator.pop(context);

                          context.read<MapBloc>().add(
                            EditFeatureRequested(feature, layer),
                          );
                        },
                      ),
                    ),

                    Expanded(
                      child: _FeatureActionButton(
                        icon: Icons.copy_outlined,
                        label: 'Copy',
                        onTap: () {
                          Navigator.pop(context);

                          context.read<MapBloc>().add(
                            CopyFeatureRequested(feature, layer),
                          );
                        },
                      ),
                    ),

                    Expanded(
                      child: _FeatureActionButton(
                        icon: Icons.add_location_alt_outlined,
                        label: 'Collect Here',
                        onTap: () {
                          Navigator.pop(context);

                          context.read<MapBloc>().add(
                            CollectHereRequested(feature, layer),
                          );
                        },
                      ),
                    ),

                    Expanded(
                      child: _FeatureActionButton(
                        icon: Icons.delete_outline,
                        label: 'Delete',
                        color: Colors.red,
                        onTap: () {
                          _confirmDelete(context);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,
          title: const Text(
            'Delete Feature?',
            style: TextStyle(color: _textColor, fontWeight: FontWeight.w700),
          ),
          content: const Text(
            'This action cannot be undone.',
            style: TextStyle(color: Color(0xFF5F6368)),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
              },
              child: const Text(
                'CANCEL',
                style: TextStyle(
                  color: _primaryColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                final bloc = context.read<MapBloc>();

                Navigator.pop(dialogContext);
                Navigator.pop(context);

                bloc.add(DeleteFeatureRequested(feature, layer));
              },
              child: const Text(
                'DELETE',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _FeatureActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  const _FeatureActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final actionColor = color ?? const Color(0xFF0079C1);

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 38,
              decoration: BoxDecoration(
                color: actionColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: actionColor, size: 23),
            ),

            const SizedBox(height: 5),

            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: actionColor,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        IconButton(
          icon: Icon(icon, color: color ?? Colors.blue),
          onPressed: onTap,
        ),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 10)),
      ],
    );
  }
}
