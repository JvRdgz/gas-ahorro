import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/station.dart';

class FuelApi {
  static const _endpoint =
      'https://sedeaplicaciones.minetur.gob.es/ServiciosRESTCarburantes/PreciosCarburantes/EstacionesTerrestres/';

  Future<List<Station>> fetchStations() async {
    final response = await http.get(Uri.parse(_endpoint));
    if (response.statusCode != 200) {
      throw Exception('Error al cargar datos (${response.statusCode}).');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final list = data['ListaEESSPrecio'] as List<dynamic>?;
    if (list == null) return [];

    return list.map((item) {
      final raw = item as Map<String, dynamic>;
      final lat = _parseDouble(raw['Latitud']);
      final lng = _parseDouble(raw['Longitud (WGS84)']);
      final prices = _extractPrices(raw);

      return Station(
        id: raw['IDEESS']?.toString() ?? '',
        name: raw['Rótulo']?.toString() ?? 'Gasolinera',
        address:
            '${raw['Dirección'] ?? ''}, ${raw['Localidad'] ?? ''}',
        lat: lat ?? 0,
        lng: lng ?? 0,
        prices: prices,
      );
    }).where((station) => station.lat != 0 && station.lng != 0).toList();
  }

  Map<String, double> _extractPrices(Map<String, dynamic> raw) {
    const fields = [
      'Precio Gasolina 95 E5',
      'Precio Gasolina 95 E5 Premium',
      'Precio Gasolina 98 E5',
      'Precio Gasolina 98 E5 Premium',
      'Precio Gasoleo A',
      'Precio Gasoleo Premium',
      'Precio Gasoleo B',
      'Precio Gasoleo C',
      'Precio GNC',
      'Precio GNL',
      'Precio GLP',
    ];

    final prices = <String, double>{};
    for (final field in fields) {
      final value = _parseDouble(raw[field]);
      if (value != null && value > 0) {
        prices[field.replaceAll('Precio ', '')] = value;
      }
    }
    return prices;
  }

  double? _parseDouble(dynamic value) {
    if (value == null) return null;
    final normalized = value.toString().replaceAll(',', '.');
    return double.tryParse(normalized);
  }
}
