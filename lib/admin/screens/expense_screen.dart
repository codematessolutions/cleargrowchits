import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/utils/kuri_theme.dart';

class ExpenseManagerWeb extends StatefulWidget {
  final String userId;
  final String userName;
  final String userRole;

  const ExpenseManagerWeb({
    super.key,
    required this.userId,
    required this.userName,
    required this.userRole,
  });

  @override
  State<ExpenseManagerWeb> createState() => _ExpenseManagerWebState();
}

class _ExpenseManagerWebState extends State<ExpenseManagerWeb> with SingleTickerProviderStateMixin {
  TabController? _tabController;
  DateTime selectedDate = DateTime(DateTime.now().year, DateTime.now().month);
  final currencyFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

  String selectedStaffFilter = "All Staff";
  String staffSearchQuery = "";

  static const Color sideBarColor = Color(0xFF0F172A);
  static const Color bgColor = Color(0xFFF8FAFC);
  static const Color borderColor = Color(0xFFE2E8F0);
  static const Color primaryBlue = Color(0xFF1E40AF);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_tabController == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      backgroundColor: bgColor,
      body: Row(
        children: [
          Expanded(
            child: Column(
              children: [
                _buildHeader(),
                _buildTabStrip(),
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    // Note: Removed .orderBy('date') to prevent crashes if 'date' field is missing.
                    // Sorting is now handled manually below for safety.
                    stream: FirebaseFirestore.instance.collection('expenses').snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

                      var allDocs = snapshot.data!.docs;

                      // 1. SAFE FILTERING & SORTING
                      var filteredDocs = allDocs.where((doc) {
                        final data = doc.data() as Map<String, dynamic>;

                        // Check for 'expenseDate' first (new format), then 'date' (old format)
                        Timestamp? ts = data['expenseDate'] as Timestamp? ?? data['date'] as Timestamp?;

                        if (ts == null) return false; // Ignore records with no date at all

                        DateTime d = ts.toDate();
                        // Filter based on the selected month/year from your header
                        return d.year == selectedDate.year && d.month == selectedDate.month;
                      }).toList();

                      // 2. MANUAL SORT (Descending by date)
                      filteredDocs.sort((a, b) {
                        final dataA = a.data() as Map<String, dynamic>;
                        final dataB = b.data() as Map<String, dynamic>;
                        Timestamp tsA = dataA['expenseDate'] as Timestamp? ?? dataA['date'] as Timestamp? ?? Timestamp.now();
                        Timestamp tsB = dataB['expenseDate'] as Timestamp? ?? dataB['date'] as Timestamp? ?? Timestamp.now();
                        return tsB.compareTo(tsA);
                      });

                      return TabBarView(
                        controller: _tabController,
                        children: [
                          _buildOverviewPanel(filteredDocs),
                          _buildKuriPanel(filteredDocs.where((d) => (d.data() as Map)['type'] == 'KURI').toList()),
                          _buildCompanyPanel(filteredDocs.where((d) => (d.data() as Map)['type'] == 'COMPANY').toList()),
                          _buildStaffAnalyticsPanel(filteredDocs),
                        ],
                      );
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

  // --- UI PANELS ---
  Widget _buildOverviewPanel(List<DocumentSnapshot> docs) {
    double kuriTotal = 0, officeTotal = 0;

    for (var d in docs) {
      final data = d.data() as Map<String, dynamic>;
      double amt = double.tryParse(data['amount']?.toString() ?? '0') ?? 0;
      if (data['type'] == 'KURI') {
        kuriTotal += amt;
      } else {
        officeTotal += amt;
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // FIXED: Using LayoutBuilder instead of Expanded to prevent ParentData errors
          LayoutBuilder(
            builder: (context, constraints) {
              double cardWidth = (constraints.maxWidth - 32) / 3;
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  SizedBox(width: cardWidth, child: _statCard("TOTAL EXPENSE", kuriTotal + officeTotal, primaryBlue, Icons.account_balance_wallet)),
                  SizedBox(width: cardWidth, child: _statCard("KURI EXPENSE", kuriTotal, Colors.orange.shade800, Icons.layers)),
                  SizedBox(width: cardWidth, child: _statCard("OFFICE/COMPANY", officeTotal, Colors.blueAccent, Icons.business)),
                ],
              );
            },
          ),

          const SizedBox(height: 32),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildSectionHeader("Recent Activities"),

            ],
          ),
          const SizedBox(height: 12),

          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))
              ],
            ),
            // We pass the list directly; _buildDataTable handles its own constraints
            child: _buildDataTable(docs.take(15).toList()),
          ),
        ],
      ),
    );
  }

  Widget _buildKuriPanel(List<DocumentSnapshot> docs) => _buildStandardPanel("Kuri Related Costs", docs);
  Widget _buildCompanyPanel(List<DocumentSnapshot> docs) => _buildStandardPanel("Office Overhead", docs);

  Widget _buildStandardPanel(String title, List<DocumentSnapshot> docs) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(title),
        const SizedBox(height: 12),
        // Table is now scrollable here safely
        Expanded(child: SingleChildScrollView(child: _buildDataTable(docs))),
      ],
    ),
  );

  Widget _buildDataTable(List<DocumentSnapshot> docs) {
    final currencyFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

    // REMOVED SingleChildScrollView from here
    return SizedBox(
      width: double.infinity,
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(const Color(0xFFF1F5F9)),
        columns: const [
          DataColumn(label: Text("ENTRY BY")),
          DataColumn(label: Text("EXP. DATE")),
          DataColumn(label: Text("STAFF")),
          DataColumn(label: Text("DESC")),
          DataColumn(label: Text("AMOUNT")),
          DataColumn(label: Text("ACTION")),
        ],
        rows: docs.map((d) {
          final data = d.data() as Map<String, dynamic>;

          final DateTime expDate = data['expenseDate'] != null
              ? (data['expenseDate'] as Timestamp).toDate()
              : (data['date'] != null ? (data['date'] as Timestamp).toDate() : DateTime.now());

          final Map<String, dynamic>? entry = data['entryDetails'] as Map<String, dynamic>?;
          final String addedBy = entry?['addedByUserName'] ?? data['userName'] ?? 'Admin';
          final DateTime addedAt = (entry?['addedAt'] as Timestamp?)?.toDate() ??
              (data['date'] as Timestamp?)?.toDate() ??
              DateTime.now();

          return DataRow(cells: [
            DataCell(Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(addedBy.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.brown)),
                  Text(DateFormat('dd-MM hh:mm a').format(addedAt), style: const TextStyle(color: Colors.grey, fontSize: 10)),
                ])),
            DataCell(Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(6)),
                child: Text(DateFormat('dd/MM/yyyy').format(expDate),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blue)))),
            DataCell(Text(data['staffName'] ?? "-")),
            DataCell(Text(data['title'].toString().toUpperCase(), style: const TextStyle(fontSize: 11))),
            DataCell(Text(currencyFormat.format(data['amount']), style: const TextStyle(fontWeight: FontWeight.bold))),
            DataCell(IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
              onPressed: () => _confirmDelete(d),
            )),
          ]);
        }).toList(),
      ),
    );
  }



  Widget _buildStaffAnalyticsPanel(List<DocumentSnapshot> docs) {
    Map<String, double> staffTotals = {};
    Map<String, int> staffCounts = {};

    for (var d in docs) {
      final data = d.data() as Map<String, dynamic>;
      String name = data['staffName'] ?? "Unknown";
      double amt = double.tryParse(data['amount']?.toString() ?? '0') ?? 0;
      staffTotals[name] = (staffTotals[name] ?? 0) + amt;
      staffCounts[name] = (staffCounts[name] ?? 0) + 1;
    }

    final filteredDocsForTable = docs.where((d) {
      final data = d.data() as Map<String, dynamic>;
      bool matchesStaff = selectedStaffFilter == "All Staff" || data['staffName'] == selectedStaffFilter;
      bool matchesSearch = data['title'].toString().toLowerCase().contains(staffSearchQuery.toLowerCase());
      return matchesStaff && matchesSearch;
    }).toList();

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left Column: Staff Summary
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("STAFF SUMMARY", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 16),
                Expanded(
                  child: ListView(
                    children: staffTotals.entries.map((e) => _buildStaffInfoCard(e.key, e.value, staffCounts[e.key]!)).toList(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 24),
          // Right Column: Detailed Transactions
          Expanded(
            flex: 5,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        const Text("TRANSACTIONS", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        const Spacer(),
                        _buildStaffDropdown(staffTotals.keys.toList()),
                        const SizedBox(width: 12),
                        _buildSearchField(),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  // Wrap table in Expanded + SingleChildScrollView to allow vertical scrolling
                  // within the right-hand panel safely.
                  Expanded(
                    child: SingleChildScrollView(
                      child: _buildDataTable(filteredDocsForTable),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- COMPONENTS ---


  Future<void> _generateReport({required bool isGrandTotal}) async {
    final pdf = pw.Document();
    final String reportTitle = isGrandTotal
        ? "GRAND TOTAL EXPENSE REPORT"
        : "EXPENSE REPORT - ${DateFormat('MMMM yyyy').format(selectedDate)}";

    final pdfCurrency = NumberFormat.currency(locale: 'en_IN', symbol: 'Rs. ', decimalDigits: 2);

    // 1. Fetch Data
    // Note: We don't orderBy 'date' here because new records use 'expenseDate'
    // Sorting is handled better in memory if you have mixed field names
    final snap = await FirebaseFirestore.instance.collection('expenses').get();

    var docs = snap.docs;

    // 2. Filter and Sort in memory to handle both old ('date') and new ('expenseDate') fields
    List<QueryDocumentSnapshot> filteredDocs = docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;

      // Use the same safe date logic used in your UI
      final DateTime d = data['expenseDate'] != null
          ? (data['expenseDate'] as Timestamp).toDate()
          : (data['date'] != null ? (data['date'] as Timestamp).toDate() : DateTime.now());

      if (isGrandTotal) return true;
      return d.year == selectedDate.year && d.month == selectedDate.month;
    }).toList();

    // Sort descending by date
    filteredDocs.sort((a, b) {
      final da = (a.data() as Map)['expenseDate'] ?? (a.data() as Map)['date'];
      final db = (b.data() as Map)['expenseDate'] ?? (b.data() as Map)['date'];
      return (db as Timestamp).compareTo(da as Timestamp);
    });

    // 3. Calculate Totals
    double total = 0;
    double kuriTotal = 0;
    double officeTotal = 0;
    for (var d in filteredDocs) {
      final data = d.data() as Map<String, dynamic>;
      double amt = double.tryParse(data['amount'].toString()) ?? 0;
      total += amt;
      if (data['type'] == 'KURI') kuriTotal += amt; else officeTotal += amt;
    }

    // 4. Create PDF Layout (Design preserved)
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) => [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(reportTitle, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
                  pw.Text("Generated on: ${DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now())}"),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text("Generated By: ${widget.userName}", style: pw.TextStyle(fontSize: 10)),
                  pw.Text("Role: ${widget.userRole}", style: pw.TextStyle(fontSize: 10)),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 20),
          pw.Divider(),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              _pdfStatCard("Total Expense", pdfCurrency.format(total)),
              _pdfStatCard("Kuri Expense", pdfCurrency.format(kuriTotal)),
              _pdfStatCard("Office/Company", pdfCurrency.format(officeTotal)),
            ],
          ),
          pw.SizedBox(height: 20),
          pw.TableHelper.fromTextArray(
            headers: ['Date & Time', 'Added By', 'Staff', 'Category', 'Description', 'Amount'],
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 10),
            headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF1E40AF)),
            cellStyle: const pw.TextStyle(fontSize: 9),
            cellHeight: 25,
            columnWidths: {
              0: const pw.FlexColumnWidth(2),
              1: const pw.FlexColumnWidth(1.5),
              2: const pw.FlexColumnWidth(1.5),
              3: const pw.FlexColumnWidth(2),
              4: const pw.FlexColumnWidth(3),
              5: const pw.FlexColumnWidth(2),
            },
            data: filteredDocs.map((d) {
              final data = d.data() as Map<String, dynamic>;
              final type = data['type'] ?? 'COMPANY';
              final kuriName = data['kuriName'] ?? '';
              final double amt = double.tryParse(data['amount'].toString()) ?? 0;

              // Safe Date Fetching
              final DateTime dateVal = data['expenseDate'] != null
                  ? (data['expenseDate'] as Timestamp).toDate()
                  : (data['date'] != null ? (data['date'] as Timestamp).toDate() : DateTime.now());

              // Get Added By from nested entryDetails map
              final entry = data['entryDetails'] as Map<String, dynamic>?;
              final String addedBy = entry?['addedByUserName'] ?? data['userName'] ?? 'Admin';

              return [
                DateFormat('dd/MM/yy, hh:mm a').format(dateVal),
                addedBy,
                data['staffName'] ?? '-',
                type == 'KURI' ? "KURI\n($kuriName)" : "OFFICE",
                data['title'].toString().toUpperCase(),
                pdfCurrency.format(amt),
              ];
            }).toList(),
          ),
          pw.SizedBox(height: 20),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
                "Final Total: ${pdfCurrency.format(total)}",
                style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)
            ),
          ),
        ],
      ),
    );

    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save());
  }  // PDF Stat Card Helper
  pw.Widget _pdfStatCard(String label, String value) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Column(
        children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
          pw.Text(value, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );
  }

  // UI Header Button Helper
  Widget _buildHeaderAction({required IconData icon, required String label, required VoidCallback onTap}) {
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18, color: primaryBlue),
      label: Text(label, style: const TextStyle(color: primaryBlue, fontSize: 12, fontWeight: FontWeight.bold)),
      style: TextButton.styleFrom(
        backgroundColor: primaryBlue.withOpacity(0.1),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }

  Widget _buildHeader() => Container(
      height: 70,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(bottom: BorderSide(color: borderColor))
      ),
      child: Row(children: [
        IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios_new, size: 20, color: KuriTheme.textDark),
          padding: const EdgeInsets.only(right: 16), // Spacing between button and title
        ),
        const Text("EXPENSE DASHBOARD", style: TextStyle(fontWeight: FontWeight.w800, color: sideBarColor)),
        const Spacer(),
        _buildDateNavigator(),
        const SizedBox(width: 16),

        // PDF Monthly Button
        _buildHeaderAction(
            icon: Icons.picture_as_pdf,
            label: "MONTHLY PDF",
            onTap: () => _generateReport(isGrandTotal: false)
        ),
        const SizedBox(width: 8),

        // PDF Grand Total Button
        _buildHeaderAction(
            icon: Icons.summarize,
            label: "GRAND TOTAL",
            onTap: () => _generateReport(isGrandTotal: true)
        ),
        const SizedBox(width: 12),

        // Original New Button
        ElevatedButton.icon(
            onPressed: () => _showAddDialog(),
            icon: const Icon(Icons.add),
            label: const Text("NEW"),
            style: ElevatedButton.styleFrom(
                backgroundColor: primaryBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18)
            )
        ),
      ])
  );
  Widget _buildTableFooter(double total) => Container(
    padding: const EdgeInsets.all(16),
    decoration: const BoxDecoration(color: Color(0xFFF8FAFC), border: Border(top: BorderSide(color: borderColor))),
    child: Row(children: [const Text("TOTAL"), const Spacer(), Text(currencyFormat.format(total), style: const TextStyle(fontWeight: FontWeight.w900, color: primaryBlue))]),
  );



  Widget _buildTabStrip() => Container(color: Colors.white, child: TabBar(controller: _tabController, labelColor: primaryBlue, indicatorColor: primaryBlue, tabs: const [Tab(text: "OVERVIEW"), Tab(text: "KURI"), Tab(text: "COMPANY"), Tab(text: "STAFF")]));
  Widget _statCard(String t, double v, Color c, IconData i) => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: borderColor),
    ),
    child: Row(
      children: [
        Icon(i, color: c, size: 32),
        const SizedBox(width: 20),
        // Use Expanded here instead to ensure text doesn't overflow the card
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min, // Keep it compact
            children: [
              Text(t, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              FittedBox( // Prevents large numbers from breaking the layout
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  currencyFormat.format(v),
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: c),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );  Widget _buildStaffInfoCard(String n, double t, int c) => Container(margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: borderColor)), child: Row(children: [CircleAvatar(child: Text(n[0])), const SizedBox(width: 16), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(n, style: const TextStyle(fontWeight: FontWeight.bold)), Text("$c Entries")]), const Spacer(), Text(currencyFormat.format(t), style: const TextStyle(fontWeight: FontWeight.bold))]));
  Widget _buildDateNavigator() {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: () => setState(() {
            // Subtract 1 month
            selectedDate = DateTime(selectedDate.year, selectedDate.month - 1, 1);
          }),
        ),
        // Changed format to 'MMMM yyyy' (e.g., March 2024)
        Text(
          DateFormat('MMMM yyyy').format(selectedDate),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          onPressed: () => setState(() {
            // Add 1 month
            selectedDate = DateTime(selectedDate.year, selectedDate.month + 1, 1);
          }),
        ),
      ],
    );
  }  Widget _buildStaffDropdown(List<String> list) => DropdownButton<String>(value: selectedStaffFilter, items: ["All Staff", ...list].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(), onChanged: (v) => setState(() => selectedStaffFilter = v!));
  Widget _buildSearchField() => SizedBox(width: 200, height: 38, child: TextField(onChanged: (v) => setState(() => staffSearchQuery = v), decoration: const InputDecoration(hintText: "Search...", border: OutlineInputBorder())));
  Widget _buildSectionHeader(String t) => Text(t, style: const TextStyle(fontWeight: FontWeight.bold, color: sideBarColor));

  void _confirmDelete(DocumentSnapshot d) => showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text("Delete?"), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("No")), ElevatedButton(onPressed: () { d.reference.delete(); Navigator.pop(ctx); }, child: const Text("Yes"))]));
  void _showAddDialog() => showDialog(context: context, builder: (ctx) => AddExpenseDialog(userId: widget.userId, userName: widget.userName, userRole: widget.userRole,));
}

