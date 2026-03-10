import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/utils/kuri_theme.dart';
import '../models/kuri_model.dart';
import '../providers/kuri_provider.dart';
import 'collector_report_screen.dart';
import 'kuri_members_screen.dart';
import 'scheme_list_screen.dart';



class KuriListScreen extends StatelessWidget {
  final String userId;
  final String userName;
  final String userRole;
  const KuriListScreen({super.key, required this.userId, required this.userName,required this.userRole});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KuriTheme.scaffoldBg,
      body: Row(
        children: [

          Expanded(
            child: Column(
              children: [
                _Header(userId: userId, userName: userName, userRole: userRole,),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: RepaintBoundary(
                      child: _KuriTableContainer(userId: userId, userName: userName, userRole: userRole,),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _KuriTableContainer extends StatelessWidget {
  final String userId;
  final String userName;
  final String userRole;
  const _KuriTableContainer({required this.userId, required this.userName,required this.userRole});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<KuriProvider>(context, listen: false);
    return Container(
      decoration: BoxDecoration(
        color: KuriTheme.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 40,
              offset: const Offset(0, 15))
        ],
        border: Border.all(color: KuriTheme.borderSubtle, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _TableTopBar(),
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(24),
                  bottomRight: Radius.circular(24)),
              child: _KuriDataTable(
                provider: provider,
                userId: userId,
                userName: userName, userRole: userRole,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _KuriDataTable extends StatelessWidget {
  final KuriProvider provider;
  final String userId;
  final String userName;
  final String userRole;

  const _KuriDataTable({
    super.key,
    required this.provider,
    required this.userId,
    required this.userName,
    required this.userRole,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<KuriModel>>(
      stream: provider.kurisStream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(60.0),
              child: CircularProgressIndicator(color: KuriTheme.primaryIndigo),
            ),
          );
        }
        final kuris = snapshot.data!;

        if (kuris.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(60.0),
              child: Column(
                children: [
                  Icon(Icons.folder_open_outlined, size: 48, color: KuriTheme.textMuted.withOpacity(0.5)),
                  const SizedBox(height: 16),
                  const Text("No active schemes found", style: TextStyle(color: KuriTheme.textMuted, fontSize: 16)),
                ],
              ),
            ),
          );
        }

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: MediaQuery.of(context).size.width - 300),
            child: DataTable(
              showCheckboxColumn: false,
              headingRowHeight: 64,
              dataRowMaxHeight: 72,
              horizontalMargin: 24,
              columnSpacing: 70,
              headingRowColor: WidgetStateProperty.all(KuriTheme.scaffoldBg.withOpacity(0.5)),
              dividerThickness: 1,
              columns: _buildColumns(),
              rows: List.generate(
                kuris.length,
                    (index) => _buildRow(context, kuris[index], index + 1),
              ),
            ),
          ),
        );
      },
    );
  }

  List<DataColumn> _buildColumns() {
    const style = TextStyle(fontWeight: FontWeight.w800, color: KuriTheme.textMuted, fontSize: 11, letterSpacing: 1);
    return const [
      DataColumn(label: Text("#", style: style)),
      DataColumn(label: Text("KURI NAME", style: style)),
      DataColumn(label: Text("START", style: style)),
      DataColumn(label: Text("END", style: style)),
      DataColumn(label: Text("DUR (M)", style: style)),
      DataColumn(label: Text("DRAW DAY", style: style)),
      DataColumn(label: Text("LAST PMT", style: style)),
      DataColumn(label: Text("MONTHLY", style: style)),
      DataColumn(label: Text("TOTAL VALUE", style: style)),
      DataColumn(label: Text("MEMBERS", style: style)),
      DataColumn(label: Text("COLLECTION\nREPORT", style: style)),
      DataColumn(label: Text("ACTIONS", style: style)),
    ];
  }

  DataRow _buildRow(BuildContext context, KuriModel kuri, int serialNo) {
    final DateTime start = (kuri.startMonth as Timestamp).toDate();
    final DateTime end = (kuri.endMonth as Timestamp).toDate();
    final currency = NumberFormat.currency(symbol: "₹", decimalDigits: 0, locale: "en_IN");
    final int lastPaymentDay = kuri.kuriDate - 2;

    return DataRow(
      // onSelectChanged: (_) => Navigator.push(
      //   context,
      //   MaterialPageRoute(
      //     builder: (c) => SchemeListScreen(
      //       kuriId: kuri.id!,
      //       kuriName: kuri.name,
      //       kuriData: kuri.toMap(),
      //       userId: userId,
      //       userName: userName,
      //       userRole: userRole,
      //     ),
      //   ),
      // ),
      cells: [
        DataCell(Text("$serialNo", style: const TextStyle(color: KuriTheme.textMuted, fontWeight: FontWeight.bold))),
        DataCell(Text(kuri.name, style: const TextStyle(fontWeight: FontWeight.bold, color: KuriTheme.textDark, fontSize: 14))),
        DataCell(Text(DateFormat('MMM yyyy').format(start))),
        DataCell(Text(DateFormat('MMM yyyy').format(end), style: const TextStyle(color: KuriTheme.accentIndigo, fontWeight: FontWeight.w600))),
        DataCell(Text("${kuri.totalMonths}")),
        DataCell(_Badge(text: "${kuri.kuriDate}th", color: Colors.blue)),
        DataCell(_Badge(text: "${lastPaymentDay}th", color: Colors.orange)),
        DataCell(Text(currency.format(kuri.monthlyAmount), style: const TextStyle(fontWeight: FontWeight.w500))),

        // Total Value Field with Green Pill
        DataCell(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: KuriTheme.successGreen.withOpacity(0.2)),
            ),
            child: Text(
              currency.format(kuri.totalAmount),
              style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF15803D), fontSize: 13),
            ),
          ),
        ),

        // Members Button
        DataCell(
          _CircleAction(
            icon: Icons.group_outlined,
            color: KuriTheme.primaryIndigo,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => KuriMembersScreen(
                  kuriId: kuri.id!,
                  kuriName: kuri.name,
                  userId: userId,
                  userName: userName,
                  userRole: userRole,
                  kuriData: kuri.toMap(),
                ),
              ),
            ),
          ),
        ),
        DataCell(
          _CircleAction(
            icon: Icons.picture_as_pdf,
            color: KuriTheme.primaryIndigo,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => CollectorReportWebScreen(
                  kuriId: kuri.id!,
                  kuriName: kuri.name,
                  // FIX: Convert Timestamp to DateTime
                  initialMonth: (kuri.startMonth as Timestamp).toDate(),
                ),
              ),
            ),
          ),
        ),

        // Actions Row
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Only show Edit and Delete if the user is a Super Admin
              if (userRole == "Super Admin") ...[
                _CircleAction(
                  icon: Icons.edit_note_outlined,
                  color: Colors.blue,
                  onTap: () => _KuriFormDialog.show(
                      context,
                      kuri: kuri,
                      userId: userId,
                      userName: userName,
                      userRole: userRole
                  ),
                ),
                const SizedBox(width: 8),
                _CircleAction(
                  icon: Icons.delete_outline_rounded,
                  color: KuriTheme.errorRed,
                  onTap: () => _showDeleteConfirm(context, kuri),
                ),
              ] else ...[
                // Optional: Show a "View Only" or "Locked" message/icon for other roles
                const Text("Read Only", style: TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ],
          ),
        ),
      ],
    );
  }

  void _showDeleteConfirm(BuildContext context, KuriModel kuri) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          width: 400,
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: KuriTheme.errorRed.withOpacity(0.1), shape: BoxShape.circle),
                child: const Icon(Icons.delete_forever_outlined, color: KuriTheme.errorRed, size: 40),
              ),
              const SizedBox(height: 24),
              const Text("Delete Kuri Scheme?", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Text("Are you sure you want to delete '${kuri.name}'? All associated data will be removed.",
                  textAlign: TextAlign.center, style: const TextStyle(color: KuriTheme.textMuted, height: 1.5)),
              const SizedBox(height: 32),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text("CANCEL", style: TextStyle(color: KuriTheme.textMuted)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: KuriTheme.errorRed,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () async {
                        Navigator.pop(ctx);
                        final p = Provider.of<KuriProvider>(context, listen: false);
                        try {
                          await p.deleteKuri(kuri.id!);
                        } catch (e) {
                          debugPrint("Delete error: $e");
                        }
                      },
                      child: const Text("CONFIRM", style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
// --- UPDATED DIALOG CLASS ---
class _KuriFormDialog extends StatefulWidget {
  final KuriModel? kuri;
  final String userId;
  final String userName;
  final String userRole;

  const _KuriFormDialog({
    super.key,
    this.kuri,
    required this.userId,
    required this.userName,
    required this.userRole,
  });

  static void show(BuildContext context, {KuriModel? kuri, required String userId, required String userName,required String userRole}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _KuriFormDialog(kuri: kuri, userId: userId, userName: userName, userRole: userRole,),
    );
  }

  @override
  State<_KuriFormDialog> createState() => _KuriFormDialogState();
}

class _KuriFormDialogState extends State<_KuriFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _name, _months, _amount, _day;
  late DateTime _startDate;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.kuri?.name);
    _months = TextEditingController(text: widget.kuri?.totalMonths.toString() ?? "");
    _amount = TextEditingController(text: widget.kuri?.monthlyAmount.toString() ?? "");
    _day = TextEditingController(text: widget.kuri?.kuriDate?.toString() ?? "");
    _startDate = (widget.kuri != null) ? (widget.kuri!.startMonth as Timestamp).toDate() : DateTime.now();
  }

  @override
  Widget build(BuildContext context) {
    final dur = int.tryParse(_months.text) ?? 0;
    final mon = double.tryParse(_amount.text) ?? 0;
    final drawDay = int.tryParse(_day.text) ?? 0;
    final endDate = DateTime(_startDate.year, _startDate.month + (dur > 0 ? dur - 1 : 0), 1);

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 600,
        decoration: BoxDecoration(color: KuriTheme.surface, borderRadius: BorderRadius.circular(24)),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildFormHeader(),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _fieldLabel("Kuri Name *"),
                      _textInput(_name, "Kuri Name", Icons.badge_outlined),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_fieldLabel("Draw Day *"), _textInput(_day, "1-31", Icons.event, isNum: true, onChanged: (_) => setState(() {}))])),
                          const SizedBox(width: 15),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(color: Colors.orange.withOpacity(0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.orange.withOpacity(0.2))),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text("PAYMENT DEADLINE", style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.orange)),
                                  Text(drawDay > 2 ? "${drawDay - 2}th of month" : "--", style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.orange, fontSize: 15)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      _fieldLabel("Duration & Amount *"),
                      Row(
                        children: [
                          Expanded(child: _textInput(_months, "Months", Icons.timer_outlined, isNum: true, onChanged: (_) => setState(() {}))),
                          const SizedBox(width: 15),
                          Expanded(child: _textInput(_amount, "₹ Monthly", Icons.account_balance_wallet_outlined, isNum: true, onChanged: (_) => setState(() {}))),
                        ],
                      ),
                      const SizedBox(height: 25),
                      _fieldLabel("Start Date"),
                      _datePickerTile(),
                      const SizedBox(height: 30),
                      _summaryPanel(endDate, dur * mon),
                    ],
                  ),
                ),
              ),
              _buildFormActions(endDate, widget.userId, widget.userName,widget.userRole),
            ],
          ),
        ),
      ),
    );
  }

  void _save(DateTime calcEndDate, String userId, String userName, String userRole) async {
    if (_formKey.currentState!.validate()) {
      try {
        // 1. Create the new model from form data
        final updatedModel = KuriModel(
          name: _name.text.trim(),
          kuriDate: int.parse(_day.text),
          startMonth: Timestamp.fromDate(_startDate),
          endMonth: Timestamp.fromDate(calcEndDate),
          totalMonths: int.parse(_months.text),
          monthlyAmount: double.parse(_amount.text),
          totalAmount: int.parse(_months.text) * double.parse(_amount.text),
          // Keep original creator info or update based on your logic
          addedById: widget.kuri?.addedById ?? userId,
          addedByName: widget.kuri?.addedByName ?? userName,
          addedByPhone: widget.kuri?.addedByPhone ?? "",
          userRole: userRole,
        );

        final p = Provider.of<KuriProvider>(context, listen: false);

        if (widget.kuri == null) {
          // --- ADD NEW KURI ---
          await p.addKuri(updatedModel);
        } else {
          // --- UPDATE EXISTING KURI WITH LOGS ---
          await p.updateKuri(
            id: widget.kuri!.id!,        // The document ID
            updatedKuri: updatedModel,   // The new data
            oldKuri: widget.kuri!,       // The original data (for logging changes)
            userId: userId,              // The Admin performing the edit
            userName: userName,          // The Admin's name
          );
        }

        if (mounted) Navigator.pop(context);
      } catch (e) {
        debugPrint("Save Error: $e");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Error saving Kuri: $e"), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Widget _buildFormHeader() => Container(
    padding: const EdgeInsets.all(24),
    decoration: const BoxDecoration(color: KuriTheme.textDark, borderRadius: BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24))),
    child: Row(children: [const Icon(Icons.add_chart, color: Colors.white, size: 20), const SizedBox(width: 12), Text(widget.kuri == null ? "Start New Kuri" : "Edit Kuri", style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))]),
  );

  Widget _fieldLabel(String l) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(l.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: KuriTheme.textMuted)));

  Widget _textInput(TextEditingController c, String h, IconData i, {bool isNum = false, Function(String)? onChanged}) {
    return TextFormField(
      controller: c,
      onChanged: onChanged,
      keyboardType: isNum ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(prefixIcon: Icon(i, size: 20), hintText: h, filled: true, fillColor: KuriTheme.scaffoldBg, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none), contentPadding: const EdgeInsets.all(18)),
      validator: (v) => (v == null || v.isEmpty) ? "Required" : null,
    );
  }

  Widget _datePickerTile() => InkWell(
    onTap: () async {
      final p = await showDatePicker(context: context, initialDate: _startDate, firstDate: DateTime(2020), lastDate: DateTime(2100));
      if (p != null) setState(() => _startDate = p);
    },
    child: Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(color: KuriTheme.scaffoldBg, borderRadius: BorderRadius.circular(12)), child: Row(children: [const Icon(Icons.calendar_month, size: 20, color: KuriTheme.primaryIndigo), const SizedBox(width: 12), Text(DateFormat('dd MMMM yyyy').format(_startDate), style: const TextStyle(fontWeight: FontWeight.bold))])),
  );

  Widget _summaryPanel(DateTime end, double total) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(color: KuriTheme.primaryIndigo.withOpacity(0.05), borderRadius: BorderRadius.circular(16)),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text("ENDS", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)), Text(DateFormat('MMM yyyy').format(end), style: const TextStyle(fontWeight: FontWeight.bold))]),
      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [const Text("TOTAL VALUE", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)), Text("₹${NumberFormat('#,##,###').format(total)}", style: const TextStyle(fontWeight: FontWeight.w900, color: KuriTheme.accentIndigo, fontSize: 18))]),
    ]),
  );

  Widget _buildFormActions(DateTime endDate, String userId, String userName,String userRole) => Padding(
    padding: const EdgeInsets.all(32),
    child: Row(children: [
      Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), style: OutlinedButton.styleFrom(padding: const EdgeInsets.all(24), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: const Text("CANCEL"))),
      const SizedBox(width: 16),
      Expanded(child: ElevatedButton(onPressed: () => _save(endDate, userId, userName,userRole), style: ElevatedButton.styleFrom(backgroundColor: KuriTheme.primaryIndigo, foregroundColor: Colors.white, padding: const EdgeInsets.all(24), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: const Text("SAVE KURI"))),
    ]),
  );
}



