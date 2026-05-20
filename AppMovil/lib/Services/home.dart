import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'friendpage.dart';
import 'profile.dart'; // Import the new profile page
import 'addpage.dart';

// UUIDs para la comunicación con el Hardware (Ajustar según tu Arduino)
const String SERVICE_UUID = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
const String CHARACTERISTIC_UUID = "beb5483e-36e1-4688-b7f5-ea07361b26a8";

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final String myUID = FirebaseAuth.instance.currentUser!.uid;
  int _selectedIndex = 0;
  StreamSubscription<QuerySnapshot>? _greetingSubscription;

  @override
  void initState() {
    super.initState();
    _setupNotifications();
    _listenForGreetings();
  }

  void _setupNotifications() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;

    // 1. Solicitar permisos (especialmente importante en iOS y Android 13+)
    NotificationSettings settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      // 2. Obtener el token único del dispositivo
      String? token = await messaging.getToken();
      if (token != null) {
        // 3. Guardarlo en el perfil del usuario en Firestore
        await FirebaseFirestore.instance.collection('users').doc(myUID).update({'Token_FCM': token});
      }
    }
  }

  void _listenForGreetings() {
    _greetingSubscription = FirebaseFirestore.instance
        .collection('links')
        .where('Users', arrayContains: myUID)
        .snapshots()
        .listen((snapshot) {
      for (var doc in snapshot.docs) {
        var data = doc.data() as Map<String, dynamic>;
        var message = data['Message'];
        if (message != null && message['Sent'] == true && message['Last_Sent'] != myUID) {
          _getGreeting(context, message['Last_Sent'], doc.id);
        }
      }
    });
  }

  void _sendGreeting(String docId) async {
    try {
      await FirebaseFirestore.instance.collection('links').doc(docId).update({
        'Message.Last_Sent': myUID,
        'Message.Last_Second': FieldValue.serverTimestamp(),
        'Message.Sent': true,
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("¡Envío realizado!")),
      );
    } catch (e) {
      print("Error al enviar: $e");
    }
  }

  void _getGreeting(BuildContext context, String senderUID, String docId) async {
    try {
      // Obtenemos los datos del vínculo y del remitente
      var linkDoc = await FirebaseFirestore.instance.collection('links').doc(docId).get();
      var senderDoc = await FirebaseFirestore.instance.collection('users').doc(senderUID).get();
      
      if (!mounted) return;

      var linkData = linkDoc.data() as Map<String, dynamic>;
      var myConfig = linkData['Config_$myUID'] ?? {};
      String color = myConfig['Color'] ?? "Blanco";
      String bandKey = myConfig['BandKey'] ?? ""; // Aquí leemos qué pulsera debe vibrar
      String senderName = senderDoc.exists ? (senderDoc.data() as Map)['Name'] : "Alguien";

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("¡Has recibido un saludo de $senderName!"),
          backgroundColor: Colors.deepPurple,
        ),
      );

      // Si el destino es 'mobile', disparamos notificación de sistema. Si es una pulsera, BLE.
      if (bandKey == 'mobile') {
        _showLocalNotification(senderName);
      } else if (bandKey.isNotEmpty) {
        _relayToPhysicalBand(bandKey, color);
      }

      await FirebaseFirestore.instance.collection('links').doc(docId).update({
        'Message.Sent': false
      });
    } catch (e) {
      print("Error al procesar saludo: $e");
    }
  }

  // Función para mostrar una notificación estándar de Android/iOS
  Future<void> _showLocalNotification(String senderName) async {
    final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
    
    const androidDetails = AndroidNotificationDetails(
      'greetings_channel',
      'Saludos recibidos',
      channelDescription: 'Notificaciones cuando recibes un saludo de un amigo',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
    );

    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(),
    );

    await flutterLocalNotificationsPlugin.show(
      DateTime.now().millisecond, // ID único para no sobreescribir anteriores
      '¡Hermodr!',
      'Has recibido un saludo de $senderName',
      notificationDetails,
    );
  }

  Future<void> _relayToPhysicalBand(String bandKey, String colorName) async {
    try {
      // 1. Buscamos la MAC de esa pulsera en nuestro perfil
      var userDoc = await FirebaseFirestore.instance.collection('users').doc(myUID).get();
      var userData = userDoc.data() as Map<String, dynamic>;
      // Obtenemos la MAC (RemoteId) guardada en el perfil del usuario
      final String? targetMac = userData[bandKey]?['MAC'];

      if (targetMac == null || targetMac.isEmpty) {
        print("BLE Error: No hay MAC asociada a la pulsera seleccionada ($bandKey)");
        return;
      }

      print("BLE Relay: Iniciando búsqueda de MAC: $targetMac");

      BluetoothDevice? targetDevice;

      // 1. Comprobar si ya está conectado (más rápido)
      List<BluetoothDevice> connected = FlutterBluePlus.connectedDevices;
      for (var d in connected) {
        if (d.remoteId.str.toLowerCase() == targetMac.toLowerCase()) {
          targetDevice = d;
          break;
        }
      }

      // 2. Si no, escaneamos para encontrarla
      if (targetDevice == null) {
        await FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));
        await for (var results in FlutterBluePlus.scanResults) {
          for (ScanResult r in results) {
            if (r.device.remoteId.str.toLowerCase() == targetMac.toLowerCase()) {
              targetDevice = r.device;
              await FlutterBluePlus.stopScan();
              break;
            }
          }
          if (targetDevice != null) break;
        }
      }

      if (targetDevice != null) {
        // 3. Conectamos y enviamos el color al prototipo
        await targetDevice.connect(timeout: const Duration(seconds: 5));
        var services = await targetDevice.discoverServices();
        for (var s in services) {
          if (s.uuid.toString().toLowerCase() == SERVICE_UUID.toLowerCase()) {
            for (var c in s.characteristics) {
              if (c.uuid.toString().toLowerCase() == CHARACTERISTIC_UUID.toLowerCase()) {
                await c.write(utf8.encode(colorName));
                print("BLE Success: Datos enviados a $targetMac");
              }
            }
          }
        }
        // Desconectamos para liberar el dispositivo y ahorrar batería
        await targetDevice.disconnect();
      } else {
        print("BLE Error: No se encontró el dispositivo con MAC $targetMac");
      }
    } catch (e) {
      print("Error BLE: $e");
    }
  }

  @override
  void dispose() {
    _greetingSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> _pages = [
      BandsMenu(myUID: myUID),
      FriendPage(myUID: myUID, onSendGreeting: _sendGreeting),
      const AddPage(),
      const ProfilePage(), // Use the new ProfilePage
    ];

    return Scaffold(
      appBar: AppBar(title: const Text("Envíos")),
      body: Stack(
        children: [_pages[_selectedIndex]],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        selectedItemColor: Colors.deepPurpleAccent,
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: "Inicio"),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: "Amigos"),
          BottomNavigationBarItem(icon: Icon(Icons.person_add), label: "Añadir"),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: "Perfil"),
        ],
      ),
    );
  }
}

