import 'dart:io';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:arcgis_maps/arcgis_maps.dart';
import 'package:gov_gis_map/features/map/domain/entities/gis_feature.dart';
import 'package:gov_gis_map/features/map/domain/repositories/map_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Events
abstract class MapEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

class LoadMapData extends MapEvent {
  final String layerUrl;
  LoadMapData(this.layerUrl);
  @override
  List<Object?> get props => [layerUrl];
}

class FeatureIdentified extends MapEvent {
  final GisFeature feature;
  FeatureIdentified(this.feature);
  @override
  List<Object?> get props => [feature];
}

class AddFeatureRequested extends MapEvent {
  final String layerUrl;
  final Geometry geometry;
  final Map<String, dynamic> attributes;
  AddFeatureRequested(this.layerUrl, this.geometry, this.attributes);
}

class StartCollectionRequested extends MapEvent {
  final FeatureLayer layer;
  StartCollectionRequested(this.layer);
}

class LocationCaptured extends MapEvent {
  final Geometry geometry;
  final Map<String, dynamic> attributes;

  LocationCaptured(this.geometry, {this.attributes = const {}});
}

class BeginLocationUpdate extends MapEvent {}

class UpdateDraftAttributes extends MapEvent {
  final Map<String, dynamic> attributes;
  UpdateDraftAttributes(this.attributes);
}

class AddDraftAttachment extends MapEvent {
  final File file;
  AddDraftAttachment(this.file);
}

class RemoveDraftAttachment extends MapEvent {
  final int index;
  RemoveDraftAttachment(this.index);
  @override
  List<Object?> get props => [index];
}

class SubmitDraftFeature extends MapEvent {}

class CancelCollection extends MapEvent {}

class PageInitialized extends MapEvent {}

class EditFeatureRequested extends MapEvent {
  final GisFeature feature;
  final FeatureLayer layer;
  EditFeatureRequested(this.feature, this.layer);
}

class CopyFeatureRequested extends MapEvent {
  final GisFeature feature;
  final FeatureLayer layer;
  CopyFeatureRequested(this.feature, this.layer);
}

class CollectHereRequested extends MapEvent {
  final GisFeature feature;
  final FeatureLayer layer;
  CollectHereRequested(this.feature, this.layer);
}

class DeleteFeatureRequested extends MapEvent {
  final GisFeature feature;
  final FeatureLayer layer;
  DeleteFeatureRequested(this.feature, this.layer);
}

class RefreshMapRequested extends MapEvent {
  final String? layerUrl;
  RefreshMapRequested({this.layerUrl});
}

class DownloadOfflineMap extends MapEvent {
  final ArcGISMap onlineMap;
  final Envelope areaOfInterest;
  final double? currentScale;
  DownloadOfflineMap(this.onlineMap, this.areaOfInterest, {this.currentScale});
}

class OpenOfflineMap extends MapEvent {}

class ExitOfflineMap extends MapEvent {}

class SyncOfflineChanges extends MapEvent {}

class RemoveOfflineMap extends MapEvent {}

class UpdateOfflineProgress extends MapEvent {
  final double downloadProgress;
  final double syncProgress;
  final bool isDownloading;
  final bool isSyncing;
  final String? errorMessage;
  final String? offlineMapPath;

  UpdateOfflineProgress({
    this.downloadProgress = 0.0,
    this.syncProgress = 0.0,
    this.isDownloading = false,
    this.isSyncing = false,
    this.errorMessage,
    this.offlineMapPath,
  });
}

// States
enum CollectionMode {
  idle,
  pickingLocation,
  fillingForm,
  submitting,
  viewDetails,
  editing,
  copying,
  collectingHere,
  deleting,
}

abstract class MapState extends Equatable {
  final bool isOfflineMode;
  final double offlineDownloadProgress;
  final double offlineSyncProgress;
  final String? offlineMapPath;
  final bool isDownloading;
  final bool isSyncing;

  MapState({
    this.isOfflineMode = false,
    this.offlineDownloadProgress = 0.0,
    this.offlineSyncProgress = 0.0,
    this.offlineMapPath,
    this.isDownloading = false,
    this.isSyncing = false,
  });

