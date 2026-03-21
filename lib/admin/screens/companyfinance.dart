import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'dart:async';

class CompanyGlobalAuditWeb extends StatefulWidget {
  final String userName;
  final String userRole;
  const CompanyGlobalAuditWeb({super.key, required this.userName, required this.userRole});

  @override
  State<CompanyGlobalAuditWeb> createState() => _CompanyGlobalAuditWebState();
}

class _CompanyGlobalAuditWebState extends State<CompanyGlobalAuditWeb> {
  DateTime selectedDate = DateTime(DateTime.now().year, DateTime.now().month);
  int viewMode = 0; // 0 = Month, 1 = Year, 2 = Total

  final uiFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
  final pdfFormat = NumberFormat.currency(locale: 'en_IN', symbol: 'Rs. ', decimalDigits: 0);

  // Theme Constants
  static const Color webBg = Color(0xFFF9FAFB);
  static const Color sideNavColor = Color(0xFF111827);
  static const Color accentBlue = Color(0xFF2563EB);
  static const Color textMain = Color(0xFF111827);
  static const Color textMuted = Color(0xFF6B7280);
  static const Color borderCol = Color(0xFFE5E7EB);

  Stream<Map<String, List<QueryDocumentSnapshot>>> _getGlobalData() {
    Query paymentQuery = FirebaseFirestore.instance.collection('payments');
    Query expenseQuery = FirebaseFirestore.instance.collection('expenses');

    if (viewMode == 0) {
      DateTime start = DateTime(selectedDate.year, selectedDate.month, 1);
      DateTime end = DateTime(selectedDate.year, selectedDate.month + 1, 1).subtract(const Duration(seconds: 1));
      paymentQuery = paymentQuery.where('paidDate', isGreaterThanOrEqualTo: start).where('paidDate', isLessThanOrEqualTo: end);
      expenseQuery = expenseQuery.where('date', isGreaterThanOrEqualTo: start).where('date', isLessThanOrEqualTo: end);
    } else if (viewMode == 1) {
      DateTime start = DateTime(selectedDate.year, 1, 1);
      DateTime end = DateTime(selectedDate.year, 12, 31, 23, 59, 59);
      paymentQuery = paymentQuery.where('paidDate', isGreaterThanOrEqualTo: start).where('paidDate', isLessThanOrEqualTo: end);
      expenseQuery = expenseQuery.where('date', isGreaterThanOrEqualTo: start).where('date', isLessThanOrEqualTo: end);
    }

    Stream<QuerySnapshot> staffStream = FirebaseFirestore.instance.collection('staff_admins').snapshots();
    Stream<QuerySnapshot> kuriMasterStream = FirebaseFirestore.instance.collection('kuris').snapshots();

    return StreamZipCustom([
      paymentQuery.snapshots(),
      expenseQuery.snapshots(),
      staffStream,
      kuriMasterStream
    ]).map((list) {
      return {
        'payments': list[0].docs,
        'expenses': list[1].docs,
        'staff': list[2].docs,
        'kuris_master': list[3].docs,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: webBg,
        body: Column(
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
                  final kuriMasterList = snapshot.data!['kuris_master']!;

                  Map<String, String> staffNameMap = {for (var s in staffList) s.id: (s.data() as Map)['name'] ?? "Unknown"};

                  // Processing Data
                  Map<String, Map<String, dynamic>> staffAudit = {
                    for (var s in staffList) s.id: {"name": staffNameMap[s.id], "cash": 0.0, "gpay": 0.0, "exp": 0.0}
                  };

                  Map<String, Map<String, dynamic>> kuriAudit = {};
                  Map<String, Map<String, Map<String, double>>> kuriStaffBreakdown = {};

                  for (var k in kuriMasterList) {
                    final kData = k.data() as Map<String, dynamic>;
                    String kId = k.id;
                    String displayName = kData['name'] ?? "Kuri ($kId)";
                    kuriAudit[kId] = {"name": displayName, "cash": 0.0, "gpay": 0.0, "exp": 0.0};
                    kuriStaffBreakdown[displayName] = {};
                  }

                  for (var doc in payments) {
                    final data = doc.data() as Map<String, dynamic>;
                    final splits = data['paymentSplits'] as List? ?? [];
                    String kId = data['kuriId']?.toString() ?? "";
                    String currentKuriDisplayName = kuriAudit[kId]?['name'] ?? "Unknown Kuri";

                    for (var s in splits) {
                      String sId = s['collectorId'] ?? "";
                      String sName = staffNameMap[sId] ?? "Unknown Staff";
                      double amt = double.tryParse(s['amount'].toString()) ?? 0.0;
                      bool isGpay = s['mode'] == "GPay";

                      if (staffAudit.containsKey(sId)) {
                        if (isGpay) staffAudit[sId]!["gpay"] += amt; else staffAudit[sId]!["cash"] += amt;
                      }
                      if (kuriAudit.containsKey(kId)) {
                        if (isGpay) kuriAudit[kId]!["gpay"] += amt; else kuriAudit[kId]!["cash"] += amt;
                      }
                      var breakdown = kuriStaffBreakdown[currentKuriDisplayName];
                      if (breakdown != null) {
                        breakdown.putIfAbsent(sName, () => {"cash": 0.0, "gpay": 0.0});
                        if (isGpay) breakdown[sName]!["gpay"] = (breakdown[sName]!["gpay"] ?? 0.0) + amt;
                        else breakdown[sName]!["cash"] = (breakdown[sName]!["cash"] ?? 0.0) + amt;
                      }
                    }
                  }

                  for (var doc in expenses) {
                    final data = doc.data() as Map<String, dynamic>;
                    String staffName = data['staffName'] ?? "";
                    double amt = double.tryParse(data['amount'].toString()) ?? 0.0;
                    staffAudit.forEach((id, val) { if (val['name'] == staffName) val['exp'] += amt; });
                  }

                  return _buildContent(staffAudit, kuriAudit, kuriStaffBreakdown);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 120,
      decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: borderCol))),
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_ios_new, size: 20)),
              const Text("Financial Audit Control", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const Spacer(),
              if (viewMode != 2) _buildDateControls(),
              const SizedBox(width: 20),
              _buildViewSwitcher(),
            ],
          ),
          const SizedBox(height: 8),
          const TabBar(
            isScrollable: true,
            labelColor: accentBlue,
            indicatorColor: accentBlue,
            tabs: [Tab(text: "STAFF PERFORMANCE"), Tab(text: "KURI PERFORMANCE"), Tab(text: "STAFF-KURI BREAKDOWN")],
          ),
        ],
      ),
    );
  }

  Widget _buildContent(Map staffData, Map kuriData, Map breakdownData) {
    double totalCol = 0; double totalExp = 0;
    staffData.forEach((k, v) {
      totalCol += (v['cash'] + v['gpay']);
      totalExp += v['exp'];
    });

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 1400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildMetricCards(totalCol, totalExp),
              const SizedBox(height: 12),
              // Updated to include breakdownData
              _buildExportAction(staffData, kuriData, breakdownData),
              ConstrainedBox(
                constraints: BoxConstraints(
                    minHeight: 300,
                    maxHeight: MediaQuery.of(context).size.height * 0.59
                ),
                child: TabBarView(
                  children: [
                    _buildTableCard(staffData.cast<String, Map<String, dynamic>>(), "STAFF NAME"),
                    _buildTableCard(kuriData.cast<String, Map<String, dynamic>>(), "KURI SCHEME"),
                    _buildKuriStaffBreakdown(breakdownData.cast<String, Map<String, Map<String, double>>>()),
                  ],
                ),
              ),
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
            Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: textMuted)),
            const SizedBox(height: 8),
            Text(uiFormat.format(val), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _buildTableCard(Map<String, Map<String, dynamic>> data, String label) {
    double grandCash = 0; double grandGPay = 0; double grandExp = 0;
    data.forEach((_, val) { grandCash += val['cash']; grandGPay += val['gpay']; grandExp += val['exp']; });

    List<DataRow> rows = data.entries.map((e) {
      double total = e.value['cash'] + e.value['gpay'];
      double balance = total - e.value['exp'];
      bool isPositive = balance >= 0;

      return DataRow(
        // REDUCED HEIGHT FOR MAXIMUM VISIBILITY
          cells: [
            DataCell(Text(e.value['name'].toString().toUpperCase(),
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: textMain))),

            DataCell(Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(uiFormat.format(total), style: const TextStyle(fontWeight: FontWeight.bold, color: accentBlue, fontSize: 12)),
                const SizedBox(width: 8),
                Text("(${uiFormat.format(e.value['cash'])}C / ${uiFormat.format(e.value['gpay'])}G)",
                    style: const TextStyle(fontSize: 10, color: textMuted)),
              ],
            )),

            DataCell(Text(uiFormat.format(e.value['exp']),
                style: TextStyle(color: Colors.red.shade400, fontSize: 12))),

            DataCell(Text(uiFormat.format(balance),
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12,
                    color: isPositive ? Colors.green.shade700 : Colors.red.shade700))),
          ]
      );
    }).toList();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderCol),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min, // Allows the container to wrap content
        children: [
          // TABLE BODY
          Theme(
            data: Theme.of(context).copyWith(dividerColor: borderCol.withOpacity(0.5)),
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(webBg),
              headingRowHeight: 40, // Slimmer Header
              dataRowMinHeight: 38, // Slimmer Rows
              dataRowMaxHeight: 38, // Slimmer Rows
              horizontalMargin: 20,
              columnSpacing: 10,
              columns: [
                DataColumn(label: Text(label, style: const TextStyle(fontWeight: FontWeight.w800, color: textMuted, fontSize: 10))),
                const DataColumn(label: Text("COLLECTED (C/G)", style: TextStyle(fontWeight: FontWeight.w800, color: textMuted, fontSize: 10))),
                const DataColumn(label: Text("EXPENSES", style: TextStyle(fontWeight: FontWeight.w800, color: textMuted, fontSize: 10))),
                const DataColumn(label: Text("BALANCE", style: TextStyle(fontWeight: FontWeight.w800, color: textMuted, fontSize: 10))),
              ],
              rows: rows,
            ),
          ),

          // COMPACT FOOTER
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: const BoxDecoration(
                color: sideNavColor,
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(11))
            ),
            child: Row(
              children: [
                const Text("TOTALS", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                const Spacer(),
                _totalColumn("COLLECTED", grandCash + grandGPay, Colors.white),
                const SizedBox(width: 24),
                _totalColumn("EXPENSES", grandExp, Colors.white70),
                const SizedBox(width: 24),
                _totalColumn("NET", (grandCash + grandGPay) - grandExp, Colors.greenAccent),
              ],
            ),
          )
        ],
      ),
    );
  }

