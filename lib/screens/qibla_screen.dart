import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/layout.dart';
import '../core/qibla.dart';
import '../core/scope.dart';
import '../core/strings.dart';
import '../theme.dart';
import '../widgets/ui.dart';
import 'reminders_screen.dart';

/// Points to the Kaaba from the reader's city, using the phone's compass.
class QiblaScreen extends StatefulWidget {
  const QiblaScreen({super.key});

  @override
  State<QiblaScreen> createState() => _QiblaScreenState();
}

class _QiblaScreenState extends State<QiblaScreen> {
  StreamSubscription<HeadingReading>? _sub;
  HeadingReading? _reading;
  bool _noCompass = false;
  bool _aligned = false;
  String? _listeningFor;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _listen();
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }

  void _listen() {
    final city = AppScope.read(context).reminders.city;
    if (city == null || city.id == _listeningFor) {
      return;
    }
    _listeningFor = city.id;
    unawaited(_sub?.cancel());
    _sub = Compass.readings(city.latitude, city.longitude).listen(
      (reading) {
        if (!mounted) {
          return;
        }
        final qibla = qiblaBearing(city.latitude, city.longitude);
        final aligned = _difference(qibla, reading.trueHeading).abs() <= 3;
        if (aligned && !_aligned) {
          HapticFeedback.mediumImpact();
        }
        setState(() {
          _reading = reading;
          _aligned = aligned;
        });
      },
      onError: (Object _) {
        if (mounted) {
          setState(() => _noCompass = true);
        }
      },
    );
  }

  /// Signed angle from one bearing to another, between -180 and 180.
  static double _difference(double target, double heading) => ((target - heading + 540) % 360) - 180;

  String _compassPoint(BuildContext context, double bearing) {
    const points = ['north', 'ne', 'e', 'se', 's', 'sw', 'w', 'nw'];
    return context.t('dir_${points[((bearing + 22.5) % 360 ~/ 45)]}');
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final city = services.reminders.city;
    _listen();
    final qibla = city == null ? null : qiblaBearing(city.latitude, city.longitude);
    final reading = _reading;
    final turn = qibla == null || reading == null ? null : _difference(qibla, reading.trueHeading);
    final dial = math.min(MediaQuery.sizeOf(context).width - 48, 300.0);
    return Scaffold(
      body: PatternBackground(
        child: SafeArea(
          child: ListView(
            padding: Layout.page(context, top: 8, bottom: 28),
            children: [
              Row(children: [RoundButton(icon: Icons.arrow_back_rounded, label: context.t('back'), onTap: () => Navigator.of(context).maybePop())]),
              const SizedBox(height: 14),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: DisplayTitle(context.t('qibla_a'), second: context.t('qibla_b'), size: 30)),
              const SizedBox(height: 14),
              if (city == null || qibla == null)
                Panel(
                  child: Column(
                    children: [
                      Text(context.t('qibla_need_city'), textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      BusyButton(label: context.t('choose_city'), expand: false, onPressed: () => pickCity(context)),
                    ],
                  ),
                )
              else ...[
                Panel(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
                  child: Column(
                    children: [
                      SizedBox(
                        width: dial,
                        height: dial,
                        child: CustomPaint(
                          painter: _DialPainter(
                            heading: reading?.trueHeading ?? 0,
                            qibla: qibla,
                            live: reading != null,
                            aligned: _aligned,
                            north: context.t('dir_n'),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _noCompass
                            ? context.t('qibla_no_compass')
                            : turn == null
                            ? context.t('qibla_waiting')
                            : _aligned
                            ? context.t('qibla_facing')
                            : context.t(turn > 0 ? 'qibla_turn_right' : 'qibla_turn_left', {'deg': turn.abs().round()}),
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: _aligned ? Palette.green : Palette.ink),
                      ),
                      if (reading != null && !reading.reliable) ...[
                        const SizedBox(height: 8),
                        Text(context.t('qibla_calibrate'), textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: Palette.bad)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Fact(label: context.t('city'), value: city.name, onTap: () => pickCity(context)),
                      _Fact(label: context.t('qibla_bearing'), value: context.t('qibla_bearing_value', {'deg': qibla.round(), 'point': _compassPoint(context, qibla)})),
                      _Fact(label: context.t('qibla_distance'), value: context.t('km', {'n': distanceToKaaba(city.latitude, city.longitude).round().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',')})),
                      const SizedBox(height: 10),
                      Text(context.t('qibla_tips'), style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value, this.onTap});

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(label, style: const TextStyle(fontSize: 14)),
      trailing: Text(value, style: TextStyle(fontSize: 13.5, color: onTap == null ? Palette.ink : Palette.green, fontWeight: FontWeight.w600)),
      onTap: onTap,
    );
  }
}

/// A compass card that turns with the phone: north marked at the top of the card, the Kaaba marker at the Qibla bearing.
class _DialPainter extends CustomPainter {
  _DialPainter({required this.heading, required this.qibla, required this.live, required this.aligned, required this.north});

  final double heading;
  final double qibla;
  final bool live;
  final bool aligned;
  final String north;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final radius = size.width / 2;
    final accent = aligned ? Palette.green : Palette.ink;

    canvas.drawCircle(centre, radius, Paint()..color = Palette.canvas);
    canvas.drawCircle(centre, radius - 1, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = aligned ? Palette.green : Palette.line);

    // The card turns opposite to the phone, so north on the card keeps pointing north.
    canvas.save();
    canvas.translate(centre.dx, centre.dy);
    canvas.rotate(-heading * math.pi / 180);
    for (var degree = 0; degree < 360; degree += 10) {
      final major = degree % 90 == 0;
      final outer = Offset(0, -radius + 8);
      final inner = Offset(0, -radius + (major ? 22 : 15));
      canvas.save();
      canvas.rotate(degree * math.pi / 180);
      canvas.drawLine(outer, inner, Paint()
        ..color = major ? Palette.ink : Palette.quiet
        ..strokeWidth = major ? 2 : 1);
      canvas.restore();
    }
    _label(canvas, north, Offset(0, -radius + 36), Palette.bad, 14);

    // Kaaba marker on the rim at the Qibla bearing.
    canvas.save();
    canvas.rotate(qibla * math.pi / 180);
    final marker = Offset(0, -radius + 44);
    final rect = Rect.fromCenter(center: marker, width: 22, height: 22);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(3)), Paint()..color = Palette.ink);
    canvas.drawRect(Rect.fromLTWH(rect.left, rect.top + 6, rect.width, 3), Paint()..color = Palette.gold);
    canvas.drawLine(Offset(0, -radius * 0.5), Offset(0, -radius + 58), Paint()
      ..color = accent
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round);
    canvas.restore();
    canvas.restore();

    // A fixed pointer at the top shows where the phone is facing.
    final pointer = Path()
      ..moveTo(centre.dx, centre.dy - radius - 2)
      ..lineTo(centre.dx - 8, centre.dy - radius + 12)
      ..lineTo(centre.dx + 8, centre.dy - radius + 12)
      ..close();
    canvas.drawPath(pointer, Paint()..color = live ? accent : Palette.quiet);
    canvas.drawCircle(centre, 6, Paint()..color = accent);
  }

  void _label(Canvas canvas, String text, Offset at, Color colour, double size) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: TextStyle(color: colour, fontSize: size, fontWeight: FontWeight.w700)),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, at - Offset(painter.width / 2, painter.height / 2));
  }

  @override
  bool shouldRepaint(_DialPainter old) => old.heading != heading || old.qibla != qibla || old.live != live || old.aligned != aligned || old.north != north;
}
