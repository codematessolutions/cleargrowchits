import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class StaffManagementScreen extends StatefulWidget {
  final String userId;
  final String userName;
  final String userRole;

  const StaffManagementScreen({
    super.key,
    required this.userId,
    required this.userName,
    required this.userRole,
  });

  @override
  State<StaffManagementScreen> createState() => _StaffManagementScreenState();
}

class _StaffManagementScreenState extends State<StaffManagementScreen> {
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _phoneCtrl = TextEditingController();
  final TextEditingController _passCtrl = TextEditingController();

  String _selectedRole = 'Admin';
  bool _isLoading = false;
  bool _isPassVisible = false;

  void _showMessage(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.redAccent : Colors.green,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(10),
      ),
    );
  }

  // --- COMPACT FORM UI ---
  void _showStaffForm({String? docId, Map<String, dynamic>? existingData}) {
    if (widget.userRole != 'Super Admin') return;

    if (existingData != null) {
      _nameCtrl.text = existingData['name'] ?? '';
      _phoneCtrl.text = existingData['phone'] ?? '';
      _passCtrl.text = existingData['password'] ?? '';
      _selectedRole = existingData['role'] ?? 'Admin';
    } else {
      _nameCtrl.clear(); _phoneCtrl.clear(); _passCtrl.clear();
      _selectedRole = 'Admin';
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: EdgeInsets.only(
              top: 12, left: 16, right: 16,
              bottom: MediaQuery.of(context).viewInsets.bottom + 20
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
              const SizedBox(height: 16),
              Text(docId == null ? "Add New Staff" : "Edit Staff Info",
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(child: _buildField(_nameCtrl, "Full Name", Icons.person)),
                  const SizedBox(width: 10),
                  Expanded(child: _buildField(_phoneCtrl, "Phone", Icons.phone, type: TextInputType.phone)),
                ],
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _passCtrl,
                      obscureText: !_isPassVisible,
                      style: const TextStyle(fontSize: 14),
                      decoration: InputDecoration(
                        labelText: "Password", isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        suffixIcon: IconButton(
                          icon: Icon(_isPassVisible ? Icons.visibility : Icons.visibility_off, size: 18),
                          onPressed: () => setSheetState(() => _isPassVisible = !_isPassVisible),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _selectedRole,
                      style: const TextStyle(fontSize: 14, color: Colors.black),
                      decoration: InputDecoration(
                          labelText: "Role", isDense: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))
                      ),
                      items: ['Admin', 'Super Admin'].map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                      onChanged: (v) => setSheetState(() => _selectedRole = v!),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity, height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E3A8A),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
                  ),
                  onPressed: _isLoading ? null : () async {
                    if (_nameCtrl.text.isEmpty || _phoneCtrl.text.isEmpty || _passCtrl.text.isEmpty) {
                      _showMessage("Please fill all fields", isError: true);
                      return;
                    }

                    setSheetState(() => _isLoading = true);

                    // CRITICAL FIX: Explicitly Map<String, dynamic> allows FieldValue
                    final Map<String, dynamic> data = {
                      'name': _nameCtrl.text.trim(),
                      'phone': _phoneCtrl.text.trim(),
                      'password': _passCtrl.text.trim(),
                      'role': _selectedRole,
                      'lastUpdatedBy': widget.userName,
                    };

                    try {
                      if (docId == null) {
                        data['createdAt'] = FieldValue.serverTimestamp(); // No more String error
                        data['addedByUserId'] = widget.userId;
                        await FirebaseFirestore.instance.collection('staff_admins').add(data);
                      } else {
                        await FirebaseFirestore.instance.collection('staff_admins').doc(docId).update(data);
                      }
                      if (mounted) Navigator.pop(context);
                    } catch (e) {
                      _showMessage("Error: $e", isError: true);
                    }
                    setSheetState(() => _isLoading = false);
                  },
                  child: _isLoading
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text("SAVE STAFF", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField(TextEditingController ctrl, String hint, IconData icon, {TextInputType type = TextInputType.text}) {
    return TextField(
      controller: ctrl, keyboardType: type, style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
          labelText: hint, isDense: true,
          prefixIcon: Icon(icon, size: 18),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isSuper = widget.userRole == 'Super Admin';
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text("Staff Management"),
        backgroundColor: const Color(0xFF1E3A8A),
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('staff_admins').orderBy('name').snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final docs = snapshot.data!.docs;

          if (docs.isEmpty) return const Center(child: Text("No staff found"));

          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            itemCount: docs.length,
            itemBuilder: (context, i) {
              final data = docs[i].data() as Map<String, dynamic>;
              final role = data['role'] ?? 'Admin';

              return Card(
                elevation: 0, margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.grey.shade200)
                ),
                child: ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 18,
                    backgroundColor: (role == 'Super Admin' ? Colors.orange : const Color(0xFF1E3A8A)).withOpacity(0.1),
                    child: Text(data['name'][0].toUpperCase(),
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: role == 'Super Admin' ? Colors.orange : const Color(0xFF1E3A8A))),
                  ),
                  title: Text(data['name'].toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  subtitle: Text("${data['phone']} • $role", style: const TextStyle(fontSize: 11)),
                  trailing: isSuper ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(icon: const Icon(Icons.edit, size: 18, color: Colors.blue), onPressed: () => _showStaffForm(docId: docs[i].id, existingData: data)),
                      IconButton(icon: const Icon(Icons.delete, size: 18, color: Colors.redAccent), onPressed: () => _confirmDelete(docs[i].id, data['name'])),
                    ],
                  ) : null,
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: isSuper ? FloatingActionButton(
        onPressed: () => _showStaffForm(),
        backgroundColor: const Color(0xFF1E3A8A),
        child: const Icon(Icons.add, color: Colors.white),
      ) : null,
    );
  }

  void _confirmDelete(String id, String name) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("Delete?", style: TextStyle(fontSize: 16)),
        content: Text("Permanently remove $name?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("No")),
          TextButton(onPressed: () {
            FirebaseFirestore.instance.collection('staff_admins').doc(id).delete();
            Navigator.pop(c);
            _showMessage("Staff removed");
          }, child: const Text("Yes", style: TextStyle(color: Colors.red))),
        ],
      ),
    );
  }
}