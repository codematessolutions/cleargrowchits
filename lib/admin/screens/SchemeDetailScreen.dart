import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Ensure this path matches your file structure
import 'dailogs/addmemberDailog.dart';

class SchemeTheme {
  static const Color primaryBlue = Color(0xFF1E3A8A);
  static const Color softBlueBg = Color(0xFFF1F5F9);
  static const Color headerGrey = Color(0xFFE2E8F0);
  static const Color colOdd = Color(0xFFF8FAFC);
}

class SchemeDetailScreen extends StatefulWidget {
  final String schemeId;
  final String userId;
  final String userName;
  final String userRole;
  final String kuriId;
  final Map<String, dynamic> schemeData;
  final Map<String, dynamic> kuriData;

  const SchemeDetailScreen({
    super.key,
    required this.schemeId,
    required this.schemeData,
    required this.kuriData,
    required this.userId,
    required this.userName,
    required this.userRole,
    required this.kuriId,
  });

  @override
  State<SchemeDetailScreen> createState() => _SchemeDetailScreenState();
}

class _SchemeDetailScreenState extends State<SchemeDetailScreen> {
  final TextEditingController _searchController = TextEditingController();
  String searchQuery = "";
  List<DocumentSnapshot> _allMembers = [];
  List<DocumentSnapshot> _allPayments = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  DocumentSnapshot? _lastDocument;

  StreamSubscription? _paymentSub;

  String selectedStatus = "All";
  String selectedMode = "All"; // Add this line
  DateTime selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  final ScrollController _verticalScroll = ScrollController();

  String get monthKey => DateFormat('yyyy_MM').format(selectedMonth);
  double _parseNum(dynamic val) => val is num ? val.toDouble() : double.tryParse(val.toString()) ?? 0.0;

