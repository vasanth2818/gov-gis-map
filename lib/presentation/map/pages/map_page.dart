import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:arcgis_maps/arcgis_maps.dart';
import 'package:arcgis_maps_toolkit/arcgis_maps_toolkit.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:gov_gis_map/core/utils/arcgis_extensions.dart';
import 'package:gov_gis_map/domain/entities/gis_feature.dart';
import 'package:gov_gis_map/presentation/map/bloc/map_bloc.dart';
import 'dart:async';

class MapPage extends StatefulWidget {
  final PortalItem? portalItem;
  const MapPage({super.key, this.portalItem});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  ArcGISMapViewController? _mapController;


  StreamSubscription? _locationSubscription;
  final _locationDataSource = SystemLocationDataSource();
  late final ArcGISMap _map;

  bool _isGettingLocation = false;

  String? _locationStatus;
  final String _layerUrl = 'https://services8.arcgis.com/OFjCtQPTf3SnshL1/arcgis/rest/services/Pole/FeatureServer/0';

  @override
  void initState() {
    super.initState();
    debugPrint('Initializing MapPage');
    final bloc = context.read<MapBloc>();
    if (widget.portalItem != null) {
      _map = ArcGISMap.withItem(widget.portalItem!);
      debugPrint('PortalItem ID: ${widget.portalItem!.itemId}');
      debugPrint('PortalItem Title: ${widget.portalItem!.title}');
    } else {
      _map = ArcGISMap.withBasemapStyle(BasemapStyle.arcGISImageryStandard);
      final featureLayer = FeatureLayerExtension.fromUrl(Uri.parse(_layerUrl));
      _map.operationalLayers.add(featureLayer);
      debugPrint('Using fallback layer URL: $_layerUrl');
    }

    _map.load().then((_) async {
      bloc.add(PageInitialized());
      debugPrint('Map loaded successfully. Operational layers: ${_map.operationalLayers.length}');

      // Ensure shared table instances are used if possible
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

      for (final layer in _map.operationalLayers) {
        debugPrint('Layer Name: ${layer.name}, Layer Type: ${layer.runtimeType}');
        if (layer is FeatureLayer) {
          await layer.load();
          final table = layer.featureTable;
          if (table != null) {
            debugPrint('FeatureLayer Name: ${layer.name}');
            debugPrint('FeatureTable Type: ${table.runtimeType}');
            if (table is ServiceFeatureTable) {
              debugPrint('FeatureTable URI: ${table.uri}');
              await table.load();
              for (final field in table.fields) {
                debugPrint('Field Name: ${field.name}, Display Name: ${field.alias}, Type: ${field.type}');
              }
            }
          }
        }
      }
    });
  }
  @override
  void dispose() {
    _locationSubscription?.cancel();
    _mapController?.dispose();
    super.dispose();
  }
  void _onMapCreated() {
    debugPrint('Map creation complete. Loading map resources...');
    _map.load().then((_) async {
      debugPrint('Map loaded successfully. Checking for editable layers...');

      await _startUserLocation();

      final featureLayers = _map.operationalLayers.whereType<FeatureLayer>();

      for (final layer in featureLayers) {
        try {
          await layer.load();
          final table = layer.featureTable;
          if (table != null) {
            await table.load();
            if (table.canAdd()) {
              debugPrint('Found editable layer: ${layer.name}');
            }
          }
        } catch (e) {
          debugPrint('Error loading layer ${layer.name}: $e');
        }
      }

      if (_firstEditableLayer == null) {
        debugPrint('No editable layers found in map operational layers.');
      }
    });
  }
  Future<bool> _checkLocationRequirements() async {
    if (!mounted) return false;

    // Check if location services are enabled at the system level
    final serviceStatus = await Permission.location.serviceStatus;
    if (serviceStatus.isDisabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Location services are disabled. Please turn on GPS/Location in your device settings.'),
            duration: const Duration(seconds: 5),
            action: SnackBarAction(label: 'OK', onPressed: () {}),
          ),
        );
        setState(() {
          _isGettingLocation = false;
          _locationStatus = 'GPS Disabled';
        });
      }
      return false;
    }

    // Check location permission
    var status = await Permission.locationWhenInUse.status;
    if (status.isDenied) {
      status = await Permission.locationWhenInUse.request();
    }

    if (status.isPermanentlyDenied) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location permission is permanently denied. Please enable it in settings.'),
            action: SnackBarAction(label: 'SETTINGS', onPressed: openAppSettings),
          ),
        );
      }
      return false;
    }

    if (!status.isGranted) {
      if (mounted) {
        setState(() {
          _isGettingLocation = false;
          _locationStatus = 'Permission denied';
        });
      }
      return false;
    }

    return true;
  }

  Future<void> _startUserLocation() async {
    if (!mounted) return;

    if (!await _checkLocationRequirements()) return;

    setState(() {
      _isGettingLocation = true;
      _locationStatus = 'Getting GPS location...';
    });

    try {
      debugPrint('Starting user location...');

      _mapController?.locationDisplay.dataSource =
          _locationDataSource;

      _mapController?.locationDisplay.autoPanMode =
          LocationDisplayAutoPanMode.recenter;

      await _locationDataSource.start();

      _locationSubscription?.cancel();

      _locationSubscription =
          _locationDataSource.onLocationChanged.listen(
                (location) async {
              final position = location.position;

              if (!mounted) return;

              await _mapController?.setViewpointCenter(
                position,
                scale: 10000,
              );

              if (mounted) {
                setState(() {
                  _isGettingLocation = false;
                  _locationStatus = 'GPS location acquired';
                });

                // Hide success message after a short delay.
                Future.delayed(const Duration(seconds: 2), () {
                  if (!mounted) return;

                  setState(() {
                    _locationStatus = null;
                  });
                });
              }
            },
          );

      debugPrint('User location started successfully.');
    } on ArcGISException catch (e) {
      debugPrint('Location error: ${e.message}');

      if (mounted) {
        setState(() {
          _isGettingLocation = false;
          _locationStatus = 'GPS unavailable';
        });
      }
    } catch (e) {
      debugPrint('Location error: $e');

      if (mounted) {
        setState(() {
          _isGettingLocation = false;
          _locationStatus = 'GPS unavailable';
        });
      }
    }
  }
  FeatureLayer? get _firstEditableLayer {
    try {
      return _map.operationalLayers.whereType<FeatureLayer>().firstWhere(
            (l) {
          final table = l.featureTable;
          return table != null && table.canAdd();
        },
      );
    } catch (_) {
      return null;
    }
  }

  void _identifyFeature(Offset screenPoint) async {
    if (_mapController == null) return;

    // Don't identify if in collection mode
    final bloc = context.read<MapBloc>();
    if (bloc.state is CollectionState && (bloc.state as CollectionState).mode != CollectionMode.idle) {
      return;
    }

    final results = await _mapController!.identifyLayers(
      screenPoint: screenPoint,
      tolerance: 10,
      returnPopupsOnly: false,
    );

    if (results.isNotEmpty) {
      final layerResult = results.first;
      if (layerResult.geoElements.isNotEmpty) {
        final element = layerResult.geoElements.first;
        if (element is Feature) {
          final table = element.featureTable as ServiceFeatureTable;
          final objectIdField = table.objectIdField;
          final gisFeature = GisFeature(
            id: element.attributes[objectIdField]?.toString() ?? '',
            geometry: element.geometry,
            attributes: Map<String, dynamic>.from(element.attributes),
          );
          if (layerResult.layerContent is FeatureLayer) {
            _showFeatureAttributes(gisFeature, layerResult.layerContent as FeatureLayer);
          }
        }
      }
    }
  }

  void _showFeatureAttributes(GisFeature feature, FeatureLayer layer) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _FeatureDetailsSheet(feature: feature, layer: layer),
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

  Future<void> _goToMyLocation() async {
    if (!await _checkLocationRequirements()) return;

    try {
      final locationDisplay = _mapController?.locationDisplay;

      if (locationDisplay != null && !locationDisplay.started) {
        await locationDisplay.dataSource.start();
      }

      locationDisplay?.autoPanMode =
          LocationDisplayAutoPanMode.recenter;

      debugPrint('Moving camera to user location...');
    } catch (e) {
      debugPrint('Unable to get user location: $e');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to get current location'),
          ),
        );
      }
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

  void _captureLocation() async {
    final controller = _mapController;
    if (controller == null) return;

    final visibleArea = controller.visibleArea;
    final extent = visibleArea?.extent;
    final center = extent?.center;

    if (center != null) {
      context.read<MapBloc>().add(LocationCaptured(center));
    }
  }

  void _refreshLayers() async {
    for (final layer in _map.operationalLayers) {
      if (layer is FeatureLayer) {
        final table = layer.featureTable;
        if (table is ServiceFeatureTable) {
          // Force a redraw if needed. In SDK 300.x, shared instances usually update.
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text(widget.portalItem?.title ?? ' '),

        actions: [
          // Sync
          IconButton(
            icon: const Icon(Icons.sync),
            tooltip: 'Sync',
            onPressed: () {
              final bloc = context.read<MapBloc>();

              bloc.add(
                RefreshMapRequested(
                  layerUrl: _layerUrl,
                ),
              );
            },
          ),

          // Layers
          IconButton(
            icon: const Icon(Icons.layers),
            tooltip: 'Layers',
            onPressed: _showLayersSheet,
          ),

          // More menu

          PopupMenuButton<String>(
            offset: const Offset(0, 60),
            icon: const Icon(Icons.more_vert),
            tooltip: 'More',
            onSelected: (value) {
              switch (value) {
                case 'basemap':
                  _showBasemapGallery();
                  break;

                case 'extent':
                  _goToDefaultMapExtent();
                  break;

                case 'legend':
                  _showComingSoon('Legend');
                  break;

                case 'measure':
                  _showComingSoon('Measure');
                  break;

                case 'markup':
                  _showComingSoon('Personal markup');
                  break;

                case 'share':
                  _showComingSoon('Share map');
                  break;
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'basemap',
                child: Text('Basemap'),
              ),
              PopupMenuItem(
                value: 'extent',
                child: Text('Default map extent'),
              ),
            ],
          ),
        ],
      ),

      body: BlocListener<MapBloc, MapState>(
        listenWhen: (previous, current) {
          // Always listen for errors
          if (current is MapError) {
            return true;
          }

          // Listen when entering fillingForm
          if (current is CollectionState &&
              current.mode == CollectionMode.fillingForm) {
            return previous is! CollectionState ||
                previous.mode != CollectionMode.fillingForm;
          }

          // Listen when feature submission is completed
          if (current is CollectionState &&
              current.mode == CollectionMode.viewDetails) {
            return true;
          }

          return false;
        },


        listener: (context, state) {
          if (state is MapError) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(state.message),
              backgroundColor: Colors.red,
            ));
          }
          if (state is CollectionState && state.mode == CollectionMode.fillingForm) {
            _showCollectionForm(context);
          }
          if (state is CollectionState && state.mode == CollectionMode.viewDetails) {
            if (mounted) {
              Navigator.pop(context); // Pop form if open
              _showFeatureAttributes(state.draftFeature!, state.targetLayer!);
            }
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

            // Crosshair Overlay (Changed to Blue for better visibility)
            BlocBuilder<MapBloc, MapState>(
              builder: (context, state) {
                if (state is CollectionState && state.mode == CollectionMode.pickingLocation) {
                  return Center(
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.blue, width: 3),
                      ),
                      child: const Icon(Icons.add, color: Colors.blue, size: 32),
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),

            // UI Controls
            Positioned(
              bottom: 24,
              right: 24,
              child: BlocBuilder<MapBloc, MapState>(
                builder: (context, state) {
                  bool isPicking = state is CollectionState &&
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
                        onPressed: () {
                          _goToMyLocation();
                          // TODO: Implement actual zoom to location logic
                        },
                        child: const Icon(Icons.my_location),
                      ),
                    ],
                  );
                },
              ),
            ),

            // Add / Update Point Button
            BlocBuilder<MapBloc, MapState>(
              builder: (context, state) {
                if (state is CollectionState &&
                    state.mode == CollectionMode.pickingLocation) {
                  final hasLocation =
                      state.draftFeature?.geometry != null;

                  return Positioned(
                    bottom: 80,
                    left: 20,
                    right: 20,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00A9E0),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      onPressed: _captureLocation,
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

  List<BasemapGalleryItem> _buildBasemapItems() {
    final styles = <MapEntry<String, BasemapStyle>>[
      MapEntry('Imagery', BasemapStyle.arcGISImagery),
      MapEntry('Imagery Standard', BasemapStyle.arcGISImageryStandard),
      MapEntry('Streets', BasemapStyle.arcGISStreets),
      MapEntry('Navigation', BasemapStyle.arcGISNavigation),
      MapEntry('Topographic', BasemapStyle.arcGISTopographic),
      MapEntry('Oceans', BasemapStyle.arcGISOceans),
      MapEntry('Light Gray', BasemapStyle.arcGISLightGray),
      MapEntry('Dark Gray', BasemapStyle.arcGISDarkGray),
    ];

    return styles.map((entry) {
      final basemap = Basemap.withStyle(entry.value);

      return BasemapGalleryItem(
        basemap: basemap,
        tooltip: entry.key,
      );
    }).toList();
  }


  void _showBasemapGallery() {
    final portal = Portal.arcGISOnline(
      connection: PortalConnection.authenticated,
    );

    final controller = BasemapGalleryController.withPortal(
      portal,
      geoModel: _map,
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return SizedBox(
          height: MediaQuery.of(context).size.height * 0.75,
          child: BasemapGallery(
            controller: controller,
          ),
        );
      },
    ).whenComplete(controller.dispose);
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
      builder: (context) {
        final operationalLayers = _map.operationalLayers.toList();

        final baseLayers = _map.basemap?.baseLayers.toList() ?? <Layer>[];

        final referenceLayers = _map.basemap?.referenceLayers.toList() ?? <Layer>[];

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

                _buildLayerSectionTitle('On device layers'),

                _buildStaticLayerTile(
                  icon: Icons.edit_location_alt,
                  title: 'Personal markup',
                  checked: true,
                ),

                const SizedBox(height: 12),

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
                    _buildOperationalLayerTile,
                  ),

                const SizedBox(height: 12),

                _buildLayerSectionTitle('Basemap layers'),

                if (baseLayers.isEmpty && referenceLayers.isEmpty)
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
                    _buildBasemapLayerTile,
                  ),
                  ...referenceLayers.map(
                    _buildBasemapLayerTile,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLayerSectionTitle(String title) {
    return Padding(
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
  }

  Widget _buildStaticLayerTile({
    required IconData icon,
    required String title,
    required bool checked,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      leading: Icon(
        icon,
        color: Colors.blueGrey,
        size: 30,
      ),
      title: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
        ),
      ),
      trailing: Checkbox(
        value: checked,
        onChanged: null,
      ),
    );
  }

  Widget _buildOperationalLayerTile(Layer layer) {
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
        onChanged: (value) {
          if (value == null) return;

          setState(() {
            layer.isVisible = value;
          });
        },
      ),
    );
  }

  Widget _buildBasemapLayerTile(Layer layer) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      leading: const Icon(
        Icons.public,
        color: Colors.orange,
        size: 30,
      ),
      title: Text(
        layer.name.isNotEmpty ? layer.name : 'Basemap',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
        ),
      ),
      trailing: Checkbox(
        value: layer.isVisible,
        onChanged: (value) {
          if (value == null) return;

          setState(() {
            layer.isVisible = value;
          });
        },
      ),
    );
  }

  void _goToDefaultMapExtent() {
    final viewpoint = _map.initialViewpoint;

    if (viewpoint == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Default map extent is not available.',
          ),
        ),
      );
      return;
    }

    _mapController?.setViewpoint(viewpoint);
  }

  void _showComingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$feature is not implemented yet.'),
      ),
    );
  }

  void _showCollectionForm(BuildContext context) {
    final bloc = context.read<MapBloc>();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _FeatureCollectionForm(
        onUpdatePoint: _beginLocationUpdate,
      ),
    ).then((_) {
      if (_returningToMapForLocationUpdate) {
        _returningToMapForLocationUpdate = false;
        return;
      }

      // Reset collection/edit state when the form is dismissed.
      if (bloc.state is CollectionState &&
          (bloc.state as CollectionState).mode == CollectionMode.fillingForm) {
        bloc.add(CancelCollection());
      }
    });
  }
}