class BandsMenu extends StatelessWidget {
  final String myUID;
  const BandsMenu({super.key, required this.myUID});

  Future<String> _getFriendNameFromLink(String linkID) async {
    if (linkID.isEmpty || linkID == "Sin asignar") return "Sin asignar";
    try {
      DocumentSnapshot linkDoc = await FirebaseFirestore.instance.collection('links').doc(linkID).get();
      if (!linkDoc.exists) return "No encontrado";
      List<dynamic> users = linkDoc['Users'];
      String friendUID = users.firstWhere((uid) => uid != myUID);
      DocumentSnapshot userDoc = await FirebaseFirestore.instance.collection('users').doc(friendUID).get();
      return (userDoc.data() as Map<String, dynamic>)['Name'] ?? "Desconocido";
    } catch (e) { return "Error"; }
  }

  // --- DIÁLOGO PARA CAMBIAR NOMBRE ---
  void _editBandName(BuildContext context, String bandKey, String currentName) {
    TextEditingController nameController = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Renombrar Pulsera"),
        content: TextField(
          controller: nameController,
          autofocus: true,
          decoration: const InputDecoration(hintText: "Nombre de la pulsera"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancelar")),
          ElevatedButton(
            onPressed: () async {
              await FirebaseFirestore.instance.collection('users').doc(myUID).update({
                '$bandKey.Band_Name': nameController.text,
              });
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text("Guardar"),
          ),
        ],
      ),
    );
  }