  @override
  void initState() {
    super.initState();
    _fetchMembers(isInitial: true);
    _initPaymentListener();

    _verticalScroll.addListener(() {
      if (_verticalScroll.position.pixels >= _verticalScroll.position.maxScrollExtent - 300) {
        _fetchMembers();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _verticalScroll.dispose();
    _paymentSub?.cancel();
    super.dispose();
  }

  Future<void> _fetchMembers({bool isInitial = false}) async {
    if (isInitial) {
      setState(() {
        _isLoading = true;
        _allMembers = [];
        _lastDocument = null;
        _hasMore = true;
      });
    }

    // Prevent multiple simultaneous loads
    if (_isLoadingMore && !isInitial) return;
    if (!isInitial) setState(() => _isLoadingMore = true);

    try {
      // 1. Start with the basic query
      Query query = FirebaseFirestore.instance
          .collection('members')
          .where('schemeId', isEqualTo: widget.schemeId);

      // 2. Add Name/Kuri Search (Note: Firestore is Case-Sensitive)
      if (searchQuery.isNotEmpty) {
        final searchNum = int.tryParse(searchQuery);
        if (searchNum != null) {
          // Search by Kuri Number (as Number)
          query = query.where('kuriNumber', isEqualTo: searchNum);
        } else {
          // Search by Name (Ensure searching for UPPERCASE as stored)
          String searchUpper = searchQuery.toUpperCase();
          query = query
              .orderBy('name') // Must order by name to use range filters
              .where('name', isGreaterThanOrEqualTo: searchUpper)
              .where('name', isLessThanOrEqualTo: '$searchUpper\uf8ff');
        }
      } else {
        // Default ordering if no search
        query = query.orderBy('kuriNumber', descending: false);
      }

      query = query.limit(50); // Increased limit slightly for better filter experience

      if (_lastDocument != null) {
        query = query.startAfterDocument(_lastDocument!);
      }

      final snap = await query.get();

      if (mounted) {
        setState(() {
          _allMembers.addAll(snap.docs);
          _hasMore = snap.docs.length == 50;
          if (snap.docs.isNotEmpty) _lastDocument = snap.docs.last;
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      print("Search Error: $e");
      setState(() { _isLoading = false; _isLoadingMore = false; });
    }
  }

  void _initPaymentListener() {
    _paymentSub = FirebaseFirestore.instance
        .collection('payments')
        .where('schemeId', isEqualTo: widget.schemeId)
        .snapshots()
        .listen((snap) {
      if (mounted) setState(() => _allPayments = snap.docs);
    });
  }

  String _calculatePaymentStatus(DateTime paidDate) {
    int kuriDay = int.tryParse(widget.kuriData['kuriDate']?.toString() ?? '') ?? 0;
    int lastPayDay = kuriDay > 2 ? (kuriDay - 2) : 1;

    DateTime firstOfSelected = DateTime(selectedMonth.year, selectedMonth.month, 1);
    DateTime lastPayDeadline = DateTime(selectedMonth.year, selectedMonth.month, lastPayDay, 23, 59, 59);

    if (paidDate.isBefore(firstOfSelected)) return "Advance";
    if (kuriDay != 0 && paidDate.isBefore(lastPayDeadline.add(const Duration(seconds: 1)))) return "On-Time";
    return "Late";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SchemeTheme.softBlueBg,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: SchemeTheme.primaryBlue,
        title: Text(widget.schemeData['schemeName'].toString().toUpperCase(),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          _buildDetailRibbonFromState(),
          _buildFilterBar(),
          _buildMonthNavigator(),
          _buildMemberTable(),
        ],
      ),


      // floatingActionButton: FloatingActionButton(
      //   backgroundColor: SchemeTheme.primaryBlue,
      //   onPressed: () => _showAddMember(),
      //   child: const Icon(Icons.person_add, color: Colors.white),
      // ),
    );
  }

  Widget _buildMemberTable() {
    final currencyFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

    final Map<String, List<DocumentSnapshot>> memberPaymentHistory = {};
    final Map<String, Map<String, dynamic>> currentMonthPaidMap = {};

    for (var p in _allPayments) {
      final pData = p.data() as Map<String, dynamic>? ?? {};
      String mid = (pData['memberId'] ?? "").toString();
      if (mid.isEmpty) continue;
      memberPaymentHistory.putIfAbsent(mid, () => []).add(p);
      if ((pData['monthKey'] ?? "").toString() == monthKey) {
        currentMonthPaidMap[mid] = pData;
      }
    }

    final filteredList = _allMembers.where((mDoc) {
      final bool isPaid = currentMonthPaidMap.containsKey(mDoc.id);
      if (selectedStatus == "Paid") return isPaid;
      if (selectedStatus == "Pending") return !isPaid;
      return true;
    }).toList();

    final monthlyAmount = _parseNum(widget.schemeData['monthlyAmount'] ?? 0);
    final int totalMonths = int.tryParse(widget.schemeData['totalMonths']?.toString() ?? '0') ?? 0;

    final tableRows = filteredList.map((mDoc) {
      final d = mDoc.data() as Map<String, dynamic>? ?? {};
      final String enrollmentId = mDoc.id;
      final String memberName = (d['name'] ?? "UNKNOWN").toString();
      final String kuriNo = (d['kuriNumber'] ?? "-").toString();
      final String remark = (d['remark'] ?? "").toString();

      final pMonth = currentMonthPaidMap[enrollmentId];
      final bool isPaid = pMonth != null;
      final mHistory = memberPaymentHistory[enrollmentId] ?? [];

      // --- LOGIC: Identify "No Chance" for UI display ---
      bool isNoChance = false;
      if (isPaid && pMonth?['paidDate'] != null) {
        DateTime pDate = (pMonth!['paidDate'] as Timestamp).toDate();
        int drawDay = int.tryParse(widget.schemeData['kuriDate']?.toString() ?? '10') ?? 10;
        DateTime drawDateDeadline = DateTime(selectedMonth.year, selectedMonth.month, drawDay, 23, 59, 59);
        if (pDate.isAfter(drawDateDeadline) && pMonth['monthKey'] == monthKey) {
          isNoChance = true;
        }
      }

      List<String> splitAmounts = isPaid ? (pMonth!['splitAmounts']?.toString() ?? pMonth['amount'].toString()).split(", ") : [];
      List<String> modes = isPaid ? (pMonth!['mode'] ?? "Cash").toString().split(", ") : [];
      List<String> collectors = isPaid ? (pMonth!['collectedBy'] ?? "-").toString().split(", ") : [];

      String entryUser = isPaid ? (pMonth!['addedByName'] ?? "Admin").toString() : "-";
      String entryTime = "-";
      if (isPaid && pMonth!['paidAt'] != null) {
        entryTime = DateFormat('dd-MM-yy hh:mm a').format((pMonth['paidAt'] as Timestamp).toDate());
      }

      final Map<String, dynamic> allWinners = widget.schemeData['winners'] != null
          ? Map<String, dynamic>.from(widget.schemeData['winners'] as Map) : {};
      String? wonMonthKey;
      allWinners.forEach((key, val) { if (val.toString() == enrollmentId) wonMonthKey = key.toString(); });
      bool isCurrentMonthWinner = wonMonthKey == monthKey;
      bool hasWonInPast = (wonMonthKey != null && wonMonthKey != monthKey);

      final totalPaid = mHistory.fold<double>(0.0, (sum, p) => sum + _parseNum(p['amount'] ?? 0));
      final balance = (monthlyAmount * totalMonths) - totalPaid;

      return DataRow(
        color: isCurrentMonthWinner ? WidgetStateProperty.all(Colors.amber.shade50) : null,
        cells: [
          DataCell(Text(kuriNo, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
          DataCell(SizedBox(width: 220, child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(children: [
                if (wonMonthKey != null) Icon(Icons.stars, color: isCurrentMonthWinner ? Colors.orange : Colors.blue, size: 14),
                const SizedBox(width: 4),
                Expanded(child: Text("${kuriNo.padLeft(3,'0')} - ${memberName.toUpperCase()}",
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),

                // WINNER ICON LOGIC
                IconButton(
                    icon: Icon(wonMonthKey != null ? Icons.emoji_events : Icons.emoji_events_outlined,
                        size: 16,
                        color: wonMonthKey != null ? Colors.orange : (isNoChance ? Colors.grey.withOpacity(0.3) : Colors.grey)),
                    // Pass pMonth into the function to solve the "Undefined name" error
                    onPressed: (hasWonInPast || isNoChance) ? null : () => _confirmWinner(enrollmentId, memberName, isPaid, pMonth)
                )
              ]),
              if (remark.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 2),
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(4)),
                  child: Text("NOTE: $remark", style: const TextStyle(fontSize: 9, color: Colors.blue, fontWeight: FontWeight.bold)),
                ),
            ],
          ))),
          DataCell(Text((d['phone'] ?? "-").toString(), style: const TextStyle(fontSize: 12))),
          DataCell(Text((d['place'] ?? "-").toString(), style: const TextStyle(fontSize: 11))),
          DataCell(Text(currencyFormat.format(monthlyAmount), style: const TextStyle(fontSize: 12))),
          DataCell(Text("${mHistory.length}/$totalMonths", style: const TextStyle(fontSize: 12))),
          DataCell(isPaid
              ? Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: splitAmounts.map((amt) => Text(currencyFormat.format(_parseNum(amt)),
                style: const TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.bold))).toList(),
          )
              : const Text("-")
          ),
          DataCell(Text(currencyFormat.format(balance < 0 ? 0 : balance), style: const TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.bold))),
          // DataCell(Container(
          //     child: (isPaid || hasWonInPast || isCurrentMonthWinner)
          //         ? _buildStatusBadge(isPaid, hasWonInPast, isCurrentMonthWinner, pMonth)
          //         : _buildPayButton(enrollmentId, memberName, d['masterId'] ?? "")
          // )),
          DataCell(Text(
              isPaid && pMonth?['paidDate'] != null
                  ? DateFormat('dd-MM-yy  hh:mm a').format((pMonth!['paidDate'] as Timestamp).toDate())
                  : "-",
              style: const TextStyle(fontSize: 11)
          )),
          DataCell(isPaid
              ? Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: List.generate(modes.length, (index) {
              String amt = splitAmounts.length > index ? currencyFormat.format(_parseNum(splitAmounts[index])) : "";
              return Text("$amt (${modes[index]})", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500));
            }),
          )
              : const Text("-")
          ),
          DataCell(isPaid
              ? Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: collectors.map((c) => Text(c, style: const TextStyle(fontSize: 12, color: Colors.blueGrey))).toList(),
          )
              : const Text("-")
          ),
          DataCell(isPaid
              ? Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(entryUser.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
              Text(entryTime, style: const TextStyle(fontSize: 9, color: Colors.grey)),
            ],
          )
              : const Text("-")
          ),
        ],
      );
    }).toList();

    return Expanded(
      child: Scrollbar(
        controller: _verticalScroll,
        child: SingleChildScrollView(
          controller: _verticalScroll,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowHeight: 40,
              dataRowMaxHeight: 65,
              columnSpacing: 60,
              horizontalMargin: 15,
              headingRowColor: WidgetStateProperty.all(Colors.grey.shade200),
              border: TableBorder.all(color: Colors.grey.shade300, width: 0.5),
              columns: _buildTableColumns(),
              rows: tableRows,
            ),
          ),
        ),
      ),
    );
  }
  Widget _buildStatusBadge(bool isPaid, bool hasWonInPast, bool isCurrentMonthWinner, Map<String, dynamic>? pMonth) {
    Color statusColor = const Color(0xFFFEE2E2); // Default Red/Pending
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

      // 1. Define Dates
      int drawDay = int.tryParse(widget.schemeData['kuriDate']?.toString() ?? '10') ?? 10;
      int lastPayDay = drawDay > 2 ? (drawDay - 2) : 1; // e.g., 8th

      DateTime firstDayOfMonth = DateTime(selectedMonth.year, selectedMonth.month, 1);
      DateTime deadlineDate = DateTime(selectedMonth.year, selectedMonth.month, lastPayDay, 23, 59, 59);
      DateTime drawDate = DateTime(selectedMonth.year, selectedMonth.month, drawDay, 23, 59, 59);

      // --- LOGIC REFINEMENT ---

      // SCENARIO: ADVANCE
      if (paymentMonthKey != currentTableMonthKey || pDate.isBefore(firstDayOfMonth)) {
        statusColor = const Color(0xFFBAE6FD); // Blue
        statusLabel = "ADVANCE";
      }
      // SCENARIO: NO CHANCE (Paid after Draw)
      else if (pDate.isAfter(drawDate)) {
        statusColor = Colors.grey.shade300;
        statusLabel = "LATE\nNO CHANCE";
      }
      // SCENARIO: LATE BUT HAS CHANCE (Paid between 8th and 10th)
      else if (pDate.isAfter(deadlineDate) && pDate.isBefore(drawDate.add(const Duration(seconds: 1)))) {
        statusColor = Colors.orange.shade200;
        statusLabel = "LATE\nWITH CHANCE";
      }
      // SCENARIO: ON-TIME (Paid before 8th)
      else {
        statusColor = const Color(0xFF54EA89); // Green
        statusLabel = "ON-TIME";
      }
    }

    return Container(
      width: double.infinity, height: 35, alignment: Alignment.center,
      decoration: BoxDecoration(color: statusColor, borderRadius: BorderRadius.circular(4)),
      child: Text(statusLabel.toUpperCase(),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.black87)),
    );
  }

  // Widget _buildPayButton(String enrollmentId, String name, String masterId) {
  //   return ElevatedButton(
  //     style: ElevatedButton.styleFrom(
  //       backgroundColor: Colors.red,
  //       padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
  //       minimumSize: const Size(60, 30),
  //       elevation: 0,
  //     ),
  //     onPressed: () => _showMarkPaymentDialog(enrollmentId, name, masterId),
  //     child: const Text("PAY", style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
  //   );
  // }

  void _confirmWinner(String enrollmentId, String name, bool isPaid, Map<String, dynamic>? pMonth) {
    // 1. Basic Check: Must be paid
    if (!isPaid) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Member must pay first."), backgroundColor: Colors.red)
      );
      return;
    }

    // 2. LATE / NO CHANCE CHECK
    // We use the pMonth passed from the table row to check the date
    if (pMonth != null && pMonth['paidDate'] != null) {
      DateTime pDate = (pMonth['paidDate'] as Timestamp).toDate();
      int drawDay = int.tryParse(widget.schemeData['kuriDate']?.toString() ?? '10') ?? 10;

      // Create the Draw Date deadline for the selected month
      DateTime drawDateDeadline = DateTime(selectedMonth.year, selectedMonth.month, drawDay, 23, 59, 59);

      // Block if payment was made AFTER the draw date
      if (pDate.isAfter(drawDateDeadline)) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("LATE PAYMENT: This member has NO CHANCE for this month's draw."),
              backgroundColor: Colors.black,
              behavior: SnackBarBehavior.floating,
            )
        );
        return;
      }
    }

    // 3. Check if Draw Date has arrived (for current month only)
    int drawDayVal = int.tryParse(widget.schemeData['kuriDate']?.toString() ?? '10') ?? 10;
    DateTime now = DateTime.now();
    if (selectedMonth.year == now.year && selectedMonth.month == now.month && now.day < drawDayVal) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Draw date is Day $drawDayVal."), backgroundColor: Colors.orange)
      );
      return;
    }

    // 4. Confirmation Dialog
    final Map<String, dynamic> existingWinners = widget.schemeData['winners'] != null
        ? Map<String, dynamic>.from(widget.schemeData['winners'] as Map) : {};
    bool isReplacement = existingWinners.containsKey(monthKey);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isReplacement ? "REPLACE WINNER" : "CONFIRM WINNER"),
        content: Text("Mark ${name.toUpperCase()} as winner for ${DateFormat('MMMM yyyy').format(selectedMonth)}?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCEL")),
          ElevatedButton(
            onPressed: () async {
              final batch = FirebaseFirestore.instance.batch();

              // 1. Database Updates
              batch.update(FirebaseFirestore.instance.collection('schemes').doc(widget.schemeId), {
                'winners.$monthKey': enrollmentId
              });

              batch.set(FirebaseFirestore.instance.collection('winners').doc("${widget.schemeId}_$monthKey"), {
                'schemeId': widget.schemeId,
                'monthKey': monthKey,
                'memberId': enrollmentId,
                'memberName': name,
                'updatedAt': FieldValue.serverTimestamp()
              });

              await batch.commit();

              if (mounted) {
                // 2. CRITICAL: Update local state immediately
                setState(() {
                  // Ensure the winners map exists locally before assigning
                  if (widget.schemeData['winners'] == null) {
                    widget.schemeData['winners'] = <String, dynamic>{};
                  }
                  // Manually set the winner in the local object
                  widget.schemeData['winners'][monthKey] = enrollmentId;
                });

                // 3. Close the dialog
                Navigator.pop(context);

                // 4. Background refresh to stay in sync with server
                _fetchMembers(isInitial: true);

                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Winner Marked Successfully"),
                      backgroundColor: Colors.orange,
                    )
                );
              }
            },
            child: const Text("CONFIRM"),
          )
        ],
      ),
    );
  }

  // void _showMarkPaymentDialog(String enrollmentId, String name, String masterId) async {
  //   // 1. Fetch both Name and ID from staff_admins
  //   final adminSnap = await FirebaseFirestore.instance.collection('staff_admins').orderBy('name').get();
  //
  //   // Create a Map for easy ID lookup: { "John": "ID123", "Jane": "ID456" }
  //   Map<String, String> adminIdMap = {
  //     for (var doc in adminSnap.docs) doc['name'].toString(): doc.id
  //   };
  //
  //   List<String> adminNames = adminIdMap.keys.toList();
  //
  //   if (!mounted) return;
  //
  //   showDialog(
  //       context: context,
  //       builder: (c) => MarkPaymentDialog(
  //         memberName: name,
  //         fullAmount: _parseNum(widget.schemeData['monthlyAmount']),
  //         adminList: adminNames,
  //         onConfirm: (splits, totalCollected) async {
  //           try {
  //             // 1. Prepare Split Array for Audit
  //             List<Map<String, dynamic>> splitArray = splits.map((s) => {
  //               'collectorName': s['collector'],
  //               'collectorId': adminIdMap[s['collector']] ?? "",
  //               'amount': s['amount'],
  //               'mode': s['mode'],
  //               'date': s['date'],
  //             }).toList();
  //
  //             // 2. Add to Firestore
  //             await FirebaseFirestore.instance.collection('payments').add({
  //               'kuriId': widget.schemeData['kuriId'],
  //               'schemeId': widget.schemeId,
  //               'memberId': enrollmentId,
  //               'masterId': masterId,
  //               'monthKey': monthKey,
  //               'amount': widget.schemeData['monthlyAmount'],
  //               'splitAmounts': splits.map((s) => s['amount'].toString()).join(", "),
  //               'mode': splits.map((s) => s['mode'].toString()).join(", "),
  //               'collectedBy': splits.map((s) => s['collector'].toString()).join(", "),
  //               'collectorIds': splits.map((s) => adminIdMap[s['collector']] ?? "").join(", "),
  //               'paymentSplits': splitArray,
  //               'paidDate': Timestamp.fromDate(splits.last['date']),
  //               'paidAt': FieldValue.serverTimestamp(),
  //               'status': _calculatePaymentStatus(splits.last['date']),
  //               'addedById': widget.userId,
  //               'addedByName': widget.userName,
  //             });
  //
  //             if (mounted) {
  //               // 3. CLOSE ONLY THE DIALOG
  //               // Navigator.of(c).pop();
  //
  //               // 4. REFRESH THE CURRENT TABLE
  //               // This ensures the "Pay" button turns into a "PAID" badge instantly
  //               _fetchMembers(isInitial: true);
  //
  //               // 5. SUCCESS FEEDBACK
  //               ScaffoldMessenger.of(context).showSnackBar(
  //                   const SnackBar(
  //                     content: Text("Payment Successful"),
  //                     backgroundColor: Colors.green,
  //                     duration: Duration(seconds: 2),
  //                   )
  //               );
  //             }
  //           } catch (e) {
  //             ScaffoldMessenger.of(context).showSnackBar(
  //                 SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red)
  //             );
  //           }
  //         },
  //       )
  //   );
  // }
  // --- EXISTING UI COMPONENTS ---
  Widget _buildDetailRibbonFromState() {
    final currencyFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
    final totalMembers = _allMembers.length;
    final paidMembers = _allPayments.where((p) => (p.data() as Map)['monthKey'] == monthKey).length;
    final schemeName = widget.schemeData['schemeName'] ?? "N/A";
    final monthlyAmt = _parseNum(widget.schemeData['monthlyAmount']);
    final moop = _parseNum(widget.schemeData['moop']);
    final totalMonths = widget.schemeData['totalMonths'] ?? widget.schemeData['totalInstallments'] ?? 0;
    String startStr = widget.schemeData['startMonth'] != null ? DateFormat('MMM yy').format((widget.schemeData['startMonth'] as Timestamp).toDate()) : "-";
    String endStr = widget.schemeData['endMonth'] != null ? DateFormat('MMM yy').format((widget.schemeData['endMonth'] as Timestamp).toDate()) : "-";
    final drawDate = _parseNum(widget.kuriData['kuriDate']);

    return Container(
      height: 35, width: double.infinity, color: SchemeTheme.primaryBlue,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          children: [
            _compactItem("SCHEME", schemeName.toString().toUpperCase(), isTitle: true),
            _vDivider(),
            _compactItem("MONTHLY", currencyFormat.format(monthlyAmt)),
            _vDivider(),
            _compactItem("MOOP", currencyFormat.format(moop)),
            _vDivider(),
            _compactItem("TOTAL", "$totalMonths Months"),
            _vDivider(),
            _compactItem("START", startStr),
            _vDivider(),
            _compactItem("END", endStr),
            _vDivider(),
            _compactItem("COLLECTION", "$paidMembers/$totalMembers PAID", isSpecial: true),
            _vDivider(),
            _compactItem("DRAW DATE", drawDate.toString()),


          ],
        ),
      ),
    );
  }

  Widget _compactItem(String label, String value, {bool isTitle = false, bool isSpecial = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white60, fontSize: 8, fontWeight: FontWeight.bold)),
          Text(value, style: TextStyle(color: isSpecial ? Colors.greenAccent : Colors.white, fontSize: isTitle ? 11 : 10, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _vDivider() => Container(height: 20, width: 1, color: Colors.white12);

  Widget _buildMonthNavigator() {
    // 1. Safely parse start date
    DateTime start = (widget.schemeData['startMonth'] is Timestamp)
        ? (widget.schemeData['startMonth'] as Timestamp).toDate()
        : DateTime.now();

    // 2. Strictly dynamic parsing - no hardcoded 21
    // We use tryParse and fallback to null if the field is missing or invalid
    final int? totalMonthsFromDb = int.tryParse(widget.schemeData['totalMonths']?.toString() ?? '');

    // 3. Generate the list ONLY if we have a valid number > 0
    final List<DateTime> allMonths = (totalMonthsFromDb != null && totalMonthsFromDb > 0)
        ? List.generate(totalMonthsFromDb, (i) => DateTime(start.year, start.month + i))
        : [];

    // 4. UI Handling for empty data
    if (allMonths.isEmpty) {
      return const SizedBox.shrink(); // Or a small "No duration set" text
    }

    return Container(
      height: 60,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: allMonths.length,
        itemBuilder: (context, index) {
          DateTime m = allMonths[index];
          bool isSelected = m.year == selectedMonth.year && m.month == selectedMonth.month;

          return GestureDetector(
            onTap: () => setState(() => selectedMonth = m),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: 100,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                color: isSelected ? SchemeTheme.primaryBlue : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? SchemeTheme.primaryBlue : Colors.grey.shade300,
                ),
                boxShadow: isSelected ? [
                  BoxShadow(
                    color: SchemeTheme.primaryBlue.withOpacity(0.2),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  )
                ] : null,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    DateFormat('MMM').format(m).toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Colors.white70 : Colors.grey.shade600,
                    ),
                  ),
                  Text(
                    DateFormat('yyyy').format(m),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Colors.white : Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
  Widget _buildFilterBar() {
    return Container(
      height: 44,
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      padding: const EdgeInsets.only(left: 12),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade200)
      ),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: TextField(
              controller: _searchController,
              style: const TextStyle(fontSize: 13),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                hintText: "Name or Kuri No...",
                hintStyle: const TextStyle(fontSize: 13, color: Colors.grey),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                // Clear button on the left
                prefixIcon: searchQuery.isNotEmpty
                    ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => searchQuery = "");
                    _fetchMembers(isInitial: true);
                  },
                )
                    : const SizedBox(width: 48),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search, color: Colors.blue, size: 20),
                  onPressed: () {
                    setState(() => searchQuery = _searchController.text.trim());
                    _fetchMembers(isInitial: true);
                  },
                ),
              ),
              onSubmitted: (v) {
                setState(() => searchQuery = v.trim());
                _fetchMembers(isInitial: true);
              },
            ),
          ),
          // Inside _buildFilterBar Row
          _vDividerForSearch(),
          Expanded(
              flex: 2,
              child: _buildCompactBox(
                  label: "Status",
                  child:_filterDropdown(
                    value: selectedStatus,
                    items: ["All", "Paid", "Pending"],
                      onChanged: (v) {
                        setState(() => selectedStatus = v!);
                        _fetchMembers(isInitial: true); // Start fresh from #1 with the new 100-batch limit
                      }
                  )
              )
          ),
          _buildCompactReset(),
        ],
      ),
    );
  }

  Widget _buildCompactBox({required String label, required Widget child}) {
    return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                  "$label:",
                  style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade500,
                      fontWeight: FontWeight.bold
                  )
              ),
              const SizedBox(width: 4),
              Expanded(child: child)
            ]
        )
    );
  }
  Widget _buildCompactReset() {
    return IconButton(
      onPressed: () {
        _searchController.clear();
        setState(() {
          selectedStatus = "All";
          selectedMode = "All";
          searchQuery = "";
          // Optional: Reset to current month
          selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
        });
        _fetchMembers(isInitial: true);
      },
      icon: const Icon(Icons.refresh, size: 18, color: Colors.grey),
      tooltip: "Reset Filters",
    );
  }


  Widget _vDividerForSearch() => VerticalDivider(color: Colors.grey.shade200, indent: 10, endIndent: 10, thickness: 1);


  Widget _filterDropdown({required String value, required List<String> items, required ValueChanged<String?> onChanged}) {
    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: value, isExpanded: true, icon: Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: Colors.grey.shade500),
        style: const TextStyle(fontSize: 14, color: Colors.black87, fontWeight: FontWeight.w500),
        items: items.map((e) => DropdownMenuItem(value: e, child: Text(e, overflow: TextOverflow.ellipsis))).toList(),
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildEntryInfoCell(bool isPaid, Map<String, dynamic>? pData) {
    if (!isPaid || pData == null) return const Text("-");

    // If you saved 'splits' as a sub-list in the payment doc, you can map them here.
    // Otherwise, we use the joined data.
    return IconButton(
      icon: const Icon(Icons.info_outline, size: 16, color: Colors.blue),
      onPressed: () {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text("Payment Breakdown"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Total: ₹${pData['amount']}"),
                const Divider(),
                Text("Modes: ${pData['mode']}"),
                Text("Collectors: ${pData['collectedBy']}"),
                Text("Date: ${DateFormat('dd MMM yyyy').format((pData['paidDate'] as Timestamp).toDate())}"),
                const SizedBox(height: 10),
                Text("Added By: ${pData['addedByName'] ?? 'Admin'}", style: const TextStyle(fontSize: 10, color: Colors.grey)),
              ],
            ),
          ),
        );
      },
    );
  }

  DataRow _buildGrandTotalRow(double paid, double bal, NumberFormat format) {
    return DataRow(color: WidgetStateProperty.all(Colors.grey[100]), cells: [
      const DataCell(Text("")), const DataCell(Text("TOTAL", style: TextStyle(fontWeight: FontWeight.bold))),
      ...List.generate(4, (_) => const DataCell(Text(""))),
      DataCell(Text(format.format(paid), style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold))),
      DataCell(Text(format.format(bal), style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold))),
      ...List.generate(5, (_) => const DataCell(Text(""))),
    ]);
  }

  List<DataColumn> _buildTableColumns() {
    return const [
      DataColumn(label: Text("K.NO")),
      DataColumn(label: Text("NAME")),
      DataColumn(label: Text("PHONE")),
      DataColumn(label: Text("PLACE")),
      DataColumn(label: Text("MONTHLY")),
      DataColumn(label: Text("INST")),
      DataColumn(label: Text("PAID")),
      DataColumn(label: Text("BAL")),
      DataColumn(label: Text("STATUS")),
      DataColumn(label: Text("DATE")),
      DataColumn(label: Text("MODE")),
      DataColumn(label: Text("COLLECTOR")),
      DataColumn(label: Text("ENTRY")), // 13th Column
    ];
  }




  // Future<void> _showAddMember() async {
  //   final bool? saved = await showDialog<bool>(
  //     context: context,
  //     builder: (context) => SelectFromMasterDialog(
  //       schemeId: widget.schemeId,
  //       schemeName: (widget.schemeData['schemeName'] ?? "Scheme").toString(),
  //       userId: widget.userId,
  //       userName: widget.userName,
  //       // Ensure these use fallbacks to empty strings to avoid Null crashes
  //       kuriId: widget.kuriId,
  //       kuriName: (widget.kuriData["name"] ?? "").toString(),
  //     ),
  //   );
  //   if (saved == true) _fetchMembers(isInitial: true);
  // }
}




