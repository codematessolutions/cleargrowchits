import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../SchemeDetailScreen.dart';

class AddMemberDialog extends StatefulWidget {
  final String schemeId;
  final String schemeName;
  final String kuriId;
  final String kuriName;
  final String userId;
  final String userName;
  const AddMemberDialog({super.key, required this.schemeId,required this.schemeName, required this.kuriId, required this.kuriName,required this.userId,required this.userName});
  @override State<AddMemberDialog> createState() => _AddMemberDialogState();
}

class _AddMemberDialogState extends State<AddMemberDialog> {
  final _n = TextEditingController();
  final _p = TextEditingController();
  final _pl = TextEditingController();
  final _kn = TextEditingController(); // NEW: Kuri Number Controller
  String? _selectedCareOf;

  @override
  Widget build(BuildContext context) {
    // Local GlobalKey for validation
    final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 550, // Comfortable web width
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 30, offset: const Offset(0, 15))
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 32),
              decoration: const BoxDecoration(
                color: Color(0xFFF8FAFC),
                borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
                border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
              ),
              child: const Row(
                children: [
                  Icon(Icons.person_add_alt_1_rounded, color: Color(0xFF6366F1), size: 28),
                  SizedBox(width: 16),
                  Text(
                    "Enroll New Member",
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF1E293B)),
                  ),
                ],
              ),
            ),

            // Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(32),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("PERSONAL INFORMATION",
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Color(0xFF94A3B8), letterSpacing: 1.2)),
                      const SizedBox(height: 20),

                      // Kuri Number & Name Row
                      Row(
                        children: [
                          Expanded(flex: 1, child: _webInput(_kn, "Kuri No.", Icons.pin, isNum: true)),
                          const SizedBox(width: 16),
                          Expanded(flex: 2, child: _webInput(_n, "Full Name", Icons.badge_outlined)),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Phone & Place Row
                      Row(
                        children: [
                          Expanded(child: _webInput(_p, "Phone Number", Icons.phone_android, isNum: true)),
                          const SizedBox(width: 16),
                          Expanded(child: _webInput(_pl, "Place", Icons.location_on_outlined)),
                        ],
                      ),
                      const SizedBox(height: 24),

                      const Text("ADMINISTRATIVE",
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Color(0xFF94A3B8), letterSpacing: 1.2)),
                      const SizedBox(height: 16),

                      // Care Of Stream Dropdown
                      StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance.collection('staff_admins').orderBy('name').snapshots(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) return const LinearProgressIndicator(color: Color(0xFF6366F1));

                          return DropdownButtonFormField<String>(
                            value: _selectedCareOf,
                            decoration: _inputDeco("Care Of", Icons.support_agent),
                            validator: (v) => v == null ? "Required" : null,
                            items: snapshot.data!.docs.map((doc) => DropdownMenuItem(
                                value: doc['name'].toString(),
                                child: Text(doc['name'], style: const TextStyle(fontSize: 14))
                            )).toList(),
                            onChanged: (v) => setState(() => _selectedCareOf = v),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Actions
            Container(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 32),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text("Discard", style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6366F1),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    // onPressed: () async {
                    //   // Use a Batch for high performance (Max 500 operations per batch)
                    //   final WriteBatch batch = FirebaseFirestore.instance.batch();
                    //   final collection = FirebaseFirestore.instance.collection('members');
                    //
                    //   final List<String> firstNames = ["Rahul", "Anas", "Sajid", "Deepak", "Vinu", "Arun", "Sree", "Nithin"];
                    //   final List<String> surNames = ["K", "P", "M", "V", "C", "T", "S", "R"];
                    //   final List<String> locations = ["MANJERI", "MALAPPURAM", "CALICUT", "NILAMBUR", "PERINTHALMANNA"];
                    //
                    //   // Show a loading indicator if you have one
                    //   // EasyLoading.show(status: 'Adding 400 test members...');
                    //
                    //   for (int i = 1; i <= 400; i++) {
                    //     final docRef = collection.doc(); // Generate a new ID
                    //
                    //     // Pick random data based on index
                    //     String name = "${firstNames[i % firstNames.length]} ${surNames[i % surNames.length]} $i";
                    //     String place = locations[i % locations.length];
                    //
                    //     batch.set(docRef, {
                    //       'memberId': docRef.id,
                    //       'schemeId': widget.schemeId,
                    //       'schemeName': widget.schemeName,
                    //       'kuriId': widget.kuriId,
                    //       'kuriName': widget.kuriName,
                    //       'kuriNumber': i, // Numeric string for sorting tests
                    //       'name': name.toUpperCase(),
                    //       'phone': "9847${i.toString().padLeft(6, '0')}", // Unique phone numbers
                    //       'place': place,
                    //       'careOf': "Self",
                    //       'addedById': widget.userId,
                    //       'addedByName': widget.userName,
                    //       'isTestData': true, // Helpful to delete them later in one go
                    //     });
                    //   }
                    //
                    //   // Submit all 400 at once
                    //   await batch.commit();
                    //
                    //   // EasyLoading.dismiss();
                    //   Navigator.pop(context);
                    // },


                    onPressed: () async {

                      if (_formKey.currentState!.validate()) {
                        // Logic kept exactly same
                        final docRef = FirebaseFirestore.instance.collection('members').doc();
                        await docRef.set({
                          'memberId': docRef.id,
                          'schemeId': widget.schemeId,
                          'schemeName': widget.schemeName,
                          'kuriId': widget.kuriId,
                          'kuriName': widget.kuriName,
                          'kuriNumber': _kn.text,
                          'name': _n.text.toUpperCase(),
                          'phone': _p.text,
                          'place': _pl.text.toUpperCase(),
                          'careOf': _selectedCareOf,
                          'addedById': widget.userId,
                          'addedByName': widget.userName
                        });
                        Navigator.pop(context);
                      }
                    },
                    child: const Text("SAVE MEMBER", style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                  )
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

// Helper for UI consistency
  Widget _webInput(TextEditingController ctrl, String label, IconData icon, {bool isNum = false}) {
    return TextFormField(
      controller: ctrl,
      keyboardType: isNum ? TextInputType.number : TextInputType.text,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      validator: (v) => (v == null || v.isEmpty) ? "Required" : null,
      decoration: _inputDeco(label, icon),
    );
  }

  InputDecoration _inputDeco(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 20, color: const Color(0xFF94A3B8)),
      labelStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF6366F1), width: 2)),
      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
    );
  }
}

