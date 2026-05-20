import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// Identificadores constantes
const String _channelId = 'hermodr_foreground';
const int _notificationId = 888;

Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    _channelId,
    'Hermodr Background Service',
    description: 'Mantiene la escucha de saludos activa para las pulseras.',
    importance: Importance.low,
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  if (Platform.isAndroid) {
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: true,
      isForegroundMode: true,
      notificationChannelId: _channelId,
      initialNotificationTitle: 'Hermodr',
      initialNotificationContent: 'Buscando saludos...',
      foregroundServiceNotificationId: _notificationId,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: true,
      onForeground: onStart,
      onBackground: (service) => true,
    ),
  );
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  // Escuchamos el evento de detener el servicio (desde el botón de la notificación)
  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  // Función para actualizar la notificación con el botón de acción
  void updateNotification() {
    flutterLocalNotificationsPlugin.show(
      _notificationId,
      'Hermodr',
      'Buscando saludos...',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'Hermodr Background Service',
          ongoing: true, // No se puede descartar deslizando
          autoCancel: false,
          showWhen: false,
          icon: '@mipmap/ic_launcher',
          actions: <AndroidNotificationAction>[
            AndroidNotificationAction(
              'stop_action',
              'Apagar Servicio',
              showsUserInterface: false,
              cancelNotification: true,
            ),
          ],
        ),
      ),
    );
  }

  // Inicializar notificaciones dentro del proceso del servicio
  await flutterLocalNotificationsPlugin.initialize(
    const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
    onDidReceiveNotificationResponse: (details) {
      if (details.actionId == 'stop_action') {
        service.invoke('stopService');
      }
    },
  );

  updateNotification();

  Timer.periodic(const Duration(seconds: 10), (timer) async {
    if (service is AndroidServiceInstance) {
      if (!(await service.isForegroundService())) {
        timer.cancel();
        return;
      }
    }

    // TODO: Implementar aquí la escucha de Firestore (Streams)
    // para detectar cuando un documento de 'links' tenga Message.Sent == true.
    print("Background Service: Buscando saludos en Firestore...");

    // Mantenemos la notificación visible y actualizada
    updateNotification();
  });
}