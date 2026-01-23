import 'dart:convert';

import 'package:http/http.dart' as http;

import 'places_key.dart';

class DirectionsApi {
  static const _endpoint = 'https://maps.googleapis.com/maps/api/directions/json';

  Future<List<Map<String, double>>> fetchRoute({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
  }) async {
    if (googleMapsApiKey.isEmpty) {
      throw Exception('GOOGLE_MAPS_API_KEY no configurada.');
    }

    final uri = Uri.parse(_endpoint).replace(queryParameters: {
      'origin': '$originLat,$originLng',
      'destination': '$destLat,$destLng',
      'mode': 'driving',
      'key': googleMapsApiKey,
      'language': 'es',
    });

    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('Error en Directions (${response.statusCode}).');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final status = data['status']?.toString();
    if (status != 'OK') {
      throw Exception('Directions status: $status');
    }

    final routes = data['routes'] as List<dynamic>;
    if (routes.isEmpty) return [];

    final overview = routes.first['overview_polyline'] as Map<String, dynamic>?;
    final points = overview?['points']?.toString();
    if (points == null || points.isEmpty) return [];

    return _decodePolyline(points);
  }

  List<Map<String, double>> _decodePolyline(String encoded) {
    final points = <Map<String, double>>[];
    var index = 0;
    var lat = 0;
    var lng = 0;

    while (index < encoded.length) {
      var result = 0;
      var shift = 0;
      int b;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final deltaLat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lat += deltaLat;

      result = 0;
      shift = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final deltaLng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lng += deltaLng;

      points.add({
        'lat': lat / 1e5,
        'lng': lng / 1e5,
      });
    }

    return points;
  }
}
