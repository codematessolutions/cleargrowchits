import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class CollectorReportWebScreen extends StatefulWidget {
  final String kuriId;
  final String kuriName;
  final DateTime initialMonth;

  const CollectorReportWebScreen({
    super.key,
    required this.kuriId,
    required this.kuriName,
    required this.initialMonth,
  });

  @override
  State<CollectorReportWebScreen> createState() => _CollectorReportWebScreenState();
}

class _CollectorReportWebScreenState extends State<CollectorReportWebScreen> {
  late DateTime selectedMonth;

  @override
  void initState() {
    super.initState();
    selectedMonth = widget.initialMonth;
  }

  double _parseNum(dynamic v) => double.tryParse(v.toString()) ?? 0.0;
  String get monthKey => DateFormat('yyyy_MM').format(selectedMonth);

  void _processEntry(Map reportData, String name, String mode, double amt, Set<String> activeModes, Map<String, double> modeTotals) {
    activeModes.add(mode);
    if (reportData.containsKey(name)) {
      reportData[name]!["m"][mode] = (reportData[name]!["m"][mode] ?? 0.0) + amt;
      reportData[name]!["total"] += amt;
      modeTotals[mode] = (modeTotals[mode] ?? 0.0) + amt;
    }
  }

  @override
  Widget build(BuildContext context) {
    final uiFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text("${widget.kuriName} - Collection Audit"),
        backgroundColor: const Color(0xFF1E293B),
        foregroundColor: Colors.white,
        actions: [ _buildMonthPicker(), const SizedBox(width: 20)],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('staff_admins').orderBy('name').snapshots(),
        builder: (context, staffSnap) {
          if (!staffSnap.hasData) return const Center(child: CircularProgressIndicator());

          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('payments')
                .where('kuriId', isEqualTo: widget.kuriId)
                .where('monthKey', isEqualTo: monthKey)
                .snapshots(),
            builder: (context, paymentSnap) {
              if (!paymentSnap.hasData) return const Center(child: CircularProgressIndicator());

              // Initialize Map
              Map<String, Map<String, dynamic>> reportData = {};
              for (var doc in staffSnap.data!.docs) {
                reportData[doc['name']] = {"name": doc['name'], "total": 0.0, "m": <String, double>{}};
              }

              double grandTotal = 0;
              Map<String, double> modeTotals = {};
              Set<String> activeModes = {"Cash", "GPay"};

              for (var doc in paymentSnap.data!.docs) {
                final data = doc.data() as Map<String, dynamic>;
                final List<dynamic> splits = data['paymentSplits'] as List? ?? [];

                if (splits.isEmpty) {
                  // Legacy fallback
                  double amt = _parseNum(data['amount']);
                  _processEntry(reportData, data['collectedBy'] ?? "Unknown", data['mode'] ?? "Cash", amt, activeModes, modeTotals);
                  grandTotal += amt;
                } else {
                  // Structured split processing
                  for (var s in splits) {
                    double amt = _parseNum(s['amount']);
                    _processEntry(reportData, s['collectorName'] ?? "Unknown", s['mode'] ?? "Other", amt, activeModes, modeTotals);
                    grandTotal += amt;
                  }
                }
              }

              final sortedModes = activeModes.toList()..sort();

              return SingleChildScrollView(
                padding: const EdgeInsets.all(40),
                child: Column(
                  children: [
                    _buildTopHeader(reportData, sortedModes, grandTotal),
                    const SizedBox(height: 32),
                    _buildStatsRow(uiFormat, modeTotals, grandTotal),
                    const SizedBox(height: 32),
                    _buildDataTable(uiFormat, reportData, sortedModes, modeTotals, grandTotal),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  // --- SUB-WIDGETS ---

  Widget _buildTopHeader(data, modes, total) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Collection Summary", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            Text("Breakdown of collection by staff and payment mode", style: TextStyle(color: Colors.grey)),
          ],
        ),
        ElevatedButton.icon(
          onPressed: () => _exportToPdf(data, modes, total),
          icon: const Icon(Icons.download),
          label: const Text("EXPORT PDF"),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white, padding: const EdgeInsets.all(20)),
        )
      ],
    );
  }

  Widget _buildStatsRow(NumberFormat uiFormat, Map<String, double> modeTotals, double total) {
    return Row(
      children: [
        _statTile(uiFormat, "Grand Total", total, Colors.indigo),
        const SizedBox(width: 20),
        _statTile(uiFormat, "Cash", modeTotals['Cash'] ?? 0.0, Colors.orange),
        const SizedBox(width: 20),
        _statTile(uiFormat, "Digital", modeTotals['GPay'] ?? 0.0, Colors.teal),
      ],
    );
  }

  Widget _statTile(NumberFormat uiFormat, String label, double val, Color col) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            Text(uiFormat.format(val), style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: col)),
          ],
        ),
      ),
    );
  }

  Widget _buildDataTable(uiFormat, data, modes, colTotals, total) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
      child: DataTable(
        columns: [
          const DataColumn(label: Text('STAFF')),
          ...modes.map((m) => DataColumn(label: Text(m.toUpperCase()))),
          const DataColumn(label: Text('TOTAL')),
        ],
        rows: [
          ...data.entries.map((e) => DataRow(cells: [
            DataCell(Text(e.value['name'].toString().toUpperCase())),
            ...modes.map((m) => DataCell(Text(uiFormat.format(e.value['m'][m] ?? 0.0)))),
            DataCell(Text(uiFormat.format(e.value['total']), style: const TextStyle(fontWeight: FontWeight.bold))),
          ])),
          DataRow(color: WidgetStateProperty.all(Colors.grey.shade50), cells: [
            const DataCell(Text("TOTALS", style: TextStyle(fontWeight: FontWeight.bold))),
            ...modes.map((m) => DataCell(Text(uiFormat.format(colTotals[m] ?? 0.0), style: const TextStyle(fontWeight: FontWeight.bold)))),
            DataCell(Text(uiFormat.format(total), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green))),
          ])
        ],
      ),
    );
  }

  Widget _buildMonthPicker() {
    return Row(
      children: [
        IconButton(icon: const Icon(Icons.arrow_back_ios, size: 16), onPressed: () => setState(() => selectedMonth = DateTime(selectedMonth.year, selectedMonth.month - 1))),
        Text(DateFormat('MMM yyyy').format(selectedMonth), style: const TextStyle(fontWeight: FontWeight.bold)),
        IconButton(icon: const Icon(Icons.arrow_forward_ios, size: 16), onPressed: () => setState(() => selectedMonth = DateTime(selectedMonth.year, selectedMonth.month + 1))),
      ],
    );
  }

  // PDF Export logic remains as previously discussed...
  Future<void> _exportToPdf(data, modes, total) async { /* PDF Code Here */ }
}