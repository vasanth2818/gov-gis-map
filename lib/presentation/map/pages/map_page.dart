import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:arcgis_maps/arcgis_maps.dart';
import 'package:image_picker/image_picker.dart';
import 'package:gov_gis_map/core/utils/arcgis_extensions.dart';
import 'package:gov_gis_map/domain/entities/gis_feature.dart';
import 'package:gov_gis_map/presentation/map/bloc/map_bloc.dart';
import 'package:gov_gis_map/data/repositories/map_repository_impl.dart';
import 'package:gov_gis_map/data/datasources/remote/arcgis_remote_datasource.dart';

class MapPage extends StatefulWidget {
  final PortalItem? portalItem;
  const MapPage({super.key, this.portalItem});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  ArcGISMapViewController? _mapController;
  late final ArcGISMap _map;
  final String _layerUrl = 'https://services.arcgis.com/P3ePLMYs2RVChqkv/arcgis/rest/services/Luminaries/FeatureServer/0';

  @override
  void initState() {
    super.initState();
    debugPrint('Initializing MapPage');

    if (widget.portalItem != null) {
      _map = ArcGISMap.withItem(widget.portalItem!);
    } else {
      _map = ArcGISMap.withBasemapStyle(BasemapStyle.arcGISImageryStandard);
      final featureLayer = FeatureLayerExtension.fromUrl(Uri.parse(_layerUrl));
      _map.operationalLayers.add(featureLayer);
    }
  }

  void _onMapCreated() {
    debugPrint('Map creation complete. Loading map resources...');
    _map.load().then((_) async {
      debugPrint('Map loaded successfully. Checking for editable layers...');
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
          final gisFeature = GisFeature(
            id: element.attributes['OBJECTID']?.toString() ?? '',
            geometry: element.geometry,
            attributes: Map<String, dynamic>.from(element.attributes),
          );
          _showFeatureAttributes(gisFeature);
        }
      }
    }
  }

  void _showFeatureAttributes(GisFeature feature) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _FeatureDetailsSheet(feature: feature),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Government Field Survey'),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync),
            onPressed: () {
              final bloc = context.read<MapBloc>();
              bloc.add(LoadMapData(_layerUrl));
            },
          ),
        ],
      ),
      body: BlocListener<MapBloc, MapState>(
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
              _showFeatureAttributes(state.draftFeature!);
            }
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
                          // TODO: Implement actual zoom to location logic
                        },
                        child: const Icon(Icons.my_location),
                      ),
                    ],
                  );
                },
              ),
            ),

            // Add Point Button
            BlocBuilder<MapBloc, MapState>(
              builder: (context, state) {
                if (state is CollectionState && state.mode == CollectionMode.pickingLocation) {
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
                      child: const Text('ADD POINT', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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

  void _showCollectionForm(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _FeatureCollectionForm(),
    ).then((_) {
       // Handle cancel if user dismisses sheet manually
       final bloc = context.read<MapBloc>();
       if (bloc.state is CollectionState && (bloc.state as CollectionState).mode == CollectionMode.fillingForm) {
         // bloc.add(CancelCollection()); 
       }
    });
  }
}

class _FeatureCollectionForm extends StatefulWidget {
  const _FeatureCollectionForm();

  @override
  State<_FeatureCollectionForm> createState() => _FeatureCollectionFormState();
}

class _FeatureCollectionFormState extends State<_FeatureCollectionForm> {
  final Map<String, TextEditingController> _controllers = {};

  @override
  void dispose() {
    for (var controller in _controllers.values) {
      controller.dispose();
    }
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
                    const Text('New Feature', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
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
                ...state.editableFields.map((field) => _buildField(field, state.draftFeature!)),

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
                        onPressed: () {},
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
                              onPressed: () {},
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
    } else {
      if (!_controllers.containsKey(field.name)) {
        _controllers[field.name] = TextEditingController(text: draft.attributes[field.name]?.toString() ?? '');
      }
      return Padding(
        padding: const EdgeInsets.only(bottom: 16.0),
        child: TextField(
          controller: _controllers[field.name],
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: field.alias.isNotEmpty ? field.alias : field.name,
            labelStyle: const TextStyle(color: Colors.grey),
            enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
            focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.blue)),
          ),
          onChanged: (val) => context.read<MapBloc>().add(UpdateDraftAttributes({field.name: val})),
        ),
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
}

class _FeatureDetailsSheet extends StatelessWidget {
  final GisFeature feature;
  const _FeatureDetailsSheet({required this.feature});

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
              Text(feature.attributes['Type'] ?? 'Feature', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
            ],
          ),
          const Divider(color: Colors.grey),
          
          // Details
          ...feature.attributes.entries.map((e) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            child: Row(
              children: [
                Text('${e.key}: ', style: const TextStyle(color: Colors.grey)),
                Text('${e.value}', style: const TextStyle(color: Colors.white)),
              ],
            ),
          )),
          
          const SizedBox(height: 24),
          
          // Actions
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              _ActionButton(icon: Icons.edit, label: 'Edit', onTap: () {}),
              _ActionButton(icon: Icons.copy, label: 'Copy', onTap: () {}),
              _ActionButton(icon: Icons.add_location, label: 'Collect Here', onTap: () {}),
              _ActionButton(icon: Icons.directions, label: 'Directions', onTap: () {}),
              _ActionButton(icon: Icons.delete, label: 'Delete', color: Colors.red, onTap: () {}),
            ],
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
