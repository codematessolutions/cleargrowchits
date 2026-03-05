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

  // --- PDF EXPORT LOGIC (UNCHANGED) ---
  Future<void> _exportToPdf(Map<String, Map<String, dynamic>> data, List<String> modes, double grandTotal) async {
    final pdf = pw.Document();
    final NumberFormat pdfFormatter = NumberFormat.decimalPattern('en_IN');

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          pw.Text("COLLECTION AUDIT REPORT",
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo900)),
          pw.Text("Kuri: ${widget.kuriName} | Month: ${DateFormat('MMMM yyyy').format(selectedMonth)}",
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
          pw.SizedBox(height: 20),
          pw.TableHelper.fromTextArray(
            headers: ['STAFF NAME', ...modes.map((m) => m.toUpperCase()), 'TOTAL'],
            data: data.entries.map((e) {
              final List<String> rowValues = [e.value['name'].toString().toUpperCase()];
              for (var mode in modes) {
                rowValues.add(pdfFormatter.format(e.value['m'][mode] ?? 0.0));
              }
              rowValues.add(pdfFormatter.format(e.value['total'] ?? 0.0));
              return rowValues;
            }).toList(),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 9),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.indigo900),
            cellStyle: const pw.TextStyle(fontSize: 9),
            cellAlignments: {0: pw.Alignment.centerLeft},
            cellAlignment: pw.Alignment.centerRight,
          ),
          pw.SizedBox(height: 20),
          pw.Divider(color: PdfColors.grey400),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
                "Grand Total: ${pdfFormatter.format(grandTotal)}",
                style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)
            ),
          ),
        ],
      ),
    );
    await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  }

  @override
  Widget build(BuildContext context) {
    final NumberFormat uiFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC), // Lighter web background
      appBar: AppBar(
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.kuriName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Text("Collection Audit Dashboard", style: TextStyle(fontSize: 11, color: Colors.white70)),
          ],
        ),
        backgroundColor: const Color(0xFF1E293B), // Navy/Slate web header
        foregroundColor: Colors.white,
        actions: [
          _buildMonthPicker(),
          const SizedBox(width: 20),
        ],
      ),
      body: _buildReportContent(uiFormat),
    );
  }

  Widget _buildMonthPicker() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, size: 20),
            onPressed: () => setState(() => selectedMonth = DateTime(selectedMonth.year, selectedMonth.month - 1)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Text(
              DateFormat('MMM yyyy').format(selectedMonth).toUpperCase(),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right, size: 20),
            onPressed: () => setState(() => selectedMonth = DateTime(selectedMonth.year, selectedMonth.month + 1)),
          ),
        ],
      ),
    );
  }

  Widget _buildReportContent(NumberFormat uiFormat) {
    return StreamBuilder<QuerySnapshot>(
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

            Map<String, Map<String, dynamic>> reportData = {};
            for (var doc in staffSnap.data!.docs) {
              reportData[doc.id] = {"name": doc['name'], "total": 0.0, "m": <String, double>{}};
            }

            double grandTotal = 0;
            Map<String, double> modeTotals = {};
            Set<String> activeModes = {"Cash", "GPay"};

            for (var doc in paymentSnap.data!.docs) {
              final data = doc.data() as Map<String, dynamic>;
              final splits = data['paymentSplits'] as List? ?? [];
              for (var s in splits) {
                String id = s['collectorId'] ?? "";
                String mode = s['mode'] ?? "Other";
                double amt = _parseNum(s['amount']);
                activeModes.add(mode);
                if (reportData.containsKey(id)) {
                  reportData[id]!["m"][mode] = (reportData[id]!["m"][mode] ?? 0.0) + amt;
                  reportData[id]!["total"] += amt;
                  modeTotals[mode] = (modeTotals[mode] ?? 0.0) + amt;
                  grandTotal += amt;
                }
              }
            }

            final List<String> sortedModes = activeModes.toList()..sort();

            return SingleChildScrollView(
              padding: const EdgeInsets.all(40),
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 1300),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildTopHeader(reportData, sortedModes, grandTotal),
                      const SizedBox(height: 32),
                      _buildStatsRow(uiFormat, modeTotals, grandTotal),
                      const SizedBox(height: 32),
                      _buildDataTable(uiFormat, reportData, sortedModes, modeTotals, grandTotal),
                      const SizedBox(height: 50),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTopHeader(data, modes, total) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.indigo.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.analytics_rounded, color: Colors.indigo),
        ),
        const SizedBox(width: 16),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Collection Audit Report", style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
              Text("Review financial breakdowns by staff and payment mode.", style: TextStyle(color: Colors.grey, fontSize: 14)),
            ],
          ),
        ),
        OutlinedButton.icon(
          onPressed: () => _exportToPdf(data, modes, total),
          icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
          label: const Text("DOWNLOAD PDF"),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            side: const BorderSide(color: Colors.indigo),
            foregroundColor: Colors.indigo,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ],
    );
  }

  Widget _buildStatsRow(NumberFormat uiFormat, Map<String, double> modeTotals, double total) {
    return Row(
      children: [
        _statTile(uiFormat, "Total Revenue", total, Colors.indigo, Icons.account_balance_wallet_rounded),
        const SizedBox(width: 20),
        _statTile(uiFormat, "Cash Collection", modeTotals['Cash'] ?? 0.0, Colors.orange, Icons.payments_rounded),
        const SizedBox(width: 20),
        _statTile(uiFormat, "Digital (GPay)", modeTotals['GPay'] ?? 0.0, Colors.teal, Icons.phonelink_ring_rounded),
      ],
    );
  }

  Widget _statTile(NumberFormat uiFormat, String label, double val, Color col, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
          border: Border.all(color: Colors.grey.shade100),
        ),
        child: Row(
          children: [
            CircleAvatar(backgroundColor: col.withOpacity(0.1), child: Icon(icon, color: col, size: 20)),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500)),
                Text(uiFormat.format(val), style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: col)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDataTable(NumberFormat uiFormat, Map<String, Map<String, dynamic>> data, List<String> modes, Map<String, double> colTotals, double total) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 20)],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: DataTable(
          headingRowHeight: 60,
          dataRowMaxHeight: 65,
          horizontalMargin: 30,
          columnSpacing: 20,
          headingRowColor: MaterialStateProperty.all(const Color(0xFFF8FAFC)),
          columns: [
            const DataColumn(label: Text('STAFF COLLECTOR', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey))),
            ...modes.map((m) => DataColumn(label: Text(m.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)))),
            const DataColumn(label: Text('MONTHLY TOTAL', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey))),
          ],
          rows: [
            ...data.entries.map((e) => DataRow(cells: [
              DataCell(Text(e.value['name'].toString().toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF1E293B)))),
              ...modes.map((m) => DataCell(Text(uiFormat.format(e.value['m'][m] ?? 0.0)))),
              DataCell(Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(6)),
                child: Text(uiFormat.format(e.value['total']), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
              )),
            ])),
            DataRow(
              color: MaterialStateProperty.all(const Color(0xFFF1F5F9)),
              cells: [
                const DataCell(Text("SUMMARY TOTALS", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F172A)))),
                ...modes.map((m) => DataCell(Text(uiFormat.format(colTotals[m] ?? 0.0), style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F172A))))),
                DataCell(Text(uiFormat.format(total), style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.green, fontSize: 16))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}