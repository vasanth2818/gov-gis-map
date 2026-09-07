import 'dart:io';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:arcgis_maps/arcgis_maps.dart';
import 'package:gov_gis_map/domain/entities/gis_feature.dart';
import 'package:gov_gis_map/domain/repositories/map_repository.dart';
import 'package:flutter/foundation.dart';

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
  LocationCaptured(this.geometry);
}

class UpdateDraftAttributes extends MapEvent {
  final Map<String, dynamic> attributes;
  UpdateDraftAttributes(this.attributes);
}

class AddDraftAttachment extends MapEvent {
  final File file;
  AddDraftAttachment(this.file);
}

class SubmitDraftFeature extends MapEvent {}

class CancelCollection extends MapEvent {}

// States
enum CollectionMode { idle, pickingLocation, fillingForm, submitting, viewDetails }

abstract class MapState extends Equatable {
  @override
  List<Object?> get props => [];
}

class MapInitial extends MapState {}
class MapLoading extends MapState {}
class MapLoaded extends MapState {
  final List<GisFeature> features;
  MapLoaded(this.features);
  @override
  List<Object?> get props => [features];
}
class FeatureSelected extends MapState {
  final GisFeature feature;
  FeatureSelected(this.feature);
  @override
  List<Object?> get props => [feature];
}
class MapError extends MapState {
  final String message;
  MapError(this.message);
  @override
  List<Object?> get props => [message];
}

class CollectionState extends MapState {
  final CollectionMode mode;
  final FeatureLayer? targetLayer;
  final GisFeature? draftFeature;
  final List<Field> editableFields;
  final String? errorMessage;

  CollectionState({
    required this.mode,
    this.targetLayer,
    this.draftFeature,
    this.editableFields = const [],
    this.errorMessage,
  });

  @override
  List<Object?> get props => [mode, targetLayer, draftFeature, editableFields, errorMessage];

  CollectionState copyWith({
    CollectionMode? mode,
    FeatureLayer? targetLayer,
    GisFeature? draftFeature,
    List<Field>? editableFields,
    String? errorMessage,
  }) {
    return CollectionState(
      mode: mode ?? this.mode,
      targetLayer: targetLayer ?? this.targetLayer,
      draftFeature: draftFeature ?? this.draftFeature,
      editableFields: editableFields ?? this.editableFields,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

// BLoC
class MapBloc extends Bloc<MapEvent, MapState> {
  final MapRepository mapRepository;

  MapBloc({required this.mapRepository}) : super(MapInitial()) {
    on<LoadMapData>((event, emit) async {
      emit(MapLoading());
      try {
        final features = await mapRepository.getFeatures(event.layerUrl);
        emit(MapLoaded(features));
      } catch (e) {
        emit(MapError(e.toString()));
      }
    });

    on<FeatureIdentified>((event, emit) {
      emit(FeatureSelected(event.feature));
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
        emit(MapError(e.toString()));
      }
    });

    on<StartCollectionRequested>((event, emit) async {
      final layer = event.layer;
      
      try {
        final table = layer.featureTable;

        if (table == null) {
          debugPrint('Feature table is null for layer: ${layer.name}');
          emit(MapError('Cannot collect data: Layer "${layer.name}" has no feature table.'));
          return;
        }

        // Load table if not loaded
        if (table.loadStatus != LoadStatus.loaded) {
          debugPrint('Loading feature table for layer: ${layer.name}');
          await table.load();
        }

        if (!table.canAdd()) {
          emit(MapError('You do not have permission to add features to this layer.'));
          return;
        }

        final editableFields = table.fields.where((f) => f.editable && !f.nullable).toList();
        if (editableFields.isEmpty) {
          debugPrint('No required editable fields found for ${layer.name}. Falling back to first 5.');
          editableFields.addAll(table.fields.where((f) => f.editable).take(5));
        }

        debugPrint('Emitting CollectionState for layer: ${layer.name}');
        emit(CollectionState(
          mode: CollectionMode.pickingLocation,
          targetLayer: layer,
          editableFields: editableFields,
          draftFeature: GisFeature(id: '', attributes: {}),
        ));
      } catch (e) {
        debugPrint('Error starting collection: $e');
        emit(MapError('Failed to initialize collection: ${e.toString()}'));
      }
    });

    on<LocationCaptured>((event, emit) {
      if (state is CollectionState) {
        final current = state as CollectionState;
        emit(current.copyWith(
          mode: CollectionMode.fillingForm,
          draftFeature: current.draftFeature?.copyWith(geometry: event.geometry),
        ));
      }
    });

    on<UpdateDraftAttributes>((event, emit) {
      if (state is CollectionState) {
        final current = state as CollectionState;
        final newAttributes = Map<String, dynamic>.from(current.draftFeature?.attributes ?? {});
        newAttributes.addAll(event.attributes);
        emit(current.copyWith(
          draftFeature: current.draftFeature?.copyWith(attributes: newAttributes),
        ));
      }
    });

    on<AddDraftAttachment>((event, emit) {
      if (state is CollectionState) {
        final current = state as CollectionState;
        final newAttachments = List<File>.from(current.draftFeature?.attachments ?? []);
        newAttachments.add(event.file);
        emit(current.copyWith(
          draftFeature: current.draftFeature?.copyWith(attachments: newAttachments),
        ));
      }
    });

    on<SubmitDraftFeature>((event, emit) async {
      if (state is CollectionState) {
        final current = state as CollectionState;
        final layer = current.targetLayer;
        final feature = current.draftFeature;

        if (layer == null || feature == null) return;

        emit(current.copyWith(mode: CollectionMode.submitting));
        try {
          final url = (layer.featureTable as ServiceFeatureTable).uri.toString();
          await mapRepository.addFeature(url, feature);
          emit(current.copyWith(mode: CollectionMode.viewDetails));
        } catch (e) {
          emit(current.copyWith(mode: CollectionMode.fillingForm, errorMessage: e.toString()));
        }
      }
    });

    on<CancelCollection>((event, emit) {
      emit(MapInitial());
    });
  }
}
