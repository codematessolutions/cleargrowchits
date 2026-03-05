import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'dart:async';

class CompanyGlobalAuditWeb extends StatefulWidget {
  final String userName;
  const CompanyGlobalAuditWeb({super.key, required this.userName});

  @override
  State<CompanyGlobalAuditWeb> createState() => _CompanyGlobalAuditWebState();
}

class _CompanyGlobalAuditWebState extends State<CompanyGlobalAuditWeb> {
  DateTime selectedDate = DateTime(DateTime.now().year, DateTime.now().month);
  bool isYearlyView = false;
  final uiFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

  Stream<Map<String, List<QueryDocumentSnapshot>>> _getGlobalData() {
    DateTime start;
    DateTime end;

    if (isYearlyView) {
      start = DateTime(selectedDate.year, 1, 1, 0, 0, 0);
      end = DateTime(selectedDate.year, 12, 31, 23, 59, 59);
    } else {
      start = DateTime(selectedDate.year, selectedDate.month, 1, 0, 0, 0);
      end = DateTime(selectedDate.year, selectedDate.month + 1, 0, 23, 59, 59);
    }

    // FIX: Using 'paidDate' to match your Firestore structure shown in screenshots
    Query paymentQuery = FirebaseFirestore.instance.collection('payments')
        .where('paidDate', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('paidDate', isLessThanOrEqualTo: Timestamp.fromDate(end));

    // Expenses typically use 'date', but ensure this matches your expenses collection
    Query expenseQuery = FirebaseFirestore.instance.collection('expenses')
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('date', isLessThanOrEqualTo: Timestamp.fromDate(end));

    Stream<QuerySnapshot> staffStream = FirebaseFirestore.instance.collection('staff_admins').snapshots();

    return StreamZipCustom([paymentQuery.snapshots(), expenseQuery.snapshots(), staffStream]).map((list) {
      return {
        'payments': list[0].docs,
        'expenses': list[1].docs,
        'staff': list[2].docs,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: Text(isYearlyView ? "ANNUAL GLOBAL AUDIT ${selectedDate.year}" : "MONTHLY GLOBAL AUDIT"),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        actions: [
          _buildViewToggle(),
          const VerticalDivider(color: Colors.white24, indent: 10, endIndent: 10),
          _buildDateSelector(),
          const SizedBox(width: 20),
        ],
      ),
      body: StreamBuilder<Map<String, List<QueryDocumentSnapshot>>>(
        stream: _getGlobalData(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text("Error: Check Indices. ${snapshot.error}"));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          final payments = snapshot.data!['payments']!;
          final expenses = snapshot.data!['expenses']!;
          final staffList = snapshot.data!['staff']!;

          Map<String, Map<String, dynamic>> auditData = {};
          for (var s in staffList) {
            final data = s.data() as Map<String, dynamic>;
            auditData[s.id] = {"name": data['name'] ?? "Unknown", "cash": 0.0, "gpay": 0.0, "exp": 0.0};
          }

          for (var doc in payments) {
            final data = doc.data() as Map<String, dynamic>;
            final splits = data['paymentSplits'] as List? ?? [];
            for (var s in splits) {
              String id = s['collectorId'] ?? "";
              double amt = double.tryParse(s['amount'].toString()) ?? 0.0;
              // 'mode' is checked here to separate Cash vs GPay totals
              String mode = s['mode'] ?? "Cash";

              if (auditData.containsKey(id)) {
                if (mode == "GPay") {
                  auditData[id]!["gpay"] += amt;
                } else {
                  auditData[id]!["cash"] += amt;
                }
              }
            }
          }

          for (var doc in expenses) {
            final data = doc.data() as Map<String, dynamic>;
            String staffName = data['staffName'] ?? "";
            double amt = double.tryParse(data['amount'].toString()) ?? 0.0;
            auditData.forEach((id, val) {
              if (val['name'] == staffName) val['exp'] += amt;
            });
          }

          return _buildUI(auditData);
        },
      ),
    );
  }

  Widget _buildViewToggle() {
    return Row(
      children: [
        const Text("MONTH", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
        Switch(
          value: isYearlyView,
          onChanged: (v) => setState(() => isYearlyView = v),
          activeColor: Colors.amber,
        ),
        const Text("YEAR", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
        const SizedBox(width: 10),
      ],
    );
  }

  Widget _buildDateSelector() {
    String label = isYearlyView ? "${selectedDate.year}" : DateFormat('MMM yyyy').format(selectedDate);
    return Row(
      children: [
        IconButton(icon: const Icon(Icons.chevron_left, color: Colors.white), onPressed: () => _adjustDate(-1)),
        Text(label.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        IconButton(icon: const Icon(Icons.chevron_right, color: Colors.white), onPressed: () => _adjustDate(1)),
      ],
    );
  }

  void _adjustDate(int offset) {
    setState(() {
      selectedDate = isYearlyView
          ? DateTime(selectedDate.year + offset, 1)
          : DateTime(selectedDate.year, selectedDate.month + offset);
    });
  }

  Widget _buildUI(Map<String, Map<String, dynamic>> data) {
    double tin = 0; double tout = 0;
    data.forEach((k, v) { tin += (v['cash'] + v['gpay']); tout += v['exp']; });

    return SingleChildScrollView(
      padding: const EdgeInsets.all(30),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Column(
            children: [
              _buildStats(tin, tout),
              const SizedBox(height: 25),
              _buildTable(data),
              const SizedBox(height: 30),
              _exportButton(data, tin, tout),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStats(double col, double exp) {
    return Row(
      children: [
        _statTile("COLLECTED", col, Colors.green),
        const SizedBox(width: 20),
        _statTile("EXPENSES", exp, Colors.red),
        const SizedBox(width: 20),
        _statTile("NET BALANCE", col - exp, Colors.indigo),
      ],
    );
  }

  Widget _statTile(String t, double v, Color c) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)]),
        child: Column(
          children: [
            Text(t, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
            Text(uiFormat.format(v), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: c)),
          ],
        ),
      ),
    );
  }

  Widget _buildTable(Map<String, Map<String, dynamic>> data) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: DataTable(
        headingRowColor: MaterialStateProperty.all(const Color(0xFFF8FAFC)),
        columns: const [
          DataColumn(label: Text("STAFF")),
          DataColumn(label: Text("COLLECTED")),
          DataColumn(label: Text("EXPENSE")),
          DataColumn(label: Text("BALANCE")),
        ],
        rows: data.entries.map((e) {
          double totalIn = e.value['cash'] + e.value['gpay'];
          double bal = totalIn - e.value['exp'];
          return DataRow(cells: [
            DataCell(Text(e.value['name'].toString().toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold))),
            DataCell(Text(uiFormat.format(totalIn))),
            DataCell(Text(uiFormat.format(e.value['exp']), style: const TextStyle(color: Colors.red))),
            DataCell(Text(uiFormat.format(bal), style: TextStyle(fontWeight: FontWeight.bold, color: bal >= 0 ? Colors.green : Colors.red))),
          ]);
        }).toList(),
      ),
    );
  }

  Widget _exportButton(data, tc, te) {
    return ElevatedButton.icon(
      onPressed: () => _generatePdf(data, tc, te),
      icon: const Icon(Icons.picture_as_pdf),
      label: Text(isYearlyView ? "DOWNLOAD ANNUAL REPORT" : "DOWNLOAD MONTHLY REPORT"),
      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F172A), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20)),
    );
  }

  Future<void> _generatePdf(Map<String, Map<String, dynamic>> data, double tc, double te) async {
    final pdf = pw.Document();
    pdf.addPage(pw.MultiPage(
      build: (context) => [
        pw.Header(level: 0, child: pw.Text("GLOBAL AUDIT: ${isYearlyView ? selectedDate.year : DateFormat('MMMM yyyy').format(selectedDate)}")),
        pw.SizedBox(height: 20),
        pw.TableHelper.fromTextArray(
          headers: ['STAFF', 'COLLECTED', 'EXPENSE', 'BALANCE'],
          data: data.entries.map((e) => [
            e.value['name'].toUpperCase(),
            (e.value['cash'] + e.value['gpay']).toString(),
            e.value['exp'].toString(),
            (e.value['cash'] + e.value['gpay'] - e.value['exp']).toString(),
          ]).toList(),
        ),
        pw.SizedBox(height: 20),
        pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text("Net Balance: Rs. ${tc - te}", style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
      ],
    ));
    await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  }
}

class StreamZipCustom {
  final List<Stream<QuerySnapshot>> streams;
  StreamZipCustom(this.streams);
  Stream<T> map<T>(T Function(List<QuerySnapshot>) mapper) {
    final controller = StreamController<T>();
    final List<QuerySnapshot?> latestSnapshots = List.filled(streams.length, null);
    final List<StreamSubscription> subscriptions = [];

    for (int i = 0; i < streams.length; i++) {
      subscriptions.add(streams[i].listen((snapshot) {
        latestSnapshots[i] = snapshot;
        if (latestSnapshots.every((s) => s != null)) {
          controller.add(mapper(latestSnapshots.cast<QuerySnapshot>()));
        }
      }, onError: (err) => controller.addError(err)));
    }
    controller.onCancel = () { for (var sub in subscriptions) { sub.cancel(); } };
    return controller.stream;
  }
}