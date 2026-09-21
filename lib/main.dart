import 'package:arcgis_maps/arcgis_maps.dart';
import 'package:flutter/material.dart';
import 'app/app.dart';
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set the ArcGIS API Key (Required for basemaps and hosted services)
  // Replace with your actual key from https://developers.arcgis.com
  //ArcGISEnvironment.apiKey = 'AAPTacNp693AxTLPYmplE57MRcA..d4OkOHw3Jqr38sbg-YlI0tPmJbMjKiGfoz_OqWgUqdx4cGcthMD3QInrkf75-Nq3jWkX84axg4uj6SojdjaUXeFAxQrxWxlqoadszo1loy-f4ARAO2M2uiQxv7aFywoGhPwxGqp9AaOyMB5WPoqMFIcElwCY9FK16Pc-9gkt8bnh8-lr4PT64ZZubXarEksCLultbb23xrxf-GuOel3KWiUUPvnBbR4d6J5jwL5R9jkcfKKLknXHk3JBAT1_4LnrRbA7';

  ArcGISEnvironment
      .authenticationManager
      .arcGISCredentialStore =
  await ArcGISCredentialStore.initPersistentStore();

  runApp(
    MyApp(),
  );
}