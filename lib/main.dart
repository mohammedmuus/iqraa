import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:workmanager/workmanager.dart';

import 'app.dart';
import 'core/rivals.dart';
import 'core/scope.dart';
import 'core/shield.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await JustAudioBackground.init(
    androidNotificationChannelId: 'tz.or.iqraa.narration',
    androidNotificationChannelName: 'Narration',
    androidNotificationOngoing: true,
  );
  final services = AppServices();
  await services.api.init();
  await services.session.load();
  await services.prefs.load();
  Palette.dark = services.prefs.wantsDark(PlatformDispatcher.instance.platformBrightness);
  await services.downloads.load();
  await services.narration.loadLast();
  await services.dhikr.load();
  await services.reminders.load();
  await services.readingLog.load();
  await services.rivals.load();
  if (Platform.isAndroid || Platform.isIOS) {
    await Workmanager().initialize(rivalsDispatcher);
  }
  unawaited(Shield.start(services.session));
  runApp(IqraaApp(services: services));
}
