import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class AddPage extends StatefulWidget {
  const AddPage({super.key});

  @override
  State<AddPage> createState() => _AddPageState();
}

class _AddPageState extends State<AddPage> {
  final _emailController = TextEditingController();
  final String myUID = FirebaseAuth.instance.currentUser!.uid;

  // Variables para BLE
  bool _showBleList = false;
  bool _isScanning = false;
  List<ScanResult> _scanResults = [];
  StreamSubscription? _scanSubscription;

  // Diálogo informativo para permisos/estado de Bluetooth
  void _showPermissionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Permisos de Bluetooth"),
        content: const Text("No tienes el permiso para usar bluetooth activado"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancelar"),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await openAppSettings(); // Abre la configuración del sistema
            },
            child: const Text("Ir a ajustes"),
          ),
        ],
      ),
    );
  }

  // --- LÓGICA BLE ---

  void _startScan() async {
    // Solicitar permisos al sistema (esto activa el pop-up oficial)
    List<Permission> permissions = [];
    if (Platform.isAndroid) {
      permissions = [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.location,
      ];
    } else if (Platform.isIOS) {
      permissions = [Permission.bluetooth];
    }

    Map<Permission, PermissionStatus> statuses = await permissions.request();

    // Si el usuario deniega los permisos necesarios
    if (statuses.values.any((status) => status.isDenied || status.isPermanentlyDenied)) {
      _showPermissionDialog();
      return;
    }

    if (await FlutterBluePlus.isSupported == false) return;

    // Comprobar si el Bluetooth está encendido y tiene permisos
    BluetoothAdapterState state = await FlutterBluePlus.adapterState.first;
    if (state != BluetoothAdapterState.on) {
      _showPermissionDialog();
      return;
    }
    
    setState(() {
      _showBleList = true;
      _isScanning = true;
      _scanResults = [];
    });

    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      if (mounted) {
        setState(() {
          // Filtramos dispositivos que tengan nombre para no llenar la lista de basura
          _scanResults = results.where((r) => r.device.platformName.isNotEmpty).toList();
        });
      }
    });

    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
    } catch (e) {
      _screenMsg("Error al escanear: $e", isError: true);
    }

    await FlutterBluePlus.isScanning.where((val) => val == false).first;
    if (mounted) setState(() => _isScanning = false);
  }

  void _stopScan() {
    FlutterBluePlus.stopScan();
    _scanSubscription?.cancel();
    setState(() {
      _showBleList = false;
      _isScanning = false;
    });
  }

  void _connectAndAddBand(BluetoothDevice device) async {
    try {
      // En BLE a veces es necesario conectar para asegurar la estabilidad del ID, 
      // aunque para obtener la MAC (RemoteId) el escaneo suele bastar.
      
      DocumentSnapshot userDoc = await FirebaseFirestore.instance.collection('users').doc(myUID).get();
      var userData = userDoc.data() as Map<String, dynamic>? ?? {};
      
      // Buscamos el siguiente índice disponible para BandN
      int i = 1;
      while (userData.containsKey('Band$i')) {
        i++;
      }
      String bandKey = 'Band$i';

      await FirebaseFirestore.instance.collection('users').doc(myUID).update({
        bandKey: {
          'Band_Name': device.platformName,
          'MAC': device.remoteId.str,
          'Destiny_LinkID': '',
        }
      });

      _screenMsg("Pulsera vinculada como $bandKey", isError: false);
      _stopScan();
    } catch (e) {
      _screenMsg("Error al vincular: $e", isError: true);
    }
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _emailController.dispose();
    super.dispose();
  }

  // --- LÓGICA AMIGOS ---

  void _sendRequest() async {
    String email = _emailController.text.trim().toLowerCase();
    if (email.isEmpty) return;

    // Buscar el email
    var result = await FirebaseFirestore.instance
        .collection('users')
        .where('Email', isEqualTo: email)
        .get();

    if (result.docs.isEmpty) {
      _screenMsg("Usuario no encontrado", isError: true);
      return;
    }

    String friendUID = result.docs.first.id;
    String friendName = result.docs.first['Name'];

    if (friendUID == myUID) {
      _screenMsg("No puedes enviarte una solicitud a ti mismo", isError: true);
      return;
    }
    // Comprobamos si ya son amigos buscando los links de los que forma parte y comprobando si en alguno está el amigo
    var existingLink = await FirebaseFirestore.instance
          .collection('links')
          .where('Users', arrayContains: myUID)
          .get();
    bool alreadyFriends = existingLink.docs.any((doc) {
        List users = doc['Users'];
        return users.contains(friendUID);
      });

      if (alreadyFriends) {
        _screenMsg("Ya eres amigo de $friendName", isError: true);
        return;
      }
    // Creamos un documento en la colección "requests" para poder hacer solicitudes aceptables/denegables
    String requestId = "request_${myUID}_$friendUID";
    // El nombre de ese documento será el de arriba, pero si ya existe dará el error de abajo
    try {
      var myDoc = await FirebaseFirestore.instance.collection('users').doc(myUID).get();
      String myName = myDoc.data()?['Name'] ?? "Usuario";
      
      var docRef = FirebaseFirestore.instance.collection('requests').doc(requestId);
      var docSnap = await docRef.get();

      if (docSnap.exists) {
        _screenMsg("Ya existe una solicitud pendiente", isError: true);
        return;
      }

    // Si no existía, se crea:
      await docRef.set({
        'From_UID': myUID,
        'To_UID': friendUID,
        'From_Name': myName,
        'Timestamp': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        Navigator.pop(context);
        _screenMsg("Solicitud enviada a $friendName", isError: false);
      }
    } catch (e) {
      _screenMsg("Error: $e", isError: true);
    }
  }

  void _screenMsg(String msg, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: isError ? Colors.red : Colors.green),
    );
  }

  void _addFriendMsg() {
    showDialog( //Popup de crear solicitud de amistad
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Añadir amigo"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Escribe el gmail de tu amigo:"),
            const SizedBox(height: 10),
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(border: OutlineInputBorder(), hintText: "email@gmail.com"),
              keyboardType: TextInputType.emailAddress,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancelar")),
          ElevatedButton(onPressed: _sendRequest, child: const Text("Enviar")),
        ],
      ),
    );
  }

  @override //Botones de la página "añadir"
  Widget build(BuildContext context) {
    if (_showBleList) {
      return Column(
        children: [
          ListTile(
            title: const Text("Buscando pulseras...", style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(_isScanning ? "Asegúrate de que el Bluetooth esté activo" : "Escaneo finalizado"),
            trailing: _isScanning 
              ? const CircularProgressIndicator() 
              : IconButton(icon: const Icon(Icons.refresh), onPressed: _startScan),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _scanResults.length,
              itemBuilder: (context, index) {
                final res = _scanResults[index];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: ListTile(
                    leading: const Icon(Icons.bluetooth),
                    title: Text(res.device.platformName),
                    subtitle: Text(res.device.remoteId.str),
                    trailing: ElevatedButton(
                      onPressed: () => _connectAndAddBand(res.device),
                      child: const Text("Vincular"),
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextButton(
              onPressed: _stopScan,
              child: const Text("Cancelar", style: TextStyle(color: Colors.red)),
            ),
          )
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        children: [
          Expanded(
            child: _buildMenuButton(
              title: "AÑADIR AMIGO",
              icon: Icons.person_add,
              color: Colors.blue,
              onTap: _addFriendMsg,
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: _buildMenuButton(
              title: "AÑADIR PULSERA",
              icon: Icons.watch,
              color: Colors.green,
              onTap: _startScan,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuButton({required String title, required IconData icon, required Color color, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color, width: 2),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 60, color: color),
            const SizedBox(height: 10),
            Text(title, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }
}