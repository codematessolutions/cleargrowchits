import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class MasterMemberScreen extends StatefulWidget {
  final String userId;
  final String userName;
  final String userRole;

  const MasterMemberScreen({
    super.key,
    required this.userId,
    required this.userName,
    required this.userRole,
  });

  @override
  State<MasterMemberScreen> createState() => _MasterMemberScreenState();
}

class _MasterMemberScreenState extends State<MasterMemberScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text("MASTER MEMBER DIRECTORY",
            style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1)),
        backgroundColor: const Color(0xFF1E3A8A),
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: ElevatedButton.icon(
              onPressed: () => _showAddMasterMemberDialog(context),
              icon: const Icon(Icons.person_add, size: 18),
              label: const Text("REGISTER NEW MEMBER"),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, foregroundColor: Colors.white),
            ),
          )
        ],
      ),
      body: Column(
        children: [
          _buildWebStatsHeader(),
          _buildWebFilterBar(),
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: _buildWebDataTable(),
            ),
          ),
        ],
      ),
    );
  }

  // --- WEB STATS HEADER (Full Width Ribbon) ---
  Widget _buildWebStatsHeader() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('master_members').snapshots(),
      builder: (context, snapshot) {
        int count = snapshot.hasData ? snapshot.data!.docs.length : 0;
        return Container(
          height: 80,
          padding: const EdgeInsets.symmetric(horizontal: 30),
          color: const Color(0xFF1E3A8A),
          child: Row(
            children: [
              _webStatItem("TOTAL DIRECTORY", count.toString(), Icons.badge),
              _webVDivider(),
              _webStatItem("ACTIVE ACCOUNTS", count.toString(), Icons.verified),
              _webVDivider(),
              _webStatItem("SYSTEM ROLE", widget.userRole.toUpperCase(), Icons.security),
            ],
          ),
        );
      },
    );
  }

  Widget _webStatItem(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: Colors.white30, size: 28),
        const SizedBox(width: 15),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Colors.white60, fontSize: 10, fontWeight: FontWeight.bold)),
            Text(value, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
          ],
        ),
        const SizedBox(width: 40),
      ],
    );
  }

  Widget _webVDivider() => Container(width: 1, height: 40, color: Colors.white10, margin: const EdgeInsets.only(right: 40));

  // --- COMPACT FILTER BAR ---
  Widget _buildWebFilterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      color: Colors.white,
      child: Row(
        children: [
          const Text("Search Members:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(width: 15),
          SizedBox(
            width: 400,
            height: 40,
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _searchQuery = v.trim().toLowerCase()),
              decoration: InputDecoration(
                hintText: "Enter Name or Mobile Number...",
                prefixIcon: const Icon(Icons.search, size: 18),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                filled: true,
                fillColor: const Color(0xFFF1F5F9),
              ),
            ),
          ),
          const Spacer(),
          TextButton.icon(onPressed: () {}, icon: const Icon(Icons.filter_list), label: const Text("Advanced Filter")),
          const SizedBox(width: 10),
          IconButton(onPressed: () => setState(() {}), icon: const Icon(Icons.refresh)),
        ],
      ),
    );
  }

  // --- COMPACT WEB DATA TABLE ---
  Widget _buildWebDataTable() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('master_members').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        var docs = snapshot.data!.docs.where((doc) {
          var name = (doc['name'] ?? "").toString().toLowerCase();
          var phone = (doc['phone'] ?? "").toString();
          return name.contains(_searchQuery) || phone.contains(_searchQuery);
        }).toList();

        return SizedBox(
          width: double.infinity,
          child: SingleChildScrollView(
            child: DataTable(
              headingRowHeight: 45,
              dataRowMaxHeight: 50,
              headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
              columns: const [
                DataColumn(label: Text("MEMBER NAME", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                DataColumn(label: Text("PHONE", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                DataColumn(label: Text("PLACE", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                DataColumn(label: Text("CARE OF (STAFF)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                DataColumn(label: Text("CREATED ON", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                DataColumn(label: Text("ACTIONS", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
              ],
              rows: docs.map((doc) {
                var data = doc.data() as Map<String, dynamic>;
                return DataRow(
                  cells: [
                    DataCell(Text(data['name'].toString().toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
                    DataCell(Text(data['phone'] ?? "-")),
                    DataCell(Text(data['place'] ?? "-")),
                    DataCell(Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(4)),
                      child: Text(data['careOfStaff'] ?? "Unassigned", style: TextStyle(color: Colors.blue.shade900, fontSize: 11, fontWeight: FontWeight.bold)),
                    )),
                    DataCell(Text(data['createdAt'] != null ? (data['createdAt'] as Timestamp).toDate().toString().split(' ')[0] : "-")),
                    DataCell(Row(
                      children: [
                        IconButton(icon: const Icon(Icons.edit, size: 16, color: Colors.grey), onPressed: () {}),
                        IconButton(icon: const Icon(Icons.history, size: 16, color: Colors.blue), onPressed: () {}),
                      ],
                    )),
                  ],
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  // --- DIALOG FOR REGISTERING (Kept similar but cleaned for Web) ---
  void _showAddMasterMemberDialog(BuildContext context) async {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final placeController = TextEditingController();

    var staffSnap = await FirebaseFirestore.instance.collection('staff_admins').get();
    List<String> staffNames = staffSnap.docs.map((doc) => doc['name'].toString()).toList();
    String? selectedStaff = staffNames.isNotEmpty ? staffNames[0] : null;

    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text("Master Registration"),
              content: SizedBox(
                width: 400, // Fixed width for web feel
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(controller: nameController, decoration: const InputDecoration(labelText: "Full Name")),
                    TextField(controller: phoneController, decoration: const InputDecoration(labelText: "Phone Number")),
                    TextField(controller: placeController, decoration: const InputDecoration(labelText: "Place")),
                    const SizedBox(height: 15),
                    DropdownButtonFormField<String>(
                      value: selectedStaff,
                      decoration: const InputDecoration(labelText: "Assigned Staff (C/O)"),
                      items: staffNames.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                      onChanged: (v) => setDialogState(() => selectedStaff = v),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
                ElevatedButton(
                  onPressed: () async {
                    await FirebaseFirestore.instance.collection('master_members').add({
                      'name': nameController.text.trim().toUpperCase(),
                      'phone': phoneController.text.trim(),
                      'place': placeController.text.trim(),
                      'careOfStaff': selectedStaff,
                      'createdAt': FieldValue.serverTimestamp(),
                    });
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: const Text("Save Member"),
                )
              ],
            );
          }
      ),
    );
  }
}