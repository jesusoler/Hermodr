import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Definir una variable con la UID del usuario logeado
  final String myUID = FirebaseAuth.instance.currentUser!.uid;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Test Saludo")),
      body: StreamBuilder<QuerySnapshot>(
        // Instancia para oír los cambios en Message.Sent de los archivos con su UID en Users
        stream: FirebaseFirestore.instance
            .collection('links')
            .where('Users', arrayContains: myUID)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Text('Error: ${snapshot.error}');
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          // Cuando ha cambiado un archivo, comprobamos que el mensaje enviado ahora es "true" y que Message.Last_Sent no es el UID del usuario 
          for (var doc in snapshot.data!.docs) {
            var data = doc.data() as Map<String, dynamic>;
            var message = data['Message'];

            if (message['Sent'] == true && message['Last_Sent'] != myUID) {
              
              Future.delayed(Duration.zero, () {
                _getGreeting(context, message['Last_Sent']);
              });
            }
          }

          return const Center(
            child: Text("Esperando saludos :)"),
          );
        },
      ),
    );
  }

  void _getGreeting(BuildContext context, String emisor) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("¡Has recibido un saludo de $emisor!"),
        backgroundColor: Colors.green,
      ),
    );
    // Devolver el estado de Message.Sent a false para esperar al siguiente mensaje
    try {
    await FirebaseFirestore.instance
        .collection('links')
        .doc(docId)
        .update({
          'Message.Sent': false,
        });
  } catch (e) {
    print("Error al resetear: $e");
  }
  }
}