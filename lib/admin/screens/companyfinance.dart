import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'dart:async';

import '../../core/utils/kuri_theme.dart';

class CompanyGlobalAuditWeb extends StatefulWidget {
  final String userName;
  final String userRole;
  const CompanyGlobalAuditWeb({super.key, required this.userName, required this.userRole});

  @override
  State<CompanyGlobalAuditWeb> createState() => _CompanyGlobalAuditWebState();
}

class _CompanyGlobalAuditWebState extends State<CompanyGlobalAuditWeb> {
  DateTime selectedDate = DateTime(DateTime.now().year, DateTime.now().month);
  bool isYearlyView = false;

  final uiFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
  final pdfFormat = NumberFormat.currency(locale: 'en_IN', symbol: 'Rs. ', decimalDigits: 0);

  // --- Professional Web Palette ---
  static const Color webBg = Color(0xFFF9FAFB);
  static const Color sideNavColor = Color(0xFF111827); // Dark Slate
  static const Color accentBlue = Color(0xFF2563EB); // Corporate Blue
  static const Color textMain = Color(0xFF111827);
  static const Color textMuted = Color(0xFF6B7280);
  static const Color borderCol = Color(0xFFE5E7EB);

  Stream<Map<String, List<QueryDocumentSnapshot>>> _getGlobalData() {
    DateTime start;
    DateTime end;

    if (isYearlyView) {
      start = DateTime(selectedDate.year, 1, 1, 0, 0, 0);
      end = DateTime(selectedDate.year, 12, 31, 23, 59, 59);
    } else {
      start = DateTime(selectedDate.year, selectedDate.month, 1, 0, 0, 0);
      end = DateTime(selectedDate.year, selectedDate.month + 1, 1).subtract(const Duration(seconds: 1));
    }

    Query paymentQuery = FirebaseFirestore.instance.collection('payments')
        .where('paidDate', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('paidDate', isLessThanOrEqualTo: Timestamp.fromDate(end));

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
      backgroundColor: webBg,
      body: Row(
        children: [
          // Fixed Sidebar

          // Main Content
          Expanded(
            child: Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: StreamBuilder<Map<String, List<QueryDocumentSnapshot>>>(
                    stream: _getGlobalData(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) return const Center(child: Text("Database Sync Error"));
                      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: accentBlue));

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
                          if (auditData.containsKey(id)) {
                            if (s['mode'] == "GPay") auditData[id]!["gpay"] += amt;
                            else auditData[id]!["cash"] += amt;
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

                      return _buildContent(auditData);
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }



  Widget _navItem(IconData icon, String label, bool active) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(color: active ? Colors.blue.withOpacity(0.15) : Colors.transparent, borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        leading: Icon(icon, color: active ? accentBlue : Colors.white54, size: 20),
        title: Text(label, style: TextStyle(color: active ? Colors.white : Colors.white54, fontSize: 14, fontWeight: FontWeight.w600)),
        onTap: () {},
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 70,
      decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: borderCol))),
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_ios_new, size: 20, color: KuriTheme.textDark),
            padding: const EdgeInsets.only(right: 16), // Spacing between button and title
          ),
          const Text("Financial Performance Overview", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textMain)),
          const Spacer(),
          _buildDateControls(),
          const SizedBox(width: 20),
          _buildViewSwitcher(),
        ],
      ),
    );
  }

  Widget _buildContent(Map<String, Map<String, dynamic>> data) {
    double totalCol = 0; double totalExp = 0;
    data.forEach((k, v) { totalCol += (v['cash'] + v['gpay']); totalExp += v['exp']; });

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Column(
            children: [
              _buildMetricCards(totalCol, totalExp),
              const SizedBox(height: 32),
              _buildTableCard(data),
              const SizedBox(height: 32),
              _buildExportAction(data, totalCol, totalExp),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetricCards(double col, double exp) {
    return Row(
      children: [
        _metricTile("Gross Collection", col, accentBlue),
        const SizedBox(width: 24),
        _metricTile("Total Expenses", exp, textMuted),
        const SizedBox(width: 24),
        _metricTile("Net System Balance", col - exp, const Color(0xFF6366F1)),
      ],
    );
  }

  Widget _metricTile(String label, double val, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: borderCol)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: textMuted)),
            const SizedBox(height: 8),
            Text(uiFormat.format(val), style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _buildTableCard(Map<String, Map<String, dynamic>> data) {
    // 1. Calculate Grand Totals
    double grandCash = 0;
    double grandGPay = 0;
    double grandExp = 0;

    data.forEach((_, val) {
      grandCash += val['cash'];
      grandGPay += val['gpay'];
      grandExp += val['exp'];
    });

    double grandTotalIn = grandCash + grandGPay;
    double grandBalance = grandTotalIn - grandExp;

    // 2. Map existing data to rows
    List<DataRow> rows = data.entries.map((e) {
      double total = e.value['cash'] + e.value['gpay'];
      double balance = total - e.value['exp'];
      return DataRow(cells: [
        DataCell(Text(e.value['name'].toString().toUpperCase(),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
        DataCell(Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(uiFormat.format(total), style: const TextStyle(fontWeight: FontWeight.bold, color: accentBlue)),
            Text("CASH: ${uiFormat.format(e.value['cash'])} | GPAY: ${uiFormat.format(e.value['gpay'])}",
                style: const TextStyle(fontSize: 10, color: textMuted)),
          ],
        )),
        DataCell(Text(uiFormat.format(e.value['exp']), style: const TextStyle(color: textMuted))),
        DataCell(Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
              color: balance >= 0 ? Colors.blue.withOpacity(0.1) : Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6)),
          child: Text(uiFormat.format(balance),
              style: TextStyle(fontWeight: FontWeight.bold, color: balance >= 0 ? accentBlue : Colors.red.shade700)),
        )),
      ]);
    }).toList();

    // 3. Add the Summary Row (Total Row)
    rows.add(
      DataRow(
        color: WidgetStateProperty.all(const Color(0xFFF1F5F9)), // Distinct light grey for total
        cells: [
          const DataCell(Text("GRAND TOTAL", style: TextStyle(fontWeight: FontWeight.w900, color: textMain))),
          DataCell(Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(uiFormat.format(grandTotalIn), style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF1E293B))),
              Text("C: ${uiFormat.format(grandCash)} | G: ${uiFormat.format(grandGPay)}",
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: textMuted)),
            ],
          )),
          DataCell(Text(uiFormat.format(grandExp),
              style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.black))),
          DataCell(Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: sideNavColor, borderRadius: BorderRadius.circular(6)),
            child: Text(uiFormat.format(grandBalance),
                style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.white)),
          )),
        ],
      ),
    );

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderCol)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: DataTable(
          headingRowHeight: 60,
          dataRowHeight: 80,
          headingRowColor: WidgetStateProperty.all(const Color(0xFFF9FAFB)),
          columns: const [
            DataColumn(label: Text("STAFF", style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text("COLLECTED", style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text("EXPENSES", style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text("BALANCE\n(Company Cash)", style: TextStyle(fontWeight: FontWeight.bold))),
          ],
          rows: rows,
        ),
      ),
    );
  }

  Widget _buildDateControls() {
    return Container(
      decoration: BoxDecoration(border: Border.all(color: borderCol), borderRadius: BorderRadius.circular(8)),
      child: Row(
        children: [
          IconButton(icon: const Icon(Icons.chevron_left, size: 20), onPressed: () => _adjustDate(-1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(isYearlyView ? "${selectedDate.year}" : DateFormat('MMM yyyy').format(selectedDate).toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          ),
          IconButton(icon: const Icon(Icons.chevron_right, size: 20), onPressed: () => _adjustDate(1)),
        ],
      ),
    );
  }

  Widget _buildViewSwitcher() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: Color(0xFFE5E7EB), borderRadius: BorderRadius.circular(8)),
      child: Row(
        children: [
          _switchItem("Month", !isYearlyView),
          _switchItem("Year", isYearlyView),
        ],
      ),
    );
  }

  Widget _switchItem(String label, bool active) {
    return InkWell(
      onTap: () => setState(() => isYearlyView = label == "Year"),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(color: active ? Colors.white : Colors.transparent, borderRadius: BorderRadius.circular(6), boxShadow: active ? [BoxShadow(color: Colors.black12, blurRadius: 4)] : []),
        child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: active ? accentBlue : textMuted)),
      ),
    );
  }

  Widget _buildExportAction(data, tc, te) {
    return Align(
      alignment: Alignment.centerRight,
      child: ElevatedButton.icon(
        onPressed: () => _generatePdf(data, tc, te),
        icon: const Icon(Icons.print_outlined),
        label: const Text("GENERATE AUDIT PDF"),
        style: ElevatedButton.styleFrom(backgroundColor: sideNavColor, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
      ),
    );
  }

  void _adjustDate(int offset) {
    setState(() {
      selectedDate = isYearlyView ? DateTime(selectedDate.year + offset, 1) : DateTime(selectedDate.year, selectedDate.month + offset);
    });
  }

  // --- PDF & COMBINER LOGIC ---
  Future<void> _generatePdf(Map<String, Map<String, dynamic>> data, double tc, double te) async {
    final pdf = pw.Document();
    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (context) => [
        pw.Header(level: 0, child: pw.Text("Audit Report: ${DateFormat('MMMM yyyy').format(selectedDate)}")),
        pw.SizedBox(height: 20),
        pw.TableHelper.fromTextArray(
          headers: ['Staff', 'Cash', 'GPay', 'Expense', 'Balance'],
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey900),
          data: data.entries.map((e) => [
            e.value['name'].toUpperCase(),
            pdfFormat.format(e.value['cash']),
            pdfFormat.format(e.value['gpay']),
            pdfFormat.format(e.value['exp']),
            pdfFormat.format(e.value['cash'] + e.value['gpay'] - e.value['exp']),
          ]).toList(),
        ),
        pw.SizedBox(height: 30),
        pw.Divider(),
        pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text("Total Revenue: ${pdfFormat.format(tc)}")),
        pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text("Net Settlement: ${pdfFormat.format(tc - te)}", style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
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