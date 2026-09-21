import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:arcgis_maps/arcgis_maps.dart';
import 'package:gov_gis_map/presentation/map/bloc/portal_bloc.dart';
import 'package:gov_gis_map/app/router/app_router.dart';
import 'package:gov_gis_map/data/datasources/service/arcgis_auth_service.dart';

class MapSelectionPage extends StatelessWidget {
  const MapSelectionPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => PortalBloc()..add(FetchUserWebMaps()),
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'Maps',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          centerTitle: false,
          actions: [
            // IconButton(icon: const Icon(Icons.search), onPressed: () {}),
            IconButton(
              icon: const Icon(Icons.account_circle),
              onPressed: () async {
                final authService = ArcGISAuthService();
                final portal = await authService.getAuthenticatedPortal();

                if (!context.mounted) return;

                final user = portal.user;

                showDialog(
                  context: context,
                  builder: (dialogContext) {
                    return AlertDialog(
                      title: const Text('Profile'),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Username',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(user?.username ?? 'Unknown'),

                          const SizedBox(height: 16),

                          // Text(
                          //   'User ID',
                          //   style: TextStyle(
                          //     fontWeight: FontWeight.bold,
                          //     color: Colors.grey[600],
                          //   ),
                          // ),
                          // const SizedBox(height: 4),
                          // Text(user?.userId ?? 'Unknown'),
                        ],
                      ),
                      actions: [
                        TextButton(
                          onPressed: () async {
                            Navigator.pop(dialogContext);

                            await authService.logout();

                            if (!context.mounted) return;

                            Navigator.of(context).pushNamedAndRemoveUntil(
                              AppRouter.login,
                              (route) => false,
                            );
                          },
                          child: const Text('Sign Out'),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ],
        ),
        body: BlocBuilder<PortalBloc, PortalState>(
          builder: (context, state) {
            if (state is PortalLoading) {
              return const Center(child: CircularProgressIndicator());
            } else if (state is PortalError) {
              return Center(child: Text(state.message));
            } else if (state is PortalLoaded) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text(
                      'My maps',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: state.webMaps.length,
                      itemBuilder: (context, index) {
                        final map = state.webMaps[index];
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: SizedBox(
                              width: 100,
                              height: 60,
                              child: map.thumbnail?.image != null
                                  ? Image.memory(
                                      map.thumbnail!.image!.getEncodedBuffer(),
                                      fit: BoxFit.cover,
                                      errorBuilder:
                                          (context, error, stackTrace) =>
                                              Container(
                                                color: Colors.grey[800],
                                                child: const Icon(Icons.map),
                                              ),
                                    )
                                  : Container(
                                      color: Colors.grey[800],
                                      child: const Icon(Icons.map),
                                    ),
                            ),
                          ),
                          title: Text(
                            map.title,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          // trailing: const Icon(Icons.more_vert),
                          onTap: () {
                            Navigator.pushNamed(
                              context,
                              AppRouter.map,
                              arguments: map,
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              );
            }
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }
}
