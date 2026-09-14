import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:arcgis_maps/arcgis_maps.dart';
import 'package:arcgis_maps_toolkit/arcgis_maps_toolkit.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:gov_gis_map/core/utils/arcgis_extensions.dart';
import 'package:gov_gis_map/domain/entities/gis_feature.dart';
import 'package:gov_gis_map/presentation/map/bloc/map_bloc.dart';
import 'package:gov_gis_map/core/gnss/mock_nmea_provider.dart';
import 'package:gov_gis_map/presentation/map/widgets/gnss_status_widget.dart';
import 'dart:async';

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
  final _mockNmeaProvider = MockNmeaProvider();
  bool _locationStarted = false;
  late ArcGISMap _map;
  late LocationDataSource _currentLocationDataSource;

  static final _locationChannel = MethodChannel('com.example.gov_gis_map/location_settings');

  String? _locationStatus = 'Initializing...';
  final String _layerUrl = 'https://services8.arcgis.com/OFjCtQPTf3SnshL1/arcgis/rest/services/Pole/FeatureServer/0';

  ArcGISLocation? _lastKnownLocation;
  int _satelliteCount = 0;
  String _fixType = 'System GPS';
  double _accuracy = 0.0;
  StreamSubscription<String>? _mockNmeaSubscription;

  @override
  void initState() {
    super.initState();
    debugPrint('Initializing MapPage');
    _currentLocationDataSource = _locationDataSource; // Default to SystemLocationDataSource.
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
    if (!bloc.state.isOfflineMode) {
      for (var i = 0; i < _map.operationalLayers.length; i++) {
        final layer = _map.operationalLayers[i];
        if (layer is FeatureLayer) {
          final table = layer.featureTable;
          if (table is ServiceFeatureTable) {
            final sharedTable = await bloc.mapRepository.getServiceFeatureTable(table.uri.toString());
            if (sharedTable != table) {
              _map.operationalLayers[i] = FeatureLayer.withFeatureTable(sharedTable);
            }
          }
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

  @override
  void dispose() {
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
          content: Text('Location permission is required to show your position.'),
        ),
      );

      return false;
    }

    // 2. Permission granted → now check Location Service
    final serviceStatus =
    await Permission.locationWhenInUse.serviceStatus;

    if (!serviceStatus.isEnabled) {
      if (!mounted) return false;

      setState(() {
        _locationStatus = 'Location service is OFF';
      });

      try {
        final result = await _locationChannel.invokeMethod<String>('resolveLocationSettings');
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
      _locationSubscription = _currentLocationDataSource.onLocationChanged.listen(
                (location) async {
                  debugPrint('LOCATION GETTING');
              final position =
                  location.position;

              final latitude =
                  position.y;

              final longitude =
                  position.x;

              debugPrint(
                'CURRENT LOCATION => '
                    'Lat: $latitude, '
                    'Lng: $longitude',
              );
              setState(() {
                _lastKnownLocation = location;
                //_accuracy = location.horizontalAccuracy;
                _accuracy = _currentLocationDataSource is NmeaLocationDataSource
                    ? 0.9
                    : location.horizontalAccuracy;
                _locationStatus = 'Current location acquired';
              });

              if (!mounted) {
                return;
              }
              if (!cameraPositioned){

                cameraPositioned = true;

                await _mapController?.setViewpointCenter(
                  position,
                  scale: 10000,
                );
              }
              // Move map to user's current location

            },
          );

    } catch (e) {

      debugPrint(
        'LOCATION ERROR => $e',
      );

      _locationStarted = false;
    }
  }



  FeatureLayer? get _firstEditableLayer {
    try {
      return _map.operationalLayers.whereType<FeatureLayer>().firstWhere(
            (layer) {
          final table = layer.featureTable;
          return table != null && table.canAdd();
        },
      );
    } catch (_) {
      return null;
    }
  }

  void _identifyFeature(Offset screenPoint) async {
    if (_mapController == null) return;

    final bloc = context.read<MapBloc>();

    debugPrint('MAP TAP: Offset $screenPoint');

    // Don't identify features while collecting a new feature.
    if (bloc.state is CollectionState &&
        (bloc.state as CollectionState).mode != CollectionMode.idle &&
        (bloc.state as CollectionState).mode != CollectionMode.viewDetails) {
      debugPrint('MAP TAP: Ignored due to active collection mode: ${(bloc.state as CollectionState).mode}');
      return;
    }

    try {
      final results = await _mapController!.identifyLayers(
        screenPoint: screenPoint,
        tolerance: 20, // Increased tolerance for easier tapping
        returnPopupsOnly: false,
      );

      debugPrint('MAP TAP: Identified ${results.length} layers');

      for (final layerResult in results) {
        debugPrint('Layer: ${layerResult.layerContent.name}, Elements: ${layerResult.geoElements.length}');
        
        if (layerResult.geoElements.isNotEmpty) {
          final element = layerResult.geoElements.first;

          if (element is Feature) {
            final table = element.featureTable;
            debugPrint('Feature found in table: ${table?.tableName}');
            
            final attributes = Map<String, dynamic>.from(element.attributes);
            debugPrint('Feature Attributes: $attributes');

            String objectId = '';
            if (table is ArcGISFeatureTable) {
              objectId = element.attributes[table.objectIdField]?.toString() ?? '';
            } else {
              objectId = element.attributes['OBJECTID']?.toString() ?? 
                         element.attributes['objectid']?.toString() ?? 
                         element.attributes['fid']?.toString() ?? '';
            }

            final gisFeature = GisFeature(
              id: objectId,
              geometry: element.geometry,
              attributes: attributes,
            );

            if (layerResult.layerContent is FeatureLayer) {
              debugPrint('Showing attributes for layer: ${layerResult.layerContent.name}');
              _showFeatureAttributes(
                gisFeature,
                layerResult.layerContent as FeatureLayer,
              );
              return; // Show first one and exit
            }
          }
        }
        
        // Check sublayers (e.g. if the layer is a GroupLayer or MapImageLayer)
        for (final subResult in layerResult.sublayerResults) {
          debugPrint('Sublayer: ${subResult.layerContent.name}, Elements: ${subResult.geoElements.length}');
          if (subResult.geoElements.isNotEmpty) {
            final element = subResult.geoElements.first;
            if (element is Feature) {
              final gisFeature = GisFeature(
                id: element.attributes['OBJECTID']?.toString() ?? '',
                geometry: element.geometry,
                attributes: Map<String, dynamic>.from(element.attributes),
              );
              if (subResult.layerContent is FeatureLayer) {
                 _showFeatureAttributes(gisFeature, subResult.layerContent as FeatureLayer);
                 return;
              }
            }
          }
        }
      }
      
      debugPrint('MAP TAP: No feature found at this location.');
    } catch (e) {
      debugPrint('MAP TAP ERROR: $e');
    }
  }

  void _showFeatureAttributes(
      GisFeature feature,
      FeatureLayer layer,
      ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _FeatureDetailsSheet(
        feature: feature,
        layer: layer,
      ),
    );
  }

  void _startCollection() {
    final layer = _firstEditableLayer;

    if (layer != null) {
      context.read<MapBloc>().add(
        StartCollectionRequested(layer),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No editable layers found in this map.'),
        ),
      );
    }
  }

  Future<void> _exitOfflineMap() async {
    try {
      debugPrint('========== EXIT OFFLINE MAP ==========');

      // Create the ONLINE map again
      if (widget.portalItem != null) {
        _map = ArcGISMap.withItem(widget.portalItem!);
      } else {
        _map = ArcGISMap.withBasemapStyle(
          BasemapStyle.arcGISImageryStandard,
        );

        final featureLayer = FeatureLayerExtension.fromUrl(
          Uri.parse(_layerUrl),
        );

        _map.operationalLayers.add(featureLayer);
      }

      // Load online map
      await _map.load();

      if (!mounted) return;

      // IMPORTANT:
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
        await controller.setViewpointCenter(
          location!.position,
          scale: 3000,
        );

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

    if (state is! CollectionState || !state.isNewFeature || state.draftFeature?.geometry == null) {
      return;
    }

    _returningToMapForLocationUpdate = true;
    Navigator.of(context).pop();
    bloc.add(BeginLocationUpdate());
  }

  void _captureLocation() {
    final controller = _mapController;

    if (controller == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Map is not ready yet.')),
      );
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

    debugPrint('========== SELECTED MAP LOCATION ==========');
    debugPrint('X/LONGITUDE: ${center.x}');
    debugPrint('Y/LATITUDE: ${center.y}');
    debugPrint('============================================');

    context.read<MapBloc>().add(
      LocationCaptured(center),
    );
  }

  void _switchLocationProvider(bool useMockGnss) async {
    try {
      await _currentLocationDataSource.stop();
    } catch (_) {}
    await _locationSubscription?.cancel();
    await _satellitesSubscription?.cancel();
    await _statusSubscription?.cancel();

    // Immediately reset stale display values belonging to the previous provider
    setState(() {
      _lastKnownLocation = null;
      _accuracy = 0.0;
      _satelliteCount = 0;
      _locationStatus = 'Acquiring location...';
      if (useMockGnss) {
        _fixType = 'Acquiring Mock GNSS...';
      } else {
        _fixType = 'Acquiring Device GPS...';
      }
    });

    if (useMockGnss) {
      if (_mockGnssDataSource == null) {
        _mockGnssDataSource = NmeaLocationDataSource.withProvider(() async {
          //_mockNmeaProvider.startSimulation();
          return _mockNmeaProvider;
        });
      }
      _currentLocationDataSource = _mockGnssDataSource!;

      _mockNmeaSubscription = _mockNmeaProvider.nmeaData.listen((sentence) {
        if (!sentence.startsWith('\$GPGSA')) {
          return;
        }

        final withoutChecksum = sentence.split('*').first;
        final fields = withoutChecksum.split(',');

        // GPGSA:
        // 0 = GPGSA
        // 1 = mode
        // 2 = fix type
        // 3..14 = satellite PRNs
        //
        // Therefore count non-empty fields from index 3 to 14.
        int count = 0;

        for (int i = 3; i <= 14 && i < fields.length; i++) {
          if (fields[i].trim().isNotEmpty) {
            count++;
          }
        }

        debugPrint(
          'MOCK NMEA SATELLITES => $count | $sentence',
        );

        if (!mounted) return;

        setState(() {
          _satelliteCount = count;
        });
      });
      _mockNmeaProvider.startSimulation();

      setState(() {
        _fixType = 'SIMULATED GNSS';
      });
    } else {
      _mockNmeaProvider.stopSimulation();
      _currentLocationDataSource = _locationDataSource;
      setState(() {
        _fixType = 'Device GPS';
      });
    }

    _statusSubscription = _currentLocationDataSource.onStatusChanged.listen((status) {
      if (!mounted) return;
      setState(() {
        _locationStatus = status.toString().split('.').last;
      });
    });

    // if (_mapController != null) {
    //   _mapController!.locationDisplay.dataSource = _currentLocationDataSource;
    //   _mapController!.locationDisplay.autoPanMode = LocationDisplayAutoPanMode.recenter;
    // }

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
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) => BlocBuilder<MapBloc, MapState>(
        builder: (context, state) {
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ListTile(
                  title: Text('Offline Maps', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
                ListTile(
                  leading: const Icon(Icons.download, color: Colors.blue),
                  title: const Text('Download Current Area', style: TextStyle(color: Colors.white)),
                  onTap: state.isDownloading ? null : () {
                    Navigator.pop(context);
                    final extent = _mapController?.visibleArea?.extent;
                    final scale = _mapController?.scale ?? 0.0;

                    if (scale > 100000) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please zoom in further to download an offline map. The current area is too large.'),
                          backgroundColor: Colors.orange,
                        ),
                      );
                      return;
                    }

                    if (extent != null) {
                      context.read<MapBloc>().add(DownloadOfflineMap(_map, extent, currentScale: scale));
                    }
                  },
                ),
                ListTile(
                  leading: Icon(Icons.map, color: state.isOfflineMode ? Colors.green : Colors.grey),
                  title: Text(state.isOfflineMode ? 'Exit Offline Map' : 'Open Offline Map', style: const TextStyle(color: Colors.white)),
                  onTap: state.offlineMapPath == null ? null : () {
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
                  title: const Text('Sync Changes', style: TextStyle(color: Colors.white)),
                  onTap: (!state.isOfflineMode || state.isSyncing) ? null : () {
                    Navigator.pop(context);
                    context.read<MapBloc>().add(SyncOfflineChanges());
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete_forever, color: Colors.red),
                  title: const Text('Remove Offline Map', style: TextStyle(color: Colors.white)),
                  onTap: state.offlineMapPath == null ? null : () {
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
            final displayTitle =
            state.isOfflineMode ? '$title (Offline)' : title;

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
              context.read<MapBloc>().add(RefreshMapRequested(layerUrl: _layerUrl));
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
          if (current is CollectionState && current.mode == CollectionMode.fillingForm) {
            return previous is! CollectionState || previous.mode != CollectionMode.fillingForm;
          }
          // Only trigger viewDetails if we transition TO viewDetails
          if (current is CollectionState && current.mode == CollectionMode.viewDetails) {
            return previous is! CollectionState || previous.mode != CollectionMode.viewDetails;
          }
          if (current.isOfflineMode != previous.isOfflineMode) return true;
          if (current.isDownloading != previous.isDownloading) return true;
          if (current.isSyncing != previous.isSyncing) return true;
          return false;
        },
        listener: (context, state) {
          if (state is MapError) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.message), backgroundColor: Colors.red));
          }

          // Handle Download Notifications
          if (state.isDownloading && state.offlineDownloadProgress == 0.0) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Download started...'), duration: Duration(seconds: 2)),
            );
          } else if (!state.isDownloading && state.offlineDownloadProgress == 1.0) {
             ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Download completed successfully.'), backgroundColor: Colors.green, duration: Duration(seconds: 3)),
            );
          }

          // Handle Sync Notifications
          if (state.isSyncing && state.offlineSyncProgress == 0.0) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Sync started...'), duration: Duration(seconds: 2)),
            );
          } else if (!state.isSyncing && state.offlineSyncProgress == 1.0) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Sync completed successfully.'), backgroundColor: Colors.green, duration: Duration(seconds: 3)),
            );
          }

          if (state is CollectionState && state.mode == CollectionMode.fillingForm) {
            _showCollectionForm(context);
          }
          if (state is CollectionState && state.mode == CollectionMode.viewDetails) {
            if (mounted) {
              Navigator.pop(context); // Pop the form sheet
              _showFeatureAttributes(state.draftFeature!, state.targetLayer!);
            }
          }
          if (state.isOfflineMode && state.offlineMapPath != null) {
            context.read<MapBloc>().mapRepository.openOfflineMap(state.offlineMapPath!).then((offlineMap) {
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
                _mapController = ArcGISMapView.createController()..arcGISMap = _map;
                return _mapController!;
              },
              onMapViewReady: _onMapCreated,
              onTap: (offset) => _identifyFeature(offset),
            ),

            Positioned(
              top: 16, left: 16, right: 16,
              child: GnssStatusWidget(
                onProviderSwitch: _switchLocationProvider,
                currentProvider: _currentLocationDataSource is NmeaLocationDataSource ? 'Mock GNSS' : 'Device GPS',
                providerStatus: _locationStatus ?? 'Unknown',
                accuracy: _accuracy,
                satelliteCount: _satelliteCount,
                fixType: _fixType,
              ),
            ),

            // Progress Indicators
            BlocBuilder<MapBloc, MapState>(
              builder: (context, state) {
                if (state.isDownloading) {
                  return Positioned(
                    top: 0, left: 0, right: 0,
                    child: LinearProgressIndicator(value: state.offlineDownloadProgress, backgroundColor: Colors.white24),
                  );
                }
                if (state.isSyncing) {
                  return Positioned(
                    top: 0, left: 0, right: 0,
                    child: LinearProgressIndicator(value: state.offlineSyncProgress, backgroundColor: Colors.white24, color: Colors.orange),
                  );
                }
                return const SizedBox.shrink();
              },
            ),

            BlocBuilder<MapBloc, MapState>(
              builder: (context, state) {
                if (state is CollectionState && state.mode == CollectionMode.pickingLocation) {
                  return Center(
                    child: Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.blue, width: 3)),
                      child: const Icon(Icons.add, color: Colors.blue, size: 32),
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),

            Positioned(
              bottom: 24, right: 24,
              child: BlocBuilder<MapBloc, MapState>(
                builder: (context, state) {
                  bool isPicking = state is CollectionState && (state.mode == CollectionMode.pickingLocation || state.mode == CollectionMode.fillingForm);
                  return Column(
                    children: [
                      if (!isPicking)
                        FloatingActionButton(heroTag: 'add_feature', onPressed: _startCollection, child: const Icon(Icons.add)),
                      const SizedBox(height: 16),
                      FloatingActionButton(heroTag: 'my_location', onPressed: _goToMyLocation, child: const Icon(Icons.my_location)),
                    ],
                  );
                },
              ),
            ),

            BlocBuilder<MapBloc, MapState>(
              builder: (context, state) {
                if (state is CollectionState && state.mode == CollectionMode.pickingLocation) {
                  final hasLocation = state.draftFeature?.geometry != null;
                  return Positioned(
                    bottom: 80, left: 20, right: 20,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00A9E0), padding: const EdgeInsets.symmetric(vertical: 16)),
                      onPressed: _captureLocation,
                      child: Text(hasLocation ? 'UPDATE POINT' : 'ADD POINT', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
          child: BasemapGallery(
            controller: controller,
          ),
        );
      },
    ).whenComplete(
      controller.dispose,
    );
  }

  void _showLayersSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(16),
        ),
      ),
      builder: (sheetContext) {
        final operationalLayers = _map.operationalLayers.toList();
        final baseLayers =
            _map.basemap?.baseLayers.toList() ?? <Layer>[];
        final referenceLayers =
            _map.basemap?.referenceLayers.toList() ?? <Layer>[];

        return StatefulBuilder(
          builder: (context, sheetSetState) {
            return SafeArea(
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.75,
                child: ListView(
                  padding: const EdgeInsets.only(
                    top: 16,
                    bottom: 24,
                  ),
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20),
                      child: Text(
                        'Layers',
                        style: TextStyle(
                          color: Colors.white,
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
                          style: TextStyle(
                            color: Colors.grey,
                          ),
                        ),
                      )
                    else
                      ...operationalLayers.map(
                            (layer) => _buildOperationalLayerTile(
                          layer,
                          sheetSetState,
                        ),
                      ),

                    const SizedBox(height: 12),

                    _buildLayerSectionTitle(
                      'Basemap layers',
                    ),

                    if (baseLayers.isEmpty &&
                        referenceLayers.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        child: Text(
                          'No basemap layers',
                          style: TextStyle(
                            color: Colors.grey,
                          ),
                        ),
                      )
                    else ...[
                      ...baseLayers.map(
                            (layer) => _buildBasemapLayerTile(
                          layer,
                          sheetSetState,
                        ),
                      ),

                      ...referenceLayers.map(
                            (layer) => _buildBasemapLayerTile(
                          layer,
                          sheetSetState,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildLayerSectionTitle(String title) => Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 8), child: Text(title, style: const TextStyle(color: Colors.grey, fontSize: 14, fontWeight: FontWeight.w600)));

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
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
        ),
      ),

      trailing: Checkbox(
        value: layer.isVisible,

        onChanged: (bool? value) {
          if (value == null) return;

          // Update ArcGIS layer
          layer.isVisible = value;

          // IMPORTANT:
          // Rebuild the BottomSheet itself
          sheetSetState(() {});
        },
      ),
    );
  }

  Widget _buildBasemapLayerTile(Layer layer, void Function(VoidCallback) sheetSetState,) => ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 20), leading: const Icon(Icons.public, color: Colors.orange, size: 30), title: Text(layer.name.isNotEmpty ? layer.name : 'Basemap', style: const TextStyle(color: Colors.white, fontSize: 16)), trailing: Checkbox(value: layer.isVisible,
      onChanged: (value) {
        if (value == null) return;

        // Update ArcGIS layer
        layer.isVisible = value;

        // IMPORTANT:
        // Rebuild the BottomSheet itself
        sheetSetState(() {});
  }));

  void _goToDefaultMapExtent() {
    final viewpoint = _map.initialViewpoint;
    if (viewpoint == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Default map extent is not available.')));
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
      builder: (context) => _FeatureCollectionForm(onUpdatePoint: _beginLocationUpdate),
    ).then((_) {
      if (_returningToMapForLocationUpdate) {
        _returningToMapForLocationUpdate = false;
        return;
      }
      if (bloc.state is CollectionState && (bloc.state as CollectionState).mode == CollectionMode.fillingForm) {
        bloc.add(CancelCollection());
      }
    });
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
          decoration: const BoxDecoration(color: Color(0xFF1E1E1E), borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 20, left: 16, right: 16, top: 16),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(state.isEdit ? 'Edit Feature' : 'New Feature', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                    if (state.mode == CollectionMode.submitting) const CircularProgressIndicator()
                    else IconButton(icon: const Icon(Icons.check, color: Colors.white), onPressed: () => context.read<MapBloc>().add(SubmitDraftFeature())),
                  ],
                ),
                if (state.errorMessage != null) Padding(padding: const EdgeInsets.only(top: 8.0), child: Text(state.errorMessage!, style: const TextStyle(color: Colors.red, fontSize: 12))),
                const SizedBox(height: 16),
                ...state.editableFields.map((field) => _buildField(field, state.draftFeature!, context)),
                if (state.isNewFeature && state.draftFeature?.geometry != null) ...[
                  const SizedBox(height: 8),
                  SizedBox(width: double.infinity, child: OutlinedButton.icon(style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.blue), padding: const EdgeInsets.symmetric(vertical: 14)), icon: const Icon(Icons.location_on_outlined), label: const Text('UPDATE POINT', style: TextStyle(fontWeight: FontWeight.bold)), onPressed: widget.onUpdatePoint)),
                ],
                const SizedBox(height: 24),
                const Text('Attachments', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: OutlinedButton.icon(style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.grey)), icon: const Icon(Icons.camera_alt), label: const Text('TAKE PHOTO'), onPressed: () => _takePhoto(context))),
                    const SizedBox(width: 8),
                    Expanded(child: OutlinedButton.icon(style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.grey)), icon: const Icon(Icons.attach_file), label: const Text('ATTACH'), onPressed: () => _attachFile(context))),
                  ],
                ),
                if (state.draftFeature?.attachments.isNotEmpty ?? false)
                  Container(
                    height: 100, margin: const EdgeInsets.only(top: 16),
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: state.draftFeature!.attachments.length,
                      itemBuilder: (context, index) => Stack(
                        children: [
                          Padding(padding: const EdgeInsets.only(right: 8.0), child: ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.file(state.draftFeature!.attachments[index], width: 100, height: 100, fit: BoxFit.cover))),
                          Positioned(top: 0, right: 8, child: IconButton(icon: const Icon(Icons.remove_circle, color: Colors.red), onPressed: () => context.read<MapBloc>().add(RemoveDraftAttachment(index)))),
                        ],
                      ),
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
    if (domain is CodedValueDomain) {
      return _buildDropdownField(label: field.alias.isNotEmpty ? field.alias : field.name, value: draft.attributes[field.name]?.toString(), options: domain.codedValues, onChanged: (val) => context.read<MapBloc>().add(UpdateDraftAttributes({field.name: val})), context: context);
    } else if (field.type == FieldType.dateOnly) {
      final selectedDate = draft.attributes[field.name] as DateOnly?;
      return Padding(
        padding: const EdgeInsets.only(bottom: 16.0),
        child: GestureDetector(
          onTap: () async {
            final bloc = context.read<MapBloc>();
            final pickedDate = await showDatePicker(context: context, initialDate: selectedDate != null ? DateTime(selectedDate.year, selectedDate.month, selectedDate.day) : DateTime.now(), firstDate: DateTime(1900), lastDate: DateTime(2100));
            if (pickedDate != null) bloc.add(UpdateDraftAttributes({field.name: DateOnly.withYearMonthDay(year: pickedDate.year, month: pickedDate.month, day: pickedDate.day)}));
          },
          child: InputDecorator(decoration: InputDecoration(labelText: field.alias.isNotEmpty ? field.alias : field.name, labelStyle: const TextStyle(color: Colors.grey), enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey)), focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.blue))), child: Text(selectedDate != null ? '${selectedDate.day.toString().padLeft(2, '0')}/${selectedDate.month.toString().padLeft(2, '0')}/${selectedDate.year}' : 'Select Date', style: const TextStyle(color: Colors.white))),
        ),
      );
    } else {
      return _CollectionTextField(key: ValueKey(field.name), field: field, draft: draft);
    }
  }

  Widget _buildDropdownField(
      {required String label, String? value, required List<CodedValue> options, required Function(dynamic) onChanged, required BuildContext context}) {
    CodedValue? current;
    try { current = options.firstWhere((o) => o.code.toString() == value); } catch (_) {}
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          DropdownButton<dynamic>(value: current?.code, isExpanded: true, dropdownColor: const Color(0xFF1E1E1E), style: const TextStyle(color: Colors.white), hint: const Text('No value', style: TextStyle(color: Colors.grey)), underline: Container(height: 1, color: Colors.grey), items: options.map((e) => DropdownMenuItem(value: e.code, child: Text(e.name))).toList(), onChanged: onChanged),
        ],
      ),
    );
  }

  void _takePhoto(BuildContext context) async {
    final picker = ImagePicker();
    final photo = await picker.pickImage(source: ImageSource.camera, imageQuality: 80);
    if (photo != null) context.read<MapBloc>().add(AddDraftAttachment(File(photo.path)));
  }

  void _attachFile(BuildContext context) async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (image != null) context.read<MapBloc>().add(AddDraftAttachment(File(image.path)));
  }
}