// --- ADD EXPENSE DIALOG (MAPPED TO YOUR COLLECTIONS) ---
class AddExpenseDialog extends StatefulWidget {
  final String userId, userName,userRole;
  const AddExpenseDialog({super.key, required this.userId, required this.userName,required this.userRole});
  @override
  State<AddExpenseDialog> createState() => _AddExpenseDialogState();
}

class _AddExpenseDialogState extends State<AddExpenseDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _amtCtrl = TextEditingController();

  String? _selectedKuriId;   // To store the Firestore Document ID
  String? _selectedKuriName; // To store the Display Name
  String _selectedType = 'COMPANY';
  String? _selectedStaff;
  String? _selectedKuri;

  @override
  void initState() {
    super.initState();
    _selectedStaff = widget.userName;
  }
  // 1. Add this variable to your State class
  DateTime _expenseDate = DateTime.now();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
          width: 450,
          padding: const EdgeInsets.all(32),
          child: Form(
              key: _formKey,
              child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("NEW EXPENSE", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
                      const SizedBox(height: 24),

                      // EXPENSE DATE PICKER (Added Section)
                      _label("Expense Date"),
                      InkWell(
                        onTap: () async {
                          final DateTime? picked = await showDatePicker(
                            context: context,
                            initialDate: _expenseDate,
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now(),
                            builder: (context, child) => Localizations.override(
                              context: context,
                              locale: const Locale('en', 'GB'), // DD/MM/YYYY
                              child: child!,
                            ),
                          );
                          if (picked != null) setState(() => _expenseDate = picked);
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(border: OutlineInputBorder()),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(DateFormat('dd/MM/yyyy').format(_expenseDate)),
                              const Icon(Icons.calendar_today, size: 18, color: Colors.blue),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      _label("Staff Member"),
                      StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance.collection('staff_admins').snapshots(),
                        builder: (context, snapshot) {
                          List<String> staff = snapshot.hasData
                              ? snapshot.data!.docs.map((d) => d['name'].toString()).toList()
                              : [widget.userName];
                          return DropdownButtonFormField<String>(
                            value: staff.contains(_selectedStaff) ? _selectedStaff : staff.first,
                            items: staff.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                            onChanged: (v) => setState(() => _selectedStaff = v),
                            decoration: const InputDecoration(border: OutlineInputBorder()),
                          );
                        },
                      ),
                      const SizedBox(height: 16),

                      _label("Category"),
                      DropdownButtonFormField<String>(
                        value: _selectedType,
                        items: const [
                          DropdownMenuItem(value: 'COMPANY', child: Text("Company")),
                          DropdownMenuItem(value: 'KURI', child: Text("Kuri"))
                        ],
                        onChanged: (v) => setState(() { _selectedType = v!; _selectedKuri = null; }),
                        decoration: const InputDecoration(border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: 16),

                      if (_selectedType == 'KURI') ...[
                        _label("Select Kuri Scheme"),
                        StreamBuilder<QuerySnapshot>(
                          stream: FirebaseFirestore.instance.collection('kuris').snapshots(),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData) return const LinearProgressIndicator();

                            return DropdownButtonFormField<String>(
                              // Use _selectedKuriId here
                              value: _selectedKuriId,
                              hint: const Text("Choose Scheme"),
                              items: snapshot.data!.docs.map((doc) {
                                final data = doc.data() as Map<String, dynamic>;
                                return DropdownMenuItem<String>(
                                  value: doc.id,
                                  child: Text(data['name'] ?? "Unnamed Kuri"),
                                );
                              }).toList(),
                              onChanged: (id) {
                                // FIND the specific document to get the name
                                final selectedDoc = snapshot.data!.docs.firstWhere((d) => d.id == id);
                                final data = selectedDoc.data() as Map<String, dynamic>;

                                setState(() {
                                  _selectedKuriId = id; // Update the ID
                                  _selectedKuriName = data['name']; // Update the Name
                                });
                              },
                              validator: (v) => _selectedType == 'KURI' && v == null ? "Required" : null,
                              decoration: const InputDecoration(border: OutlineInputBorder()),
                            );
                          },
                        ),
                        const SizedBox(height: 16),
                      ],

                      _label("Description"),
                      TextFormField(
                          controller: _titleCtrl,
                          decoration: const InputDecoration(border: OutlineInputBorder()),
                          validator: (v) => v!.isEmpty ? "Required" : null
                      ),
                      const SizedBox(height: 16),

                      _label("Amount (₹)"),
                      TextFormField(
                          controller: _amtCtrl,
                          decoration: const InputDecoration(border: OutlineInputBorder()),
                          keyboardType: TextInputType.number,
                          validator: (v) => (double.tryParse(v ?? "") ?? 0) <= 0 ? "Invalid" : null
                      ),

                      const SizedBox(height: 32),
                      SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF1E40AF),
                                  foregroundColor: Colors.white
                              ),
                              onPressed: _submit,
                              child: const Text("SAVE")
                          )
                      ),
                    ],
                  )
              )
          )
      ),
    );
  }

  void _submit() async {
    if (_formKey.currentState!.validate()) {
      await FirebaseFirestore.instance.collection('expenses').add({
        'expenseDate': Timestamp.fromDate(_expenseDate),
        'title': _titleCtrl.text.trim(),
        'amount': double.tryParse(_amtCtrl.text) ?? 0.0,
        'type': _selectedType,
        'staffName': _selectedStaff,

        // Use the variables updated in onChanged
        'kuriId': _selectedType == 'KURI' ? _selectedKuriId : 'OFFICE',
        'kuriName': _selectedType == 'KURI' ? _selectedKuriName : 'OFFICE',

        'entryDetails': {
          'addedAt': FieldValue.serverTimestamp(),
          'addedByUserId': widget.userId,
          'addedByUserName': widget.userName,
        }
      });
      Navigator.pop(context);
    }
  }

  Widget _label(String t) => Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(t, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)));


}