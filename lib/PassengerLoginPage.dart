import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'PassengerPage.dart';
import 'RoleSelectionPage.dart';
import 'PassengerSignUpPage.dart';

class PassengerLoginPage extends StatefulWidget {
  @override
  _PassengerLoginPageState createState() => _PassengerLoginPageState();
}

class _PassengerLoginPageState extends State<PassengerLoginPage> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  bool _rememberMe = false; // Variable to keep track of "Remember Me" state

  @override
  void initState() {
    super.initState();
    _loadLoginDetails(); // Load saved login details on startup
  }

  // Load saved login details from SharedPreferences
  void _loadLoginDetails() async {
    final prefs = await SharedPreferences.getInstance();
    final savedEmail = prefs.getString('savedEmail');
    final savedPassword = prefs.getString('savedPassword');
    final rememberMe = prefs.getBool('rememberMe') ?? false;

    setState(() {
      _rememberMe = rememberMe;
      emailController.text = savedEmail ?? '';
      passwordController.text = savedPassword ?? '';
    });
  }

  // Save login details to SharedPreferences
  void _saveLoginDetails() async {
    final prefs = await SharedPreferences.getInstance();
    if (_rememberMe) {
      await prefs.setString('savedEmail', emailController.text);
      await prefs.setString('savedPassword', passwordController.text);
      await prefs.setBool('rememberMe', _rememberMe);
    } else {
      await prefs.remove('savedEmail');
      await prefs.remove('savedPassword');
      await prefs.remove('rememberMe');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Passenger Login'),
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (context) => RoleSelectionPage()),
                  (route) => false,
            );
          },
        ),
      ),
      body: Center(
        child: Card(
          elevation: 5,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          margin: EdgeInsets.all(20),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  'Passenger Login',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 20),
                TextField(
                  controller: emailController,
                  decoration: InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                SizedBox(height: 20),
                TextField(
                  controller: passwordController,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  obscureText: true,
                ),
                SizedBox(height: 20),
                CheckboxListTile(
                  title: Text('Remember Me'),
                  value: _rememberMe,
                  onChanged: (bool? value) {
                    setState(() {
                      _rememberMe = value ?? false;
                    });
                  },
                ),
                SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () async {
                    String email = emailController.text;
                    String password = passwordController.text;

                    try {
                      UserCredential userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
                        email: email,
                        password: password,
                      );
                      _saveLoginDetails(); // Save login details if "Remember Me" is checked
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => PassengerPage()),
                      );
                    } on FirebaseAuthException catch (e) {
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: Text('Login Failed'),
                          content: Text(e.message ?? 'An error occurred'),
                          actions: <Widget>[
                            TextButton(
                              onPressed: () {
                                Navigator.of(context).pop();
                              },
                              child: Text('OK'),
                            ),
                          ],
                        ),
                      );
                    }
                  },
                  child: Text('Login'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => PassengerSignUpPage()),
                    );
                  },
                  child: Text("Don't have an account? Create one"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