// Updated Helper for ultra-compact footer columns
  Widget _totalColumn(String label, double value, Color color) {
    return Row(
      children: [
        Text("$label: ", style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 10)),
        Text(uiFormat.format(value), style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
      ],
    );
  }



  Widget _miniCircle(Color color) {
    return Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle));
  }

  Widget _buildKuriStaffBreakdown(Map<String, Map<String, Map<String, double>>> data) {
    if (data.isEmpty) return _buildEmptyState();
    return LayoutBuilder(builder: (context, constraints) {
      int crossAxisCount = constraints.maxWidth > 1400 ? 3 : (constraints.maxWidth > 900 ? 2 : 1);
      return GridView.builder(
        padding: const EdgeInsets.all(24),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: crossAxisCount, crossAxisSpacing: 24, mainAxisSpacing: 24, mainAxisExtent: 480),
        itemCount: data.length,
        itemBuilder: (context, index) {
          String kuriName = data.keys.elementAt(index);
          var staffData = data[kuriName]!;
          double totalCash = 0; double totalGpay = 0;
          staffData.forEach((_, val) { totalCash += val['cash']!; totalGpay += val['gpay']!; });
          var activeStaff = staffData.entries.where((e) => (e.value['cash']! + e.value['gpay']!) > 0).toList();
          return Container(
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: borderCol), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 2))]),
            child: Column(
              children: [
                _buildKuriCardHeader(kuriName, totalCash + totalGpay, totalCash, totalGpay),
                _buildBreakdownTableSubHeader(),
                Expanded(child: activeStaff.isEmpty ? const Center(child: Text("No Data", style: TextStyle(color: textMuted))) : ListView.separated(itemCount: activeStaff.length, separatorBuilder: (context, i) => const Divider(height: 1, color: borderCol), itemBuilder: (context, i) => _buildStaffRow(i + 1, activeStaff[i].key, activeStaff[i].value['cash']!, activeStaff[i].value['gpay']!))),
                _buildKuriCardFooter(activeStaff.length),
              ],
            ),
          );
        },
      );
    });
  }

  Widget _buildKuriCardHeader(String name, double total, double cash, double gpay) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: accentBlue.withOpacity(0.04), borderRadius: const BorderRadius.vertical(top: Radius.circular(12))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(name.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: textMain, letterSpacing: 0.5), overflow: TextOverflow.ellipsis), const SizedBox(height: 4), Row(children: [_miniTag("Cash: ${uiFormat.format(cash)}", Colors.green), const SizedBox(width: 8), _miniTag("GPay: ${uiFormat.format(gpay)}", accentBlue)])])),
          Text(uiFormat.format(total), style: const TextStyle(fontWeight: FontWeight.w900, color: accentBlue, fontSize: 18)),
        ],
      ),
    );
  }

  Widget _buildBreakdownTableSubHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: webBg,
      child: const Row(children: [
        SizedBox(width: 30, child: Text("SI", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: textMuted))),
        Expanded(flex: 3, child: Text("COLLECTOR", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: textMuted))),
        Expanded(flex: 2, child: Text("CASH", textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: textMuted))),
        Expanded(flex: 2, child: Text("GPAY", textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: textMuted))),
        Expanded(flex: 2, child: Text("TOTAL", textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: textMuted))),
      ]),
    );
  }

  Widget _buildStaffRow(int si, String name, double cash, double gpay) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(children: [
        SizedBox(width: 30, child: Text("$si", style: const TextStyle(color: textMuted, fontSize: 12))),
        Expanded(flex: 3, child: Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: textMain))),
        Expanded(flex: 2, child: Text(uiFormat.format(cash), textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, color: Colors.green))),
        Expanded(flex: 2, child: Text(uiFormat.format(gpay), textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, color: accentBlue))),
        Expanded(flex: 2, child: Text(uiFormat.format(cash + gpay), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: textMain))),
      ]),
    );
  }

  Widget _miniTag(String label, Color color) {
    return Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(4)), child: Text(label, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold)));
  }

  Widget _buildKuriCardFooter(int count) {
    return Container(padding: const EdgeInsets.all(12), decoration: const BoxDecoration(border: Border(top: BorderSide(color: borderCol))), child: Row(children: [const Icon(Icons.group, size: 14, color: textMuted), const SizedBox(width: 6), Text("$count Collectors Active", style: const TextStyle(color: textMuted, fontSize: 11))]));
  }

  Widget _buildEmptyState() {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Container(padding: const EdgeInsets.all(32), decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: borderCol.withOpacity(0.5))), child: const Icon(Icons.folder_open_rounded, size: 64, color: textMuted)), const SizedBox(height: 24), const Text("No Records Found", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), const Text("Try selecting a different date range.", style: TextStyle(color: textMuted))]));
  }

  Widget _buildViewSwitcher() {
    return Container(padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: const Color(0xFFE5E7EB), borderRadius: BorderRadius.circular(8)), child: Row(children: [_switchItem("Month", viewMode == 0, 0), _switchItem("Year", viewMode == 1, 1), _switchItem("Total", viewMode == 2, 2)]));
  }

  Widget _switchItem(String label, bool active, int mode) {
    return InkWell(onTap: () => setState(() => viewMode = mode), child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), decoration: BoxDecoration(color: active ? Colors.white : Colors.transparent, borderRadius: BorderRadius.circular(6)), child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: active ? accentBlue : textMuted))));
  }

  Widget _buildDateControls() {
    return Container(decoration: BoxDecoration(border: Border.all(color: borderCol), borderRadius: BorderRadius.circular(8)), child: Row(children: [IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => _adjustDate(-1)), Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text(viewMode == 1 ? "${selectedDate.year}" : DateFormat('MMM yyyy').format(selectedDate).toUpperCase())), IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => _adjustDate(1))]));
  }

  void _adjustDate(int offset) {
    setState(() { selectedDate = viewMode == 1 ? DateTime(selectedDate.year + offset, 1) : DateTime(selectedDate.year, selectedDate.month + offset); });
  }

  Widget _buildExportAction(Map staffData, Map kuriData, Map breakdownData) {
    double totalCol = 0; double totalExp = 0;
    staffData.forEach((k, v) { totalCol += (v['cash'] + v['gpay']); totalExp += v['exp']; });

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderCol)
      ),
      child: Row(
        children: [
          const Icon(Icons.print_rounded, color: accentBlue, size: 24),
          const SizedBox(width: 16),
          const Text("PRINT AUDIT REPORTS:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: textMuted)),
          const SizedBox(width: 24),

          // Report 1: Staff
          _reportBtn("STAFF PERFORMANCE", () => _generatePdf(staffData, totalCol, totalExp, "STAFF")),
          const SizedBox(width: 12),

          // Report 2: Kuri
          _reportBtn("KURI PERFORMANCE", () => _generatePdf(kuriData, totalCol, totalExp, "KURI")),
          const SizedBox(width: 12),

          // Report 3: Breakdown
          _reportBtn("COLLECTION BREAKDOWN", () => _generatePdf(breakdownData, totalCol, totalExp, "BREAKDOWN")),
        ],
      ),
    );
  }

  Widget _reportBtn(String label, VoidCallback onPress) {
    return OutlinedButton.icon(
      onPressed: onPress,
      icon: const Icon(Icons.picture_as_pdf, size: 16),
      label: Text(label),
      style: OutlinedButton.styleFrom(
          foregroundColor: sideNavColor,
          side: const BorderSide(color: borderCol),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))
      ),
    );
  }

  Future<void> _generatePdf(Map data, double tc, double te, String type) async {
    final pdf = pw.Document();
    String reportPeriod = viewMode == 0
        ? DateFormat('MMMM yyyy').format(selectedDate)
        : (viewMode == 1 ? "Year ${selectedDate.year}" : "Lifetime Total");

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          // --- HEADER ---
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text("$type AUDIT REPORT",
                      style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                  pw.SizedBox(height: 4),
                  pw.Text("Period: $reportPeriod", style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                ],
              ),
              pw.Text("Generated: ${DateFormat('dd-MMM-yyyy').format(DateTime.now())}",
                  style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
            ],
          ),
          pw.SizedBox(height: 15),
          pw.Divider(thickness: 1, color: PdfColors.grey300),
          pw.SizedBox(height: 15),

          // --- SUMMARY TILES ---
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              _pdfSummaryTile("Total Collected", pdfFormat.format(tc)),
              _pdfSummaryTile("Total Expenses", pdfFormat.format(te)),
              _pdfSummaryTile("Net System Balance", pdfFormat.format(tc - te), isHighlight: true),
            ],
          ),
          pw.SizedBox(height: 25),

          // --- DYNAMIC CONTENT BASED ON TYPE ---
          if (type == "BREAKDOWN")
            _buildBreakdownPdfTable(data.cast<String, Map<String, Map<String, double>>>())
          else
            _buildStandardPdfTable(data.cast<String, Map<String, dynamic>>(), type),

          pw.SizedBox(height: 40),

          // --- FOOTER ---
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              _pdfSignatureBox("Prepared By"),
              _pdfSignatureBox("Authorised Signatory"),
            ],
          ),
        ],
      ),
    );

    await Printing.layoutPdf(onLayout: (format) async => pdf.save(), name: '${type}_Report_$reportPeriod');
  }

