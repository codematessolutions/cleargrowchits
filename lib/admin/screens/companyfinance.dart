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

  // 0 = Month, 1 = Year, 2 = Total
  int viewMode = 0;

  final uiFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
  final pdfFormat = NumberFormat.currency(locale: 'en_IN', symbol: 'Rs. ', decimalDigits: 0);

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
    // viewMode 2 (Total) adds no filters to the queries

    Stream<QuerySnapshot> staffStream = FirebaseFirestore.instance.collection('staff_admins').snapshots();
    Stream<QuerySnapshot> kuriMasterStream = FirebaseFirestore.instance.collection('kuris').snapshots();

    return StreamZipCustom([paymentQuery.snapshots(), expenseQuery.snapshots(), staffStream, kuriMasterStream]).map((list) {
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

                  Map<String, String> staffNameMap = { for (var s in staffList) s.id : (s.data() as Map)['name'] ?? "Unknown" };

                  // Initialize Staff Data
                  Map<String, Map<String, dynamic>> staffAudit = {};
                  for (var s in staffList) {
                    staffAudit[s.id] = {"name": staffNameMap[s.id], "cash": 0.0, "gpay": 0.0, "exp": 0.0};
                  }

                  // Initialize Kuri Data from Master List (Ensures all Kuris show up)
                  Map<String, Map<String, dynamic>> kuriAudit = {};
                  Map<String, Map<String, Map<String, double>>> kuriStaffBreakdown = {};

                  for (var k in kuriMasterList) {
                    final kData = k.data() as Map<String, dynamic>;
                    String kId = k.id;
                    String displayName = kData['name'] ?? "Kuri ($kId)";

                    kuriAudit[kId] = {"name": displayName, "cash": 0.0, "gpay": 0.0, "exp": 0.0};
                    // We use displayName for the breakdown UI
                    kuriStaffBreakdown[displayName] = {};
                  }

                  // Process Collections
                  for (var doc in payments) {
                    final data = doc.data() as Map<String, dynamic>;
                    final splits = data['paymentSplits'] as List? ?? [];
                    String kId = data['kuriId']?.toString() ?? "";

                    // Find the correct display name from our master list using the ID
                    String currentKuriDisplayName = kuriAudit[kId]?['name'] ?? "Unknown Kuri";

                    for (var s in splits) {
                      String sId = s['collectorId'] ?? "";
                      String sName = staffNameMap[sId] ?? "Unknown Staff";
                      double amt = double.tryParse(s['amount'].toString()) ?? 0.0;
                      bool isGpay = s['mode'] == "GPay";

                      // Update Staff Totals
                      if (staffAudit.containsKey(sId)) {
                        if (isGpay) staffAudit[sId]!["gpay"] += amt;
                        else staffAudit[sId]!["cash"] += amt;
                      }

                      // Update Kuri Totals (Using kId to ensure it matches)
                      if (kuriAudit.containsKey(kId)) {
                        if (isGpay) kuriAudit[kId]!["gpay"] += amt;
                        else kuriAudit[kId]!["cash"] += amt;
                      }

                      // Update Breakdown (Using the name we found)
                      var breakdown = kuriStaffBreakdown[currentKuriDisplayName];
                      if (breakdown != null) {
                        breakdown.putIfAbsent(sName, () => {"cash": 0.0, "gpay": 0.0});
                        if (isGpay) {
                          breakdown[sName]!["gpay"] = (breakdown[sName]!["gpay"] ?? 0.0) + amt;
                        } else {
                          breakdown[sName]!["cash"] = (breakdown[sName]!["cash"] ?? 0.0) + amt;
                        }
                      }
                    }
                  }

                  // Process Expenses
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
            tabs: [
              Tab(text: "STAFF PERFORMANCE"),
              Tab(text: "KURI PERFORMANCE"),
              Tab(text: "STAFF-KURI BREAKDOWN")
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildViewSwitcher() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: const Color(0xFFE5E7EB), borderRadius: BorderRadius.circular(8)),
      child: Row(
        children: [
          _switchItem("Month", viewMode == 0, 0),
          _switchItem("Year", viewMode == 1, 1),
          _switchItem("Total", viewMode == 2, 2),
        ],
      ),
    );
  }

  Widget _switchItem(String label, bool active, int mode) {
    return InkWell(
      onTap: () => setState(() => viewMode = mode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(color: active ? Colors.white : Colors.transparent, borderRadius: BorderRadius.circular(6)),
        child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: active ? accentBlue : textMuted)),
      ),
    );
  }

  Widget _buildContent(Map staffData, Map kuriData, Map breakdownData) {
    double totalCol = 0; double totalExp = 0;
    staffData.forEach((k, v) { totalCol += (v['cash'] + v['gpay']); totalExp += v['exp']; });

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Column(
            children: [
              _buildMetricCards(totalCol, totalExp),
              const SizedBox(height: 32),
              SizedBox(
                height: 800,
                child: TabBarView(
                  children: [
                    _buildTableCard(staffData.cast<String, Map<String, dynamic>>(), "STAFF NAME"),
                    _buildTableCard(kuriData.cast<String, Map<String, dynamic>>(), "KURI SCHEME"),
                    _buildKuriStaffBreakdown(breakdownData.cast<String, Map<String, Map<String, double>>>()),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              _buildExportAction(staffData, totalCol, totalExp),
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
      return DataRow(cells: [
        DataCell(Text(e.value['name'].toString().toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
        DataCell(Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(uiFormat.format(total), style: const TextStyle(fontWeight: FontWeight.bold, color: accentBlue)),
          Text("C: ${uiFormat.format(e.value['cash'])} | G: ${uiFormat.format(e.value['gpay'])}", style: const TextStyle(fontSize: 10, color: textMuted)),
        ])),
        DataCell(Text(uiFormat.format(e.value['exp']), style: const TextStyle(color: textMuted))),
        DataCell(Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: balance >= 0 ? Colors.blue.withOpacity(0.1) : Colors.red.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
          child: Text(uiFormat.format(balance), style: TextStyle(fontWeight: FontWeight.bold, color: balance >= 0 ? accentBlue : Colors.red.shade700)),
        )),
      ]);
    }).toList();

    rows.add(DataRow(color: WidgetStateProperty.all(const Color(0xFFF1F5F9)), cells: [
      const DataCell(Text("GRAND TOTAL", style: TextStyle(fontWeight: FontWeight.w900))),
      DataCell(Text(uiFormat.format(grandCash + grandGPay), style: const TextStyle(fontWeight: FontWeight.w900))),
      DataCell(Text(uiFormat.format(grandExp), style: const TextStyle(fontWeight: FontWeight.w900))),
      DataCell(Text(uiFormat.format((grandCash + grandGPay) - grandExp), style: const TextStyle(fontWeight: FontWeight.w900))),
    ]));

    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: borderCol)),
      child: ClipRRect(borderRadius: BorderRadius.circular(12), child: SingleChildScrollView(child: DataTable(headingRowHeight: 60, dataRowHeight: 80, columns: [
        DataColumn(label: Text(label, style: const TextStyle(fontWeight: FontWeight.bold))),
        const DataColumn(label: Text("COLLECTED")), const DataColumn(label: Text("EXPENSES")), const DataColumn(label: Text("BALANCE")),
      ], rows: rows))),
    );
  }

  Widget _buildKuriStaffBreakdown(Map<String, Map<String, Map<String, double>>> data) {
    if (data.isEmpty) return _buildEmptyState();

    // Use LayoutBuilder to make the grid responsive
    return LayoutBuilder(builder: (context, constraints) {
      int crossAxisCount = constraints.maxWidth > 1400 ? 3 : (constraints.maxWidth > 900 ? 2 : 1);

      return GridView.builder(
        padding: const EdgeInsets.all(24),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: 24,
          mainAxisSpacing: 24,
          mainAxisExtent: 480, // Taller for better list visibility
        ),
        itemCount: data.length,
        itemBuilder: (context, index) {
          String kuriName = data.keys.elementAt(index);
          var staffData = data[kuriName]!;

          double totalCash = 0;
          double totalGpay = 0;
          staffData.forEach((_, val) {
            totalCash += val['cash']!;
            totalGpay += val['gpay']!;
          });

          var activeStaff = staffData.entries
              .where((e) => (e.value['cash']! + e.value['gpay']!) > 0)
              .toList();

          return Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderCol),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 2))],
            ),
            child: Column(
              children: [
                // --- DASHBOARD HEADER ---
                _buildKuriCardHeader(kuriName, totalCash + totalGpay, totalCash, totalGpay),

                // --- COLUMN TITLES ---
                _buildBreakdownTableSubHeader(),

                // --- DATA LIST ---
                Expanded(
                  child: activeStaff.isEmpty
                      ? const Center(child: Text("No Data", style: TextStyle(color: textMuted)))
                      : ListView.separated(
                    itemCount: activeStaff.length,
                    separatorBuilder: (context, i) => const Divider(height: 1, color: borderCol),
                    itemBuilder: (context, i) {
                      final s = activeStaff[i];
                      return _buildStaffRow(i + 1, s.key, s.value['cash']!, s.value['gpay']!);
                    },
                  ),
                ),

                // --- FOOTER ---
                _buildKuriCardFooter(activeStaff.length),
              ],
            ),
          );
        },
      );
    });
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: borderCol.withOpacity(0.5)),
            ),
            child: Icon(Icons.folder_open_rounded, size: 64, color: textMuted.withOpacity(0.3)),
          ),
          const SizedBox(height: 24),
          const Text(
            "No Data Records Found",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: textMain,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            "There are no collections for the selected period.",
            style: TextStyle(color: textMuted),
          ),
        ],
      ),
    );
  }

