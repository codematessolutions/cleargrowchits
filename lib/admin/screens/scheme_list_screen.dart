import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'SchemeDetailScreen.dart';

// --- THEME ---
class SchemeTheme {
  static const Color primaryBlue = Color(0xFF1E3A8A);
  static const Color softBlueBg = Color(0xFFF8FAFC);
  static const Color borderGrey = Color(0xFFCBD5E1);
}

class SchemeListScreen extends StatefulWidget {
  final String kuriId;
  final String kuriName;
  final String userId;
  final String userName;
  final String userRole;
  final Map<String, dynamic> kuriData;

  const SchemeListScreen({
    super.key,
    required this.kuriId,
    required this.kuriName,
    required this.kuriData,
    required this.userId,
    required this.userName,
    required this.userRole,
  });

  @override
  State<SchemeListScreen> createState() => _SchemeListScreenState();
}

class _SchemeListScreenState extends State<SchemeListScreen> {
  String searchQuery = "";

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: "₹", decimalDigits: 0, locale: "en_IN");

    return Scaffold(
      backgroundColor: SchemeTheme.softBlueBg,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: SchemeTheme.primaryBlue,
        centerTitle: true,
        title: Text(widget.kuriName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: Column(
        children: [
          _buildRibbon(currency),

          // Search Bar
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              onChanged: (v) => setState(() => searchQuery = v.toLowerCase()),
              decoration: InputDecoration(
                hintText: "Search schemes...",
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),

          // FULL WIDTH DATA TABLE WITH ALL FIELDS
          Expanded(
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15)],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: _buildSchemeListStream(),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddSchemeDialog(context,widget.userId,widget.userName,widget.userRole),
        backgroundColor: SchemeTheme.primaryBlue,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text("ADD SCHEME", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }

  // UPDATED TABLE: SHOWING ALL DATABASE FIELDS
  Widget _buildSchemeListStream() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('schemes')
          .where('kuriId', isEqualTo: widget.kuriId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: Color(0xFF6366F1)));

        var docs = snapshot.data!.docs;
        if (searchQuery.isNotEmpty) {
          docs = docs.where((d) => d['schemeName'].toString().toLowerCase().contains(searchQuery.toLowerCase())).toList();
        }

        if (docs.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(40.0),
              child: Text("No schemes found matching '$searchQuery'", style: const TextStyle(color: Color(0xFF64748B))),
            ),
          );
        }

        return LayoutBuilder(builder: (context, constraints) {
          return SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: Container(
                  margin: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 20, offset: const Offset(0, 10))
                    ],
                  ),
                  child: DataTable(
                    // Web-optimized styling
                    headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
                    headingRowHeight: 60,
                    dataRowMaxHeight: 75,
                    horizontalMargin: 24,
                    columnSpacing: 32,
                    showCheckboxColumn: false,
                    dividerThickness: 1,
                    columns: [
                      DataColumn(label: _headerText("SCHEME NAME")),
                      DataColumn(label: _headerText("START DATE")),
                      DataColumn(label: _headerText("END DATE")),
                      DataColumn(label: _headerText("DURATION")),
                      DataColumn(label: _headerText("MONTHLY")),
                      DataColumn(label: _headerText("MOOP")),
                      DataColumn(label: _headerText("PAYOUT AMOUNT")),
                    ],
                    rows: docs.map((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      String format(dynamic d) => DateFormat('MMM yyyy').format((d as Timestamp).toDate());
                      final currency = NumberFormat.currency(symbol: "₹", decimalDigits: 0, locale: "en_IN");

                      return DataRow(
                        onLongPress: () => _confirmDelete(doc.id),
                        onSelectChanged: (selected) {
                          if (selected != null && selected) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => SchemeDetailScreen(
                                  schemeId: doc.id,
                                  schemeData: data,
                                  kuriData: widget.kuriData,
                                  userId: widget.userId,
                                  userName: widget.userName,
                                  userRole: widget.userRole,
                                ),
                              ),
                            );
                          }
                        },
                        cells: [
                          // SCHEME NAME
                          DataCell(Text(
                            data['schemeName'].toString().toUpperCase(),
                            style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF1E293B), fontSize: 13, letterSpacing: 0.5),
                          )),
                          // START
                          DataCell(Text(format(data['startMonth']), style: const TextStyle(color: Color(0xFF475569)))),
                          // END
                          DataCell(Text(
                            format(data['endMonth']),
                            style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF6366F1)),
                          )),
                          // DUR
                          DataCell(Text("${data['totalMonths']} Months", style: const TextStyle(fontWeight: FontWeight.w500))),
                          // MONTHLY
                          DataCell(Text(currency.format(data['monthlyAmount']), style: const TextStyle(fontWeight: FontWeight.w500))),
                          // MOOP
                          DataCell(Text(
                            currency.format(data['moop']),
                            style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
                          )),
                          // PAYOUT (Pill Design)
                          DataCell(Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF0FDF4),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFF10B981).withOpacity(0.2)),
                            ),
                            child: Text(
                              currency.format(data['memberFinalAmount']),
                              style: const TextStyle(color: Color(0xFF15803D), fontWeight: FontWeight.w900, fontSize: 13),
                            ),
                          )),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          );
        });
      },
    );
  }

