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

  // Escuchamos el evento de detener el servicio que viene de la acción de la notificación
  service.on('stop_service_action').listen((_) async {
    print("Background Service: Recibida acción para detener el servicio.");
    await flutterLocalNotificationsPlugin.cancel(_notificationId); // Borra la notificación
    service.stopSelf();
  });

  await flutterLocalNotificationsPlugin.initialize( 
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
    onDidReceiveNotificationResponse: (details) {
      if (details.actionId == 'stop_service_action') {
        // Reenviamos el evento al listener de arriba
        service.invoke('stop_service_action');
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
          showWhen: false,
          onlyAlertOnce: true, // Evita sonidos/vibración en cada actualización
          icon: '@mipmap/ic_launcher',
          actions: [
            AndroidNotificationAction(
              'stop_service_action',
              'Detener proceso',
            ),
          ],
        ),
      ),
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

          if (bandKey.isNotEmpty && bandKey != 'mobile') {
            updateForegroundNotification(content: "¡Saludo recibido! Conectando a pulsera...");
            
            // Obtener MAC del usuario
            var userDoc = await FirebaseFirestore.instance.collection('users').doc(myUID).get();
            String? targetMac = userDoc.data()?[bandKey]?['MAC'];

            if (targetMac != null && targetMac.isNotEmpty) {
              await _relayToBandFromBackground(targetMac, color);
            }
          }
          
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