// 1. Clean Gradient-ish Header
  Widget _buildKuriCardHeader(String name, double total, double cash, double gpay) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: accentBlue.withOpacity(0.04),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name.toUpperCase(),
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: textMain, letterSpacing: 0.5),
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Row(
                  children: [
                    _miniTag("Cash: ${uiFormat.format(cash)}", Colors.green),
                    const SizedBox(width: 8),
                    _miniTag("GPay: ${uiFormat.format(gpay)}", accentBlue),
                  ],
                ),
              ],
            ),
          ),
          Text(uiFormat.format(total), style: const TextStyle(fontWeight: FontWeight.w900, color: accentBlue, fontSize: 18)),
        ],
      ),
    );
  }

// 2. Sticky Sub-header for the "Table"
  Widget _buildBreakdownTableSubHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: webBg,
      child: Row(
        children: const [
          SizedBox(width: 30, child: Text("SI", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: textMuted))),
          Expanded(flex: 3, child: Text("COLLECTOR", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: textMuted))),
          Expanded(flex: 2, child: Text("CASH", textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: textMuted))),
          Expanded(flex: 2, child: Text("GPAY", textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: textMuted))),
          Expanded(flex: 2, child: Text("TOTAL", textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: textMuted))),
        ],
      ),
    );
  }

