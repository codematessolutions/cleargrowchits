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

class _ExpenseManagerWebState extends State<ExpenseManagerWeb> {
  DateTime selectedDate = DateTime(DateTime.now().year, DateTime.now().month);
  final currencyFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

  // Permission logic based on your Firestore screenshots
  bool get _canManage {
    final role = widget.userRole.trim();
    return role == 'Admin' || role == 'Super Admin';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        elevation: 1,
        backgroundColor: Colors.white,
        title: Row(
          children: [
            const Icon(Icons.account_balance_wallet, color: Color(0xFF1E3A8A)),
            const SizedBox(width: 12),
            const Text("EXPENSE DASHBOARD",
                style: TextStyle(color: Color(0xFF1E3A8A), fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        actions: [
          if (_canManage)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: ElevatedButton.icon(
                onPressed: () => _showAddExpenseDialog(context),
                icon: const Icon(Icons.add, size: 18),
                label: const Text("NEW EXPENSE"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          const SizedBox(width: 12),
          _buildDownloadButton(),
          const SizedBox(width: 20),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('expenses')
            .orderBy('date', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Text("Error fetching data"));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          List<DocumentSnapshot> allDocs = snapshot.data!.docs;

          // Filtered for the Main Table (Monthly)
          var monthlyDocs = allDocs.where((doc) {
            DateTime d = (doc['date'] as Timestamp).toDate();
            return d.year == selectedDate.year && d.month == selectedDate.month;
          }).toList();

          double totalMonthly = 0;
          double totalYearly = 0;
          Map<String, double> staffTotals = {};

          for (var doc in allDocs) {
            DateTime d = (doc['date'] as Timestamp).toDate();
            double amt = double.tryParse(doc['amount'].toString()) ?? 0.0;

            if (d.year == selectedDate.year) {
              totalYearly += amt;
              if (d.month == selectedDate.month) {
                totalMonthly += amt;
                String staff = doc['staffName'] ?? "Unknown";
                staffTotals[staff] = (staffTotals[staff] ?? 0.0) + amt;
              }
            }
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSidebar(totalMonthly, totalYearly, staffTotals),
              Expanded(child: _buildMainTable(monthlyDocs)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDownloadButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: PopupMenuButton<String>(
        onSelected: (val) => _prepareAndGeneratePDF(val == 'year'),
        itemBuilder: (context) => [
          const PopupMenuItem(value: 'month', child: Text("Detailed Monthly Report")),
          const PopupMenuItem(value: 'year', child: Text("Detailed Yearly Report")),
        ],
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFF1E3A8A)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Row(
            children: [
              Icon(Icons.picture_as_pdf, size: 18, color: Color(0xFF1E3A8A)),
              SizedBox(width: 8),
              Text("GENERATE REPORT", style: TextStyle(color: Color(0xFF1E3A8A), fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSidebar(double monthly, double yearly, Map<String, double> staffMap) {
    return Container(
      width: 320,
      decoration: BoxDecoration(color: Colors.white, border: Border(right: BorderSide(color: Colors.grey.shade200))),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("SELECT PERIOD", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
          const SizedBox(height: 12),
          _buildMonthSelector(),
          const Divider(height: 40),
          _buildSummaryCard("MONTHLY TOTAL", monthly, Colors.redAccent),
          const SizedBox(height: 20),
          _buildSummaryCard("YEARLY TOTAL (${selectedDate.year})", yearly, const Color(0xFF1E3A8A)),
          const SizedBox(height: 40),
          const Text("STAFF-WISE (MONTHLY)", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
          const SizedBox(height: 16),
          Expanded(
            child: ListView(
              children: staffMap.entries.map((e) => _buildStaffRow(e.key, e.value)).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(String title, double amount, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
        const SizedBox(height: 4),
        Text(currencyFormat.format(amount), style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: color)),
      ],
    );
  }

  Widget _buildMonthSelector() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(onPressed: () => setState(() => selectedDate = DateTime(selectedDate.year, selectedDate.month - 1)), icon: const Icon(Icons.arrow_back_ios, size: 14)),
        Text(DateFormat('MMMM yyyy').format(selectedDate).toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        IconButton(onPressed: () => setState(() => selectedDate = DateTime(selectedDate.year, selectedDate.month + 1)), icon: const Icon(Icons.arrow_forward_ios, size: 14)),
      ],
    );
  }

  Widget _buildStaffRow(String name, double amount) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(name, style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w500)),
          Text(currencyFormat.format(amount), style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildMainTable(List<DocumentSnapshot> docs) {
    return Container(
      margin: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
      child: docs.isEmpty
          ? const Center(child: Text("No expenses found for this month."))
          : SingleChildScrollView(
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
          columns: [
            const DataColumn(label: Text("DATE")),
            const DataColumn(label: Text("DESCRIPTION")),
            const DataColumn(label: Text("AUTHORIZED BY")),
            const DataColumn(label: Text("AMOUNT")),
            if (_canManage) const DataColumn(label: Text("ACTIONS")),
          ],
          rows: docs.map((doc) {
            var data = doc.data() as Map<String, dynamic>;
            return DataRow(cells: [
              DataCell(Text(DateFormat('dd-MM-yyyy').format((data['date'] as Timestamp).toDate()))),
              DataCell(Text(data['title'].toString().toUpperCase(), style: const TextStyle(fontSize: 12))),
              DataCell(Text(data['staffName'])),
              DataCell(Text("₹${data['amount']}", style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold))),
              if (_canManage)
                DataCell(IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20), onPressed: () => _confirmDelete(doc.id))),
            ]);
          }).toList(),
        ),
      ),
    );
  }

  void _confirmDelete(String docId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete Record?"),
        content: const Text("This action will permanently remove this expense entry."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCEL")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              FirebaseFirestore.instance.collection('expenses').doc(docId).delete();
              Navigator.pop(ctx);
            },
            child: const Text("DELETE", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _prepareAndGeneratePDF(bool isYearly) async {
    final snap = await FirebaseFirestore.instance.collection('expenses').orderBy('date', descending: true).get();

    var filtered = snap.docs.where((doc) {
      DateTime d = (doc['date'] as Timestamp).toDate();
      return isYearly ? (d.year == selectedDate.year) : (d.year == selectedDate.year && d.month == selectedDate.month);
    }).toList();

    if (filtered.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No data to export")));
      return;
    }

    final pdf = pw.Document();
    final String reportTitle = isYearly
        ? "ANNUAL EXPENSE REPORT - ${selectedDate.year}"
        : "MONTHLY EXPENSE REPORT - ${DateFormat('MMMM yyyy').format(selectedDate)}";

    double totalGrand = 0;
    Map<String, double> staffSummary = {};
    for (var d in filtered) {
      double amt = double.tryParse(d['amount'].toString()) ?? 0.0;
      totalGrand += amt;
      String name = d['staffName'] ?? "Unknown";
      staffSummary[name] = (staffSummary[name] ?? 0.0) + amt;
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) => [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(reportTitle, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
              pw.Text("Total: Rs. ${totalGrand.toStringAsFixed(2)}", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            ],
          ),
          pw.SizedBox(height: 20),
          pw.Text("STAFF-WISE SUMMARY", style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
            headers: ['STAFF NAME', 'TOTAL AMOUNT'],
            data: staffSummary.entries.map((e) => [e.key.toUpperCase(), "Rs. ${e.value.toStringAsFixed(2)}"]).toList(),
          ),
          pw.SizedBox(height: 20),
          pw.Text("DETAILED LOG", style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blue900),
            headers: ['DATE', 'DESCRIPTION', 'STAFF', 'AMOUNT'],
            data: filtered.map((d) => [
              DateFormat('dd-MM-yy').format((d['date'] as Timestamp).toDate()),
              d['title'].toString().toUpperCase(),
              d['staffName'],
              "Rs. ${d['amount']}"
            ]).toList(),
          ),
        ],
      ),
    );

    await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  }

  void _showAddExpenseDialog(BuildContext context) {
    showDialog(context: context, builder: (context) => AddExpenseDialog(userId: widget.userId, userName: widget.userName, userRole: widget.userRole));
  }
}

class AddExpenseDialog extends StatefulWidget {
  final String userId, userName, userRole;
  const AddExpenseDialog({super.key, required this.userId, required this.userName, required this.userRole});
  @override
  State<AddExpenseDialog> createState() => _AddExpenseDialogState();
}

class _AddExpenseDialogState extends State<AddExpenseDialog> {
  final _titleCtrl = TextEditingController();
  final _amtCtrl = TextEditingController();
  String? _selectedStaff;
  DateTime _selectedDate = DateTime.now();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _selectedStaff = widget.userName;
  }

  void _saveExpense() async {
    final title = _titleCtrl.text.trim();
    final amtText = _amtCtrl.text.trim();
    if (title.isEmpty || amtText.isEmpty || _selectedStaff == null) return;
    double? amt = double.tryParse(amtText);
    if (amt == null) return;

    setState(() => _isSaving = true);
    await FirebaseFirestore.instance.collection('expenses').add({
      'title': title,
      'amount': amt,
      'staffName': _selectedStaff,
      'date': Timestamp.fromDate(_selectedDate),
      'createdAt': FieldValue.serverTimestamp(),
      'userId': widget.userId,
      'userName': widget.userName,
      'userRole': widget.userRole,
    });
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 450,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Create New Expense", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A))),
            const SizedBox(height: 20),
            TextField(controller: _titleCtrl, decoration: const InputDecoration(labelText: "Description", border: OutlineInputBorder())),
            const SizedBox(height: 16),
            TextField(controller: _amtCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Amount", prefixText: "₹ ", border: OutlineInputBorder())),
            const SizedBox(height: 16),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('staff_admins').orderBy('name').snapshots(),
              builder: (context, snapshot) {
                Set<String> names = {widget.userName};
                if (snapshot.hasData) for (var d in snapshot.data!.docs) names.add(d['name']);
                return DropdownButtonFormField<String>(
                  value: _selectedStaff,
                  decoration: const InputDecoration(labelText: "Authorized By", border: OutlineInputBorder()),
                  items: names.map((n) => DropdownMenuItem(value: n, child: Text(n))).toList(),
                  onChanged: (v) => setState(() => _selectedStaff = v),
                );
              },
            ),
            const SizedBox(height: 16),
            ListTile(
              title: const Text("Date"),
              subtitle: Text(DateFormat('dd MMMM yyyy').format(_selectedDate)),
              trailing: const Icon(Icons.calendar_month),
              onTap: () async {
                DateTime? p = await showDatePicker(context: context, initialDate: _selectedDate, firstDate: DateTime(2024), lastDate: DateTime.now());
                if (p != null) setState(() => _selectedDate = p);
              },
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text("Discard")),
                const SizedBox(width: 12),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E3A8A), foregroundColor: Colors.white),
                  onPressed: _isSaving ? null : _saveExpense,
                  child: _isSaving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text("Save Expense"),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}