class _CollectionTextField extends StatefulWidget {
  final Field field;
  final GisFeature draft;
  const _CollectionTextField({super.key, required this.field, required this.draft});
  @override
  State<_CollectionTextField> createState() => _CollectionTextFieldState();
}

class _CollectionTextFieldState extends State<_CollectionTextField> {
  late final TextEditingController _controller;
  @override
  void initState() { super.initState(); _controller = TextEditingController(text: widget.draft.attributes[widget.field.name]?.toString() ?? ''); }
  @override
  void dispose() { _controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: TextField(controller: _controller, style: const TextStyle(color: Colors.white), decoration: InputDecoration(labelText: widget.field.alias.isNotEmpty ? widget.field.alias : widget.field.name, labelStyle: const TextStyle(color: Colors.grey), enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey)), focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.blue))), onChanged: (val) => context.read<MapBloc>().add(UpdateDraftAttributes({widget.field.name: val}))),
    );
  }
}

class _FeatureDetailsSheet extends StatelessWidget {
  final GisFeature feature;
  final FeatureLayer layer;
  const _FeatureDetailsSheet({required this.feature, required this.layer});
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: Color(0xFF1E1E1E), borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                (() {
                  final poleIdKey = feature.attributes.keys.firstWhere(
                    (k) => k.toLowerCase() == 'pole_id',
                    orElse: () => 'pole_id',
                  );
                  final typeKey = feature.attributes.keys.firstWhere(
                    (k) => k.toLowerCase() == 'type',
                    orElse: () => 'Type',
                  );
                  return feature.attributes[poleIdKey] ?? feature.attributes[typeKey] ?? 'Feature';
                })(),
                style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
              ),
              IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
            ],
          ),
          const Divider(color: Colors.grey),
          if (feature.attributes.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: Text('No attributes available for this feature', style: TextStyle(color: Colors.grey))),
            ),
          ...['pole_id', 'pole_type', 'condition', 'status', 'remarks', 'survey_date'].map((key) {
            // Case-insensitive attribute lookup
            final actualKey = feature.attributes.keys.firstWhere(
              (k) => k.toLowerCase() == key.toLowerCase(),
              orElse: () => key,
            );
            final value = feature.attributes[actualKey];
            if (value == null) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4.0),
              child: Row(
                children: [
                  Text('$key: ', style: const TextStyle(color: Colors.grey)),
                  Expanded(child: Text('$value', style: const TextStyle(color: Colors.white))),
                ],
              ),
            );
          }),
          const SizedBox(height: 24),
          Wrap(
            spacing: 16, runSpacing: 16,
            children: [
              _ActionButton(icon: Icons.edit, label: 'Edit', onTap: () { Navigator.pop(context); context.read<MapBloc>().add(EditFeatureRequested(feature, layer)); }),
              _ActionButton(icon: Icons.copy, label: 'Copy', onTap: () { Navigator.pop(context); context.read<MapBloc>().add(CopyFeatureRequested(feature, layer)); }),
              _ActionButton(icon: Icons.add_location, label: 'Collect Here', onTap: () { Navigator.pop(context); context.read<MapBloc>().add(CollectHereRequested(feature, layer)); }),
              _ActionButton(icon: Icons.delete, label: 'Delete', color: Colors.red, onTap: () => _confirmDelete(context)),
            ],
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Delete Feature?', style: TextStyle(color: Colors.white)),
        content: const Text('This action cannot be undone.', style: TextStyle(color: Colors.grey)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('CANCEL')),
          TextButton(onPressed: () { final bloc = context.read<MapBloc>(); Navigator.pop(dialogContext); Navigator.pop(context); bloc.add(DeleteFeatureRequested(feature, layer)); }, child: const Text('DELETE', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  const _ActionButton({required this.icon, required this.label, required this.onTap, this.color});
  @override
  Widget build(BuildContext context) {
    return Column(children: [IconButton(icon: Icon(icon, color: color ?? Colors.blue), onPressed: onTap), Text(label, style: const TextStyle(color: Colors.white, fontSize: 10))]);
  }
}