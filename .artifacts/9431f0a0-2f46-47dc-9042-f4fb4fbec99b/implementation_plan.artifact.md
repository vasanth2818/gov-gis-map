# Fix ArcGIS "Invalid URL" Error and Floating Action Button Issues

This plan addresses the `ArcGISException: code=400; Invalid URL` error and the issue where clicking the "+" button in `MapPage` results in "No editable layers found" or no visible feedback.

## User Review Required

> [!IMPORTANT]
> **API Key Required:** The application is using ArcGIS basemaps and hosted services but does not initialize an API Key. This is likely the cause of the `400 Bad Request` error. I will add a placeholder for the API key in `main.dart`, which the user should replace with their actual key.

> [!NOTE]
> **Redundant BlocProvider:** `MapPage` currently creates a new instance of `MapBloc` even though one is already provided globally in `app.dart`. This can lead to state desynchronization. I will unify the BLoC usage.

## Proposed Changes

### Core / Initialization

#### [MODIFY] [main.dart](file:///F:/gov_gis_map/lib/main.dart)
- Add `ArcGISEnvironment.apiKey` initialization.

### Presentation / Map

#### [MODIFY] [map_bloc.dart](file:///F:/gov_gis_map/lib/presentation/map/bloc/map_bloc.dart)
- Improve error handling in `StartCollectionRequested`.
- Add more descriptive logging.
- Ensure `table.load()` is awaited safely.

#### [MODIFY] [map_page.dart](file:///F:/gov_gis_map/lib/presentation/map/pages/map_page.dart)
- Remove redundant `BlocProvider` from `build`.
- Improve `_firstEditableLayer` to wait for layer loading and provide better logging.
- Change the crosshair color to be visible against light maps (e.g., Blue).
- Ensure the "ADD POINT" button and crosshair are correctly synchronized with the BLoC state.

### Data / Remote

#### [MODIFY] [arcgis_remote_datasource.dart](file:///F:/gov_gis_map/lib/data/datasources/remote/arcgis_remote_datasource.dart)
- Add robust URL validation and error logging for `ServiceFeatureTable` loading.

---

## Verification Plan

### Automated Tests
- Not applicable for this UI/Service integration fix, but manual verification is key.

### Manual Verification
1. Run the app and check if the `ArcGISException` SnackBar still appears.
2. Click the "+" button and verify:
   - The button disappears.
   - A crosshair appears in the center of the map.
   - The "ADD POINT" button appears at the bottom.
3. Click "ADD POINT" and verify that the collection form opens.
4. Verify that the "No editable layers found" SnackBar no longer appears if the service is correctly loaded.
