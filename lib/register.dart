// register.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'login.dart';

class Register extends StatefulWidget {
  const Register({Key? key}) : super(key: key);

  @override
  State<Register> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<Register> {
  final supabase = Supabase.instance.client;
  final nameCtrl = TextEditingController();
  final emailCtrl = TextEditingController();
  final passCtrl = TextEditingController();
  String role = 'rider';
  bool loading = false;
  bool _obscure = true;

  Future<void> _register() async {
    setState(() => loading = true);
    try {
      final res = await supabase.auth.signUp(
        email: emailCtrl.text.trim(),
        password: passCtrl.text.trim(),
      );
      final userId = res.user?.id;
      if (userId == null) throw "Failed to create user";

      // insert profile (with role)
      await supabase.from('profiles').insert({
        'id': userId,
        'full_name': nameCtrl.text.trim(),
        'role': role,
      });

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Account created! Please verify email (if enabled) and login.')));
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const Login()));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Registration failed: $e')));
    } finally {
      setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const campusGreen = Color(0xFF00BFA6);
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('Register'), backgroundColor: campusGreen),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            TextField(controller: nameCtrl, decoration: InputDecoration(hintText: 'Full Name', filled: true, fillColor: Colors.grey[100], border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))),
            const SizedBox(height: 20),
            TextField(controller: emailCtrl, decoration: InputDecoration(hintText: 'Email', filled: true, fillColor: Colors.grey[100], border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))),
            const SizedBox(height: 20),
            TextField(controller: passCtrl, obscureText: _obscure, decoration: InputDecoration(hintText: 'Password', filled: true, fillColor: Colors.grey[100], suffixIcon: IconButton(icon: Icon(_obscure? Icons.visibility_off: Icons.visibility), onPressed: () => setState(()=>_obscure=!_obscure)), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))),
            const SizedBox(height: 20),
            Row(children: [
              const Text('Register as: '),
              const SizedBox(width: 12),
              DropdownButton<String>(
                value: role,
                items: const [
                  DropdownMenuItem(value: 'rider', child: Text('Rider')),
                  DropdownMenuItem(value: 'driver', child: Text('Driver')),
                ],
                onChanged: (v) => setState(()=>role=v!),
              )
            ]),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: loading ? null : _register,
                style: ElevatedButton.styleFrom(backgroundColor: campusGreen, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: loading ? const CircularProgressIndicator(color: Colors.white) : const Text('Create Account', style: TextStyle(fontSize: 18)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