// 3. Modern Row Design
  Widget _buildStaffRow(int si, String name, double cash, double gpay) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          SizedBox(width: 30, child: Text("$si", style: const TextStyle(color: textMuted, fontSize: 12))),
          Expanded(flex: 3, child: Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: textMain))),
          Expanded(flex: 2, child: Text(uiFormat.format(cash), textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, color: Colors.green))),
          Expanded(flex: 2, child: Text(uiFormat.format(gpay), textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, color: accentBlue))),
          Expanded(
              flex: 2,
              child: Text(uiFormat.format(cash + gpay),
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: textMain)
              )
          ),
        ],
      ),
    );
  }

  Widget _miniTag(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
      child: Text(label, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildKuriCardFooter(int count) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: borderCol))),
      child: Row(
        children: [
          Icon(Icons.group, size: 14, color: textMuted.withOpacity(0.7)),
          const SizedBox(width: 6),
          Text("$count Collectors Active", style: const TextStyle(color: textMuted, fontSize: 11)),
        ],
      ),
    );
  }



  Widget _buildDateControls() {
    return Container(
      decoration: BoxDecoration(border: Border.all(color: borderCol), borderRadius: BorderRadius.circular(8)),
      child: Row(children: [
        IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => _adjustDate(-1)),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text(viewMode == 1 ? "${selectedDate.year}" : DateFormat('MMM yyyy').format(selectedDate).toUpperCase())),
        IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => _adjustDate(1)),
      ]),
    );
  }

  void _adjustDate(int offset) {
    setState(() { selectedDate = viewMode == 1 ? DateTime(selectedDate.year + offset, 1) : DateTime(selectedDate.year, selectedDate.month + offset); });
  }

  Widget _buildExportAction(data, tc, te) {
    return Align(alignment: Alignment.centerRight, child: ElevatedButton.icon(onPressed: () => _generatePdf(data, tc, te), icon: const Icon(Icons.print), label: const Text("PRINT AUDIT REPORT"), style: ElevatedButton.styleFrom(backgroundColor: sideNavColor, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20))));
  }

  Future<void> _generatePdf(Map data, double tc, double te) async {
    final pdf = pw.Document();
    pdf.addPage(pw.MultiPage(build: (context) => [
      pw.Header(level: 0, child: pw.Text("Audit Report: ${viewMode == 2 ? 'LIFETIME TOTAL' : DateFormat('MMMM yyyy').format(selectedDate)}")),
      pw.SizedBox(height: 20),
      pw.TableHelper.fromTextArray(headers: ['Entity', 'Cash', 'GPay', 'Expense', 'Balance'], data: data.entries.map((e) => [
        e.value['name'].toUpperCase(), pdfFormat.format(e.value['cash']), pdfFormat.format(e.value['gpay']), pdfFormat.format(e.value['exp']), pdfFormat.format(e.value['cash'] + e.value['gpay'] - e.value['exp'])
      ]).toList()),
      pw.Divider(),
      pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text("Gross Collection: ${pdfFormat.format(tc)}", style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
      pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text("Net Balance: ${pdfFormat.format(tc - te)}", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)))
    ]));
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
        if (latestSnapshots.every((s) => s != null)) controller.add(mapper(latestSnapshots.cast<QuerySnapshot>()));
      }));
    }
    controller.onCancel = () { for (var sub in subscriptions) sub.cancel(); };
    return controller.stream;
  }
}