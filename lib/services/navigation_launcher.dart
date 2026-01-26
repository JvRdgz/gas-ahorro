import 'dart:io';

import 'package:url_launcher/url_launcher.dart';

class NavigationLauncher {
  Future<bool> openDefaultMaps(double lat, double lng) async {
    if (Platform.isIOS) {
      final uri = Uri.parse('https://maps.apple.com/?daddr=$lat,$lng');
      return launchUrl(uri, mode: LaunchMode.externalApplication);
    }

    final geoUri = Uri.parse('geo:$lat,$lng?q=$lat,$lng');
    if (await canLaunchUrl(geoUri)) {
      return launchUrl(geoUri, mode: LaunchMode.externalApplication);
    }

    final webUri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng',
    );
    return launchUrl(webUri, mode: LaunchMode.externalApplication);
  }
}
