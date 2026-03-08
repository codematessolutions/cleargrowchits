import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
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
  // --- DATA & PAGINATION ---
  List<DocumentSnapshot> _allMembers = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  DocumentSnapshot? _lastDocument;
  final ScrollController _verticalScroll = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  // --- FILTERS ---
  String searchQuery = "";
  String selectedStatus = "All";
  late DateTime selectedMonth;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    selectedMonth = DateTime(now.year, now.month);
    _fetchMembers(isInitial: true);

    _verticalScroll.addListener(() {
      if (_verticalScroll.position.pixels >= _verticalScroll.position.maxScrollExtent - 300) {
        if (!_isLoadingMore && _hasMore) _fetchMembers();
      }
    });
  }

  @override
  void dispose() {
    _verticalScroll.dispose();
    _searchController.dispose();
    super.dispose();
  }

  String get monthKey => DateFormat('yyyy_MM').format(selectedMonth);

  double _parseNum(dynamic val) =>
      val is num ? val.toDouble() : double.tryParse(val.toString()) ?? 0.0;

  // --- CORE FETCH LOGIC ---
  Future<void> _fetchMembers({bool isInitial = false}) async {
    if (isInitial) {
      setState(() {
        _isLoading = true;
        _allMembers = []; // Clear existing list for fresh fetch
        _lastDocument = null;
        _hasMore = true;
      });
    }

    // Prevent redundant calls
    if (!_hasMore || (_isLoadingMore && !isInitial)) return;
    if (!isInitial) setState(() => _isLoadingMore = true);

    try {
      // Base Query: Filter by the entire Kuri
      Query query = FirebaseFirestore.instance
          .collection('members')
          .where('kuriId', isEqualTo: widget.kuriId);

      if (searchQuery.isNotEmpty) {
        final searchNum = int.tryParse(searchQuery);
        if (searchNum != null) {
          // 1. Search by Unique Kuri Number (Direct match)
          query = query.where('kuriNumber', isEqualTo: searchNum);
        } else {
          // 2. Search by Name (Range filter)
          String searchUpper = searchQuery.toUpperCase();
          query = query
              .where('name', isGreaterThanOrEqualTo: searchUpper)
              .where('name', isLessThanOrEqualTo: '$searchUpper\uf8ff')
              .orderBy('name');
        }
      } else {
        // 3. Default View: Order by the unique Kuri-wide Number
        query = query.orderBy('kuriNumber', descending: false);
      }

      const int fetchLimit = 20;
      query = query.limit(fetchLimit);

      // Pagination logic
      if (_lastDocument != null && !isInitial) {
        query = query.startAfterDocument(_lastDocument!);
      }

      final snap = await query.get();

      if (mounted) {
        setState(() {
          // If it's a new search or refresh, replace the list; otherwise, append
          if (isInitial) {
            _allMembers = snap.docs;
          } else {
            _allMembers.addAll(snap.docs);
          }

          _hasMore = snap.docs.length == fetchLimit;
          if (snap.docs.isNotEmpty) _lastDocument = snap.docs.last;

          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      debugPrint("Firestore Error: $e");
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isLoadingMore = false;
          _hasMore = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: SchemeTheme.primaryBlue,
        foregroundColor: Colors.white,
        title: Text(widget.kuriName.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_rounded),
            onPressed: _generateMonthlyPDF, // <--- Add this
            tooltip: "Generate Monthly Report",
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: Column(
        children: [
          _buildDetailRibbon(),
          _buildFilterBar(),
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
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('members').where('kuriId', isEqualTo: widget.kuriId).snapshots(),
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
                        _compactItem("MONTHLY", currencyFormat.format(_parseNum(kuriData['monthlyAmount']))),
                        _vDivider(),
                        _compactItem("COLLECTION", "$paidMembers/$totalMembers PAID", isSpecial: true),
                        _vDivider(),
                        _compactItem("DRAW DATE", kuriData['kuriDate']?.toString() ?? "15"),
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
                hintStyle: const TextStyle(fontSize: 13, color: Colors.black54),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                prefixIcon: const SizedBox(width: 48),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search, color: SchemeTheme.primaryBlue, size: 20),
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
          VerticalDivider(color: Colors.grey.shade200, indent: 10, endIndent: 10, thickness: 1),
          Expanded(
              flex: 2,
              child: _buildCompactBox(
                  label: "Status",
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                        value: selectedStatus, isExpanded: true,
                        icon: Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: Colors.grey.shade500),
                        style: const TextStyle(fontSize: 13, color: Colors.black87, fontWeight: FontWeight.w500),
                        items: ["All", "Paid", "Pending"].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                        onChanged: (v) {
                          setState(() {
                            selectedStatus = v!;
                            if (_verticalScroll.hasClients) _verticalScroll.jumpTo(0);
                          });
                          _fetchMembers(isInitial: true);
                        }
                    ),
                  )
              )
          ),
          IconButton(
              onPressed: () {
                _searchController.clear();
                setState(() { selectedStatus = "All"; searchQuery = ""; });
                _fetchMembers(isInitial: true);
              },
              icon: const Icon(Icons.refresh, size: 18, color: Colors.grey)
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
      height: 70, margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: Colors.grey.shade200))),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: allMonths.length,
        itemBuilder: (context, index) {
          DateTime m = allMonths[index];
          bool isSelected = m.year == selectedMonth.year && m.month == selectedMonth.month;
          return Padding(
            padding: const EdgeInsets.only(right: 12),
            child: InkWell(
              onTap: () => setState(() => selectedMonth = m),
              borderRadius: BorderRadius.circular(12),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250), width: 100,
                decoration: BoxDecoration(
                  color: isSelected ? SchemeTheme.primaryBlue : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: isSelected ? SchemeTheme.primaryBlue : Colors.grey.shade200, width: 1.5),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(DateFormat('MMM').format(m).toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isSelected ? Colors.white70 : Colors.blueGrey.shade400)),
                    Text(DateFormat('yyyy').format(m), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: isSelected ? Colors.white : Colors.blueGrey.shade900)),
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
      stream: FirebaseFirestore.instance.collection('schemes').where('kuriId', isEqualTo: widget.kuriId).snapshots(),
      builder: (context, sSnap) {
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('payments').where('kuriId', isEqualTo: widget.kuriId).snapshots(),
          builder: (context, pSnap) {
            final schemesMap = {for (var doc in (sSnap.data?.docs ?? [])) doc.id: doc.data() as Map<String, dynamic>};
            final allPayments = pSnap.data?.docs ?? [];

            Map<String, Map<String, dynamic>> currentMonthPaidMap = {
              for (var doc in allPayments.where((p) => p['monthKey'] == monthKey))
                doc['memberId'].toString(): doc.data() as Map<String, dynamic>
            };

            List<DocumentSnapshot> filteredMembers = _allMembers.where((mDoc) {
              final d = mDoc.data() as Map<String, dynamic>;
              if (searchQuery.isNotEmpty) {
                String name = d['name'].toString().toLowerCase();
                String kuri = d['kuriNumber'].toString();
                String target = searchQuery.toLowerCase();
                if (!name.contains(target) && kuri != target) return false;
              }
              final isPaid = currentMonthPaidMap.containsKey(mDoc.id);
              if (selectedStatus == "Paid" && !isPaid) return false;
              if (selectedStatus == "Pending" && isPaid) return false;
              return true;
            }).toList();

            double grandTotalPaid = 0;
            double grandTotalBalance = 0;

            List<DataRow> rows = filteredMembers.map((m) {
              final mid = m.id;
              final d = m.data() as Map<String, dynamic>;
              final schemeId = d['schemeId']?.toString() ?? '';
              final scheme = schemesMap[schemeId] ?? {};
              final String remark = (d['remark'] ?? "").toString();

              final isPaid = currentMonthPaidMap.containsKey(mid);
              final pMonth = isPaid ? currentMonthPaidMap[mid] : null;

              List<dynamic> splits = isPaid ? (pMonth!['paymentSplits'] as List? ?? []) : [];

              final Map<String, dynamic> schemeWinners = scheme['winners'] != null
                  ? Map<String, dynamic>.from(scheme['winners'] as Map)
                  : {};
              String? wonMonthKey;
              schemeWinners.forEach((key, value) { if (value.toString() == mid) wonMonthKey = key.toString(); });
              bool isCurrentMonthWinner = wonMonthKey == monthKey;
              bool hasWonInPast = false;
              String winnerSubtitle = "";
              if (wonMonthKey != null) {
                try {
                  DateTime winDate = DateFormat('yyyy_MM').parse(wonMonthKey!);
                  if (!isCurrentMonthWinner && winDate.isBefore(selectedMonth)) hasWonInPast = true;
                  DateTime start = (scheme['startMonth'] is Timestamp) ? (scheme['startMonth'] as Timestamp).toDate() : winDate;
                  int monthOrdinal = (((winDate.year - start.year) * 12) + winDate.month - start.month) + 1;
                  winnerSubtitle = "$monthOrdinal Month Winner - ${DateFormat('MMM yyyy').format(winDate)}";
                } catch (e) { winnerSubtitle = "Winner"; }
              }

              double monthlyAmount = _parseNum(scheme['monthlyAmount']);
              final int totalInstCountFromDb = int.tryParse(scheme['totalMonths']?.toString() ?? '0') ?? 0;
              int expectedInst = totalInstCountFromDb;
              if (wonMonthKey != null) {
                DateTime start = (scheme['startMonth'] is Timestamp) ? (scheme['startMonth'] as Timestamp).toDate() : DateTime.now();
                List<String> keys = List.generate(totalInstCountFromDb, (i) => DateFormat('yyyy_MM').format(DateTime(start.year, start.month + i)));
                int winIdx = keys.indexOf(wonMonthKey!);
                expectedInst = (winIdx != -1) ? (winIdx + 1) : totalInstCountFromDb;
              }

              final mPayments = allPayments.where((p) => p['memberId'] == mid);
              double totalPaid = mPayments.fold(0.0, (sum, p) => sum + _parseNum(p['amount']));
              double balance = (monthlyAmount * expectedInst) - totalPaid;
              if (balance < 0) balance = 0;
              grandTotalPaid += totalPaid;
              grandTotalBalance += balance;

              Color statusBgColor = const Color(0xFFFEE2E2);
              String statusLabel = "PENDING";
              if (hasWonInPast) { statusBgColor = const Color(0xFFEFF6FF); statusLabel = "WON"; }
              else if (isCurrentMonthWinner) { statusBgColor = Colors.amber.shade100; statusLabel = "WINNER"; }
              else if (isPaid && pMonth?['paidAt'] != null) {
                DateTime pDate = (pMonth!['paidDate'] as Timestamp).toDate();
                DateTime schemeStartDate = (scheme['startMonth'] is Timestamp) ? (scheme['startMonth'] as Timestamp).toDate() : DateTime.now();
                int drawDay = int.tryParse(widget.kuriData['kuriDate']?.toString() ?? '') ?? 0;
                int lastPayDay = drawDay > 2 ? (drawDay - 2) : 1;
                DateTime deadline = DateTime(selectedMonth.year, selectedMonth.month, lastPayDay, 23, 59, 59);
                if (pDate.isBefore(schemeStartDate)) { statusBgColor = const Color(0xFFECD907); statusLabel = "Advance"; }
                else if (pDate.isBefore(deadline.add(const Duration(seconds: 1)))) { statusBgColor = const Color(0xFF54EA89); statusLabel = "On-Time"; }
                else { statusBgColor = const Color(0xFFFB923C); statusLabel = "Late"; }
              }

              return DataRow(
                color: isCurrentMonthWinner ? WidgetStateProperty.all(Colors.amber.shade50) : null,
                cells: [
                  DataCell(Text(d['kuriNumber']?.toString() ?? "-", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold))),
                  DataCell(SizedBox(width: 240, child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(children: [
                        if (wonMonthKey != null) Icon(Icons.stars, color: isCurrentMonthWinner ? Colors.orange : Colors.blue, size: 14),
                        const SizedBox(width: 4),
                        Expanded(child: Text(d['name'].toString().toUpperCase(),
                            style: TextStyle(fontSize: 13, color: hasWonInPast ? Colors.blue.shade900 : Colors.black, fontWeight: FontWeight.bold))),
                      ]),
                      if (remark.isNotEmpty)
                        Text("NOTE: $remark", style: const TextStyle(fontSize: 10, color: Colors.blue, fontWeight: FontWeight.bold)),
                      if (wonMonthKey != null)
                        Text(winnerSubtitle, style: const TextStyle(fontSize: 10, color: Colors.blue, fontWeight: FontWeight.w600)),
                    ],
                  ))),
                  DataCell(Text(d['phone'] ?? "-", style: const TextStyle(fontSize: 13))),
                  DataCell(Text(scheme['schemeName']?.toString().toUpperCase() ?? "N/A", style: const TextStyle(fontSize: 12))),
                  DataCell(Text(currencyFormat.format(monthlyAmount), style: const TextStyle(fontSize: 13))),
                  DataCell(Text("${mPayments.length}/$expectedInst", style: const TextStyle(fontSize: 13))),
                  DataCell(Text(currencyFormat.format(totalPaid), style: const TextStyle(fontSize: 13, color: Colors.green, fontWeight: FontWeight.bold))),
                  DataCell(Text(currencyFormat.format(balance), style: const TextStyle(fontSize: 13, color: Colors.red, fontWeight: FontWeight.bold))),
                  DataCell(Container(
                    width: double.infinity, height: double.infinity, alignment: Alignment.center,
                    color: statusBgColor,
                    child: (isPaid || hasWonInPast || isCurrentMonthWinner)
                        ? Text(statusLabel.toUpperCase(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))
                        : _buildPayButton(mid, d['name'], monthlyAmount, schemeId),
                  )),
                  DataCell(Text(isPaid && pMonth?['paidDate'] != null ? DateFormat('dd-MM-yy').format((pMonth!['paidDate'] as Timestamp).toDate()) : "-", style: const TextStyle(fontSize: 12))),

                  DataCell(isPaid
                      ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: splits.isNotEmpty
                        ? splits.map((s) => Text("${currencyFormat.format(_parseNum(s['amount']))} (${s['mode']})", style: const TextStyle(fontSize: 11))).toList()
                        : [Text(pMonth?['mode'] ?? "Cash", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500))],
                  )
                      : const Text("-", style: TextStyle(fontSize: 12))),

                  DataCell(isPaid
                      ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: splits.isNotEmpty
                        ? splits.map((s) => Text(s['collectorName']?.toString() ?? "-", style: const TextStyle(fontSize: 11))).toList()
                        : [Text(pMonth?['collectedBy'] ?? "-", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500))],
                  )
                      : const Text("-", style: TextStyle(fontSize: 12))),

                  DataCell(isPaid
                      ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text((pMonth?['addedByName'] ?? "-").toString().toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      if (pMonth?['paidAt'] != null)
                        Text(DateFormat('dd-MMM hh:mm a').format((pMonth!['paidAt'] as Timestamp).toDate()),
                            style: const TextStyle(fontSize: 10, color: Colors.black87, fontWeight: FontWeight.w500)),
                    ],
                  )
                      : const Text("-", style: TextStyle(fontSize: 12))),
                ],
              );
            }).toList();

            return Expanded(child: Column(children: [
              Expanded(child: Scrollbar(
                  controller: _verticalScroll,
                  child: SingleChildScrollView(
                      controller: _verticalScroll,
                      child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                              headingRowHeight: 30,
                              dataRowMaxHeight: 49, // Increased to fit larger text
                              columnSpacing: 50,    // Increased for horizontal breathing room
                              horizontalMargin: 10,
                              headingRowColor: WidgetStateProperty.all(Colors.grey.shade200),
                              border: TableBorder.all(color: Colors.grey.shade300, width: 0.5),
                              columns: const [
                                DataColumn(label: Text("K.NO", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold))),
                                DataColumn(label: Text("NAME", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold))),
                                DataColumn(label: Text("PHONE", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold))),
                                DataColumn(label: Text("SCHEME", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold))),
                                DataColumn(label: Text("MONTHLY", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold))),
                                DataColumn(label: Text("INST", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold))),
                                DataColumn(label: Text("PAID", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold))),
                                DataColumn(label: Text("BAL", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold))),
                                DataColumn(label: Text("STATUS", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold))),
                                DataColumn(label: Text("DATE", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold))),
                                DataColumn(label: Text("MODE", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold))),
                                DataColumn(label: Text("COLLECTOR", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold))),
                                DataColumn(label: Text("ENTRY", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold))),
                              ],
                              rows: rows
                          )
                      )
                  )
              ))
            ]));
          },
        );
      },
    );
  }

  // --- UPDATED WINNER ACTION ---

  void _confirmWinner(String memberId, String name, bool isPaid, String schemeId, Map<String, dynamic> schemeData) {
    // 1. Eligibility Check
    if (!isPaid) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Member must pay first to be eligible."), backgroundColor: Colors.red)
      );
      return;
    }

    // 2. Draw Date Check
    int drawDay = int.tryParse(widget.kuriData['kuriDate']?.toString() ?? "0") ?? 0;
    DateTime now = DateTime.now();
    if (selectedMonth.year == now.year && selectedMonth.month == now.month) {
      if (now.day < drawDay) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Draw date is Day $drawDay. Cannot mark winner yet."), backgroundColor: Colors.orange)
        );
        return;
      }
    }

    // Check if a winner already exists for this month to show a "Replace" warning
    final schemeWinners = schemeData['winners'] as Map<String, dynamic>? ?? {};
    bool exists = schemeWinners.containsKey(monthKey);
    String existingWinnerId = schemeWinners[monthKey] ?? "";

    // Prevent selecting the same person twice
    if (exists && existingWinnerId == memberId) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("This member is already the winner for this month."))
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 500,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20, offset: const Offset(0, 10))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 140,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: exists ? Colors.red.shade50 : Colors.orange.shade50,
                  borderRadius: const BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
                ),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(color: exists ? Colors.red.shade100 : Colors.orange.shade100, shape: BoxShape.circle),
                    child: Icon(exists ? Icons.published_with_changes_rounded : Icons.emoji_events_rounded,
                        size: 60, color: exists ? Colors.red.shade800 : Colors.orange.shade800),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 24, 32, 32),
                child: Column(
                  children: [
                    Text(exists ? "REPLACE MONTHLY WINNER" : "CONFIRM MONTHLY WINNER",
                        style: TextStyle(letterSpacing: 1.2, fontSize: 12, fontWeight: FontWeight.bold, color: exists ? Colors.red : Colors.orange)),
                    const SizedBox(height: 16),
                    Text(name.toUpperCase(),
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A))),
                    const SizedBox(height: 8),
                    Text("Month: ${DateFormat('MMMM yyyy').format(selectedMonth)}",
                        style: TextStyle(fontSize: 16, color: Colors.grey.shade600)),
                    if (exists) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(12)),
                        child: const Text(
                          "Note: A winner is already assigned for this month. Confirming will replace them with this member.",
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.w600),
                        ),
                      )
                    ]
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(24), bottomRight: Radius.circular(24)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 20)),
                        onPressed: () => Navigator.pop(context),
                        child: const Text("CANCEL", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: exists ? Colors.red.shade800 : Colors.orange.shade800,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () async {
                          try {
                            final batch = FirebaseFirestore.instance.batch();
                            final schemeRef = FirebaseFirestore.instance.collection('schemes').doc(schemeId);
                            final winnerDocId = "${schemeId}_$monthKey";
                            final winnerRef = FirebaseFirestore.instance.collection('winners').doc(winnerDocId);
                            final logRef = FirebaseFirestore.instance.collection('winner_logs').doc();

                            Map<String, dynamic> winnerData = {
                              'schemeId': schemeId,
                              'schemeName': schemeData['schemeName'] ?? 'Unknown',
                              'monthKey': monthKey,
                              'memberId': memberId,
                              'memberName': name,
                              'updatedAt': FieldValue.serverTimestamp(),
                              'updatedBy': widget.userName,
                              'previousWinnerId': existingWinnerId, // Track the change
                            };

                            // Overwrites existing month key in the map
                            batch.update(schemeRef, {'winners.$monthKey': memberId});
                            // Overwrites the winner document for this scheme/month
                            batch.set(winnerRef, winnerData);
                            // Creates a new log entry
                            batch.set(logRef, { ...winnerData, 'action': exists ? 'REPLACED' : 'ASSIGNED' });

                            await batch.commit();

                            if (context.mounted) Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(exists ? "Winner Replaced!" : "Winner Assigned!"))
                            );
                          } catch (e) {
                            debugPrint("Winner Error: $e");
                          }
                        },
                        child: Text(exists ? "CONFIRM REPLACE" : "CONFIRM WINNER", style: const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- HELPERS ---

  Widget _buildCompactBox({required String label, required Widget child}) => Row(mainAxisSize: MainAxisSize.min, children: [
    Text("$label:", style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontWeight: FontWeight.bold)),
    const SizedBox(width: 4), Expanded(child: child)
  ]);

  Widget _vDivider() => Container(margin: const EdgeInsets.symmetric(horizontal: 4), height: 20, width: 1, color: Colors.white24);

  Widget _compactItem(String label, String value, {bool isTitle = false, bool isSpecial = false}) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 10),
    child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: Colors.white60, fontSize: 7, fontWeight: FontWeight.bold)),
      Text(value, style: TextStyle(color: isSpecial ? Colors.greenAccent : Colors.white, fontSize: isTitle ? 11 : 10, fontWeight: FontWeight.bold)),
    ]),
  );

  Widget _buildPayButton(String id, String name, double amt, String sid) => ElevatedButton(onPressed: () {},
      style: ElevatedButton.styleFrom(backgroundColor: Colors.red, minimumSize: const Size(40, 35)), child: const Text("PENDING", style: TextStyle(fontSize: 8, color: Colors.white)));





  Future<void> _generateMonthlyPDF() async {
    final pdf = pw.Document();
    final currencyFormat = NumberFormat.currency(locale: 'en_IN', symbol: 'Rs.', decimalDigits: 0);
    final dateStr = DateFormat('MMMM yyyy').format(selectedMonth);

    // 1. Fetch Data
    final schemesSnap = await FirebaseFirestore.instance.collection('schemes').where('kuriId', isEqualTo: widget.kuriId).get();
    final schemesMap = {for (var doc in schemesSnap.docs) doc.id: doc.data() as Map<String, dynamic>};
    final paymentsSnap = await FirebaseFirestore.instance.collection('payments').where('kuriId', isEqualTo: widget.kuriId).get();
    final allPayments = paymentsSnap.docs;

    Map<String, Map<String, dynamic>> currentMonthPaidMap = {
      for (var doc in allPayments.where((p) => p['monthKey'] == monthKey))
        doc['memberId'].toString(): doc.data() as Map<String, dynamic>
    };

    double totalReceivedThisMonth = 0;
    int paidCount = 0;
    int pendingCount = 0;

    // 2. Map Member Data to Table Rows
    final tableData = _allMembers.map((m) {
      final mid = m.id;
      final d = m.data() as Map<String, dynamic>;
      final schemeId = d['schemeId']?.toString() ?? '';
      final scheme = schemesMap[schemeId] ?? {};
      final pMonth = currentMonthPaidMap[mid];
      final isPaid = pMonth != null;

      if (isPaid) {
        paidCount++;
        totalReceivedThisMonth += _parseNum(pMonth['amount']);
      } else {
        pendingCount++;
      }

      final Map<String, dynamic> schemeWinners = scheme['winners'] != null
          ? Map<String, dynamic>.from(scheme['winners'] as Map)
          : {};

      String? wonMonthKey;
      schemeWinners.forEach((k, v) { if (v.toString() == mid) wonMonthKey = k.toString(); });

      bool isCurrentMonthWinner = wonMonthKey == monthKey;
      bool hasWonInPast = false;
      if (wonMonthKey != null && !isCurrentMonthWinner) {
        try {
          DateTime winDate = DateFormat('yyyy_MM').parse(wonMonthKey!);
          if (winDate.isBefore(selectedMonth)) hasWonInPast = true;
        } catch (e) { hasWonInPast = true; }
      }

      double mAmount = _parseNum(scheme['monthlyAmount']);
      int totalMonths = int.tryParse(scheme['totalMonths']?.toString() ?? '0') ?? 0;

      int expectedInst = totalMonths;
      String winnerFullLabel = "";

      if (wonMonthKey != null) {
        DateTime start = (scheme['startMonth'] is Timestamp) ? (scheme['startMonth'] as Timestamp).toDate() : DateTime.now();
        List<String> keys = List.generate(totalMonths, (i) => DateFormat('yyyy_MM').format(DateTime(start.year, start.month + i)));
        int winIdx = keys.indexOf(wonMonthKey!);
        expectedInst = (winIdx != -1) ? (winIdx + 1) : totalMonths;

        // Format Month & Year from wonMonthKey
        DateTime winDateObj = DateFormat('yyyy_MM').parse(wonMonthKey!);
        String winMonthYear = DateFormat('MMMM yyyy').format(winDateObj);

        // Suffix Logic (st, nd, rd, th)
        String suffix = "th";
        int digit = expectedInst % 10;
        int lastTwo = expectedInst % 100;
        if (digit == 1 && lastTwo != 11) suffix = "st";
        else if (digit == 2 && lastTwo != 12) suffix = "nd";
        else if (digit == 3 && lastTwo != 13) suffix = "rd";

        winnerFullLabel = "$expectedInst$suffix Month Winner - $winMonthYear";
      }

      final mPayments = allPayments.where((p) => p['memberId'] == mid);
      double totalPaid = mPayments.fold(0.0, (sum, p) => sum + _parseNum(p['amount']));
      double balance = (mAmount * expectedInst) - totalPaid;

      // --- STATUS & DETAILS LOGIC ---
      String status = "PENDING";
      String details = "-";

      if (wonMonthKey != null) {
        details = winnerFullLabel;
        if (hasWonInPast) {
          status = "WON";
        } else if (isCurrentMonthWinner) {
          status = "WINNER";
        }
      } else if (isPaid && pMonth['paidDate'] != null) {
        DateTime pDate = (pMonth['paidDate'] as Timestamp).toDate();
        details = "${DateFormat('dd/MM').format(pDate)}\n${pMonth['collectedBy'] ?? ''}\n${pMonth['mode'] ?? ''}";

        int drawDay = int.tryParse(widget.kuriData['kuriDate']?.toString() ?? '') ?? 0;
        int lastPayDay = drawDay > 2 ? (drawDay - 2) : 1;
        DateTime boundary = DateTime(selectedMonth.year, selectedMonth.month, lastPayDay, 23, 59);

        if (pDate.isBefore(DateTime(selectedMonth.year, selectedMonth.month, 1))) status = "Advance";
        else if (drawDay != 0 && pDate.isBefore(boundary)) status = "On-Time";
        else status = "Late";
      }

      return [
        d['kuriNumber']?.toString() ?? "-",
        d['name'].toString().toUpperCase(),
        d['phone'] ?? "-",
        scheme['schemeName']?.toString().toUpperCase() ?? "N/A",
        currencyFormat.format(mAmount),
        status.toUpperCase(),
        details,
        currencyFormat.format(totalPaid),
        currencyFormat.format(balance < 0 ? 0 : balance),
      ];
    }).toList();

    // 3. Generate PDF Document
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.symmetric(horizontal: 30, vertical: 30),
        header: (context) => pw.Header(
          level: 0,
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(widget.kuriName.toUpperCase(), style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                  pw.Text("Monthly Collection Report", style: const pw.TextStyle(fontSize: 10)),
                ],
              ),
              pw.Text("Month: $dateStr", style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
            ],
          ),
        ),
        build: (context) => [
          pw.TableHelper.fromTextArray(
            headers: ['K.NO', 'NAME', 'PHONE', 'SCHEME', 'MONTHLY', 'STATUS', 'DETAILS', 'PAID', 'BALANCE'],
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8),
            cellStyle: const pw.TextStyle(fontSize: 8),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
            columnWidths: {
              0: const pw.FixedColumnWidth(25),
              1: const pw.FixedColumnWidth(90),
              2: const pw.FixedColumnWidth(70),
              3: const pw.FixedColumnWidth(70),
              4: const pw.FixedColumnWidth(60),
              5: const pw.FixedColumnWidth(60),
              6: const pw.FixedColumnWidth(120), // Increased width for the long winner label
              7: const pw.FixedColumnWidth(60),
              8: const pw.FixedColumnWidth(60),
            },
            data: tableData,
          ),
          pw.SizedBox(height: 20),
          _buildPdfSummary(currencyFormat, totalReceivedThisMonth, paidCount, pendingCount),
        ],
      ),
    );

    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save());
  }

// --- PDF HELPER WIDGETS ---

  pw.Widget _buildPdfSummary(NumberFormat currencyFormat, double totalReceived, int paid, int pending) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text("COLLECTION SUMMARY", style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
          pw.Divider(thickness: 0.5, color: PdfColors.grey400),
          pw.SizedBox(height: 5),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              _pdfSummaryItem("Total Members", _allMembers.length.toString()),
              _pdfSummaryItem("Paid Members", paid.toString()),
              _pdfSummaryItem("Pending Members", pending.toString()),
              _pdfSummaryItem("Collection (Month)", currencyFormat.format(totalReceived)),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _pdfSummaryItem(String label, String value) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(label, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
        pw.SizedBox(height: 2),
        pw.Text(value, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
      ],
    );
  }


}