  @override
  List<Object?> get props => [
    isOfflineMode,
    offlineDownloadProgress,
    offlineSyncProgress,
    offlineMapPath,
    isDownloading,
    isSyncing,
  ];
}

class MapInitial extends MapState {
  MapInitial({
    super.isOfflineMode,
    super.offlineDownloadProgress,
    super.offlineSyncProgress,
    super.offlineMapPath,
    super.isDownloading,
    super.isSyncing,
  });
}

class MapLoading extends MapState {
  MapLoading({
    super.isOfflineMode,
    super.offlineDownloadProgress,
    super.offlineSyncProgress,
    super.offlineMapPath,
    super.isDownloading,
    super.isSyncing,
  });
}

class MapLoaded extends MapState {
  final List<GisFeature> features;
  MapLoaded(
    this.features, {
    super.isOfflineMode,
    super.offlineDownloadProgress,
    super.offlineSyncProgress,
    super.offlineMapPath,
    super.isDownloading,
    super.isSyncing,
  });
  @override
  List<Object?> get props => [features, ...super.props];
}

class FeatureSelected extends MapState {
  final GisFeature feature;
  FeatureSelected(
    this.feature, {
    super.isOfflineMode,
    super.offlineDownloadProgress,
    super.offlineSyncProgress,
    super.offlineMapPath,
    super.isDownloading,
    super.isSyncing,
  });
  @override
  List<Object?> get props => [feature, ...super.props];
}

class MapError extends MapState {
  final String message;
  MapError(
    this.message, {
    super.isOfflineMode,
    super.offlineDownloadProgress,
    super.offlineSyncProgress,
    super.offlineMapPath,
    super.isDownloading,
    super.isSyncing,
  });
  @override
  List<Object?> get props => [message, ...super.props];
}

class CollectionState extends MapState {
  final CollectionMode mode;
  final FeatureLayer? targetLayer;
  final GisFeature? draftFeature;
  final List<Field> editableFields;
  final String? errorMessage;
  final bool isEdit;
  final bool isNewFeature;

  CollectionState({
    required this.mode,
    this.targetLayer,
    this.draftFeature,
    this.editableFields = const [],
    this.errorMessage,
    this.isEdit = false,
    this.isNewFeature = false,
    super.isOfflineMode,
    super.offlineDownloadProgress,
    super.offlineSyncProgress,
    super.offlineMapPath,
    super.isDownloading,
    super.isSyncing,
  });

  factory CollectionState.error(String message, {bool isOfflineMode = false}) {
    return CollectionState(
      mode: CollectionMode.idle,
      errorMessage: message,
      isOfflineMode: isOfflineMode,
    );
  }

  factory CollectionState.success(
    List<Field> fields, {
    bool isEdit = false,
    bool isOfflineMode = false,
  }) {
    return CollectionState(
      mode: CollectionMode.fillingForm,
      editableFields: fields,
      isEdit: isEdit,
      isOfflineMode: isOfflineMode,
    );
  }

  @override
  List<Object?> get props => [
    mode,
    targetLayer,
    draftFeature,
    editableFields,
    errorMessage,
    isEdit,
    isNewFeature,
    ...super.props,
  ];

  CollectionState copyWith({
    CollectionMode? mode,
    FeatureLayer? targetLayer,
    GisFeature? draftFeature,
    List<Field>? editableFields,
    String? errorMessage,
    bool? isEdit,
    bool? isNewFeature,
    bool? isOfflineMode,
    double? offlineDownloadProgress,
    double? offlineSyncProgress,
    String? offlineMapPath,
    bool? isDownloading,
    bool? isSyncing,
  }) {
    return CollectionState(
      mode: mode ?? this.mode,
      targetLayer: targetLayer ?? this.targetLayer,
      draftFeature: draftFeature ?? this.draftFeature,
      editableFields: editableFields ?? this.editableFields,
      errorMessage: errorMessage ?? this.errorMessage,
      isEdit: isEdit ?? this.isEdit,
      isNewFeature: isNewFeature ?? this.isNewFeature,
      isOfflineMode: isOfflineMode ?? this.isOfflineMode,
      offlineDownloadProgress:
          offlineDownloadProgress ?? this.offlineDownloadProgress,
      offlineSyncProgress: offlineSyncProgress ?? this.offlineSyncProgress,
      offlineMapPath: offlineMapPath ?? this.offlineMapPath,
      isDownloading: isDownloading ?? this.isDownloading,
      isSyncing: isSyncing ?? this.isSyncing,
    );
  }
}

