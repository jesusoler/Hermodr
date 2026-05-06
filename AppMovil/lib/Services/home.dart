import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'friendpage.dart';
import 'addpage.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final String myUID = FirebaseAuth.instance.currentUser!.uid;
  int _selectedIndex = 0;

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
    String senderName = senderUID; 
    try {
      DocumentSnapshot userDoc = await FirebaseFirestore.instance.collection('users').doc(senderUID).get();
      if (userDoc.exists) {
        var userData = userDoc.data() as Map<String, dynamic>;
        senderName = userData['Name'] ?? senderUID;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("¡Has recibido un saludo de $senderName!"),
          backgroundColor: Colors.deepPurple,
        ),
      );
      await FirebaseFirestore.instance.collection('links').doc(docId).update({'Message.Sent': false});
    } catch (e) {
      print("Error al resetear: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> _pages = [
      BandsMenu(myUID: myUID),
      FriendPage(myUID: myUID, onSendGreeting: _sendGreeting),
      const AddPage(),
      const Center(child: Text("Próximamente: Perfil")),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text("Envíos")),
      body: Stack(
        children: [
          SizedBox(
            height: 0,
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('links').where('Users', arrayContains: myUID).snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasData) {
                  for (var doc in snapshot.data!.docs) {
                    var data = doc.data() as Map<String, dynamic>;
                    var message = data['Message'];
                    if (message['Sent'] == true && message['Last_Sent'] != myUID) {
                      Future.delayed(Duration.zero, () {
                        _getGreeting(context, message['Last_Sent'], doc.id);
                      });
                    }
                  }
                }
                return const SizedBox.shrink();
              },
            ),
          ),
          _pages[_selectedIndex],
        ],
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

  // --- DIÁLOGO PARA CAMBIAR COLOR ---
  void _editBandColor(BuildContext context, String linkID) {
    if (linkID.isEmpty) return;
    List<String> colors = ['Rojo', 'Azul', 'Verde', 'Amarillo', 'Morado', 'Naranja', 'Rosa'];
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Color de Notificación"),
        content: Wrap(
          alignment: WrapAlignment.center,
          spacing: 15,
          runSpacing: 15,
          children: colors.map((color) => GestureDetector(
            onTap: () async {
              await FirebaseFirestore.instance.collection('links').doc(linkID).update({
                'Config_$myUID.Color': color
              });
              if (context.mounted) Navigator.pop(context);
            },
            child: Container(
              width: 45, height: 45,
              decoration: BoxDecoration(
                color: _colorFromName(color),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.black26, width: 2),
              ),
            ),
          )).toList(),
        ),
      ),
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
                        GestureDetector( // Click en el cuadro de color
                          onTap: () => _editBandColor(context, destinyID),
                          child: _LinkColorBox(linkID: destinyID, myUID: myUID),
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
            color: BandsMenu._colorFromName(colorName), 
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.black12)
          ),
          child: const Icon(Icons.palette, size: 16, color: Colors.white54),
        );
      },
    );
  }
}