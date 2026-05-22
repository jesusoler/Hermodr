import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../firebase_options.dart' as firebase_options;

// Identificadores constantes
const String _channelId = 'hermodr_foreground';
const String _alertChannelId = 'greetings_channel'; // Nuevo canal para alertas
const int _notificationId = 888;
const String SERVICE_UUID = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
const String CHARACTERISTIC_UUID = "beb5483e-36e1-4688-b7f5-ea07361b26a8";

// Mapa para rastrear conexiones activas y evitar duplicados
final Map<String, StreamSubscription> _activeSubscriptions = {};

Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    _channelId,
    'Hermodr Background Service',
    description: 'Mantiene la escucha de saludos activa para las pulseras.',
    importance: Importance.low,
  );

  const AndroidNotificationChannel alertChannel = AndroidNotificationChannel(
    _alertChannelId,
    'Saludos recibidos',
    description: 'Notificaciones cuando recibes un saludo de un amigo.',
    importance: Importance.max, // Máxima importancia para que aparezca el popup
    playSound: true,
    enableVibration: true,
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  if (Platform.isAndroid) {
    final androidPlugin = flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(channel);
    await androidPlugin?.createNotificationChannel(alertChannel); // Registramos el nuevo canal
  }

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: true,
      isForegroundMode: true,
      notificationChannelId: _channelId,
      initialNotificationTitle: 'Hermodr',
      initialNotificationContent: 'Buscando mensajes...',
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

  // Inicializar Firebase dentro del Isolate del servicio
  await Firebase.initializeApp(
    options: firebase_options.DefaultFirebaseOptions.currentPlatform,
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  // Función centralizada para detener el servicio
  Future<void> stopServiceInternal() async {
    print("Background Service: Deteniendo proceso y cancelando notificaciones.");
    await flutterLocalNotificationsPlugin.cancel(_notificationId);
    service.stopSelf();
  }

  // Escuchamos el evento de detener el servicio que viene de la acción de la notificación
  service.on('stop_service_action').listen((_) {
    stopServiceInternal();
  });

  await flutterLocalNotificationsPlugin.initialize( 
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
    onDidReceiveNotificationResponse: (details) {
      if (details.actionId == 'stop_service_action') {
        stopServiceInternal();
      }
    }, 
  );

  void updateForegroundNotification({String? title, String? content}) {
    // En lugar de service.setNotificationInfo, usamos el plugin directamente
    // para poder incluir el botón de acción (AndroidNotificationAction)
    flutterLocalNotificationsPlugin.show(
      _notificationId,
      title ?? 'Hermodr (Activo)',
      content ?? 'Buscando mensajes...',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'Hermodr Background Service',
          ongoing: true, // No se puede quitar deslizando
          autoCancel: false, // No se quita al pulsarla
          showWhen: false,
          onlyAlertOnce: true, // Evita sonidos/vibración en cada actualización
          icon: '@mipmap/ic_launcher',
          actions: [
            AndroidNotificationAction(
              'stop_service_action',
              'Detener proceso',
              showsUserInterface: false, // Importante: No abre la app
            ),
          ],
        ),
      ),
    );
  }

  // Función para mostrar la notificación emergente de saludo
  Future<void> showGreetingAlert(String senderName) async {
    const androidDetails = AndroidNotificationDetails(
      _alertChannelId,
      'Saludos recibidos',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
      icon: '@mipmap/ic_launcher',
    );

    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(),
    );

    // Usamos un ID basado en el tiempo para que no se sobreescriban si llegan varias
    await flutterLocalNotificationsPlugin.show(
      DateTime.now().millisecond,
      '¡Hermodr!',
      'Has recibido un saludo de $senderName',
      notificationDetails,
    );
  }

  updateForegroundNotification(); // Establece el contenido inicial de la notificación

  // --- LÓGICA DE ESCUCHA DE FIRESTORE ---
  final String? myUID = FirebaseAuth.instance.currentUser?.uid;
  StreamSubscription? greetingSubscription;

  if (myUID != null) {
    greetingSubscription = FirebaseFirestore.instance
        .collection('links')
        .where('Users', arrayContains: myUID)
        .snapshots()
        .listen((snapshot) async {
      for (var doc in snapshot.docs) {
        var data = doc.data();
        var message = data['Message'];
        if (message != null && message['Sent'] == true && message['Last_Sent'] != myUID) {
          
          String senderUID = message['Last_Sent'];
          var myConfig = data['Config_$myUID'] ?? {};
          String color = myConfig['Color'] ?? "Blanco";
          String bandKey = myConfig['BandKey'] ?? "";

          // Obtenemos el nombre del remitente para la notificación
          var senderDoc = await FirebaseFirestore.instance.collection('users').doc(senderUID).get();
          String senderName = senderDoc.data()?['Name'] ?? "Alguien";

          // Si es para móvil o pulsera, siempre lanzamos la notificación visual en el teléfono
          if (bandKey.isNotEmpty && bandKey != 'mobile') {
            updateForegroundNotification(content: "¡Saludo recibido! Conectando a pulsera...");
            
            // Obtener MAC del usuario
            var userDoc = await FirebaseFirestore.instance.collection('users').doc(myUID).get();
            String? targetMac = userDoc.data()?[bandKey]?['MAC'];

            if (targetMac != null && targetMac.isNotEmpty) {
              await _relayToBandFromBackground(targetMac, color);
            }
          } else if (bandKey == 'mobile') {
            print("Background Service: Notificación solo móvil detectada.");
          }
          
          await showGreetingAlert(senderName); // Disparamos la alerta visual/sonora

          // Marcar como procesado en Firestore
          await FirebaseFirestore.instance.collection('links').doc(doc.id).update({
            'Message.Sent': false
          });
          updateForegroundNotification();
        }
      }
    });
  }

  Timer.periodic(const Duration(seconds: 10), (timer) async {
    if (service is AndroidServiceInstance) {
      if (!(await service.isForegroundService())) {
        greetingSubscription?.cancel();
        timer.cancel();
        return;
      }
    }
    // Mantenemos la notificación visible y actualizada
    updateForegroundNotification();

    // Intentamos conectar y escuchar las pulseras registradas que no estén activas
    if (myUID != null) {
      _monitorBandsForInput(myUID);
    }
  });
}

