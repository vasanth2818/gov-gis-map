import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:arcgis_maps/arcgis_maps.dart';

class GisFeature extends Equatable {
  final String id;
  final Geometry? geometry;
  final Map<String, dynamic> attributes;
  final List<File> attachments;

  const GisFeature({
    required this.id,
    this.geometry,
    required this.attributes,
    this.attachments = const [],
  });

  @override
  List<Object?> get props => [id, geometry, attributes, attachments];

  GisFeature copyWith({
    String? id,
    Geometry? geometry,
    Map<String, dynamic>? attributes,
    List<File>? attachments,
  }) {
    return GisFeature(
      id: id ?? this.id,
      geometry: geometry ?? this.geometry,
      attributes: attributes ?? this.attributes,
      attachments: attachments ?? this.attachments,
    );
  }
}
