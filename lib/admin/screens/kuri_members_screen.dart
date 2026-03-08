import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

// Ensure the path to your updated dialog is correct
import 'dailogs/addmemberDailog.dart';

class SchemeTheme {
  static const primaryBlue = Color(0xFF1E3A8A);
}

class KuriMembersScreen extends StatefulWidget {
  final String kuriId;
  final String kuriName;
  final String userId;
  final String userName;
  final String userRole;
  final Map<String, dynamic> kuriData;

  const KuriMembersScreen({
    super.key,
    required this.kuriId,
    required this.kuriName,
    required this.userId,
    required this.userName,
    required this.userRole,
    required this.kuriData,
  });

  @override
  State<KuriMembersScreen> createState() => _KuriMembersScreenState();
}

class _KuriMembersScreenState extends State<KuriMembersScreen> {
  List<DocumentSnapshot> _allMembers = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  DocumentSnapshot? _lastDocument;

  String searchQuery = "";
  String selectedStatus = "All";
  DateTime selectedMonth = DateTime.now();
  String get monthKey => DateFormat('yyyy_MM').format(selectedMonth);

  final ScrollController _verticalScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _fetchMembers(isInitial: true);

    _verticalScroll.addListener(() {
      // Trigger when scrolled 90% of the way down
      if (_verticalScroll.position.pixels >= _verticalScroll.position.maxScrollExtent * 0.9) {
        if (!_isLoadingMore && _hasMore) {
          _fetchMembers(isInitial: false);
        }
      }
    });
  }

  double _parseNum(dynamic val) {
    if (val == null) return 0.0;
    if (val is num) return val.toDouble();
    return double.tryParse(val.toString()) ?? 0.0;
  }

  // --- CORE FETCH LOGIC ---
  Future<void> _fetchMembers({bool isInitial = false}) async {
    // Prevent multiple simultaneous fetches
    if (_isLoadingMore || (_isLoading && !isInitial)) return;

    if (isInitial) {
      setState(() {
        _isLoading = true;
        _allMembers = [];
        _lastDocument = null;
        _hasMore = true;
      });
    } else {
      if (!_hasMore) return; // Stop if no more data to load
      setState(() => _isLoadingMore = true);
    }

    try {
      Query query = FirebaseFirestore.instance
          .collection('enrollments')
          .where('kuriId', isEqualTo: widget.kuriId);

      if (searchQuery.isNotEmpty) {
        // Note: Ensure your data in Firestore is stored in UPPERCASE for this to work
        String searchUpper = searchQuery.toUpperCase();
        query = query
            .where('name', isGreaterThanOrEqualTo: searchUpper)
            .where('name', isLessThanOrEqualTo: '$searchUpper\uf8ff')
            .orderBy('name');
      } else {
        query = query.orderBy('kuriNumber', descending: false);
      }

      // Cost-efficient limit
      const int fetchLimit = 20;
      query = query.limit(fetchLimit);

      if (_lastDocument != null && !isInitial) {
        query = query.startAfterDocument(_lastDocument!);
      }

      final snap = await query.get();

      if (mounted) {
        setState(() {
          if (isInitial) {
            _allMembers = snap.docs;
          } else {
            _allMembers.addAll(snap.docs);
          }

          // If we got fewer than 20, we reached the end
          _hasMore = snap.docs.length == fetchLimit;
          if (snap.docs.isNotEmpty) _lastDocument = snap.docs.last;

          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      debugPrint("Firestore Error: $e");
      if (mounted) setState(() {
        _isLoading = false;
        _isLoadingMore = false;
      });
    }
  }
  void _showAddMember() async {
    final bool? saved = await showDialog<bool>(
      context: context,
      builder: (context) => SelectFromMasterDialog(
        kuriId: widget.kuriId,
        kuriName: widget.kuriName,
        userId: widget.userId,
        userName: widget.userName,
        kuriData: widget.kuriData,
      ),
    );
    if (saved == true) _fetchMembers(isInitial: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("${widget.kuriName} Management"),
        backgroundColor: SchemeTheme.primaryBlue,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddMember,
        label: const Text("Enroll Member",style: TextStyle(color: Colors.white),),
        icon: const Icon(Icons.person_add_alt_1,color: Colors.white,),
        backgroundColor: SchemeTheme.primaryBlue,
      ),
      body: Column(
        children: [
          _buildDetailRibbon(),
          _buildSearchAndFilters(),
          _buildMonthNavigator(),

          _buildMemberTableContent(),
        ],
      ),
    );
  }

  // --- UI COMPONENTS ---

  Widget _buildDetailRibbon() {
    final currencyFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('kuris').doc(widget.kuriId).snapshots(),
      builder: (context, kSnap) {
        if (!kSnap.hasData) return const SizedBox(height: 35);
        var kuriData = kSnap.data!.data() as Map<String, dynamic>;

        // Format Start and End Dates
        String startStr = kuriData['startMonth'] != null
            ? DateFormat('MMM yy').format((kuriData['startMonth'] as Timestamp).toDate())
            : "-";
        String endStr = kuriData['endMonth'] != null
            ? DateFormat('MMM yy').format((kuriData['endMonth'] as Timestamp).toDate())
            : "-";

        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('enrollments').where('kuriId', isEqualTo: widget.kuriId).snapshots(),
          builder: (context, mSnap) {
            return StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('payments')
                  .where('kuriId', isEqualTo: widget.kuriId)
                  .where('monthKey', isEqualTo: monthKey).snapshots(),
              builder: (context, pSnap) {
                final totalMembers = mSnap.data?.docs.length ?? 0;
                final paidMembers = pSnap.data?.docs.length ?? 0;

                return Container(
                  height: 35, width: double.infinity, color: SchemeTheme.primaryBlue,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(
                      children: [
                        _compactItem("KURI", widget.kuriName.toUpperCase(), isTitle: true),


                        _vDivider(),
                        _compactItem("COLLECTION", "$paidMembers/$totalMembers PAID", isSpecial: true),
                        _vDivider(),
                        _compactItem("DRAW DATE", kuriData['kuriDate']?.toString() ?? ""),
                        _vDivider(),
                        // Added Start and End Dates at the end
                        _compactItem("START", startStr),
                        _vDivider(),
                        _compactItem("END", endStr),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildSearchAndFilters() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      color: Colors.white,
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: TextField(
                onChanged: (val) => searchQuery = val,
                onSubmitted: (val) {
                  searchQuery = val;
                  _fetchMembers(isInitial: true);
                },
                decoration: InputDecoration(
                  hintText: "Search name...",
                  prefixIcon: const Icon(Icons.person, size: 20),
                  // MANUAL SEARCH BUTTON
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.search, color: SchemeTheme.primaryBlue),
                    onPressed: () => _fetchMembers(isInitial: true),
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.only(top: 7),
                ),
              ),
            ),
          ),
          const SizedBox(width: 20),
          DropdownButton<String>(
            value: selectedStatus,
            onChanged: (val) => setState(() => selectedStatus = val!),
            items: ["All", "Paid", "Pending"].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthNavigator() {
    DateTime start = (widget.kuriData['startMonth'] is Timestamp)
        ? (widget.kuriData['startMonth'] as Timestamp).toDate()
        : DateTime.now();
    final int? totalMonthsFromDb = int.tryParse(widget.kuriData['totalMonths']?.toString() ?? '');
    final List<DateTime> allMonths = (totalMonthsFromDb != null && totalMonthsFromDb > 0)
        ? List.generate(totalMonthsFromDb, (i) => DateTime(start.year, start.month + i))
        : [];

    if (allMonths.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 60,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        itemCount: allMonths.length,
        itemBuilder: (context, index) {
          DateTime m = allMonths[index];
          bool isSelected = m.year == selectedMonth.year && m.month == selectedMonth.month;

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: InkWell(
              onTap: () => setState(() => selectedMonth = m),
              borderRadius: BorderRadius.circular(30),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isSelected ? SchemeTheme.primaryBlue : Colors.white,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: isSelected
                      ? [BoxShadow(color: SchemeTheme.primaryBlue.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4))]
                      : [],
                  border: Border.all(
                    color: isSelected ? SchemeTheme.primaryBlue : Colors.grey.shade300,
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Text(
                      DateFormat('MMM').format(m).toUpperCase(),
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isSelected ? Colors.white : Colors.black87
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      DateFormat('yy').format(m),
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: isSelected ? Colors.white70 : Colors.grey
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMemberTableContent() {
    if (_isLoading) return const Expanded(child: Center(child: CircularProgressIndicator()));
    final currencyFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('payments')
          .where('kuriId', isEqualTo: widget.kuriId)
          .snapshots(),
      builder: (context, pSnap) {
        if (!pSnap.hasData) return const Expanded(child: Center(child: CircularProgressIndicator()));

        final allPayments = pSnap.data!.docs;

        Map<String, Map<String, dynamic>> currentMonthPaidMap = {
          for (var doc in allPayments.where((p) => p['monthKey'] == monthKey))
            doc['memberId'].toString(): doc.data() as Map<String, dynamic>
        };

        List<DocumentSnapshot> filteredList = _allMembers.where((mDoc) {
          final isPaid = currentMonthPaidMap.containsKey(mDoc.id);
          if (selectedStatus == "Paid" && !isPaid) return false;
          if (selectedStatus == "Pending" && isPaid) return false;
          return true;
        }).toList();

        return Expanded(
          child: Column(
            children: [
              Expanded(
                child: Scrollbar(
                  controller: _verticalScroll,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _verticalScroll,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        headingRowHeight: 45,
                        dataRowMaxHeight: 60,
                        columnSpacing: 40,
                        headingRowColor: WidgetStateProperty.all(Colors.grey.shade100),
                        border: TableBorder.all(color: Colors.grey.shade300, width: 0.5),
                        columns: const [
                          DataColumn(label: Text("K.NO", style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text("NAME", style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text("PLACE", style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text("MONTHLY", style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text("INST", style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text("PAID", style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text("BAL", style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text("STATUS", style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text("DATE", style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text("MODE & SPLITS", style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text("COLLECTOR", style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text("ENTRY", style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text("ACTION", style: TextStyle(fontWeight: FontWeight.bold))),
                        ],
                        rows: filteredList.map((m) {
                          final d = m.data() as Map<String, dynamic>;
                          final mid = m.id;
                          final isPaid = currentMonthPaidMap.containsKey(mid);
                          final pMonth = isPaid ? currentMonthPaidMap[mid] : null;

                          double monthlyAmount = _parseNum(d['monthlyAmount']);
                          int totalMonths = int.tryParse(d['totalMonths']?.toString() ?? '0') ?? 0;

                          // Winner Logic Definitions
                          String? winnerMonth = d['winnerMonth'];
                          bool isCurrentMonthWinner = winnerMonth == monthKey;
                          bool hasWonInPast = winnerMonth != null && !isCurrentMonthWinner;

                          final mPayments = allPayments.where((p) => p['memberId'] == mid);
                          double totalPaid = mPayments.fold(0.0, (sum, p) => sum + _parseNum(p['amount']));
                          double balance = (monthlyAmount * totalMonths) - totalPaid;

                          return DataRow(
                            color: isCurrentMonthWinner ? WidgetStateProperty.all(Colors.amber.shade50) : null,
                            cells: [
                              DataCell(Text(d['kuriNumber']?.toString() ?? "-", style: const TextStyle(fontWeight: FontWeight.bold))),
                              DataCell(Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(d['name'].toString().toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                  Text(d['phone'] ?? "-", style: const TextStyle(fontSize: 10, color: Colors.grey)),
                                ],
                              )),
                              DataCell(Text(d['place']?.toString() ?? "-", style: const TextStyle(fontSize: 11))),
                              DataCell(Text(currencyFormat.format(monthlyAmount), style: const TextStyle(fontSize: 11))),
                              DataCell(Text("${mPayments.length}/$totalMonths", style: const TextStyle(fontSize: 11))),
                              DataCell(Text(currencyFormat.format(totalPaid), style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 11))),
                              DataCell(Text(currencyFormat.format(balance > 0 ? balance : 0), style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 11))),
                              DataCell(_buildStatusBadge(isPaid, hasWonInPast, isCurrentMonthWinner, pMonth)),
                              DataCell(Text(isPaid ? DateFormat('dd-MM-yy').format((pMonth!['paidDate'] as Timestamp).toDate()) : "-", style: const TextStyle(fontSize: 11))),
                              DataCell(
                                isPaid ? Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(pMonth!['mode']?.toString() ?? "-", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                    if (pMonth['splitAmounts'] != null)
                                      Text("₹${pMonth['splitAmounts']}", style: const TextStyle(fontSize: 9, color: Colors.blueGrey, fontStyle: FontStyle.italic)),
                                  ],
                                ) : const Text("-"),
                              ),
                              DataCell(Text(isPaid ? pMonth!['collectedBy'] ?? "-" : "-", style: const TextStyle(fontSize: 10))),
                              DataCell(isPaid ? Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(pMonth!['addedByName']?.toString().toUpperCase() ?? "-", style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold)),
                                  if (pMonth['paidAt'] != null)
                                    Text(DateFormat('dd-MMM hh:mm').format((pMonth['paidAt'] as Timestamp).toDate()), style: const TextStyle(fontSize: 8)),
                                ],
                              ) : const Text("-")),
                              DataCell(Row(
                                children: [
                                  // Show Pay button only if not paid and hasn't won before
                                  if (!isPaid && !hasWonInPast)
                                    _buildPayButton(mid, d['name'], d['masterId'] ?? mid, monthlyAmount),

                                  // Winner Button with Conditions
                                  if (!hasWonInPast)
                                    IconButton(
                                      icon: Icon(
                                        isCurrentMonthWinner ? Icons.stars : Icons.emoji_events_outlined,
                                        color: isCurrentMonthWinner
                                            ? Colors.orange
                                            : (isPaid ? Colors.blue : Colors.grey.shade400),
                                        size: 20,
                                      ),
                                      onPressed: isCurrentMonthWinner
                                          ? null
                                          : () => _markAsWinner(mid, d['name'], isPaid, d),
                                      tooltip: isCurrentMonthWinner
                                          ? "Winner"
                                          : (isPaid ? "Mark Winner" : "Payment Required"),
                                    ),
                                ],
                              )),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),
              ),
              if (_isLoadingMore)
                Container(
                  padding: const EdgeInsets.all(12),
                  width: double.infinity,
                  color: Colors.white,
                  child: const Center(child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))),
                ),
            ],
          ),
        );
      },
    );
  }
// Helper to build the status badge using the logic you provided
  Widget _buildStatusBadge(bool isPaid, bool hasWonInPast, bool isCurrentMonthWinner, Map<String, dynamic>? pMonth) {
    Color statusColor = const Color(0xFFFEE2E2);
    String statusLabel = "PENDING";

    if (hasWonInPast) {
      statusColor = const Color(0xFFEFF6FF);
      statusLabel = "WON";
    } else if (isCurrentMonthWinner) {
      statusColor = Colors.amber.shade100;
      statusLabel = "WINNER";
    } else if (isPaid && pMonth != null) {
      DateTime pDate = (pMonth['paidDate'] as Timestamp).toDate();
      String paymentMonthKey = pMonth['monthKey']?.toString() ?? "";
      String currentTableMonthKey = monthKey;

      int drawDay = int.tryParse(widget.kuriData['kuriDate']?.toString() ?? '10') ?? 10;
      int lastPayDay = drawDay > 2 ? (drawDay - 2) : 1;

      DateTime firstDayOfMonth = DateTime(selectedMonth.year, selectedMonth.month, 1);
      DateTime deadlineDate = DateTime(selectedMonth.year, selectedMonth.month, lastPayDay, 23, 59, 59);
      DateTime drawDate = DateTime(selectedMonth.year, selectedMonth.month, drawDay, 23, 59, 59);

      if (paymentMonthKey != currentTableMonthKey || pDate.isBefore(firstDayOfMonth)) {
        statusColor = const Color(0xFFBAE6FD);
        statusLabel = "ADVANCE";
      } else if (pDate.isAfter(drawDate)) {
        statusColor = Colors.grey.shade300;
        statusLabel = "LATE\nNO CHANCE";
      } else if (pDate.isAfter(deadlineDate)) {
        statusColor = Colors.orange.shade200;
        statusLabel = "LATE\nWITH CHANCE";
      } else {
        statusColor = const Color(0xFF54EA89);
        statusLabel = "ON-TIME";
      }
    }

    return Container(
      width: 90, height: 35, alignment: Alignment.center,
      decoration: BoxDecoration(color: statusColor, borderRadius: BorderRadius.circular(4)),
      child: Text(statusLabel.toUpperCase(),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.black87)),
    );
  }
  // --- UPDATED WINNER ACTION ---

  void _markAsWinner(String mid, String name, bool isPaid, Map<String, dynamic> memberData) async {
    // --- EXISTING CHECKS (Date, Payment, Late) ---
    final int drawDay = int.tryParse(widget.kuriData['kuriDate']?.toString() ?? '0') ?? 0;
    final int todayDay = DateTime.now().day;
    final DateTime now = DateTime.now();

    bool isDrawDateReached = (now.year > selectedMonth.year) ||
        (now.year == selectedMonth.year && now.month > selectedMonth.month) ||
        (now.year == selectedMonth.year && now.month == selectedMonth.month && todayDay >= drawDay);

    if (!isDrawDateReached) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Draw date ($drawDay) not reached yet."), backgroundColor: Colors.orange));
      return;
    }

    if (!isPaid) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Pending members cannot win."), backgroundColor: Colors.red));
      return;
    }

    if (memberData['isLate'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Late members disqualified."), backgroundColor: Colors.black));
      return;
    }

    // --- NEW: ONE WINNER PER MONTH CHECK ---
    try {
      final existingWinnerSnap = await FirebaseFirestore.instance
          .collection('enrollments')
          .where('kuriId', isEqualTo: widget.kuriId)
          .where('winnerMonth', isEqualTo: monthKey)
          .limit(1)
          .get();

      if (existingWinnerSnap.docs.isNotEmpty) {
        String currentWinnerName = existingWinnerSnap.docs.first['name'] ?? "Someone";
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("ERROR: $currentWinnerName is already the winner for this month!"),
            backgroundColor: Colors.red.shade900,
          ),
        );
        return;
      }
    } catch (e) {
      debugPrint("Winner Check Error: $e");
    }

    // --- PROCEED TO CONFIRMATION ---
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Confirm Winner"),
        content: Text("Are you sure you want to mark $name as the ONLY winner for ${DateFormat('MMMM yyyy').format(selectedMonth)}?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () async {
              await FirebaseFirestore.instance.collection('enrollments').doc(mid).update({
                'winnerMonth': monthKey,
                'winDate': FieldValue.serverTimestamp(),
              });
              Navigator.pop(context);
              _fetchMembers(isInitial: true);
            },
            child: const Text("Confirm Winner"),
          ),
        ],
      ),
    );
  }

  Widget _buildPayButton(String enrollmentId, String name, String masterId, double monthlyAmount) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.green,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
        minimumSize: const Size(50, 28),
        elevation: 0,
      ),
      onPressed: () => _showMarkPaymentDialog(enrollmentId, name, masterId, monthlyAmount),
      child: const Text("PAY", style: TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold)),
    );
  }

  void _showMarkPaymentDialog(String enrollmentId, String name, String masterId, double monthlyAmount) async {
    final adminSnap = await FirebaseFirestore.instance.collection('staff_admins').orderBy('name').get();
    Map<String, String> adminIdMap = {for (var doc in adminSnap.docs) doc['name'].toString(): doc.id};
    List<String> adminNames = adminIdMap.keys.toList();

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (c) => MarkPaymentDialog(
        memberName: name,
        fullAmount: monthlyAmount,
        adminList: adminNames,
        onConfirm: (splits, totalCollected) async {
          try {
            // --- NEW: Create a string of just the amounts for the table ---
            String splitAmountsStr = splits.map((s) => s['amount'].toString()).join(", ");

            await FirebaseFirestore.instance.collection('payments').add({
              'kuriId': widget.kuriId,
              'memberId': enrollmentId,
              'masterId': masterId,
              'monthKey': monthKey,
              'amount': monthlyAmount,
              'collectedTotal': totalCollected,
              'splitAmounts': splitAmountsStr, // Saved for quick display in table
              'mode': splits.map((s) => s['mode'].toString()).join(", "),
              'collectedBy': splits.map((s) => s['collector'].toString()).join(", "),
              'paymentSplits': splits.map((s) => {
                'collectorName': s['collector'],
                'collectorId': adminIdMap[s['collector']] ?? "",
                'amount': s['amount'],
                'mode': s['mode'],
                'date': s['date'],
              }).toList(),
              'paidDate': Timestamp.fromDate(splits.last['date']),
              'paidAt': FieldValue.serverTimestamp(),
              'addedById': widget.userId,
              'addedByName': widget.userName,
            });

            _fetchMembers(isInitial: true);
            if (mounted) Navigator.pop(c); // Close dialog
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Paid Successfully"), backgroundColor: Colors.green));
          } catch (e) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
          }
        },
      ),
    );
  }
  // --- HELPERS ---

  Widget _buildCompactBox({required String label, required Widget child}) => Row(mainAxisSize: MainAxisSize.min, children: [
    Text("$label:", style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontWeight: FontWeight.bold)),
    const SizedBox(width: 4), Expanded(child: child)
  ]);


// Helper methods for the Ribbon UI
  Widget _compactItem(String label, String value, {bool isTitle = false, bool isSpecial = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Text("$label: ", style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w400)),
          Text(value, style: TextStyle(
              color: isSpecial ? Colors.yellowAccent : Colors.white,
              fontSize: isTitle ? 14 : 14,
              fontWeight: FontWeight.bold
          )),
        ],
      ),
    );
  }

  Widget _vDivider() {
    return VerticalDivider(color: Colors.white24, indent: 8, endIndent: 8, width: 20);
  }










}
