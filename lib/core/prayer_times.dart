import 'dart:math' as math;

/// Calculation methods in common use, with the sun angles below the horizon for Fajr and Isha.
/// Umm al-Qura sets Isha a fixed 90 minutes after Maghrib.
enum PrayerMethod {
  mwl('Muslim World League', 18, 17),
  egypt('Egyptian General Authority', 19.5, 17.5),
  makkah('Umm al-Qura, Makkah', 18.5, 0, ishaMinutes: 90),
  karachi('University of Islamic Sciences, Karachi', 18, 18),
  isna('Islamic Society of North America', 15, 15);

  const PrayerMethod(this.label, this.fajrAngle, this.ishaAngle, {this.ishaMinutes = 0});

  final String label;
  final double fajrAngle;
  final double ishaAngle;
  final int ishaMinutes;
}

/// Asr starts when an object's shadow equals its length (Shafi'i, Maliki, Hanbali) or twice its length (Hanafi).
enum AsrMethod { standard, hanafi }

class PrayerDay {
  const PrayerDay({required this.fajr, required this.sunrise, required this.dhuhr, required this.asr, required this.maghrib, required this.isha});

  final DateTime fajr;
  final DateTime sunrise;
  final DateTime dhuhr;
  final DateTime asr;
  final DateTime maghrib;
  final DateTime isha;
}

/// Prayer times for a place, worked out from the sun's position and returned as UTC instants,
/// so a reminder fires at the right moment whatever time zone the phone is set to.
class PrayerTimes {
  const PrayerTimes({required this.latitude, required this.longitude, this.method = PrayerMethod.mwl, this.asr = AsrMethod.standard});

  final double latitude;
  final double longitude;
  final PrayerMethod method;
  final AsrMethod asr;

  /// The calendar date at the place itself, judged from its longitude.
  DateTime localDate(DateTime instant) {
    final solar = instant.toUtc().add(Duration(minutes: (longitude * 4).round()));
    return DateTime.utc(solar.year, solar.month, solar.day);
  }

  PrayerDay forDate(DateTime date) {
    final day = DateTime.utc(date.year, date.month, date.day);
    final jd = _julian(day.year, day.month, day.day) - longitude / (15 * 24);

    // Two passes: the first uses rough times of day, the second refines them with the sun's position at those times.
    // A time the sun never reaches comes back NaN, and its rough estimate is used again in the next pass.
    var fajr = 5.0, sunrise = 6.0, dhuhr = 12.0, asrTime = 13.0, sunset = 18.0, isha = 18.0;
    for (var pass = 0; pass < 2; pass++) {
      fajr = _sunAngleTime(jd, method.fajrAngle, fajr.isNaN ? 5 : fajr, before: true);
      sunrise = _sunAngleTime(jd, 0.833, sunrise.isNaN ? 6 : sunrise, before: true);
      dhuhr = _midDay(jd, dhuhr);
      asrTime = _asrTime(jd, asr == AsrMethod.hanafi ? 2 : 1, asrTime.isNaN ? 13 : asrTime);
      sunset = _sunAngleTime(jd, 0.833, sunset.isNaN ? 18 : sunset, before: false);
      isha = method.ishaMinutes > 0 ? sunset + method.ishaMinutes / 60 : _sunAngleTime(jd, method.ishaAngle, isha.isNaN ? 18 : isha, before: false);
    }

    // Far from the equator the sun may not sink low enough for Fajr or Isha; each then takes its share of the night.
    final night = 24 - (sunset - sunrise);
    final fajrLimit = sunrise - method.fajrAngle / 60 * night;
    if (fajr.isNaN || fajr < fajrLimit) {
      fajr = fajrLimit;
    }
    if (method.ishaMinutes == 0) {
      final ishaLimit = sunset + method.ishaAngle / 60 * night;
      if (isha.isNaN || isha > ishaLimit) {
        isha = ishaLimit;
      }
    }

    final shift = longitude / 15;
    DateTime at(double hours) => day.add(Duration(seconds: ((hours - shift) * 3600).round()));
    return PrayerDay(fajr: at(fajr), sunrise: at(sunrise), dhuhr: at(dhuhr), asr: at(asrTime), maghrib: at(sunset), isha: at(isha));
  }

  double _midDay(double jd, double hours) {
    final (_, equation) = _sun(jd + hours / 24);
    return _fixHour(12 - equation);
  }

  double _sunAngleTime(double jd, double angle, double hours, {required bool before}) {
    final (declination, _) = _sun(jd + hours / 24);
    final noon = _midDay(jd, hours);
    final cosine = (-_sin(angle) - _sin(declination) * _sin(latitude)) / (_cos(declination) * _cos(latitude));
    if (cosine < -1 || cosine > 1) {
      return double.nan;
    }
    final offset = _acos(cosine) / 15;
    return noon + (before ? -offset : offset);
  }

  double _asrTime(double jd, int factor, double hours) {
    final (declination, _) = _sun(jd + hours / 24);
    final angle = -_acot(factor + _tan((latitude - declination).abs()));
    return _sunAngleTime(jd, angle, hours, before: false);
  }

  /// The sun's declination and the equation of time (in hours) for a Julian day.
  static (double, double) _sun(double jd) {
    final d = jd - 2451545.0;
    final g = _fixAngle(357.529 + 0.98560028 * d);
    final q = _fixAngle(280.459 + 0.98564736 * d);
    final l = _fixAngle(q + 1.915 * _sin(g) + 0.020 * _sin(2 * g));
    final e = 23.439 - 0.00000036 * d;
    final rightAscension = _fixHour(_atan2(_cos(e) * _sin(l), _cos(l)) / 15);
    final declination = _asin(_sin(e) * _sin(l));
    return (declination, q / 15 - rightAscension);
  }

  static double _julian(int year, int month, int day) {
    if (month <= 2) {
      year -= 1;
      month += 12;
    }
    final a = (year / 100).floor();
    final b = 2 - a + (a / 4).floor();
    return (365.25 * (year + 4716)).floor() + (30.6001 * (month + 1)).floor() + day + b - 1524.5;
  }

  static double _radians(double degrees) => degrees * math.pi / 180;
  static double _degrees(double radians) => radians * 180 / math.pi;
  static double _sin(double degrees) => math.sin(_radians(degrees));
  static double _cos(double degrees) => math.cos(_radians(degrees));
  static double _tan(double degrees) => math.tan(_radians(degrees));
  static double _asin(double value) => _degrees(math.asin(value));
  static double _acos(double value) => _degrees(math.acos(value));
  static double _atan2(double y, double x) => _degrees(math.atan2(y, x));
  static double _acot(double value) => _degrees(math.atan(1 / value));
  static double _fixAngle(double value) => value - 360 * (value / 360).floor();
  static double _fixHour(double value) => value - 24 * (value / 24).floor();
}
