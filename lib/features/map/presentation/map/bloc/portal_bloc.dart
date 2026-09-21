import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:arcgis_maps/arcgis_maps.dart';
import 'package:gov_gis_map/features/map/data/datasources/service/arcgis_auth_service.dart';

// Events
abstract class PortalEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

class FetchUserWebMaps extends PortalEvent {}

// States
abstract class PortalState extends Equatable {
  @override
  List<Object?> get props => [];
}

class PortalInitial extends PortalState {}

class PortalLoading extends PortalState {}

class PortalLoaded extends PortalState {
  final List<PortalItem> webMaps;
  PortalLoaded(this.webMaps);
  @override
  List<Object?> get props => [webMaps];
}

class PortalError extends PortalState {
  final String message;
  PortalError(this.message);
  @override
  List<Object?> get props => [message];
}

class PortalBloc extends Bloc<PortalEvent, PortalState> {
  final ArcGISAuthService _authService;

  PortalBloc({ArcGISAuthService? authService})
    : _authService = authService ?? ArcGISAuthService(),
      super(PortalInitial()) {
    on<FetchUserWebMaps>((event, emit) async {
      emit(PortalLoading());
      try {
        final maps = await _authService.fetchUserWebMaps();
        emit(PortalLoaded(maps));
      } catch (e) {
        emit(PortalError(e.toString()));
      }
    });
  }
}
