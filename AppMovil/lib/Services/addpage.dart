import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AddPage extends StatefulWidget {
  const AddPage({super.key});

  @override
  State<AddPage> createState() => _AddPageState();
}

class _AddPageState extends State<AddPage> {
  final _emailController = TextEditingController();
  final String myUID = FirebaseAuth.instance.currentUser!.uid;

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
              onTap: () => print("Próximamente pulseras"),
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