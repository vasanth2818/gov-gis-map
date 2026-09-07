import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:arcgis_maps/arcgis_maps.dart';
import 'package:arcgis_maps_toolkit/arcgis_maps_toolkit.dart';
import 'package:gov_gis_map/app/router/app_router.dart';
import 'package:gov_gis_map/app/theme/app_theme.dart';
import 'package:gov_gis_map/presentation/auth/bloc/auth_bloc.dart';
import 'package:gov_gis_map/presentation/map/bloc/map_bloc.dart';
import 'package:gov_gis_map/data/datasources/remote/arcgis_remote_datasource.dart';
import 'package:gov_gis_map/data/repositories/map_repository_impl.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final oauthConfiguration = OAuthUserConfiguration(
      portalUri: Uri.parse('https://www.arcgis.com'),
      clientId: 'J2aU21TR7GpPuiwk',
      redirectUri: Uri.parse('my-gis-app://auth'),
    );

    final mapRepository = MapRepositoryImpl(ArcGISRemoteDataSource());

    return Authenticator(
      oAuthUserConfigurations: [oauthConfiguration],
      child: MultiBlocProvider(
        providers: [
          BlocProvider(create: (context) => AuthBloc()..add(CheckAuthStatus())),
          BlocProvider(create: (context) => MapBloc(mapRepository: mapRepository)),
        ],
        child: MaterialApp(
          title: 'GIS Field Survey',
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeMode.dark,
          onGenerateRoute: AppRouter.onGenerateRoute,
          initialRoute: AppRouter.login,
          debugShowCheckedModeBanner: false,
        ),
      ),
    );
  }
}
