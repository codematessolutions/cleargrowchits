import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart'; // Required for session saving
import 'admin_home_screen.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _phoneCtrl = TextEditingController();
  final TextEditingController _passCtrl = TextEditingController();

  bool _isObscured = true;
  bool _isLoading = false;

  // --- LOGIN LOGIC WITH SESSION SAVING ---
  void _login() async {
    String phone = _phoneCtrl.text.trim();
    String pass = _passCtrl.text.trim();

    if (phone.isEmpty || pass.isEmpty) {
      _showError("Please enter both phone and password");
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Search for the staff member
      var result = await FirebaseFirestore.instance
          .collection('staff_admins')
          .where('phone', isEqualTo: phone)
          .limit(1)
          .get();

      if (result.docs.isEmpty) {
        _showError("User not found");
      } else {
        var userData = result.docs.first.data();
        String dbPassword = userData['password'] ?? "";

        if (dbPassword == pass) {
          // 1. SAVE SESSION TO SHARED PREFERENCES
          final SharedPreferences prefs = await SharedPreferences.getInstance();
          await prefs.setBool('isLoggedIn', true);
          await prefs.setString('userId', result.docs.first.id);
          await prefs.setString('userName', userData['name'] ?? 'Admin');
          await prefs.setString('userRole', userData['role'] ?? 'Admin');

          // 2. NAVIGATE TO HOME
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => AdminHome(
                  userId: result.docs.first.id,
                  userName: userData['name'],
                  userRole: userData['role'] ?? 'Admin',
                ),
              ),
            );
          }
        } else {
          _showError("Incorrect password");
        }
      }
    } catch (e) {
      _showError("Login Error: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(20),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;
    // Responsive width for "Medium Container" look
    double containerWidth = screenWidth > 600 ? 400 : screenWidth * 0.88;

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9), // Modern light slate background
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            children: [
              const Icon(Icons.admin_panel_settings, size: 70, color: Color(0xFF1E3A8A)),
              const SizedBox(height: 10),
              const Text(
                "Staff Login",
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A)),
              ),
              const SizedBox(height: 30),

              // The Centered "Medium" Container
              Container(
                width: containerWidth,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    )
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Phone Number", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 8),
                    _buildTextField(
                      controller: _phoneCtrl,
                      hint: "Enter phone number",
                      icon: Icons.phone_android,
                      isPassField: false,
                    ),
                    const SizedBox(height: 20),
                    const Text("Password", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 8),
                    _buildTextField(
                      controller: _passCtrl,
                      hint: "••••••••",
                      icon: Icons.lock_outline,
                      isPassField: true,
                    ),
                    const SizedBox(height: 30),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1E3A8A),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        onPressed: _isLoading ? null : _login,
                        child: _isLoading
                            ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                            : const Text(
                          "LOGIN",
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
              const Text("Secure Access Control", style: TextStyle(color: Colors.grey, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  // --- REFINED TEXTFIELD HELPER ---
  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    required bool isPassField,
  }) {
    return TextField(
      controller: controller,
      obscureText: isPassField ? _isObscured : false,
      keyboardType: isPassField ? TextInputType.text : TextInputType.phone,
      style: const TextStyle(fontSize: 15),
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, size: 20, color: Colors.blueGrey),
        suffixIcon: isPassField
            ? IconButton(
          icon: Icon(_isObscured ? Icons.visibility_off : Icons.visibility, size: 20),
          onPressed: () => setState(() => _isObscured = !_isObscured),
        )
            : null,
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF1E3A8A), width: 1.5),
        ),
      ),
    );
  }
}