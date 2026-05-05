import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'friendpage.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Definir una variable con la UID del usuario logeado
  final String myUID = FirebaseAuth.instance.currentUser!.uid;
  int _selectedIndex = 0;

  void _sendGreeting(String docId) async {
    try { //Para enviar el mensaje cambiamos los campos pertinentes en la BBDD
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
    String senderName = senderUID; 
    
    try {
      DocumentSnapshot userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(senderUID)
        .get();

      if (userDoc.exists) {
        var userData = userDoc.data() as Map<String, dynamic>;
        senderName = userData ['Name'] ?? senderUID;
      }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("¡Has recibido un saludo de $senderName!"),
        backgroundColor: Colors.deepPurple,
      ),
    );
    // Devolver el estado de Message.Sent a false para esperar al siguiente mensaje
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

  @override
  Widget build(BuildContext context) {
    // Páginas del menú
    final List<Widget> _pages = [
      const Center(child:Text("Próximamente: Menú")),
      FriendPage(myUID: myUID, onSendGreeting: _sendGreeting),
      const Center(child: Text("Próximamente: Añadir Amigos")),
      const Center(child: Text("Próximamente: Perfil")),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text("Envíos")),
      body: Stack(
        children: [
          // Activar el stream (Siempre activo de fondo)
          SizedBox(
            height: 0,
            child: StreamBuilder<QuerySnapshot>(
              // Instancia para oír los cambios en Message.Sent de los archivos con su UID en Users
              stream: FirebaseFirestore.instance
                  .collection('links')
                  .where('Users', arrayContains: myUID)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasData) {
                  // Cuando ha cambiado un archivo, comprobamos que el mensaje enviado ahora es "true" y que Message.Last_Sent no es el UID del usuario
                  for (var doc in snapshot.data!.docs) {
                    var data = doc.data() as Map<String, dynamic>;
                    var message = data['Message'];
                    String docId = doc.id;

                    if (message['Sent'] == true && message['Last_Sent'] != myUID) {
                      Future.delayed(Duration.zero, () {
                        _getGreeting(context, message['Last_Sent'], docId);
                      });
                    }
                  }
                }
                return const SizedBox.shrink();
              },
            ),
          ),
          // Vista de la página seleccionada
          _pages[_selectedIndex],
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
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