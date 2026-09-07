import 'dart:developer';

import 'package:arcgis_maps/arcgis_maps.dart';

class ArcGISAuthService {
  static const String _portalUrl =
      'https://vasanth-gis.maps.arcgis.com';

  static const String _clientId =
      'J2aU21TR7GpPuiwk';

  static const String _redirectUrl =
      'my-gis-app://auth';

  final OAuthUserConfiguration _configuration =
  OAuthUserConfiguration(
    portalUri: Uri.parse(_portalUrl),
    clientId: _clientId,
    redirectUri: Uri.parse(_redirectUrl),
  );

  Future<OAuthUserCredential> login() async {
    log('Starting ArcGIS OAuth login');

    final credential = await OAuthUserCredential.create(
      configuration: _configuration,
    );

    ArcGISEnvironment
        .authenticationManager
        .arcGISCredentialStore
        .add(
      credential: credential,
    );

    log('ArcGIS OAuth login successful');

    return credential;
  }

  Future<void> logout() async {
    log('Starting ArcGIS logout');

    final credentials = ArcGISEnvironment
        .authenticationManager
        .arcGISCredentialStore
        .getCredentials();

    for (final credential in credentials) {
      if (credential is OAuthUserCredential) {
        try {
          await credential.revokeToken();
        } catch (e) {
          log('Token revoke failed: $e');
        }
      }
    }

    ArcGISEnvironment
        .authenticationManager
        .arcGISCredentialStore
        .removeAll();

    log('ArcGIS logout completed');
  }

  bool get isAuthenticated {
    final credentials = ArcGISEnvironment
        .authenticationManager
        .arcGISCredentialStore
        .getCredentials();

    return credentials.isNotEmpty;
  }

  Future<List<PortalItem>> fetchUserWebMaps() async {
    log('Fetching user web maps');

    final portal = Portal.arcGISOnline(
      connection: PortalConnection.authenticated,
    );

    await portal.load();

    log('Authenticated user: ${portal.user?.username}');

    final queryParams = PortalQueryParameters(
      query: 'id:eee6c5fb0c87465d8d44a802f3c9353d',
    );

    final result = await portal.findItems(
      parameters: queryParams,
    );

    await Future.wait(
      result.results.map(
        (item) async {
          try {
            await item.load();

            if (item.thumbnail != null) {
              await item.thumbnail!.load();
            }
          } catch (e) {
            log(
              'Error loading item ${item.itemId}: $e',
            );
          }
        },
      ),
    );

    log(
      'Found ${result.results.length} web maps',
    );

    return result.results;
  }
}