/// Busca las pulseras del usuario y establece una escucha para el botón físico
Future<void> _monitorBandsForInput(String myUID) async {
  try {
    var userDoc = await FirebaseFirestore.instance.collection('users').doc(myUID).get();
    if (!userDoc.exists) return;

    var userData = userDoc.data() as Map<String, dynamic>;
    var bandKeys = userData.keys.where((k) => k.startsWith('Band')).toList();

    for (String key in bandKeys) {
      String? mac = userData[key]['MAC'];
      String? destinyLink = userData[key]['Destiny_LinkID'];

      if (mac != null && mac.isNotEmpty && destinyLink != null && destinyLink.isNotEmpty) {
        if (!_activeSubscriptions.containsKey(mac)) {
          _listenToBandButton(mac, destinyLink, myUID);
        }
      }
    }
  } catch (e) {
    print("Error monitoreando pulseras: $e");
  }
}

/// Conecta a la pulsera y se suscribe a las notificaciones del botón
Future<void> _listenToBandButton(String mac, String destinyLink, String myUID) async {
  BluetoothDevice? device;
  try {
    // Buscar dispositivo
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 2));
    await for (var results in FlutterBluePlus.scanResults) {
      for (var r in results) {
        if (r.device.remoteId.str.toLowerCase() == mac.toLowerCase()) {
          device = r.device;
          break;
        }
      }
      if (device != null) break;
    }
    await FlutterBluePlus.stopScan();

    if (device != null) {
      await device.connect(autoConnect: true);
      List<BluetoothService> services = await device.discoverServices();
      
      for (var s in services) {
        if (s.uuid.toString().toLowerCase() == SERVICE_UUID.toLowerCase()) {
          for (var c in s.characteristics) {
            if (c.uuid.toString().toLowerCase() == CHARACTERISTIC_UUID.toLowerCase()) {
              // Suscribirse a las notificaciones (El botón de la pulsera debe activar esta característica)
              await c.setNotifyValue(true);
              
              final sub = c.onValueReceived.listen((value) async {
                print("Input recibido de pulsera $mac. Enviando a $destinyLink");
                // Lógica de envío a Firestore
                await FirebaseFirestore.instance.collection('links').doc(destinyLink).update({
                  'Message.Last_Sent': myUID,
                  'Message.Last_Second': FieldValue.serverTimestamp(),
                  'Message.Sent': true,
                });
              });

              _activeSubscriptions[mac] = sub;
              device.connectionState.listen((state) {
                if (state == BluetoothConnectionState.disconnected) {
                  _activeSubscriptions.remove(mac)?.cancel();
                }
              });
            }
          }
        }
      }
    }
  } catch (e) {
    print("Error estableciendo escucha en $mac: $e");
  }
}

Future<void> _relayToBandFromBackground(String mac, String color) async {
  try {
    BluetoothDevice? device;
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 4));
    await for (var results in FlutterBluePlus.scanResults) {
      for (var r in results) {
        if (r.device.remoteId.str.toLowerCase() == mac.toLowerCase()) {
          device = r.device;
          await FlutterBluePlus.stopScan();
          break;
        }
      }
      if (device != null) break;
    }

    if (device != null) {
      await device.connect();
      var services = await device.discoverServices();
      for (var s in services) {
        if (s.uuid.toString().toLowerCase() == SERVICE_UUID.toLowerCase()) {
          for (var c in s.characteristics) {
            if (c.uuid.toString().toLowerCase() == CHARACTERISTIC_UUID.toLowerCase()) {
              await c.write(utf8.encode(color));
            }
          }
        }
      }
      await device.disconnect();
    }
  } catch (e) {
    print("Background BLE Error: $e");
  }
}