import 'package:flutter/material.dart';
import 'auth_login.dart'; 

class CreateScreen extends StatefulWidget {
  const CreateScreen({super.key});

  @override
  State<CreateScreen> createState() => _CreateScreenState();
}

class _CreateScreenState extends State<CreateScreen> {
  // Instanciamos tu clase de autenticación (ajústalo al nombre de tu clase)
  final AuthLogin _authLogin = AuthLogin(); 

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _cargando = false;

  void _ejecutarRegistro() async {
    if (_nameController.text.isEmpty || _emailController.text.isEmpty || _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Por favor, rellena todos los campos")),
      );
      return;
    }

    setState(() => _cargando = true);

    // Llamamos a tu función vieja tal cual la tienes
    final user = await _authLogin.signup(
      _emailController.text.trim(),
      _passwordController.text.trim(),
      _nameController.text.trim(),
    );

    setState(() => _cargando = false);

    if (user != null) {
      // Si el usuario se creó bien, volvemos al login o el main.dart nos redirigirá
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Cuenta creada con éxito"), backgroundColor: Colors.green),
        );
        Navigator.pop(context);
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Error al registrar. Revisa los datos o el formato."), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Nueva Cuenta")),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: "Nombre", icon: Icon(Icons.person)),
            ),
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: "Email", icon: Icon(Icons.email)),
              keyboardType: TextInputType.emailAddress,
            ),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(labelText: "Contraseña", icon: Icon(Icons.lock)),
              obscureText: true,
            ),
            const SizedBox(height: 30),
            _cargando 
              ? const CircularProgressIndicator() 
              : ElevatedButton(
                  onPressed: _ejecutarRegistro,
                  style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
                  child: const Text("Registrarme"),
                ),
          ],
        ),
      ),
    );
  }
}