import 'dart:developer';
import 'package:arcgis_maps/arcgis_maps.dart';
import 'package:arcgis_maps_toolkit/arcgis_maps_toolkit.dart';

class ArcGISAuthService {
  Future<void> login() async {
    log('Starting ArcGIS login process');
    
    // Attempting to load the portal with an authenticated connection
    // will trigger an ArcGISAuthenticationChallenge if not already authenticated.
    // The Authenticator widget in app.dart will catch this and show the login UI.
    final portal = Portal.arcGISOnline(connection: PortalConnection.authenticated);
    
    try {
      await portal.load();
      log('Portal loaded successfully: ${portal.user?.fullName}');
    } catch (e) {
      log('Error during login: $e');
      rethrow;
    }
  }

  Future<void> logout() async {
    log('Starting logout process');
    
    // Toolkit provides helper methods for revoking and clearing tokens
    await Authenticator.revokeOAuthTokens();
    await Authenticator.clearCredentials();
    
    // Clear the HTTP cache to ensure fresh state
    ArcGISEnvironment.httpClient.cache.evictAll();
    
    log('Logout process completed');
  }

  bool get isAuthenticated {
    final credentials = ArcGISEnvironment.authenticationManager.arcGISCredentialStore.getCredentials();
    return credentials.isNotEmpty;
  }

  Future<List<PortalItem>> fetchUserWebMaps() async {
    log('Fetching user web maps');
    final portal = Portal.arcGISOnline(connection: PortalConnection.authenticated);
    await portal.load();
    
    final queryParams = PortalQueryParameters(
      query: 'owner:${portal.user?.username} type:"Web Map"',
    );

    final result = await portal.findItems(parameters: queryParams);
    // Load metadata and thumbnails for all items in parallel
    await Future.wait(result.results.map((item) async {
      try {
        await item.load();
        if (item.thumbnail != null) {
          await item.thumbnail!.load();
        }
      } catch (e) {
        log('Error loading item ${item.itemId}: $e');
      }
    }));
    
    log('Found ${result.results.length} web maps');
    return result.results;
  }
}
