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
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
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
    importance: Importance.high, // Aumentamos la importancia para que sea más difícil de matar
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
  if (service is AndroidServiceInstance) {
    // Esto debe ser lo primero que se ejecute
    service.setAsForegroundService();
  }

  DartPluginRegistrant.ensureInitialized();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  // Definición de la notificación (Mantenida igual pero movida arriba)
  void updateForegroundNotification({String? title, String? content}) {
    flutterLocalNotificationsPlugin.show(
      _notificationId,
      title ?? 'Hermodr (Activo)',
      content ?? 'Buscando mensajes...',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'Hermodr Background Service',
          priority: Priority.high,
          importance: Importance.high,
          ongoing: true,
          autoCancel: false,
          showWhen: false,
          onlyAlertOnce: true,
          icon: '@mipmap/ic_launcher',
          actions: [
            AndroidNotificationAction(
              'stop_service_action',
              'Detener proceso',
              showsUserInterface: false,
            ),
          ],
        ),
      ),
    );
  }

  // 1. Inicializar notificaciones y mostrar la notificación persistente INMEDIATAMENTE.
  // Esto soluciona el error "ForegroundServiceDidNotStartInTimeException".
  await flutterLocalNotificationsPlugin.initialize( 
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
    onDidReceiveNotificationResponse: (details) {
      if (details.actionId == 'stop_service_action') {
        service.stopSelf();
      }
    }, 
  );

  updateForegroundNotification();

  // 2. Inicializar Firebase ahora que ya estamos seguros en foreground.
  try {
    await Firebase.initializeApp(
      options: firebase_options.DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    print("Error inicializando Firebase en Background: $e");
  }

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

          try {
            // Obtenemos el nombre del remitente
            var senderDoc = await FirebaseFirestore.instance.collection('users').doc(senderUID).get();
            String senderName = senderDoc.data()?['Name'] ?? "Alguien";

            // 1. Lógica de Hardware (Solo si no es 'mobile')
            if (bandKey.isNotEmpty && bandKey != 'mobile') {
              var userDoc = await FirebaseFirestore.instance.collection('users').doc(myUID).get();
              String? targetMac = userDoc.data()?[bandKey]?['MAC'];
              if (targetMac != null && targetMac.isNotEmpty) {
                _relayToBandFromBackground(targetMac, color); // Disparamos sin esperar (async)
              }
            }

            // 2. Lógica de Notificación (Siempre, tanto para móvil como pulsera)
            service.invoke('on_greeting', {'senderName': senderName});
            await showGreetingAlert(senderName);
          } catch (e) {
            print("Error procesando saludo en background: $e");
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

  // Aumentamos el intervalo a 30 segundos para reducir el consumo y evitar que el SO lo mate por uso excesivo
  Timer.periodic(const Duration(seconds: 30), (timer) async {
    if (service is AndroidServiceInstance) {
      if (!(await service.isForegroundService())) {
        greetingSubscription?.cancel();
        timer.cancel();
        return;
      }
    }
    // Mantenemos la notificación visible y actualizada
    updateForegroundNotification();

    // Intentamos mantener la conexión SOLO para las pulseras que envían mensajes (tienen Destiny_LinkID)
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

    Set<String> activeMacsInFirestore = {};

    for (String key in bandKeys) {
      String? mac = userData[key]['MAC'];
      String? destinyLink = userData[key]['Destiny_LinkID'];

      if (mac != null && mac.isNotEmpty && destinyLink != null && destinyLink.isNotEmpty) {
        activeMacsInFirestore.add(mac.toLowerCase());
        if (!_activeSubscriptions.containsKey(mac)) {
          _listenToBandButton(mac, destinyLink, myUID);
        }
      }
    }

    // Limpieza de suscripciones y conexiones que ya no existen en Firestore
    final activeMacs = _activeSubscriptions.keys.toList();
    for (var mac in activeMacs) {
      if (!activeMacsInFirestore.contains(mac.toLowerCase())) {
        print("Cerrando conexión BLE para pulsera eliminada o desvinculada: $mac");
        _activeSubscriptions.remove(mac)?.cancel();

        // Intentar desconectar físicamente el dispositivo para ahorrar batería
        for (var device in FlutterBluePlus.connectedDevices) {
          if (device.remoteId.str.toLowerCase() == mac.toLowerCase()) {
            device.disconnect();
          }
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
    // 1. Verificar si ya está conectado para evitar escaneos innecesarios
    List<BluetoothDevice> connected = FlutterBluePlus.connectedDevices;
    for (var d in connected) {
      if (d.remoteId.str.toLowerCase() == mac.toLowerCase()) {
        device = d;
        break;
      }
    }

    // 2. Si no está conectado, buscarlo brevemente
    if (device == null) {
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 2));
      
      // Esperamos resultados de forma síncrona para no bloquear el flujo
      await for (var results in FlutterBluePlus.scanResults.timeout(const Duration(seconds: 2), onTimeout: (sink) => sink.close())) {
      for (var r in results) {
        if (r.device.remoteId.str.toLowerCase() == mac.toLowerCase()) {
          device = r.device;
          break;
        }
      }
      if (device != null) break;
    }
    await FlutterBluePlus.stopScan();
    }

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

    // 1. ¿Ya estamos conectados por la escucha del botón?
    List<BluetoothDevice> connected = FlutterBluePlus.connectedDevices;
    for (var d in connected) {
      if (d.remoteId.str.toLowerCase() == mac.toLowerCase()) {
        device = d;
        break;
      }
    }

    // 2. Si no, escaneo rápido
    if (device == null) {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 3));
      await for (var results in FlutterBluePlus.scanResults.timeout(const Duration(seconds: 3), onTimeout: (sink) => sink.close())) {
      for (var r in results) {
        if (r.device.remoteId.str.toLowerCase() == mac.toLowerCase()) {
          device = r.device;
          break;
        }
      }
        if (device != null) {
          await FlutterBluePlus.stopScan();
          break;
        }
      }
    }

    if (device != null) {
      if (!device.isConnected) {
        await device.connect(timeout: const Duration(seconds: 4));
      }
      
      List<BluetoothService> services = await device.discoverServices();
      for (var s in services) {
        if (s.uuid.toString().toLowerCase() == SERVICE_UUID.toLowerCase()) {
          for (var c in s.characteristics) {
            if (c.uuid.toString().toLowerCase() == CHARACTERISTIC_UUID.toLowerCase()) {
              await c.write(utf8.encode(color));
            }
          }
        }
      }
      // IMPORTANTE: Solo desconectar si NO estamos escuchando el botón (Destiny_LinkID vacío)
      // Pero para simplificar el prototipo, mejor no desconectar abruptamente.
    }
  } catch (e) {
    print("Background BLE Error: $e");
  }
}