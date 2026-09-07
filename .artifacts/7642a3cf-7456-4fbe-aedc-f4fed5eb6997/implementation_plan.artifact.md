# Implementation Plan - Government GIS Field Survey Application

Build a feasibility prototype for a mobile GIS field-survey application using Flutter and ArcGIS Maps SDK for Flutter (300.1.0+5042). The app will follow Clean Architecture and BLoC patterns, inspired by ArcGIS Field Maps.

## User Review Required

> [!IMPORTANT]
> The ArcGIS Maps SDK for Flutter version 300.1.0+5042 contains significant API changes from previous versions. I will be using the new APIs as specified in the provided replacement list.

> [!WARNING]
> Offline synchronization and high-accuracy GNSS integration are complex features. For this feasibility prototype, I will implement the core workflows and hooks for these features, demonstrating how they would work in a production environment.

## Proposed Changes

### Core & App Layers
Setup routing, theme, and shared constants.

#### [NEW] [app_router.dart](file:///F:/gov_gis_map/lib/app/router/app_router.dart)
#### [NEW] [app_theme.dart](file:///F:/gov_gis_map/lib/app/theme/app_theme.dart)

### Domain Layer
Define entities and repository interfaces for GIS features, authentication, and offline tasks.

#### [NEW] [gis_feature.dart](file:///F:/gov_gis_map/lib/domain/entities/gis_feature.dart)
#### [NEW] [map_repository.dart](file:///F:/gov_gis_map/lib/domain/repositories/map_repository.dart)

### Data Layer
Implement ArcGIS-specific data sources and repositories using the 300.1.x API.

#### [NEW] [arcgis_remote_datasource.dart](file:///F:/gov_gis_map/lib/data/datasources/remote/arcgis_remote_datasource.dart)
#### [MODIFY] [map_repository_impl.dart](file:///F:/gov_gis_map/lib/data/repositories/map_repository_impl.dart)

### Presentation Layer
Implement BLoCs and UI components for Map, Auth, and Offline workflows.

#### [MODIFY] [map_page.dart](file:///F:/gov_gis_map/lib/presentation/map/pages/map_page.dart)
Update the existing MapPage to use the new architecture and ArcGIS API.
#### [NEW] [map_bloc.dart](file:///F:/gov_gis_map/lib/presentation/map/bloc/map_bloc.dart)

## Verification Plan

### Automated Tests
- Unit tests for Use Cases and Repositories (Mocking ArcGIS SDK where possible).
- BLoC tests for state transitions.

### Manual Verification
- Verify Map rendering and Basemap switching.
- Verify Current Location tracking.
- Verify Feature Identification (Tap on map).
- Verify CRUD operations on features.
- Verify Offline map download workflow (mocked or with a test service).