class _FeatureCollectionForm extends StatefulWidget {
  final VoidCallback? onUpdatePoint;

  const _FeatureCollectionForm({
    this.onUpdatePoint,
  });

  @override
  State<_FeatureCollectionForm> createState() => _FeatureCollectionFormState();
}

class _FeatureCollectionFormState extends State<_FeatureCollectionForm> {
  //final Map<String, TextEditingController> _controllers = {};

  @override
  void dispose() {
    // for (var controller in _controllers.values) {
    //   controller.dispose();
    // }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<MapBloc, MapState>(
      builder: (context, state) {
        if (state is! CollectionState) return const SizedBox.shrink();

        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1E1E1E),
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
                    Text(state.isEdit ? 'Edit Feature' : 'New Feature', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                    if (state.mode == CollectionMode.submitting)
                      const CircularProgressIndicator()
                    else
                      IconButton(
                        icon: const Icon(Icons.check, color: Colors.white),
                        onPressed: () {
                          final bloc = context.read<MapBloc>();
                          bloc.add(SubmitDraftFeature());
                        },
                      ),
                  ],
                ),
                if (state.errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(state.errorMessage!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                  ),
                const SizedBox(height: 16),

                // Dynamic Form Fields
                ...state.editableFields.map(
                      (field) => _buildField(field, state.draftFeature!),
                ),

                if (state.isNewFeature &&
                    state.draftFeature?.geometry != null) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.blue),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      icon: const Icon(Icons.location_on_outlined),
                      label: const Text(
                        'UPDATE POINT',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onPressed: widget.onUpdatePoint,
                    ),
                  ),
                ],

                const SizedBox(height: 24),

                // Attachments
                const Text('Attachments', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.grey)),
                        icon: const Icon(Icons.camera_alt),
                        label: const Text('TAKE PHOTO'),
                        onPressed: _takePhoto,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.grey)),
                        icon: const Icon(Icons.attach_file),
                        label: const Text('ATTACH'),
                        onPressed: _attachFile,
                      ),
                    ),
                  ],
                ),

                // Attachment list preview
                if (state.draftFeature?.attachments.isNotEmpty ?? false)
                  Container(
                    height: 100,
                    margin: const EdgeInsets.only(top: 16),
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: state.draftFeature!.attachments.length,
                      itemBuilder: (context, index) => Stack(
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.file(state.draftFeature!.attachments[index], width: 100, height: 100, fit: BoxFit.cover),
                            ),
                          ),
                          Positioned(
                            top: 0,
                            right: 8,
                            child: IconButton(
                              icon: const Icon(Icons.remove_circle, color: Colors.red),
                              onPressed: () {
                                context.read<MapBloc>().add(RemoveDraftAttachment(index));
                              },
                            ),
                          )
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

  Widget _buildField(Field field, GisFeature draft) {
    final domain = field.domain;
    if (domain is CodedValueDomain) {
      return _buildDropdownField(
        label: field.alias.isNotEmpty ? field.alias : field.name,
        value: draft.attributes[field.name]?.toString(),
        options: domain.codedValues,
        onChanged: (val) {
          context.read<MapBloc>().add(UpdateDraftAttributes({field.name: val}));
        },
      );
    } else if (field.type == FieldType.dateOnly) {
      final selectedDate = draft.attributes[field.name] as DateOnly?;

      return Padding(
        padding: const EdgeInsets.only(bottom: 16.0),
        child: GestureDetector(
          onTap: () async {
            final bloc = context.read<MapBloc>();
            final initialDate = selectedDate != null
                ? DateTime(
              selectedDate.year,
              selectedDate.month,
              selectedDate.day,
            )
                : DateTime.now();

            final pickedDate = await showDatePicker(
              context: context,
              initialDate: initialDate,
              firstDate: DateTime(1900),
              lastDate: DateTime(2100),
            );

            if (pickedDate != null) {
              final dateOnly = DateOnly.withYearMonthDay(
                year: pickedDate.year,
                month: pickedDate.month,
                day: pickedDate.day,
              );

              bloc.add(
                UpdateDraftAttributes({
                  field.name: dateOnly,
                }),
              );
            }
          },
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: field.alias.isNotEmpty
                  ? field.alias
                  : field.name,
              labelStyle: const TextStyle(color: Colors.grey),
              enabledBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.grey),
              ),
              focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.blue),
              ),
            ),
            child: Text(
              selectedDate != null
                  ? '${selectedDate.day.toString().padLeft(2, '0')}/'
                  '${selectedDate.month.toString().padLeft(2, '0')}/'
                  '${selectedDate.year}'
                  : 'Select Date',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ),
      );

    } else {
      return _CollectionTextField(
        key: ValueKey(field.name),
        field: field,
        draft: draft,
      );
    }
  }

  Widget _buildDropdownField({
    required String label,
    String? value,
    required List<CodedValue> options,
    required Function(dynamic) onChanged,
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
            dropdownColor: const Color(0xFF1E1E1E),
            style: const TextStyle(color: Colors.white),
            hint: const Text('No value', style: TextStyle(color: Colors.grey)),
            underline: Container(height: 1, color: Colors.grey),
            items: options.map((e) => DropdownMenuItem(value: e.code, child: Text(e.name))).toList(),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  void _takePhoto() async {
    final picker = ImagePicker();
    final photo = await picker.pickImage(source: ImageSource.camera, imageQuality: 80);
    if (photo != null && mounted) {
      context.read<MapBloc>().add(AddDraftAttachment(File(photo.path)));
    }
  }

  void _attachFile() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (image != null && mounted) {
      context.read<MapBloc>().add(AddDraftAttachment(File(image.path)));
    }
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
  State<_CollectionTextField> createState() =>
      _CollectionTextFieldState();
}

class _CollectionTextFieldState extends State<_CollectionTextField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();

    _controller = TextEditingController(
      text: widget.draft.attributes[widget.field.name]?.toString() ?? '',
    );
  }

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
        style: const TextStyle(color: Colors.white),
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
        onChanged: (val) {
          context.read<MapBloc>().add(
            UpdateDraftAttributes({
              widget.field.name: val,
            }),
          );
        },
      ),
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
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(feature.attributes['pole_id'] ?? feature.attributes['Type'] ?? 'Feature', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
            ],
          ),
          const Divider(color: Colors.grey),

          // Details
          ...['pole_id', 'pole_type', 'condition', 'status', 'remarks', 'survey_date'].map((key) {
            final value = feature.attributes[key];
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

          // Actions
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              _ActionButton(
                  icon: Icons.edit,
                  label: 'Edit',
                  onTap: () {
                    Navigator.pop(context);
                    context.read<MapBloc>().add(EditFeatureRequested(feature, layer));
                  }
              ),
              _ActionButton(
                  icon: Icons.copy,
                  label: 'Copy',
                  onTap: () {
                    Navigator.pop(context);
                    context.read<MapBloc>().add(CopyFeatureRequested(feature, layer));
                  }
              ),
              _ActionButton(
                  icon: Icons.add_location,
                  label: 'Collect Here',
                  onTap: () {
                    Navigator.pop(context);
                    context.read<MapBloc>().add(CollectHereRequested(feature, layer));
                  }
              ),
              _ActionButton(icon: Icons.directions, label: 'Directions', onTap: () {}),
              _ActionButton(
                icon: Icons.delete,
                label: 'Delete',
                color: Colors.red,
                onTap: () => _confirmDelete(context),
              ),
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
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () {
              final bloc = context.read<MapBloc>();

              Navigator.pop(dialogContext);
              Navigator.pop(context);

              bloc.add(
                DeleteFeatureRequested(feature, layer),
              );
            },
            child: const Text(
              'DELETE',
              style: TextStyle(color: Colors.red),
            ),
          ),
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
