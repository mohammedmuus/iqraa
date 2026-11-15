import 'prayer_times.dart';

/// A place readers can pick for prayer times, with the calculation method most used there.
class City {
  const City(this.id, this.name, this.country, this.latitude, this.longitude, [this.method = PrayerMethod.mwl]);

  final String id;
  final String name;
  final String country;
  final double latitude;
  final double longitude;
  final PrayerMethod method;

  static City? byId(String? id) {
    for (final city in all) {
      if (city.id == id) {
        return city;
      }
    }
    return null;
  }

  static const all = [
    City('dar-es-salaam', 'Dar es Salaam', 'Tanzania', -6.7924, 39.2083),
    City('zanzibar', 'Zanzibar', 'Tanzania', -6.1659, 39.2026),
    City('pemba', 'Chake Chake, Pemba', 'Tanzania', -5.2459, 39.7666),
    City('dodoma', 'Dodoma', 'Tanzania', -6.1630, 35.7516),
    City('arusha', 'Arusha', 'Tanzania', -3.3869, 36.6830),
    City('moshi', 'Moshi', 'Tanzania', -3.3348, 37.3404),
    City('tanga', 'Tanga', 'Tanzania', -5.0689, 39.0988),
    City('morogoro', 'Morogoro', 'Tanzania', -6.8278, 37.6591),
    City('mwanza', 'Mwanza', 'Tanzania', -2.5164, 32.9175),
    City('tabora', 'Tabora', 'Tanzania', -5.0162, 32.8266),
    City('kigoma', 'Kigoma', 'Tanzania', -4.8769, 29.6267),
    City('singida', 'Singida', 'Tanzania', -4.8163, 34.7436),
    City('iringa', 'Iringa', 'Tanzania', -7.7700, 35.6900),
    City('mbeya', 'Mbeya', 'Tanzania', -8.9094, 33.4608),
    City('lindi', 'Lindi', 'Tanzania', -9.9971, 39.7165),
    City('mtwara', 'Mtwara', 'Tanzania', -10.2736, 40.1828),
    City('nairobi', 'Nairobi', 'Kenya', -1.2921, 36.8219),
    City('mombasa', 'Mombasa', 'Kenya', -4.0435, 39.6682),
    City('lamu', 'Lamu', 'Kenya', -2.2717, 40.9020),
    City('kampala', 'Kampala', 'Uganda', 0.3476, 32.5825),
    City('kigali', 'Kigali', 'Rwanda', -1.9441, 30.0619),
    City('bujumbura', 'Bujumbura', 'Burundi', -3.3614, 29.3599),
    City('moroni', 'Moroni', 'Comoros', -11.7172, 43.2473),
    City('mogadishu', 'Mogadishu', 'Somalia', 2.0469, 45.3182),
    City('addis-ababa', 'Addis Ababa', 'Ethiopia', 9.0300, 38.7400),
    City('maputo', 'Maputo', 'Mozambique', -25.9692, 32.5732),
    City('lilongwe', 'Lilongwe', 'Malawi', -13.9626, 33.7741),
    City('lusaka', 'Lusaka', 'Zambia', -15.3875, 28.3228),
    City('johannesburg', 'Johannesburg', 'South Africa', -26.2041, 28.0473),
    City('cape-town', 'Cape Town', 'South Africa', -33.9249, 18.4241),
    City('lagos', 'Lagos', 'Nigeria', 6.5244, 3.3792),
    City('cairo', 'Cairo', 'Egypt', 30.0444, 31.2357, PrayerMethod.egypt),
    City('makkah', 'Makkah', 'Saudi Arabia', 21.3891, 39.8579, PrayerMethod.makkah),
    City('madinah', 'Madinah', 'Saudi Arabia', 24.5247, 39.5692, PrayerMethod.makkah),
    City('riyadh', 'Riyadh', 'Saudi Arabia', 24.7136, 46.6753, PrayerMethod.makkah),
    City('jeddah', 'Jeddah', 'Saudi Arabia', 21.4858, 39.1925, PrayerMethod.makkah),
    City('muscat', 'Muscat', 'Oman', 23.5880, 58.3829),
    City('dubai', 'Dubai', 'United Arab Emirates', 25.2048, 55.2708),
    City('doha', 'Doha', 'Qatar', 25.2854, 51.5310),
    City('istanbul', 'Istanbul', 'Turkey', 41.0082, 28.9784),
    City('karachi', 'Karachi', 'Pakistan', 24.8607, 67.0011, PrayerMethod.karachi),
    City('mumbai', 'Mumbai', 'India', 19.0760, 72.8777, PrayerMethod.karachi),
    City('kuala-lumpur', 'Kuala Lumpur', 'Malaysia', 3.1390, 101.6869),
    City('jakarta', 'Jakarta', 'Indonesia', -6.2088, 106.8456),
    City('london', 'London', 'United Kingdom', 51.5074, -0.1278),
    City('berlin', 'Berlin', 'Germany', 52.5200, 13.4050),
    City('stockholm', 'Stockholm', 'Sweden', 59.3293, 18.0686),
    City('new-york', 'New York', 'United States', 40.7128, -74.0060, PrayerMethod.isna),
    City('toronto', 'Toronto', 'Canada', 43.6532, -79.3832, PrayerMethod.isna),
  ];
}
