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
      // Generamos el ID del link ordenando los UIDs alfabéticamente
      List<String> ids = [myUID, friendUID]..sort();
      String linkId = "link_${ids[0]}_${ids[1]}"; //El nombre del archivo y el id del link
      WriteBatch batch = FirebaseFirestore.instance.batch();

      batch.set(FirebaseFirestore.instance.collection('links').doc(linkId), {
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

      batch.delete(FirebaseFirestore.instance.collection('requests').doc(requestId));
      
      await batch.commit();
      
      if (context.mounted) Navigator.pop(context); // Cierra el popup al aceptar
    } catch (e) {
      print("Error al aceptar: $e");
    }
  }

  // --- DIÁLOGO PARA CAMBIAR COLOR ---
  void _editBandColor(BuildContext context, String linkID) {
    if (linkID.isEmpty) return;
    final List<String> colors = ['Rojo', 'Azul', 'Verde', 'Amarillo', 'Morado', 'Naranja', 'Rosa']; // Lista de colores disponibles
    
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Ajustes del Vínculo"),
          content: StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance.collection('users').doc(myUID).snapshots(),
            builder: (context, userSnap) {
              if (!userSnap.hasData) return const CircularProgressIndicator();
              var userData = userSnap.data!.data() as Map<String, dynamic>;
              var bandKeys = userData.keys.where((k) => k.startsWith('Band')).toList()..sort();

              return StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instance.collection('links').doc(linkID).snapshots(),
                builder: (context, linkSnap) {
                  if (!linkSnap.hasData) return const CircularProgressIndicator();
                  var config = linkSnap.data!['Config_$myUID'] as Map<String, dynamic>;
                  String selectedColor = config['Color'] ?? "";
                  String selectedBand = config['BandKey'] ?? "";

                  return Column(
                    mainAxisSize: MainAxisSize.min, // Ajusta el tamaño de la columna al contenido
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Color de notificación:", style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        children: colors.map((color) => GestureDetector(
                          onTap: () => FirebaseFirestore.instance.collection('links').doc(linkID).update({'Config_$myUID.Color': color}),
                          child: Container(
                            width: 35, height: 35,
                            decoration: BoxDecoration(
                              color: _colorFromName(color),
                              shape: BoxShape.circle,
                              border: Border.all( // Borde para indicar el color seleccionado
                                color: selectedColor == color ? Colors.black : Colors.transparent,
                                width: 3,
                              ),
                            ),
                          ),
                        )).toList(),
                      ),
                      const SizedBox(height: 20),
                      const Text("Pulsera destino:", style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      if (bandKeys.isEmpty)
                        const Text("No tienes pulseras vinculadas.", style: TextStyle(fontSize: 12, color: Colors.grey)) // Mensaje si no hay pulseras
                      else
                        DropdownButton<String>(
                          isExpanded: true,
                          value: selectedBand.isEmpty ? null : selectedBand,
                          hint: const Text("Seleccionar pulsera"),
                          items: bandKeys.map((key) {
                            return DropdownMenuItem(
                              value: key,
                              child: Text(userData[key]['Band_Name'] ?? key), // Muestra el nombre de la pulsera o su clave
                            );
                          }).toList(),
                          onChanged: (val) {
                            FirebaseFirestore.instance.collection('links').doc(linkID).update({'Config_$myUID.BandKey': val});
                          },
                        ),
                    ],
                  );
                },
              );
            },
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cerrar")), // Botón para cerrar el diálogo
          ],
        );
      },
    );
  }
  static Color _colorFromName(String name) {
    switch (name.toLowerCase()) {
      case 'rojo': return Colors.red;
      case 'azul': return Colors.blue;
      case 'verde': return Colors.green;
      case 'amarillo': return Colors.yellow;
      case 'morado': return Colors.purple;
      case 'naranja': return Colors.orange;
      case 'rosa': return Colors.pink;
      default: return Colors.blueGrey;
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
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                "Configura las notificaciones",
                                style: TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                              const SizedBox(width: 8), // Espacio entre el texto y el botón de color
                              GestureDetector( // Click en el cuadro de color
                                onTap: () => _editBandColor(context, docId),
                                child: _LinkColorBox(linkID: docId, myUID: myUID),
                              ),
                              IconButton(
                                icon: const Icon(Icons.send, color: Colors.deepPurpleAccent),
                                onPressed: () => onSendGreeting(docId),
                              ),
                            ],
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

class _LinkColorBox extends StatelessWidget {
  final String linkID;
  final String myUID;
  const _LinkColorBox({required this.linkID, required this.myUID});

  @override
  Widget build(BuildContext context) {
    if (linkID.isEmpty) {
      return Container(
        width: 35, height: 35, 
        decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(8))
      );
    }
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('links').doc(linkID).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || !snapshot.data!.exists) return const SizedBox(width: 35, height: 35);
        var data = snapshot.data!.data() as Map<String, dynamic>;
        String colorName = data['Config_$myUID']?['Color'] ?? "Gris";
        return Container(
          width: 35, height: 35,
          decoration: BoxDecoration(
            color: FriendPage._colorFromName(colorName), 
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.black12)
          ),
          child: const Icon(Icons.palette, size: 16, color: Colors.white54),
        );
      },
    );
  }
}