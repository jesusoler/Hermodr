import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthLogin {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  
  //Signup
  
  Future<User?> signup(String email, String password, String nombre) async {
    try {
      UserCredential res = await _auth.createUserWithEmailAndPassword(
          email: email, password: password);
      User? user = res.user;
    if (user != null) {
      await _db.collection('users').doc(user.uid).set ({
        'Name': nombre,
        'Email': email,
        'UID': user.uid,
        'Band1': {
          'Band_Name': '',
          'MAC': '',
          'Destiny_LinkID': ''
        },
        'Token_FCM': '',
        'Profile_Pic': ''
      });
    }
      return user;
    } catch (e) {
      print ("Error en un registro $e");
      return null;
    }
  }
  
  //Login
  
  Future<User?> login(String email, String password) async {
    try {
      UserCredential res = await _auth.signInWithEmailAndPassword(
          email: email, password: password);
      return res.user;
    } catch (e) {
      print("Error en login: $e");
      return null;
    }
  }
  
  //Logout
  
  Future<void> logout() async => await _auth.signOut();
}