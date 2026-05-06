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

  // Lo que se creará al aceptar a un amigo
  void _acceptFriendRequest(BuildContext context, String requestId, String friendUID, String friendName) async {
    try {
      String linkId = "link_${myUID}_$friendUID"; //El nombre del archivo y el id del link

      await FirebaseFirestore.instance.collection('links').doc(linkId).set({
        'Config_$myUID': {'Color': ''},
        'Config_$friendUID': {'Color': ''},
        'LinkID': linkId,
        'Message': {
          'Last_Second': FieldValue.serverTimestamp(),
          'Last_Sent': '',
          'Sent': false,
        },
        'Users': [myUID, friendUID],
      });

      await FirebaseFirestore.instance.collection('requests').doc(requestId).delete();
      
      if (context.mounted) Navigator.pop(context); // Cierra el popup al aceptar
    } catch (e) {
      print("Error al aceptar: $e");
    }
  }

  // Popup que muestra la lista de solicitudes
  void _showRequestsDialog(BuildContext context, List<QueryDocumentSnapshot> solicitudes) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Solicitudes pendientes"),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: solicitudes.map((doc) {
              return ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person_add)),
                title: Text(doc['From_Name'] ?? "Alguien"),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton( //Al pulsar el tick se aplica la función de antes
                      icon: const Icon(Icons.check, color: Colors.green),
                      onPressed: () => _acceptFriendRequest(context, doc.id, doc['From_UID'], doc['From_Name']),
                    ),
                    IconButton( //Al pulsar la X se borrará el documento
                      icon: const Icon(Icons.close, color: Colors.red),
                      onPressed: () => doc.reference.delete(),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cerrar")),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Widget para el popup de las solicitudes, solo aparecerá si tienes solicitudes
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('requests')
              .where('To_UID', isEqualTo: myUID)
              .snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return const SizedBox.shrink(); 
            }

            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.amber.shade50, 
              child: ListTile(
                onTap: () => _showRequestsDialog(context, snapshot.data!.docs),
                leading: const CircleAvatar(
                  backgroundColor: Colors.amber,
                  child: Icon(Icons.notifications_active, color: Colors.white),
                ),
                title: const Text("Solicitudes de amistad"),
                subtitle: Text("Tienes ${snapshot.data!.docs.length} pendiente(s)"),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              ),
            );
          },
        ),

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