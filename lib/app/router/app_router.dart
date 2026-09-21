import 'package:flutter/material.dart';
import 'package:arcgis_maps/arcgis_maps.dart';
import 'package:gov_gis_map/features/map/presentation/auth/pages/login_page.dart';
import 'package:gov_gis_map/features/map/presentation/map/pages/map_page.dart';
import 'package:gov_gis_map/features/map/presentation/map/pages/map_selection_page.dart';

class AppRouter {
  static const String login = '/';
  static const String mapSelection = '/maps';
  static const String map = '/map';

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case login:
        return MaterialPageRoute(builder: (_) => const LoginPage());
      case mapSelection:
        return MaterialPageRoute(builder: (_) => const MapSelectionPage());
      case map:
        final portalItem = settings.arguments as PortalItem?;
        return MaterialPageRoute(
          builder: (_) => MapPage(portalItem: portalItem),
        );
      default:
        return MaterialPageRoute(
          builder: (_) => Scaffold(
            body: Center(child: Text('No route defined for ${settings.name}')),
          ),
        );
    }
  }
}
