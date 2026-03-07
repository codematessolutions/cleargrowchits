import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

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
          _buildSidebar(),
          Expanded(
            child: Column(
              children: [
                _buildHeader(),
                _buildTabStrip(),
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance.collection('expenses').orderBy('date', descending: true).snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

                      var allDocs = snapshot.data!.docs;
                      var filteredDocs = allDocs.where((doc) {
                        DateTime d = (doc['date'] as Timestamp).toDate();
                        return d.year == selectedDate.year && d.month == selectedDate.month;
                      }).toList();

                      return TabBarView(
                        controller: _tabController,
                        children: [
                          _buildOverviewPanel(filteredDocs),
                          _buildKuriPanel(filteredDocs.where((d) => d['type'] == 'KURI').toList()),
                          _buildCompanyPanel(filteredDocs.where((d) => d['type'] == 'COMPANY').toList()),
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
      double amt = double.tryParse(d['amount'].toString()) ?? 0;
      if (d['type'] == 'KURI') kuriTotal += amt; else officeTotal += amt;
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(children: [
        Row(children: [
          _statCard("TOTAL EXPENSE", kuriTotal + officeTotal, primaryBlue, Icons.account_balance_wallet),
          const SizedBox(width: 16),
          _statCard("KURI SCHEMES", kuriTotal, Colors.orange.shade800, Icons.layers),
          const SizedBox(width: 16),
          _statCard("OFFICE/COMPANY", officeTotal, Colors.blueAccent, Icons.business),
        ]),
        const SizedBox(height: 24),
        _buildSectionHeader("Recent Activities"),
        const SizedBox(height: 12),
        Container(height: 500, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: borderColor)), child: _buildDataTable(docs.take(15).toList())),
      ]),
    );
  }

  Widget _buildKuriPanel(List<DocumentSnapshot> docs) => _buildStandardPanel("Kuri Related Costs", docs);
  Widget _buildCompanyPanel(List<DocumentSnapshot> docs) => _buildStandardPanel("Office Overhead", docs);

  Widget _buildStandardPanel(String title, List<DocumentSnapshot> docs) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _buildSectionHeader(title),
      const SizedBox(height: 12),
      Expanded(child: _buildDataTable(docs)),
    ]),
  );

  Widget _buildStaffAnalyticsPanel(List<DocumentSnapshot> docs) {
    Map<String, double> staffTotals = {};
    Map<String, int> staffCounts = {};
    for (var d in docs) {
      String name = d['staffName'] ?? "Unknown";
      double amt = double.tryParse(d['amount'].toString()) ?? 0;
      staffTotals[name] = (staffTotals[name] ?? 0) + amt;
      staffCounts[name] = (staffCounts[name] ?? 0) + 1;
    }

    final filteredDocsForTable = docs.where((d) {
      bool matchesStaff = selectedStaffFilter == "All Staff" || d['staffName'] == selectedStaffFilter;
      bool matchesSearch = d['title'].toString().toLowerCase().contains(staffSearchQuery.toLowerCase());
      return matchesStaff && matchesSearch;
    }).toList();

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 2, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text("STAFF SUMMARY", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: sideBarColor)),
            const SizedBox(height: 16),
            Expanded(child: ListView(children: staffTotals.entries.map((e) => _buildStaffInfoCard(e.key, e.value, staffCounts[e.key]!)).toList())),
          ])),
          const SizedBox(width: 24),
          Expanded(flex: 5, child: Container(
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: borderColor)),
            child: Column(children: [
              Padding(padding: const EdgeInsets.all(16.0), child: Row(children: [
                const Text("TRANSACTIONS", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const Spacer(),
                _buildStaffDropdown(staffTotals.keys.toList()),
                const SizedBox(width: 12),
                _buildSearchField(),
              ])),
              const Divider(height: 1),
              Expanded(child: _buildDataTable(filteredDocsForTable)),
            ]),
          )),
        ],
      ),
    );
  }

  // --- COMPONENTS ---
  Widget _buildDataTable(List<DocumentSnapshot> docs) {
    double totalSum = docs.fold(0, (sum, doc) => sum + (double.tryParse(doc['amount'].toString()) ?? 0));
    if (docs.isEmpty) return const Center(child: Text("No records found", style: TextStyle(color: Colors.grey)));

    return Column(children: [
      Expanded(
        child: SingleChildScrollView(
          child: SizedBox(
            width: double.infinity,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(const Color(0xFFF1F5F9)),
              columns: const [
                DataColumn(label: Text("ENTRY DETAILS")), // Who & When
                DataColumn(label: Text("STAFF")),         // For Whom
                DataColumn(label: Text("CATEGORY")),      // KURI or COMPANY
                DataColumn(label: Text("DESC")),          // Description
                DataColumn(label: Text("AMOUNT")),
                DataColumn(label: Text("ACTION")),
              ],
              rows: docs.map((d) {
                final String type = d['type'] ?? 'COMPANY';
                final String kuriName = d['kuriName'] ?? '';
                final DateTime entryDate = (d['date'] as Timestamp).toDate();
                final String addedBy = d['userName'] ?? 'Admin';

                return DataRow(cells: [
                  // 1. ENTRY DETAILS (Added By + Date/Time)
                  DataCell(
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("By: $addedBy", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          Text(DateFormat('dd MMM, hh:mm a').format(entryDate), style: const TextStyle(color: Colors.grey, fontSize: 11)),
                        ],
                      ),
                    ),
                  ),

                  // 2. STAFF
                  DataCell(Text(d['staffName'] ?? "-")),

                  // 3. CATEGORY (Shows KURI + Name or COMPANY)
                  DataCell(
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: type == 'KURI' ? Colors.orange.shade100 : Colors.blue.shade100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            type,
                            style: TextStyle(
                              color: type == 'KURI' ? Colors.orange.shade900 : Colors.blue.shade900,
                              fontWeight: FontWeight.bold,
                              fontSize: 10,
                            ),
                          ),
                        ),
                        if (type == 'KURI' && kuriName.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(kuriName, style: const TextStyle(fontSize: 11, color: Colors.blueGrey)),
                          ),
                      ],
                    ),
                  ),

                  // 4. DESCRIPTION
                  DataCell(Text(d['title'].toString().toUpperCase(), overflow: TextOverflow.ellipsis)),

                  // 5. AMOUNT
                  DataCell(Text(currencyFormat.format(d['amount']), style: const TextStyle(fontWeight: FontWeight.bold))),

                  // 6. ACTION
                  DataCell(IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                    onPressed: () => _confirmDelete(d),
                  )),
                ]);
              }).toList(),
            ),
          ),
        ),
      ),
      _buildTableFooter(totalSum),
    ]);
  }

  Future<void> _generateReport({required bool isGrandTotal}) async {
    final pdf = pw.Document();
    final String reportTitle = isGrandTotal
        ? "GRAND TOTAL EXPENSE REPORT"
        : "EXPENSE REPORT - ${DateFormat('MMMM yyyy').format(selectedDate)}";

    // Create a PDF-safe number format (Standard text instead of symbol)
    final pdfCurrency = NumberFormat.currency(locale: 'en_IN', symbol: 'Rs. ', decimalDigits: 2);

    // 1. Fetch Data
    final snap = await FirebaseFirestore.instance.collection('expenses').orderBy('date', descending: true).get();

    var docs = snap.docs;
    if (!isGrandTotal) {
      docs = docs.where((doc) {
        DateTime d = (doc['date'] as Timestamp).toDate();
        return d.year == selectedDate.year && d.month == selectedDate.month;
      }).toList();
    }

    // 2. Calculate Totals
    double total = 0;
    double kuriTotal = 0;
    double officeTotal = 0;
    for (var d in docs) {
      double amt = double.tryParse(d['amount'].toString()) ?? 0;
      total += amt;
      if (d['type'] == 'KURI') kuriTotal += amt; else officeTotal += amt;
    }

    // 3. Create PDF Layout
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape, // Landscape handles many columns better
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) => [
          // Header
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

          // Overview Summary
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              _pdfStatCard("Total Expense", pdfCurrency.format(total)),
              _pdfStatCard("Kuri Schemes", pdfCurrency.format(kuriTotal)),
              _pdfStatCard("Office/Company", pdfCurrency.format(officeTotal)),
            ],
          ),
          pw.SizedBox(height: 20),

          // Table
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
            data: docs.map((d) {
              final type = d['type'] ?? 'COMPANY';
              final kuriName = d['kuriName'] ?? '';
              double amt = double.tryParse(d['amount'].toString()) ?? 0;

              return [
                DateFormat('dd/MM/yy, hh:mm a').format((d['date'] as Timestamp).toDate()),
                d['userName'] ?? 'Admin',
                d['staffName'] ?? '-',
                type == 'KURI' ? "KURI\n($kuriName)" : "OFFICE",
                d['title'].toString().toUpperCase(),
                pdfCurrency.format(amt), // Using safe currency format
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
  }
  // PDF Stat Card Helper
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

  Widget _buildSidebar() => Container(width: 80, color: sideBarColor, child: const Column(children: [SizedBox(height: 40), Icon(Icons.account_balance, color: Colors.white, size: 30), SizedBox(height: 40), Icon(Icons.dashboard, color: Colors.white54)]));


  Widget _buildTabStrip() => Container(color: Colors.white, child: TabBar(controller: _tabController, labelColor: primaryBlue, indicatorColor: primaryBlue, tabs: const [Tab(text: "OVERVIEW"), Tab(text: "KURI"), Tab(text: "COMPANY"), Tab(text: "STAFF")]));
  Widget _statCard(String t, double v, Color c, IconData i) => Expanded(child: Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: borderColor)), child: Row(children: [Icon(i, color: c, size: 32), const SizedBox(width: 20), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(t, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)), Text(currencyFormat.format(v), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: c))])])));
  Widget _buildStaffInfoCard(String n, double t, int c) => Container(margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: borderColor)), child: Row(children: [CircleAvatar(child: Text(n[0])), const SizedBox(width: 16), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(n, style: const TextStyle(fontWeight: FontWeight.bold)), Text("$c Entries")]), const Spacer(), Text(currencyFormat.format(t), style: const TextStyle(fontWeight: FontWeight.bold))]));
  Widget _buildDateNavigator() => Row(children: [IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => setState(() => selectedDate = DateTime(selectedDate.year, selectedDate.month - 1))), Text(DateFormat('dd MMM, hh:mm a').format(selectedDate)), IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => setState(() => selectedDate = DateTime(selectedDate.year, selectedDate.month + 1)))]);
  Widget _buildStaffDropdown(List<String> list) => DropdownButton<String>(value: selectedStaffFilter, items: ["All Staff", ...list].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(), onChanged: (v) => setState(() => selectedStaffFilter = v!));
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

  String _selectedType = 'COMPANY';
  String? _selectedStaff;
  String? _selectedKuri;

  @override
  void initState() {
    super.initState();
    _selectedStaff = widget.userName;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(width: 450, padding: const EdgeInsets.all(32), child: Form(key: _formKey, child: SingleChildScrollView(child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("NEW EXPENSE", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
          const SizedBox(height: 24),

          // STAFF FROM staff_admins
          _label("Staff Member"),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('staff_admins').snapshots(),
            builder: (context, snapshot) {
              List<String> staff = snapshot.hasData ? snapshot.data!.docs.map((d) => d['name'].toString()).toList() : [widget.userName];
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
            items: const [DropdownMenuItem(value: 'COMPANY', child: Text("Company")), DropdownMenuItem(value: 'KURI', child: Text("Kuri"))],
            onChanged: (v) => setState(() { _selectedType = v!; _selectedKuri = null; }),
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),

          // KURIs FROM kuris collection
          if (_selectedType == 'KURI') ...[
            _label("Select Kuri Scheme"),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('kuris').snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const LinearProgressIndicator();
                List<String> schemes = snapshot.data!.docs.map((d) => d['name'].toString()).toList();
                return DropdownButtonFormField<String>(
                  value: _selectedKuri,
                  hint: const Text("Choose Scheme"),
                  items: schemes.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                  onChanged: (v) => setState(() => _selectedKuri = v),
                  validator: (v) => _selectedType == 'KURI' && v == null ? "Required" : null,
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                );
              },
            ),
            const SizedBox(height: 16),
          ],

          _label("Description"),
          TextFormField(controller: _titleCtrl, decoration: const InputDecoration(border: OutlineInputBorder()), validator: (v) => v!.isEmpty ? "Required" : null),
          const SizedBox(height: 16),
          _label("Amount (₹)"),
          TextFormField(controller: _amtCtrl, decoration: const InputDecoration(border: OutlineInputBorder()), keyboardType: TextInputType.number, validator: (v) => (double.tryParse(v ?? "") ?? 0) <= 0 ? "Invalid" : null),

          const SizedBox(height: 32),
          SizedBox(width: double.infinity, height: 50, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E40AF), foregroundColor: Colors.white), onPressed: _submit, child: const Text("SAVE"))),
        ],
      )))),
    );
  }

  Widget _label(String t) => Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(t, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)));

  void _submit() async {
    if (_formKey.currentState!.validate()) {
      await FirebaseFirestore.instance.collection('expenses').add({
        'title': _titleCtrl.text.trim(),
        'amount': double.parse(_amtCtrl.text),
        'type': _selectedType,
        'staffName': _selectedStaff,
        'date': Timestamp.now(),
        'kuriName': _selectedType == 'KURI' ? _selectedKuri : 'OFFICE',
        'userId': widget.userId,
        'userName': widget.userName,
        'userRole': widget.userRole,
      });
      Navigator.pop(context);
    }
  }
}