// Updated Header text helper for consistent web typography
  Widget _headerText(String label) {
    return Text(
      label,
      style: const TextStyle(
        fontWeight: FontWeight.w800,
        color: Color(0xFF64748B),
        fontSize: 11,
        letterSpacing: 1.2,
      ),
    );
  }
  Widget _buildRibbon(NumberFormat currency) {
    final end = (widget.kuriData['endMonth'] as Timestamp).toDate();
    final start = (widget.kuriData['startMonth'] as Timestamp).toDate();
    return Container(
      width: double.infinity,
      color: SchemeTheme.primaryBlue,
      padding: const EdgeInsets.only(bottom: 20),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            _ribbonTile("MONTHLY", currency.format(widget.kuriData['monthlyAmount'] ?? 0), Icons.payments),
            _ribbonTile("TOTAL AMOUNT", currency.format(widget.kuriData['totalAmount'] ?? 0), Icons.account_balance),
            _ribbonTile("DRAW DATE", "${widget.kuriData['kuriDate']}th", Icons.event),
            _ribbonTile("START DATE", DateFormat('MMM yyyy').format(start), Icons.flag),
            _ribbonTile("END DATE", DateFormat('MMM yyyy').format(end), Icons.flag),
            _ribbonTile("TOTAL MONTHS", "${widget.kuriData['totalMonths']}", Icons.calendar_month),          ],
        ),
      ),
    );
  }

  Widget _ribbonTile(String label, String value, IconData icon) {
    return Container(
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [Icon(icon, size: 12, color: Colors.white70), const SizedBox(width: 4), Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10))]),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
        ],
      ),
    );
  }

  void _confirmDelete(String id) {
    showDialog(context: context, builder: (c) => AlertDialog(
      title: const Text("Delete Scheme?"),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text("Cancel")),
        TextButton(onPressed: () { FirebaseFirestore.instance.collection('schemes').doc(id).delete(); Navigator.pop(c); }, child: const Text("Delete", style: TextStyle(color: Colors.red))),
      ],
    ));
  }

  void _showAddSchemeDialog(BuildContext context,String userId,String userName,String userRole) {
    showDialog(context: context, barrierDismissible: false, builder: (c) => AddSchemeDialog(kuriId: widget.kuriId, kuriName: widget.kuriName, kuriData: widget.kuriData, userId: userId, userName: userName, userRole: userRole,));
  }
}

// --- MEDIUM ADD SCHEME DIALOG ---
class AddSchemeDialog extends StatefulWidget {
  final String kuriId;
  final String kuriName;
  final String userId;
  final String userName;
  final String userRole;
  final Map<String, dynamic> kuriData;
  const AddSchemeDialog({super.key, required this.kuriId, required this.kuriName, required this.kuriData,required this.userId,required this.userName, required this.userRole});

  @override
  State<AddSchemeDialog> createState() => _AddSchemeDialogState();
}

