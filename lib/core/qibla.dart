import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';

import 'magnetic_model.dart';

/// The Kaaba in Makkah.
const kaabaLatitude = 21.422487;
const kaabaLongitude = 39.826206;

/// Direction of the Kaaba from a place, in degrees clockwise from true north, along the shortest path on the globe.
double qiblaBearing(double latitude, double longitude) {
  final phi1 = _radians(latitude), phi2 = _radians(kaabaLatitude);
  final delta = _radians(kaabaLongitude - longitude);
  final y = math.sin(delta) * math.cos(phi2);
  final x = math.cos(phi1) * math.sin(phi2) - math.sin(phi1) * math.cos(phi2) * math.cos(delta);
  return (_degrees(math.atan2(y, x)) + 360) % 360;
}

/// Distance to the Kaaba in kilometres.
double distanceToKaaba(double latitude, double longitude) {
  final phi1 = _radians(latitude), phi2 = _radians(kaabaLatitude);
  final dPhi = phi2 - phi1, dLambda = _radians(kaabaLongitude - longitude);
  final a = math.pow(math.sin(dPhi / 2), 2) + math.cos(phi1) * math.cos(phi2) * math.pow(math.sin(dLambda / 2), 2);
  return 6371.0 * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

double _radians(double degrees) => degrees * math.pi / 180;
double _degrees(double radians) => radians * 180 / math.pi;

class HeadingReading {
  const HeadingReading({required this.trueHeading, required this.reliable});

  /// Where the top of the phone points, in degrees clockwise from true north.
  final double trueHeading;

  /// False while the compass needs calibrating.
  final bool reliable;
}

/// The phone's own calibrated compass, corrected from magnetic north to true north for the reader's city.
class Compass {
  Compass._();

  static const _channel = EventChannel('tz.or.iqraa/heading');

  /// Readings while listened to. Ends with an error when the phone has no compass.
  static Stream<HeadingReading> readings(double latitude, double longitude) {
    final declination = MagneticModel.declination(latitude, longitude, DateTime.now().toUtc());
    return _channel.receiveBroadcastStream().map((event) {
      final values = (event as List).cast<num>();
      return HeadingReading(trueHeading: (values[0].toDouble() + declination + 360) % 360, reliable: values[1] > 0);
    });
  }
}