// BLoC
class MapBloc extends Bloc<MapEvent, MapState> {
  final MapRepository mapRepository;

  MapBloc({required this.mapRepository}) : super(MapInitial()) {
    on<LoadMapData>((event, emit) async {
      emit(
        MapLoading(
          isOfflineMode: state.isOfflineMode,
          offlineMapPath: state.offlineMapPath,
        ),
      );
      try {
        final features = await mapRepository.getFeatures(event.layerUrl);
        emit(
          MapLoaded(
            features,
            isOfflineMode: state.isOfflineMode,
            offlineMapPath: state.offlineMapPath,
          ),
        );
      } catch (e) {
        emit(
          MapError(
            e.toString(),
            isOfflineMode: state.isOfflineMode,
            offlineMapPath: state.offlineMapPath,
          ),
        );
      }
    });

    on<FeatureIdentified>((event, emit) {
      emit(
        FeatureSelected(
          event.feature,
          isOfflineMode: state.isOfflineMode,
          offlineMapPath: state.offlineMapPath,
        ),
      );
    });

    on<AddFeatureRequested>((event, emit) async {
      try {
        final newFeature = GisFeature(
          id: '', // Server will assign
          geometry: event.geometry,
          attributes: event.attributes,
        );
        await mapRepository.addFeature(event.layerUrl, newFeature);
        add(LoadMapData(event.layerUrl)); // Refresh
      } catch (e) {
        emit(
          MapError(
            e.toString(),
            isOfflineMode: state.isOfflineMode,
            offlineMapPath: state.offlineMapPath,
          ),
        );
      }
    });

    on<StartCollectionRequested>((event, emit) async {
      final layer = event.layer;

      try {
        final table = layer.featureTable;

        if (table == null) {
          debugPrint('Feature table is null for layer: ${layer.name}');
          emit(
            MapError(
              'Cannot collect data: Layer "${layer.name}" has no feature table.',
              isOfflineMode: state.isOfflineMode,
              offlineMapPath: state.offlineMapPath,
            ),
          );
          return;
        }

        // Load table if not loaded
        if (table.loadStatus != LoadStatus.loaded) {
          debugPrint('Loading feature table for layer: ${layer.name}');
          await table.load();
        }

        if (!table.canAdd()) {
          emit(
            MapError(
              'You do not have permission to add features to this layer.',
              isOfflineMode: state.isOfflineMode,
              offlineMapPath: state.offlineMapPath,
            ),
          );
          return;
        }

        final editableFields = _getCollectionFields(table);

        if (editableFields.isEmpty) {
          emit(
            CollectionState.error(
              'No editable fields available for collection.',
              isOfflineMode: state.isOfflineMode,
            ),
          );
          return;
        }

        emit(
          CollectionState(
            mode: CollectionMode.pickingLocation,
            targetLayer: layer,
            editableFields: editableFields,
            draftFeature: GisFeature(id: '', attributes: {}),
            isNewFeature: true,
            isOfflineMode: state.isOfflineMode,
            offlineMapPath: state.offlineMapPath,
          ),
        );
      } catch (e) {
        debugPrint('Error starting collection: $e');
        emit(
          MapError(
            'Failed to initialize collection: ${e.toString()}',
            isOfflineMode: state.isOfflineMode,
            offlineMapPath: state.offlineMapPath,
          ),
        );
      }
    });

    on<BeginLocationUpdate>((event, emit) {
      if (state is CollectionState) {
        final current = state as CollectionState;

        if (!current.isNewFeature || current.draftFeature?.geometry == null) {
          return;
        }

        emit(current.copyWith(mode: CollectionMode.pickingLocation));
      }
    });

    on<LocationCaptured>((event, emit) {
      if (state is! CollectionState) {
        return;
      }

      final current = state as CollectionState;

      var geometry = event.geometry;

      final table = current.targetLayer?.featureTable;

      debugPrint('Geometry type : ${geometry.runtimeType}');
      debugPrint('Feature table : ${table?.tableName}');
      debugPrint('Table hasZ    : ${table?.hasZ}');

      if (table != null && table.hasZ) {
        final currentZ = geometry is ArcGISPoint ? geometry.z : null;

        final z = currentZ != null && currentZ.isFinite ? currentZ : 0.0;

        geometry = GeometryEngine.setZ(geometry: geometry, z: z);

        debugPrint('Z-aware geometry created');
        debugPrint('Z value: $z');
      }

      final newAttributes = Map<String, dynamic>.from(
        current.draftFeature?.attributes ?? {},
      );

      newAttributes.addAll(event.attributes);

      final capturedFeature = current.draftFeature?.copyWith(
        geometry: geometry,
        attributes: newAttributes,
      );

      // for DEBUG
      if (capturedFeature != null) {
        _debugPrintFeatureSnapshot('AFTER LOCATION CAPTURE', capturedFeature);
      }

      emit(
        current.copyWith(
          mode: CollectionMode.fillingForm,
          draftFeature: capturedFeature,
        ),
      );
    });

    on<UpdateDraftAttributes>((event, emit) {
      if (state is CollectionState) {
        final current = state as CollectionState;

        final newAttributes = Map<String, dynamic>.from(
          current.draftFeature?.attributes ?? {},
        );

        newAttributes.addAll(event.attributes);

        emit(
          current.copyWith(
            draftFeature: current.draftFeature?.copyWith(
              attributes: newAttributes,
            ),
          ),
        );
      }
    });

    on<AddDraftAttachment>((event, emit) {
      if (state is CollectionState) {
        final current = state as CollectionState;
        final newAttachments = List<File>.from(
          current.draftFeature?.attachments ?? [],
        );
        newAttachments.add(event.file);
        emit(
          current.copyWith(
            draftFeature: current.draftFeature?.copyWith(
              attachments: newAttachments,
            ),
          ),
        );
      }
    });

    on<RemoveDraftAttachment>((event, emit) {
      if (state is CollectionState) {
        final current = state as CollectionState;
        final attachments = List<File>.from(
          current.draftFeature?.attachments ?? [],
        );

        if (event.index < 0 || event.index >= attachments.length) {
          return;
        }

        attachments.removeAt(event.index);

        emit(
          current.copyWith(
            draftFeature: current.draftFeature?.copyWith(
              attachments: attachments,
            ),
          ),
        );
      }
    });

    on<SubmitDraftFeature>((event, emit) async {
      if (state is CollectionState) {
        final current = state as CollectionState;
        final layer = current.targetLayer;
        final feature = current.draftFeature;

        if (layer == null || feature == null) {
          return;
        }

        _debugPrintFeatureSnapshot('BEFORE SUBMIT', feature);

        // Validate required fields using ArcGIS field metadata.
        final validationError = _validateRequiredFields(current);

        if (validationError != null) {
          emit(
            current.copyWith(
              mode: CollectionMode.fillingForm,
              errorMessage: validationError,
            ),
          );
          return;
        }

        emit(current.copyWith(mode: CollectionMode.submitting));

        try {
          final table = layer.featureTable;

          final url = table is ServiceFeatureTable ? table.uri.toString() : '';

          GisFeature savedFeature = feature;

          if (current.isEdit) {
            await mapRepository.updateFeature(url, feature, table: table);
          } else {
            savedFeature = await mapRepository.addFeature(
              url,
              feature,
              table: table,
            );
          }

          _debugPrintFeatureSnapshot(
            current.isEdit ? 'AFTER UPDATE' : 'AFTER ADD / SERVER SAVE',
            savedFeature,
          );

          if (state.isOfflineMode) {
            emit(
              current.copyWith(
                mode: CollectionMode.viewDetails,
                draftFeature: savedFeature,
              ),
            );
          } else {
            add(RefreshMapRequested(layerUrl: url));

            emit(
              current.copyWith(
                mode: CollectionMode.viewDetails,
                draftFeature: savedFeature,
              ),
            );
          }
        } catch (e) {
          emit(
            current.copyWith(
              mode: CollectionMode.fillingForm,
              errorMessage: e.toString(),
            ),
          );
        }
      }
    });

    on<EditFeatureRequested>((event, emit) async {
      try {
        final table = event.layer.featureTable!;
        await table.load();
        final editableFields = _getCollectionFields(table);

        emit(
          CollectionState(
            mode: CollectionMode.fillingForm,
            targetLayer: event.layer,
            editableFields: editableFields,
            draftFeature: event.feature,
            isEdit: true,
            isOfflineMode: state.isOfflineMode,
            offlineMapPath: state.offlineMapPath,
          ),
        );
      } catch (e) {
        emit(
          MapError(
            'Failed to start editing: $e',
            isOfflineMode: state.isOfflineMode,
            offlineMapPath: state.offlineMapPath,
          ),
        );
      }
    });

    on<CopyFeatureRequested>((event, emit) async {
      try {
        final table = event.layer.featureTable!;

        if (table.loadStatus != LoadStatus.loaded) {
          await table.load();
        }

        final editableFields = _getCollectionFields(table);

        final copiedAttributes = <String, dynamic>{};

        for (final field in editableFields) {
          if (event.feature.attributes.containsKey(field.name)) {
            copiedAttributes[field.name] = event.feature.attributes[field.name];
          }
        }

        debugPrint('Original OBJECTID : ${event.feature.id}');
        debugPrint('Copied attributes : ${copiedAttributes.length}');
        debugPrint('Copied geometry   : ${event.feature.geometry}');

        emit(
          CollectionState(
            // Show the form immediately.
            mode: CollectionMode.fillingForm,

            targetLayer: event.layer,

            editableFields: editableFields,

            draftFeature: GisFeature(
              id: '',

              geometry: event.feature.geometry,

              attributes: copiedAttributes,
            ),

            isEdit: false,

            isNewFeature: true,

            isOfflineMode: state.isOfflineMode,
            offlineMapPath: state.offlineMapPath,
          ),
        );
      } catch (e, stackTrace) {
        debugPrint('COPY FEATURE ERROR: $e');
        debugPrint('$stackTrace');

        emit(
          MapError(
            'Failed to copy feature: $e',
            isOfflineMode: state.isOfflineMode,
            offlineMapPath: state.offlineMapPath,
          ),
        );
      }
    });
    on<CollectHereRequested>((event, emit) async {
      try {
        final table = event.layer.featureTable!;

        if (table.loadStatus != LoadStatus.loaded) {
          await table.load();
        }

        final editableFields = _getCollectionFields(table);

        // Existing feature location
        final geometry = event.feature.geometry;

        if (geometry == null) {
          throw Exception('Source feature has no geometry.');
        }

        // Convert selected/existing geometry to WGS84
        final projectedGeometry = GeometryEngine.project(
          geometry,
          outputSpatialReference: SpatialReference.wgs84,
        );

        if (projectedGeometry is! ArcGISPoint) {
          throw Exception('Unable to get point geometry.');
        }

        final latitude = projectedGeometry.y;
        final longitude = projectedGeometry.x;

        final newAttributes = <String, dynamic>{};

        // Collect Here should have EMPTY business/user fields.
        newAttributes['esrignss_latitude'] = latitude;
        newAttributes['esrignss_longitude'] = longitude;
        emit(
          CollectionState(
            mode: CollectionMode.fillingForm,
            targetLayer: event.layer,
            editableFields: editableFields,

            draftFeature: GisFeature(
              id: '',
              geometry: geometry,
              attributes: newAttributes,
            ),

            isEdit: false,
            // Do NOT show UPDATE POINT.
            isNewFeature: false,

            isOfflineMode: state.isOfflineMode,
            offlineMapPath: state.offlineMapPath,
          ),
        );
      } catch (e, stackTrace) {
        debugPrint('COLLECT HERE ERROR: $e');
        debugPrint('$stackTrace');

        emit(
          MapError(
            'Failed to collect here: $e',
            isOfflineMode: state.isOfflineMode,
            offlineMapPath: state.offlineMapPath,
          ),
        );
      }
    });
    on<DeleteFeatureRequested>((event, emit) async {
      try {
        final table = event.layer.featureTable;
        final url = table is ServiceFeatureTable ? table.uri.toString() : '';
        await mapRepository.deleteFeature(url, event.feature.id, table: table);

        if (!state.isOfflineMode) {
          add(RefreshMapRequested(layerUrl: url));
        }
        emit(
          MapInitial(
            isOfflineMode: state.isOfflineMode,
            offlineMapPath: state.offlineMapPath,
          ),
        );
      } catch (e) {
        emit(
          MapError(
            'Failed to delete feature: $e',
            isOfflineMode: state.isOfflineMode,
            offlineMapPath: state.offlineMapPath,
          ),
        );
      }
    });

    on<RefreshMapRequested>((event, emit) async {
      if (state.isOfflineMode) return;

      if (event.layerUrl != null) {
        add(LoadMapData(event.layerUrl!));
      } else {
        emit(
          MapInitial(
            isOfflineMode: state.isOfflineMode,
            offlineMapPath: state.offlineMapPath,
          ),
        );
      }
    });

    on<DownloadOfflineMap>((event, emit) async {
      // Prevent multiple simultaneous downloads
      if (state.isDownloading) {
        emit(
          MapError(
            'A download is already in progress.',
            isOfflineMode: state.isOfflineMode,
            offlineMapPath: state.offlineMapPath,
          ),
        );
        return;
      }

      try {
        final directory = await getApplicationDocumentsDirectory();
        final downloadPath = '${directory.path}/offline_map';

        final downloadDir = Directory(downloadPath);

        // Clean previous offline map
        if (await downloadDir.exists()) {
          await downloadDir.delete(recursive: true);
        }

        // Start downloading
        add(UpdateOfflineProgress(downloadProgress: 0.0, isDownloading: true));

        final job = await mapRepository.generateOfflineMap(
          onlineMap: event.onlineMap,
          areaOfInterest: event.areaOfInterest,
          downloadPath: downloadPath,
          currentScale: event.currentScale,
        );

        job.onProgressChanged.listen((progress) {
          add(
            UpdateOfflineProgress(
              downloadProgress: progress / 100.0,
              isDownloading: true,
            ),
          );
        });

        final result = await job.run();
        for (final entry in result.layerErrors.entries) {
          debugPrint(
            'OFFLINE LAYER ERROR -> '
            '"${entry.key.name}": ${entry.value.message}',
          );
        }

        for (final entry in result.tableErrors.entries) {
          debugPrint(
            'OFFLINE TABLE ERROR -> '
            '"${entry.key.tableName}": ${entry.value.message}',
          );
        }

        if (result.hasErrors) {
          final errors = <String>[
            ...result.layerErrors.entries.map(
              (entry) => 'Layer "${entry.key.name}": ${entry.value.message}',
            ),
            ...result.tableErrors.entries.map(
              (entry) =>
                  'Table "${entry.key.tableName}": ${entry.value.message}',
            ),
          ];

          throw Exception(
            errors.isEmpty
                ? 'Some map content could not be taken offline.'
                : errors.join('\n'),
          );
        }

        debugPrint('========== OFFLINE DOWNLOAD SUCCESS ==========');
        debugPrint('OFFLINE MAP PATH: $downloadPath');

        final prefs = await SharedPreferences.getInstance();

        await prefs.setString('offline_map_path', downloadPath);

        add(
          UpdateOfflineProgress(
            downloadProgress: 1.0,
            isDownloading: false,
            offlineMapPath: downloadPath,
          ),
        );
      } catch (e) {
        debugPrint('OFFLINE DOWNLOAD ERROR: $e');

        emit(
          MapError(
            'Failed to download offline map: $e',
            isOfflineMode: state.isOfflineMode,
            offlineMapPath: state.offlineMapPath,
          ),
        );

        add(UpdateOfflineProgress(downloadProgress: 0.0, isDownloading: false));
      }
    });

    on<OpenOfflineMap>((event, emit) async {
      final prefs = await SharedPreferences.getInstance();
      final path = prefs.getString('offline_map_path');
      if (path != null && await Directory(path).exists()) {
        emit(MapInitial(isOfflineMode: true, offlineMapPath: path));
      } else {
        emit(MapError('No offline map found.'));
      }
    });

    on<ExitOfflineMap>((event, emit) async {
      try {
        final prefs = await SharedPreferences.getInstance();

        // Do NOT delete the offline map.
        // We only leave offline mode.
        final path = prefs.getString('offline_map_path');

        emit(MapInitial(isOfflineMode: false, offlineMapPath: path));

        debugPrint('========== OFFLINE MODE EXITED ==========');
      } catch (e) {
        emit(
          MapError(
            'Failed to exit offline map: $e',
            isOfflineMode: state.isOfflineMode,
            offlineMapPath: state.offlineMapPath,
          ),
        );
      }
    });

    on<SyncOfflineChanges>((event, emit) async {
      if (state.offlineMapPath == null) return;

      try {
        final job = await mapRepository.syncOfflineMap(state.offlineMapPath!);
        add(UpdateOfflineProgress(isSyncing: true));

        job.onProgressChanged.listen((progress) {
          add(
            UpdateOfflineProgress(
              syncProgress: progress / 100.0,
              isSyncing: true,
            ),
          );
        });

        final result = await job.run();

        if (result.hasErrors) {
          throw Exception(
            'ArcGIS reported errors while synchronizing the offline map.',
          );
        }

        add(UpdateOfflineProgress(syncProgress: 1.0, isSyncing: false));
      } catch (e) {
        emit(
          MapError(
            'Failed to sync changes: $e',
            isOfflineMode: state.isOfflineMode,
            offlineMapPath: state.offlineMapPath,
          ),
        );
        add(UpdateOfflineProgress(isSyncing: false));
      }
    });

    on<RemoveOfflineMap>((event, emit) async {
      final path = state.offlineMapPath;

      if (path == null) {
        emit(MapInitial(isOfflineMode: false));
        return;
      }

      try {
        debugPrint('========== REMOVING OFFLINE MAP ==========');
        debugPrint('OFFLINE MAP PATH => $path');

        if (state.isOfflineMode) {
          emit(MapInitial(isOfflineMode: false, offlineMapPath: path));
        }

        // Remove the offline package from disk.
        await mapRepository.removeOfflineMap(path);

        // Remove saved path.
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('offline_map_path');

        // Final state: no offline map exists.
        emit(MapInitial(isOfflineMode: false, offlineMapPath: null));

        debugPrint('========== OFFLINE MAP REMOVED ==========');
      } catch (e) {
        debugPrint('REMOVE OFFLINE MAP ERROR => $e');

        emit(
          MapError(
            'Failed to remove offline map: $e',
            isOfflineMode: state.isOfflineMode,
            offlineMapPath: path,
          ),
        );
      }
    });

    on<UpdateOfflineProgress>((event, emit) {
      emit(_mapStateWithOffline(state, event));
    });

    on<CancelCollection>((event, emit) {
      emit(
        MapInitial(
          isOfflineMode: state.isOfflineMode,
          offlineMapPath: state.offlineMapPath,
        ),
      );
    });

    on<PageInitialized>((event, emit) async {
      final prefs = await SharedPreferences.getInstance();
      final path = prefs.getString('offline_map_path');

      emit(
        MapInitial(offlineMapPath: path, isOfflineMode: state.isOfflineMode),
      );
    });
    ;
  }