class _AddSchemeDialogState extends State<AddSchemeDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _amtCtrl = TextEditingController();
  final _moopCtrl = TextEditingController();
  final _monthCountCtrl = TextEditingController();
  DateTime? _start;
  DateTime? _end;

  bool get _isInitialFilled => _nameCtrl.text.trim().isNotEmpty && _amtCtrl.text.isNotEmpty && _moopCtrl.text.isNotEmpty;

  void _calculateDuration() {
    if (_start == null) return;
    DateTime kuriEnd = (widget.kuriData['endMonth'] as Timestamp).toDate();
    int duration = ((kuriEnd.year - _start!.year) * 12) + kuriEnd.month - _start!.month + 1;
    setState(() {
      _monthCountCtrl.text = duration.toString();
      _end = kuriEnd;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Logic remains exactly as provided
    double monthly = double.tryParse(_amtCtrl.text) ?? 0;
    int duration = int.tryParse(_monthCountCtrl.text) ?? 0;
    double moop = double.tryParse(_moopCtrl.text) ?? 0;
    double payout = (monthly * duration) - moop;
    final currency = NumberFormat.currency(symbol: "₹", decimalDigits: 0, locale: "en_IN");

    return Dialog(
      backgroundColor: Colors.transparent, // Allows us to use our own Container styling
      child: Container(
        width: 500, // Wider for web comfort
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 40,
              offset: const Offset(0, 20),
            )
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header Section
            Container(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 32),
              decoration: const BoxDecoration(
                color: Color(0xFFF8FAFC), // Modern slate background
                borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
                border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: SchemeTheme.primaryBlue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.add_chart_rounded, color: SchemeTheme.primaryBlue, size: 24),
                  ),
                  const SizedBox(width: 16),
                  const Text(
                    "Create New Scheme",
                    style: TextStyle(color: Color(0xFF1E293B), fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),

            // Content Section
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(32),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("SCHEME DETAILS", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Color(0xFF94A3B8), letterSpacing: 1.2)),
                      const SizedBox(height: 16),
                      _modernInp(_nameCtrl, "Scheme Name", Icons.badge_outlined),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(child: _modernInp(_amtCtrl, "Monthly Amount", Icons.payments_outlined, isNum: true)),
                          const SizedBox(width: 16),
                          Expanded(child: _modernInp(_moopCtrl, "Moop (Comm.)", Icons.cut_outlined, isNum: true)),
                        ],
                      ),
                      const Divider(height: 48, color: Color(0xFFF1F5F9)),
                      const Text("TIMELINE & DURATION", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Color(0xFF94A3B8), letterSpacing: 1.2)),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(child: _dateButton()),
                          const SizedBox(width: 16),
                          Expanded(child: _modernInp(_monthCountCtrl, "Total Duration", Icons.timer_outlined, enabled: false)),
                        ],
                      ),
                      const SizedBox(height: 32),

                      // Calculation Box (Modern Web Card)
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9), // Light blueish slate
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          children: [
                            _sumLine("Gross Value", currency.format(monthly * duration), const Color(0xFF64748B)),
                            const SizedBox(height: 8),
                            _sumLine("Commission Deduction", "- ${currency.format(moop)}", Colors.orange.shade700),
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Divider(height: 1, color: Color(0xFFCBD5E1)),
                            ),
                            _sumLine("Net Payout Amount", currency.format(payout), const Color(0xFF059669), isBold: true, isLarge: true),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Actions Section
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
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      foregroundColor: const Color(0xFF64748B),
                    ),
                    child: const Text("Discard Changes", style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: SchemeTheme.primaryBlue,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(0xFFE2E8F0),
                      disabledForegroundColor: const Color(0xFF94A3B8),
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: (_isInitialFilled && _start != null)
                        ? () => _save(widget.userId, widget.userName, widget.userRole)
                        : null,
                    child: const Text("CREATE SCHEME", style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                  )
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  Widget _sumLine(String label, String value, Color color, {bool isBold = false, bool isLarge = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: const Color(0xFF64748B), // Neutral slate
            fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
            fontSize: isLarge ? 14 : 13,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontWeight: isBold || isLarge ? FontWeight.w900 : FontWeight.w700,
            fontSize: isLarge ? 18 : 14, // Makes the final payout stand out
          ),
        ),
      ],
    );
  }
  Widget _modernInp(TextEditingController c, String l, IconData i, {bool isNum = false, bool enabled = true}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: c,
        enabled: enabled,
        keyboardType: isNum ? TextInputType.number : TextInputType.text,
        onChanged: (v) => setState(() {}),
        decoration: InputDecoration(
          labelText: l,
          prefixIcon: Icon(i, color: SchemeTheme.primaryBlue, size: 20),
          filled: true,
          fillColor: enabled ? Colors.white : const Color(0xFFF1F5F9),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: SchemeTheme.borderGrey)),
        ),
      ),
    );
  }

  Widget _dateButton() {
    bool active = _isInitialFilled;
    return InkWell(
      onTap: !active ? null : () async {
        DateTime kEnd = (widget.kuriData['endMonth'] as Timestamp).toDate();
        DateTime now = DateTime.now();
        DateTime first = now.day > (widget.kuriData['kuriDate'] ?? 0) ? DateTime(now.year, now.month + 1) : DateTime(now.year, now.month);
        final p = await showDatePicker(context: context, initialDate: first, firstDate: DateTime(2020), lastDate: kEnd);
        if (p != null) {
          setState(() => _start = p);
          _calculateDuration();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color: active ? Colors.white : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: active ? SchemeTheme.primaryBlue : SchemeTheme.borderGrey),
        ),
        child: Row(children: [
          Icon(Icons.calendar_month, color: active ? SchemeTheme.primaryBlue : Colors.grey, size: 20),
          const SizedBox(width: 12),
          Text(_start == null ? "Select Start Date" : DateFormat('MMM yyyy').format(_start!),
              style: TextStyle(color: active ? Colors.black : Colors.grey, fontWeight: FontWeight.bold)),
        ]),
      ),
    );
  }



  void _save(String userId,userName ,String userRole ) async {
    if (_formKey.currentState!.validate() && _start != null) {
      await FirebaseFirestore.instance.collection('schemes').add({
        'kuriId': widget.kuriId,
        'kuriName': widget.kuriName,
        'schemeName': _nameCtrl.text.trim(),
        'monthlyAmount': double.parse(_amtCtrl.text),
        'moop': double.parse(_moopCtrl.text),
        'startMonth': Timestamp.fromDate(_start!),
        'endMonth': Timestamp.fromDate(_end!),
        'totalMonths': int.parse(_monthCountCtrl.text),
        'memberFinalAmount': (double.parse(_amtCtrl.text) * int.parse(_monthCountCtrl.text)) - double.parse(_moopCtrl.text),
        'createdAt': FieldValue.serverTimestamp(),
        "addedById": userId,
        "addedByName": userName,
        "userRole": userRole,
      });
      if (mounted) Navigator.pop(context);
    }
  }
}