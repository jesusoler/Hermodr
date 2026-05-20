import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'auth_login.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool _isUploadingImage = false; // Nuevo estado para el indicador de carga
  void _editName(BuildContext context, String currentName, String uid) {
    final controller = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Editar Nombre"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: "Ingresa tu nombre"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancelar")),
          ElevatedButton(
            onPressed: () async {
              try {
                if (controller.text.trim().isNotEmpty) {
                  await FirebaseFirestore.instance.collection('users').doc(uid).update({'Name': controller.text.trim()});
                }
                if (context.mounted) Navigator.pop(context);
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error al actualizar: $e")));
                }
              }
            },
            child: const Text("Guardar"),
          ),
        ],
      ),
    );
  }

  Future<void> _editProfilePic(BuildContext context, String uid) async {
    final ImagePicker picker = ImagePicker();
    
    // Seleccionar imagen de la galería
    final XFile? image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 50);

    if (image == null) return; // Si el usuario cancela, no hacemos nada

    setState(() => _isUploadingImage = true);

    try {
      // Referencia en Firebase Storage para la foto de perfil del usuario
      Reference ref = FirebaseStorage.instance.ref().child('profile_pics').child('$uid.jpg');

      // Subir el archivo
      await ref.putFile(File(image.path));

      // Obtener la URL de descarga pública
      String downloadURL = await ref.getDownloadURL();

      if (!mounted) return;

      // Actualizar Firestore con la nueva URL generada por Storage
      await FirebaseFirestore.instance.collection('users').doc(uid).update({'Profile_Pic': downloadURL});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error al subir imagen: $e")));
      }
    } finally {
      if (mounted) {
        setState(() => _isUploadingImage = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final String myUID = FirebaseAuth.instance.currentUser!.uid;

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(myUID).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text("Error: ${snapshot.error}"));
        }
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const Center(child: Text("Datos de usuario no encontrados."));
        }

        var userData = snapshot.data!.data() as Map<String, dynamic>;
        String userName = userData['Name'] ?? "Usuario Desconocido";
        String profilePicUrl = userData['Profile_Pic'] ?? "";

        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: () => _editProfilePic(context, myUID),
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 60,
                      backgroundColor: Colors.deepPurple.shade100,
                      backgroundImage: profilePicUrl.isNotEmpty
                          ? NetworkImage(profilePicUrl) as ImageProvider
                          : null,
                      child: profilePicUrl.isEmpty && !_isUploadingImage // Mostrar icono solo si no hay foto y no se está subiendo
                          ? Icon(
                              Icons.person,
                              size: 80,
                              color: Colors.deepPurple.shade400,
                            )
                          : null,
                    ),
                    if (_isUploadingImage) // Mostrar indicador de carga si se está subiendo
                      Positioned.fill(
                        child: Container(
                          decoration: const BoxDecoration(
                            color: Colors.black54, // Fondo semitransparente
                            shape: BoxShape.circle,
                          ),
                          child: const Center(
                            child: CircularProgressIndicator(color: Colors.white),
                          ),
                        ),
                      ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(color: Colors.deepPurple, shape: BoxShape.circle),
                        child: const Icon(Icons.edit, size: 20, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              GestureDetector(
                onTap: () => _editName(context, userName, myUID),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      userName,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.deepPurple,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.edit, size: 20, color: Colors.grey),
                  ],
                ),
              ),
              const SizedBox(height: 40),
              ElevatedButton.icon(
                onPressed: () => AuthLogin().logout(),
                icon: const Icon(Icons.logout),
                label: const Text("Cerrar Sesión"),
                style: ElevatedButton.styleFrom(
                  foregroundColor: Colors.red,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}