class _Header extends StatelessWidget {
  final String userId;
  final String userName;
  final String userRole;
  const _Header({required this.userId, required this.userName,required this.userRole});

  @override
  Widget build(BuildContext context) => Container(
    height: 90,
    padding: const EdgeInsets.symmetric(horizontal: 40),
    decoration: const BoxDecoration(color: KuriTheme.surface, border: Border(bottom: BorderSide(color: KuriTheme.borderSubtle))),
    child: Row(children: [
      // --- BACK BUTTON ---
      IconButton(
        onPressed: () => Navigator.pop(context),
        icon: const Icon(Icons.arrow_back_ios_new, size: 20, color: KuriTheme.textDark),
        padding: const EdgeInsets.only(right: 16), // Spacing between button and title
      ),

      const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Kuri Administration",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: KuriTheme.textDark)),
            Text("Manage and monitor all active Kuri",
                style: TextStyle(color: KuriTheme.textMuted, fontSize: 13))
          ]
      ),

      const Spacer(),

      ElevatedButton.icon(
          onPressed: () => _KuriFormDialog.show(context, userId: userId, userName: userName, userRole: userRole),
          style: ElevatedButton.styleFrom(
              backgroundColor: KuriTheme.primaryIndigo,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
          ),
          icon: const Icon(Icons.add, size: 20),
          label: const Text("START NEW KURI")
      )
    ]),
  );
}

class _TableTopBar extends StatelessWidget {
  const _TableTopBar();
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20), decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: KuriTheme.borderSubtle))), child: const Row(children: [Text("Kuri Overview", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: KuriTheme.textDark)), Spacer()]));
}

class _Badge extends StatelessWidget {
  final String text;
  final Color color;
  const _Badge({required this.text, required this.color});
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(6)), child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11)));
}

class _CircleAction extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _CircleAction({required this.icon, required this.color, required this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(onTap: onTap, borderRadius: BorderRadius.circular(8), child: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: color.withOpacity(0.05), borderRadius: BorderRadius.circular(8)), child: Icon(icon, color: color, size: 18)));
}