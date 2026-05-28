import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
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
  StreamSubscription? _serviceSubscription;

  @override
  void initState() {
    super.initState();
    // Iniciamos el servicio cada vez que se abre la app para asegurar persistencia
    FlutterBackgroundService().startService();
    _setupNotifications();
    _requestBluetoothPermissions();
    
    // Escuchamos al servicio de segundo plano para mostrar el SnackBar si la app está abierta
    _serviceSubscription = FlutterBackgroundService().on('on_greeting').listen((event) {
      if (mounted) {
        String senderName = event?['senderName'] ?? "Alguien";
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("¡Has recibido un saludo de $senderName!"),
            backgroundColor: const Color(0xFF204173),
          ),
        );
      }
    });
  }

  void _requestBluetoothPermissions() async {
    // Solicitamos los permisos necesarios para BLE en el hilo de la UI.
    // Esto evita que el servicio de fondo intente pedirlos y crashee.
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
      Permission.notification, // Fundamental para que el servicio no falle al mostrar la barra
    ].request();
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

  @override
  void dispose() {
    _serviceSubscription?.cancel();
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
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Stack(
          children: [_pages[_selectedIndex]],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        selectedItemColor: const Color(0xFF204173),
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
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD9E5F8),
              foregroundColor: const Color(0xFF204173),
            ),
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
              color: const Color(0xFFD9E5F8),
              margin: const EdgeInsets.only(bottom: 15),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              child: Padding(
                padding: const EdgeInsets.all(15),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.watch_outlined, size: 40, color: Colors.black),
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
                                      Text(bName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black)),
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
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFD9E5F8),
                          foregroundColor: const Color(0xFF204173),
                        ),
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