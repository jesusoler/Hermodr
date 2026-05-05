import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class FriendPage extends StatelessWidget {
  final String myUID;
  final Function(String) onSendGreeting;

  const FriendPage({
    super.key,
    required this.myUID,
    required this.onSendGreeting,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Lista de amigos
        const Padding(
          padding: EdgeInsets.all(16.0),
          child: Text("Amigos",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ),

        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('links')
                .where('Users', arrayContains: myUID)
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              var docs = snapshot.data!.docs;
              if (docs.isEmpty) {
                return const Center(
                    child: Text("No tienes amigos añadidos todavía."));
              }

              return ListView.builder(
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  var linkData = docs[index].data() as Map<String, dynamic>;
                  String docId = docs[index].id;
                  List users = linkData['Users'];
                  // Buscamos el UID del otro
                  String friendUID = users.firstWhere((id) => id != myUID);
                  // Buscamos su nombre en base a su UID
                  return FutureBuilder<DocumentSnapshot>(
                    future: FirebaseFirestore.instance
                        .collection('users')
                        .doc(friendUID)
                        .get(),
                    builder: (context, userSnapshot) {
                      String friendName = "Cargando nombre...";

                      if (userSnapshot.hasData && userSnapshot.data!.exists) {
                        var userData =
                            userSnapshot.data!.data() as Map<String, dynamic>;
                        friendName = userData['Name'] ?? "No se ha encontrado nombre";
                      }

                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: ListTile(
                          leading: const CircleAvatar(child: Icon(Icons.person)),
                          title: Text(friendName),
                          subtitle: const Text("Pulsa para enviar saludo"),
                          trailing: IconButton(
                            icon: const Icon(Icons.send, color: Colors.deepPurpleAccent),
                            onPressed: () => onSendGreeting(docId),
                          ),
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}