class MarkPaymentDialog extends StatefulWidget {
  final String memberName;
  final double fullAmount;
  final List<String> adminList;
  final Function(List<Map<String, dynamic>> splits, DateTime date) onConfirm;

  const MarkPaymentDialog({
    super.key,
    required this.memberName,
    required this.fullAmount,
    required this.adminList,
    required this.onConfirm,
  });

  @override
  State<MarkPaymentDialog> createState() => _MarkPaymentDialogState();
}

class _MarkPaymentDialogState extends State<MarkPaymentDialog> {
  List<Map<String, dynamic>> splits = [
    {
      "mode": "Cash",
      "amount": 0.0,
      "collector": null,
      "date": DateTime.now() // Individual date per split
    }
  ];

  double get totalEntered => splits.fold(0.0, (sum, item) => sum + (item['amount'] as double));

  @override
  Widget build(BuildContext context) {
    bool isTotalMatched = totalEntered.toInt() == widget.fullAmount.toInt();
    bool areFieldsFilled = !splits.any((s) => s['collector'] == null || s['amount'] <= 0);
    bool isComplete = isTotalMatched && areFieldsFilled;

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 750, // Wider for 4-column layout
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                const Icon(Icons.receipt_long, color: Color(0xFF1E3A8A), size: 28),
                const SizedBox(width: 12),
                Text(widget.memberName.toUpperCase(),
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Color(0xFF1E3A8A))),
                const Spacer(),
                Text("DUE: ₹${widget.fullAmount.toInt()}",
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.grey)),
              ],
            ),
            const Divider(height: 32),

            // Split Headers
            const Padding(
              padding: EdgeInsets.only(bottom: 8, left: 4),
              child: Row(
                children: [
                  SizedBox(width: 130, child: Text("DATE", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold))),
                  SizedBox(width: 110, child: Text("AMOUNT", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold))),
                  Expanded(child: Text("MODE", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold))),
                  SizedBox(width: 10),
                  Expanded(child: Text("COLLECTOR", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold))),
                  SizedBox(width: 40),
                ],
              ),
            ),

            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: splits.asMap().entries.map((entry) => _buildSplitRow(entry.key)).toList(),
                ),
              ),
            ),

            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () => setState(() => splits.add({
                "mode": "Cash", "amount": 0.0, "collector": null, "date": DateTime.now()
              })),
              icon: const Icon(Icons.add_circle_outline),
              label: const Text("ADD ANOTHER DATE / SPLIT"),
            ),

            const SizedBox(height: 24),
            // Summary Bar
            _buildSummaryBar(isTotalMatched),

            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCEL")),
                const SizedBox(width: 12),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E3A8A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  ),
                  onPressed: isComplete ? () async {
                    // 1. Wait for the Firestore save to finish
                    await widget.onConfirm(splits, splits.first['date']);

                    // 2. Only pop ONCE
                    if (context.mounted) {
                      Navigator.of(context).pop();
                    }
                  } : null,
                  child: const Text("CONFIRM PAYMENT"),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSplitRow(int index) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. DATE PICKER
          SizedBox(
            width: 130,
            child: InkWell(
              onTap: () async {
                DateTime? p = await showDatePicker(
                  context: context,
                  initialDate: splits[index]['date'],
                  firstDate: DateTime(2024),
                  lastDate: DateTime.now(),
                );
                if (p != null) setState(() => splits[index]['date'] = p);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today, size: 14, color: Colors.blue),
                    const SizedBox(width: 8),
                    Text(DateFormat('dd-MM-yy').format(splits[index]['date']),
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // 2. AMOUNT
          SizedBox(
            width: 110,
            child: TextFormField(
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(prefixText: "₹", isDense: true, border: OutlineInputBorder()),
              onChanged: (v) => setState(() => splits[index]['amount'] = double.tryParse(v) ?? 0.0),
            ),
          ),
          const SizedBox(width: 8),
          // 3. MODE
          Expanded(
            child: DropdownButtonFormField<String>(
              value: splits[index]['mode'],
              isDense: true,
              decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.all(10)),
              items: ["Cash", "GPay", "Bank", "Cheque"].map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 13)))).toList(),
              onChanged: (v) => setState(() => splits[index]['mode'] = v),
            ),
          ),
          const SizedBox(width: 8),
          // 4. COLLECTOR
          Expanded(
            child: DropdownButtonFormField<String>(
              value: splits[index]['collector'],
              isDense: true,
              decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.all(10)),
              items: widget.adminList.map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 13)))).toList(),
              onChanged: (v) => setState(() => splits[index]['collector'] = v),
            ),
          ),
          // DELETE
          SizedBox(
            width: 40,
            child: splits.length > 1
                ? IconButton(onPressed: () => setState(() => splits.removeAt(index)), icon: const Icon(Icons.delete_outline, color: Colors.red))
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryBar(bool isMatch) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isMatch ? Colors.green.shade50 : Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isMatch ? Colors.green.shade200 : Colors.red.shade200),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text("TOTAL COLLECTED: ₹${totalEntered.toInt()}",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isMatch ? Colors.green.shade900 : Colors.red.shade900)),
          if (!isMatch)
            Text("WAITING FOR ₹${(widget.fullAmount - totalEntered).toInt()}",
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
        ],
      ),
    );
  }
}
Widget buildFunnyLoader() {
  final messages = [
    "Counting your members... 🏃‍♂️",
    "Fetching first 20 records... ✨",
    "Polishing the table... 🪄",
    "Almost there! Hang tight... 🧐",
  ];

  return StreamBuilder<int>(
    stream: Stream.periodic(const Duration(seconds: 2), (i) => i % messages.length),
    builder: (context, snapshot) {
      int index = snapshot.data ?? 0;
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: SchemeTheme.primaryBlue),
            const SizedBox(height: 20),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 500),
              child: Text(messages[index], key: ValueKey(index),
                  style: const TextStyle(color: SchemeTheme.primaryBlue, fontStyle: FontStyle.italic, fontWeight: FontWeight.w500)),
            ),
          ],
        ),
      );
    },
  );
}