  void _debugPrintFeatureSnapshot(String stage, GisFeature feature) {

    final geometry = feature.geometry;

    if (geometry == null) {
      debugPrint('Geometry     : NULL');
    } else {
      debugPrint('Type         : ${geometry.runtimeType}');
      debugPrint('Spatial Ref  : ${geometry.spatialReference}');

      if (geometry is ArcGISPoint) {
        debugPrint('X            : ${geometry.x}');
        debugPrint('Y            : ${geometry.y}');
        debugPrint('Z            : ${geometry.z}');
      } else {
        debugPrint('Geometry     : $geometry');
      }
    }

    debugPrint('');
    debugPrint('---------------- ATTRIBUTES ----------------');

    if (feature.attributes.isEmpty) {
      debugPrint('No attributes');
    } else {
      for (final entry in feature.attributes.entries) {
        debugPrint('${entry.key.padRight(35)} : ${entry.value}');
      }
    }

    debugPrint('');
    debugPrint('---------------- ATTACHMENTS ----------------');

    if (feature.attachments.isEmpty) {
      debugPrint('No attachments');
    } else {
      for (int i = 0; i < feature.attachments.length; i++) {
        final file = feature.attachments[i];

        debugPrint('${i + 1}. ${file.path}');
      }
    }

  }

