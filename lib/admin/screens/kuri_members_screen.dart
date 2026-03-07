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
    print("dddddd"+isInitial.toString());
    if (isInitial) {
      setState(() {
        _isLoading = true;
        _allMembers = [];
        _lastDocument = null;
        _hasMore = true;
      });
    }

    if (!_hasMore || (_isLoadingMore && !isInitial)) return;
    if (!isInitial) setState(() => _isLoadingMore = true);

    try {
      Query query = FirebaseFirestore.instance
          .collection('members')
          .where('kuriId', isEqualTo: widget.kuriId);

      if (searchQuery.isNotEmpty) {
        final searchNum = int.tryParse(searchQuery);
        if (searchNum != null) {
          query = query.where('kuriNumber', isEqualTo: searchNum)
              .orderBy('kuriNumber', descending: false);
        } else {
          String searchUpper = searchQuery.toUpperCase();
          query = query
              .where('name', isGreaterThanOrEqualTo: searchUpper)
              .where('name', isLessThanOrEqualTo: '$searchUpper\uf8ff')
              .orderBy('name');
        }
      } else {
        query = query.orderBy('kuriNumber', descending: false);
      }

      const int fetchLimit = 20;
      query = query.limit(fetchLimit);

      if (_lastDocument != null) {
        query = query.startAfterDocument(_lastDocument!);
      }

      final snap = await query.get();

      if (mounted) {
        setState(() {
          _allMembers.addAll(snap.docs);
          _hasMore = snap.docs.length == fetchLimit;
          if (snap.docs.isNotEmpty) _lastDocument = snap.docs.last;
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      debugPrint("Firestore Error: $e");
      if (mounted) setState(() { _isLoading = false; _isLoadingMore = false; });
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

            if (filteredMembers.length < 5 && _hasMore && !_isLoadingMore && (selectedStatus != "All" || searchQuery.isNotEmpty)) {
              WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _fetchMembers(); });
            }

            double grandTotalPaid = 0;
            double grandTotalBalance = 0;

            List<DataRow> rows = filteredMembers.map((m) {
              final mid = m.id;
              final d = m.data() as Map<String, dynamic>;
              final schemeId = d['schemeId']?.toString() ?? '';
              final scheme = schemesMap[schemeId] ?? {};
              final isPaid = currentMonthPaidMap.containsKey(mid);
              final pMonth = isPaid ? currentMonthPaidMap[mid] : null;

              // --- WINNER LOGIC ---
              final schemeWinners = scheme['winners'] as Map<String, dynamic>? ?? {};
              String? wonMonthKey;
              schemeWinners.forEach((key, value) { if (value == mid) wonMonthKey = key; });
              bool isCurrentMonthWinner = wonMonthKey == monthKey;
              bool hasWonInPast = false;
              if (wonMonthKey != null && !isCurrentMonthWinner) {
                try {
                  DateTime winDate = DateFormat('yyyy_MM').parse(wonMonthKey!);
                  if (winDate.isBefore(selectedMonth)) hasWonInPast = true;
                } catch (e) { hasWonInPast = true; }
              }

              // --- CALCULATIONS ---
              double monthlyAmount = _parseNum(scheme['monthlyAmount']);
              final int? totalInstCountFromDb = int.tryParse(scheme['totalMonths']?.toString() ?? '');
              int? expectedInst = wonMonthKey != null ? (schemeWinners.keys.toList().indexOf(wonMonthKey!) + 1) : totalInstCountFromDb;
              final mPayments = allPayments.where((p) => p['memberId'] == mid);
              double totalPaid = mPayments.fold(0.0, (sum, p) => sum + _parseNum(p['amount']));
              double balance = (expectedInst != null) ? (monthlyAmount * expectedInst) - totalPaid : 0;
              if (balance < 0) balance = 0;

              grandTotalPaid += totalPaid;
              grandTotalBalance += balance;

              // --- STRICT STATUS & COLOR LOGIC ---
              Color statusBgColor = const Color(0xFFFEE2E2); // Default: Pending (Light Red)
              String statusLabel = "PENDING";

              if (isPaid && pMonth?['paidDate'] != null) {
                DateTime pDate = (pMonth!['paidDate'] as Timestamp).toDate();

                // Get Draw Day strictly from DB
                int drawDay = int.tryParse(widget.kuriData['kuriDate']?.toString() ?? '') ?? 0;
                int lastPayDay = drawDay > 2 ? (drawDay - 2) : 1;

                DateTime monthStart = DateTime(selectedMonth.year, selectedMonth.month, 1);
                DateTime lastPayBoundary = DateTime(selectedMonth.year, selectedMonth.month, lastPayDay, 23, 59, 59);

                if (pDate.isBefore(monthStart)) {
                  statusBgColor = const Color(0xFFECD907); // Yellow
                  statusLabel = "Advance";
                } else if (drawDay != 0 && pDate.isBefore(lastPayBoundary.add(const Duration(seconds: 1)))) {
                  statusBgColor = const Color(0xFF54EA89);
                  statusLabel = "On-Time";
                } else {
                  statusBgColor =  const Color(0xFFFB923C); // Orange
                  statusLabel = "Late";
                }
              } else if (hasWonInPast) {
                statusBgColor = const Color(0xFFEFF6FF); // Blue
                statusLabel = "WON";
              }

              return DataRow(
                color: isCurrentMonthWinner ? WidgetStateProperty.all(Colors.amber.shade50) : null,
                cells: [
                  DataCell(Text(d['kuriNumber']?.toString() ?? "-")),
                  DataCell(SizedBox(width: 180, child: Row(children: [
                    if (wonMonthKey != null) Icon(Icons.stars, color: isCurrentMonthWinner ? Colors.orange : Colors.blue, size: 16),
                    Expanded(child: Text(d['name'].toString().toUpperCase(), style: TextStyle(fontSize: 11, color: hasWonInPast ? Colors.blue.shade900 : Colors.black, fontWeight: isCurrentMonthWinner ? FontWeight.bold : FontWeight.normal))),
                    IconButton(icon: Icon(wonMonthKey != null ? Icons.emoji_events : Icons.emoji_events_outlined, size: 16, color: wonMonthKey != null ? Colors.orange : Colors.grey), onPressed: hasWonInPast ? null : () => _confirmWinner(mid, d['name'], isPaid, schemeId, scheme))
                  ]))),
                  DataCell(Text(d['phone'] ?? "-")),
                  DataCell(Text(scheme['schemeName']?.toString().toUpperCase() ?? "N/A", style: const TextStyle(fontSize: 9))),
                  DataCell(Text(currencyFormat.format(monthlyAmount))),
                  DataCell(Text("${mPayments.length} / ${totalInstCountFromDb ?? '-'}")),
                  DataCell(Text(currencyFormat.format(totalPaid), style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold))),
                  DataCell(Text(currencyFormat.format(balance), style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold))),
                  DataCell(Container(
                    width: double.infinity,
                    height: double.infinity,
                    alignment: Alignment.center,
                    color: statusBgColor,
                    child: isPaid || hasWonInPast
                        ? Text(statusLabel.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold))
                        : _buildPayButton(mid, d['name'], monthlyAmount, schemeId),
                  )),
                  DataCell(Text(isPaid && pMonth?['paidDate'] != null ? DateFormat('dd-MM-yy').format((pMonth!['paidDate'] as Timestamp).toDate()) : "-")),
                  DataCell(Text(isPaid ? (pMonth?['mode'] ?? "Cash") : "-")),
                  DataCell(Text(isPaid ? (pMonth?['collectedBy'] ?? "-") : "-")),
                  DataCell(Text(isPaid ? (pMonth?['addedByName'] ?? "-") : "-")),
                ],
              );
            }).toList();

            if (rows.isNotEmpty) {
              rows.add(DataRow(color: WidgetStateProperty.all(Colors.grey[100]), cells: [
                const DataCell(Text("")), const DataCell(Text("GRAND TOTAL", style: TextStyle(fontWeight: FontWeight.bold))),
                const DataCell(Text("")), const DataCell(Text("")), const DataCell(Text("")), const DataCell(Text("")),
                DataCell(Text(currencyFormat.format(grandTotalPaid), style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold))),
                DataCell(Text(currencyFormat.format(grandTotalBalance), style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold))),
                const DataCell(Text("")), const DataCell(Text("")), const DataCell(Text("")), const DataCell(Text("")), const DataCell(Text("")),
              ]));
            }

            return Expanded(child: Column(children: [
              Expanded(child: Scrollbar(controller: _verticalScroll, child: SingleChildScrollView(controller: _verticalScroll, child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: DataTable(headingRowHeight: 45, dataRowMaxHeight: 60, headingRowColor: WidgetStateProperty.all(Colors.grey.shade200), border: TableBorder.all(color: Colors.grey.shade300, width: 0.5), columns: const [
                DataColumn(label: Text("K.NO")), DataColumn(label: Text("NAME / WINNER")), DataColumn(label: Text("PHONE")),
                DataColumn(label: Text("SCHEME")), DataColumn(label: Text("MONTHLY")), DataColumn(label: Text("INST")),
                DataColumn(label: Text("PAID")), DataColumn(label: Text("BAL")), DataColumn(label: Text("STATUS")),
                DataColumn(label: Text("DATE")), DataColumn(label: Text("MODE")), DataColumn(label: Text("COLLECTOR")), DataColumn(label: Text("ENTRY")),
              ], rows: rows))))),
              if (_isLoadingMore) const LinearProgressIndicator(),
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
    final schemesMap = {for (var doc in schemesSnap.docs) doc.id: doc.data()};
    final paymentsSnap = await FirebaseFirestore.instance.collection('payments').where('kuriId', isEqualTo: widget.kuriId).get();
    final allPayments = paymentsSnap.docs;

    Map<String, Map<String, dynamic>> currentMonthPaidMap = {
      for (var doc in allPayments.where((p) => p['monthKey'] == monthKey))
        doc['memberId'].toString(): doc.data()
    };

    // Summary variables
    double totalReceivedThisMonth = 0;
    int paidCount = 0;
    int pendingCount = 0;

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

      double mAmount = _parseNum(scheme['monthlyAmount']);
      final mPayments = allPayments.where((p) => p['memberId'] == mid);
      double totalPaid = mPayments.fold(0.0, (sum, p) => sum + _parseNum(p['amount']));

      final schemeWinners = scheme['winners'] as Map<String, dynamic>? ?? {};
      String? wonMonthKey;
      schemeWinners.forEach((k, v) { if (v == mid) wonMonthKey = k; });
      int totalMonths = int.tryParse(scheme['totalMonths']?.toString() ?? '0') ?? 0;
      int expectedInst = wonMonthKey != null ? (schemeWinners.keys.toList().indexOf(wonMonthKey!) + 1) : totalMonths;
      double balance = (mAmount * expectedInst) - totalPaid;

      String status = "PENDING";
      String details = "-";

      if (isPaid && pMonth['paidDate'] != null) {
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

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.symmetric(horizontal: 40, vertical: 30), // Increased horizontal margin reduces table width
        header: (context) => pw.Header(
          level: 0,
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(widget.kuriName.toUpperCase(), style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
              pw.Text("Month: $dateStr", style: const pw.TextStyle(fontSize: 10)),
            ],
          ),
        ),
        build: (context) => [
          pw.TableHelper.fromTextArray(
            headers: ['K.NO', 'NAME', 'PHONE', 'SCHEME', 'MONTHLY', 'STATUS', 'DETAILS', 'PAID', 'BALANCE'],
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
            cellStyle: const pw.TextStyle(fontSize: 12),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
            // Reduced widths for a tighter look
            columnWidths: {
              0: const pw.FixedColumnWidth(25),
              1: const pw.FixedColumnWidth(80),
              2: const pw.FixedColumnWidth(80),
              3: const pw.FixedColumnWidth(80),
              4: const pw.FixedColumnWidth(80),
              5: const pw.FixedColumnWidth(80),
              6: const pw.FixedColumnWidth(80), // Details gets slightly more for the font
              7: const pw.FixedColumnWidth(80),
              8: const pw.FixedColumnWidth(80),
            },
            data: tableData,
          ),
          pw.SizedBox(height: 20),

          // --- SUMMARY SECTION ---
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey400),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text("COLLECTION SUMMARY", style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                pw.Divider(thickness: 0.5),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    _summaryItem("Total Members", _allMembers.length.toString()),
                    _summaryItem("Paid Members", paidCount.toString()),
                    _summaryItem("Pending Members", pendingCount.toString()),
                    _summaryItem("Current Month Collection", currencyFormat.format(totalReceivedThisMonth)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );

    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save());
  }

// Helper widget for summary items
  pw.Widget _summaryItem(String title, String value) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(title, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
        pw.Text(value, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
      ],
    );
  }}