  void _deleteBand(BuildContext context, String bandKey) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Eliminar Pulsera"),
        content: const Text("¿Estás seguro de que quieres eliminar esta pulsera?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancelar")),
          ElevatedButton(
            onPressed: () async {
              await FirebaseFirestore.instance.collection('users').doc(myUID).update({
                bandKey: FieldValue.delete(),
              });
              if (context.mounted) Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text("Eliminar"),
          ),
        ],
      ),
    );
  }

  void _showFriendSelector(BuildContext context, String bandKey) {
    showDialog(
      context: context,
      builder: (context) {
        String searchQuery = "";
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text("Seleccionar Destino"),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      decoration: const InputDecoration(hintText: "Buscar amigo...", prefixIcon: Icon(Icons.search)),
                      onChanged: (val) => setState(() => searchQuery = val.toLowerCase()),
                    ),
                    const SizedBox(height: 15),
                    Flexible(
                      child: StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance.collection('links').where('Users', arrayContains: myUID).snapshots(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                          return ListView.builder(
                            shrinkWrap: true,
                            itemCount: snapshot.data!.docs.length,
                            itemBuilder: (context, index) {
                              var link = snapshot.data!.docs[index];
                              return FutureBuilder<String>(
                                future: _getFriendNameFromLink(link.id),
                                builder: (context, nameSnapshot) {
                                  String friendName = nameSnapshot.data ?? "Cargando...";
                                  if (searchQuery.isNotEmpty && !friendName.toLowerCase().contains(searchQuery)) return const SizedBox.shrink();
                                  return ListTile(
                                    leading: const CircleAvatar(child: Icon(Icons.person)),
                                    title: Text(friendName),
                                    onTap: () async {
                                      await FirebaseFirestore.instance.collection('users').doc(myUID).update({'$bandKey.Destiny_LinkID': link.id});
                                      if (context.mounted) Navigator.pop(context);
                                    },
                                  );
                                },
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(myUID).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        var userData = snapshot.data!.data() as Map<String, dynamic>;
        List<String> bandKeys = userData.keys.where((key) => key.startsWith('Band')).toList()..sort();

        if (bandKeys.isEmpty) return const Center(child: Text("No hay pulseras registradas"));

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: bandKeys.length,
          itemBuilder: (context, index) {
            String key = bandKeys[index];
            var bandData = userData[key] as Map<String, dynamic>;
            String destinyID = bandData['Destiny_LinkID'] ?? "";
            String bName = bandData['Band_Name'] ?? "Pulsera";

            return Card(
              elevation: 3,
              margin: const EdgeInsets.only(bottom: 15),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              child: Padding(
                padding: const EdgeInsets.all(15),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.watch_outlined, size: 40, color: Colors.deepPurple),
                        const SizedBox(width: 15),
                        Expanded(
                          child: InkWell( // Click en el nombre
                            onTap: () => _editBandName(context, key, bName),
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(bName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                      const SizedBox(width: 5),
                                      const Icon(Icons.edit, size: 14, color: Colors.grey),
                                    ],
                                  ),
                                  Text("MAC: ${bandData['MAC']}", style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                ],
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                          onPressed: () => _deleteBand(context, key),
                        ),
                      ],
                    ),
                    const Divider(height: 25),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.sync),
                        onPressed: () => _showFriendSelector(context, key),
                        label: FutureBuilder<String>(
                          future: _getFriendNameFromLink(destinyID),
                          builder: (context, nameSnap) => Text(destinyID.isEmpty ? "VINCULAR CONTACTO" : "DESTINO: ${nameSnap.data ?? '...'}"),
                        ),
                      ),
                    )
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}