  String? _validateRequiredFields(CollectionState state) {
    final feature = state.draftFeature;

    if (feature == null) {
      return 'Feature data is missing.';
    }

    for (final field in state.editableFields) {
      if (field.nullable) {
        continue;
      }

      final value = feature.attributes[field.name];

      // Null value
      if (value == null) {
        final label = field.alias.isNotEmpty ? field.alias : field.name;

        return '$label is required.';
      }

      // Empty string
      if (value is String && value.trim().isEmpty) {
        final label = field.alias.isNotEmpty ? field.alias : field.name;

        return '$label is required.';
      }
    }

    return null;
  }

  MapState _mapStateWithOffline(
    MapState currentState,
    UpdateOfflineProgress event,
  ) {
    final common = {
      'isOfflineMode': currentState.isOfflineMode,
      'offlineDownloadProgress': event.downloadProgress,
      'offlineSyncProgress': event.syncProgress,
      'offlineMapPath': event.offlineMapPath ?? currentState.offlineMapPath,
      'isDownloading': event.isDownloading,
      'isSyncing': event.isSyncing,
    };

    if (currentState is MapInitial) {
      return MapInitial(
        isOfflineMode: common['isOfflineMode'] as bool,
        offlineDownloadProgress: common['offlineDownloadProgress'] as double,
        offlineSyncProgress: common['offlineSyncProgress'] as double,
        offlineMapPath: common['offlineMapPath'] as String?,
        isDownloading: common['isDownloading'] as bool,
        isSyncing: common['isSyncing'] as bool,
      );
    } else if (currentState is MapLoading) {
      return MapLoading(
        isOfflineMode: common['isOfflineMode'] as bool,
        offlineDownloadProgress: common['offlineDownloadProgress'] as double,
        offlineSyncProgress: common['offlineSyncProgress'] as double,
        offlineMapPath: common['offlineMapPath'] as String?,
        isDownloading: common['isDownloading'] as bool,
        isSyncing: common['isSyncing'] as bool,
      );
    } else if (currentState is MapLoaded) {
      return MapLoaded(
        currentState.features,
        isOfflineMode: common['isOfflineMode'] as bool,
        offlineDownloadProgress: common['offlineDownloadProgress'] as double,
        offlineSyncProgress: common['offlineSyncProgress'] as double,
        offlineMapPath: common['offlineMapPath'] as String?,
        isDownloading: common['isDownloading'] as bool,
        isSyncing: common['isSyncing'] as bool,
      );
    } else if (currentState is FeatureSelected) {
      return FeatureSelected(
        currentState.feature,
        isOfflineMode: common['isOfflineMode'] as bool,
        offlineDownloadProgress: common['offlineDownloadProgress'] as double,
        offlineSyncProgress: common['offlineSyncProgress'] as double,
        offlineMapPath: common['offlineMapPath'] as String?,
        isDownloading: common['isDownloading'] as bool,
        isSyncing: common['isSyncing'] as bool,
      );
    } else if (currentState is MapError) {
      return MapError(
        event.errorMessage ?? currentState.message,
        isOfflineMode: common['isOfflineMode'] as bool,
        offlineDownloadProgress: common['offlineDownloadProgress'] as double,
        offlineSyncProgress: common['offlineSyncProgress'] as double,
        offlineMapPath: common['offlineMapPath'] as String?,
        isDownloading: common['isDownloading'] as bool,
        isSyncing: common['isSyncing'] as bool,
      );
    } else if (currentState is CollectionState) {
      return currentState.copyWith(
        offlineDownloadProgress: common['offlineDownloadProgress'] as double,
        offlineSyncProgress: common['offlineSyncProgress'] as double,
        offlineMapPath: common['offlineMapPath'] as String?,
        isDownloading: common['isDownloading'] as bool,
        isSyncing: common['isSyncing'] as bool,
      );
    }
    return currentState;
  }

  List<Field> _getCollectionFields(FeatureTable table) {
    final excludedPrefixes = ['esrignss_', 'esrisnsr_'];
    final excludedNames = [
      'OBJECTID',
      'GlobalID',
      'CreationDate',
      'Creator',
      'EditDate',
      'Editor',
    ];

    return table.fields.where((field) {
      final name = field.name;
      final isExcluded =
          excludedPrefixes.any((prefix) => name.startsWith(prefix)) ||
          excludedNames.contains(name);
      return !isExcluded && field.editable;
    }).toList();
  }
}