// Table for Staff & Kuri Performance
// Standard Table for Staff and Kuri Performance
  pw.Widget _buildStandardPdfTable(Map<String, Map<String, dynamic>> data, String type) {
    return pw.TableHelper.fromTextArray(
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 8),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey900),
      cellStyle: const pw.TextStyle(fontSize: 8),
      cellHeight: 22,
      cellAlignment: pw.Alignment.centerRight,
      cellAlignments: {0: pw.Alignment.centerLeft},

      // CORRECT PARAMETER NAME IS 'border'
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),

      headers: [type == "STAFF" ? 'STAFF NAME' : 'KURI NAME', 'CASH', 'GPAY', 'EXPENSE', 'NET'],
      data: data.entries.map((e) {
        double net = (e.value['cash'] + e.value['gpay']) - e.value['exp'];
        return [
          e.value['name'].toString().toUpperCase(),
          pdfFormat.format(e.value['cash']),
          pdfFormat.format(e.value['gpay']),
          pdfFormat.format(e.value['exp']),
          pdfFormat.format(net),
        ];
      }).toList(),
    );
  }

// Complex Table for Staff-Kuri Breakdown
  pw.Widget _buildBreakdownPdfTable(Map<String, Map<String, Map<String, double>>> data) {
    List<pw.Widget> rows = [];

    data.forEach((kuriName, staffMap) {
      double kuriTotal = 0;
      staffMap.forEach((_, val) => kuriTotal += (val['cash']! + val['gpay']!));

      if (kuriTotal > 0) {
        rows.add(
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(6),
              decoration: const pw.BoxDecoration(color: PdfColors.grey200),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(kuriName.toUpperCase(), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                  pw.Text("Total: ${pdfFormat.format(kuriTotal)}", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                ],
              ),
            )
        );

        rows.add(pw.TableHelper.fromTextArray(
          cellStyle: const pw.TextStyle(fontSize: 8),
          cellHeight: 18,
          headerStyle: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold),
          cellAlignment: pw.Alignment.centerRight,
          cellAlignments: {0: pw.Alignment.centerLeft},

          // CORRECT PARAMETER NAME IS 'border'
          border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),

          headers: ['Collector', 'Cash', 'GPay', 'Total'],
          data: staffMap.entries.where((s) => (s.value['cash']! + s.value['gpay']!) > 0).map((s) => [
            s.key,
            pdfFormat.format(s.value['cash']),
            pdfFormat.format(s.value['gpay']),
            pdfFormat.format(s.value['cash']! + s.value['gpay']!),
          ]).toList(),
        ));
        rows.add(pw.SizedBox(height: 15));
      }
    });

    return pw.Column(children: rows);
  }
// Table for the complex Staff-Kuri Breakdown

  pw.Widget _pdfSummaryTile(String label, String value, {bool isHighlight = false}) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      width: 140,
      decoration: pw.BoxDecoration(
        color: isHighlight ? PdfColors.blue50 : PdfColors.white,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
        border: pw.Border.all(color: isHighlight ? PdfColors.blue900 : PdfColors.grey300),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label, style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700)),
          pw.SizedBox(height: 2),
          pw.Text(value, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: isHighlight ? PdfColors.blue900 : PdfColors.black)),
        ],
      ),
    );
  }

  pw.Widget _pdfSignatureBox(String label) {
    return pw.Column(
      children: [
        pw.Container(
          width: 100,
          // Use decoration instead of border
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              top: pw.BorderSide(width: 0.5, color: PdfColors.black),
            ),
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(label, style: const pw.TextStyle(fontSize: 8)),
      ],
    );
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
        if (latestSnapshots.every((s) => s != null)) controller.add(mapper(latestSnapshots.cast<QuerySnapshot>()));
      }));
    }
    controller.onCancel = () { for (var sub in subscriptions) sub.cancel(); };
    return controller.stream;
  }
}