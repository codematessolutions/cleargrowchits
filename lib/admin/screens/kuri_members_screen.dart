import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

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

      // 1. Search Logic & Correct Ordering (Fixed Sort for Name Search)
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
              .orderBy('name'); // MUST sort by Name for range filter
        }
      } else {
        query = query.orderBy('kuriNumber', descending: false);
      }

      // 2. STRICT 20 LIMIT
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
        elevation: 0, backgroundColor: SchemeTheme.primaryBlue, foregroundColor: Colors.white,
        title: Text(widget.kuriName.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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

            // 1. IMPROVED FILTERING: Matches status and search local results
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

            // 2. RECURSIVE CHECK: If filtered list is too small but DB has more, fetch next batch
            if (filteredMembers.length < 5 && _hasMore && !_isLoadingMore && (selectedStatus != "All" || searchQuery.isNotEmpty)) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _fetchMembers();
              });
            }

            double grandTotalPaid = 0;
            double grandTotalBalance = 0;

            List<DataRow> rows = filteredMembers.map((m) {
              final d = m.data() as Map<String, dynamic>;
              final scheme = schemesMap[d['schemeId']] ?? {};
              final isPaid = currentMonthPaidMap.containsKey(m.id);
              final pMonth = isPaid ? currentMonthPaidMap[m.id] : null;

              // Winner logic
              final schemeWinners = scheme['winners'] as Map<String, dynamic>? ?? {};
              String? wonMonthKey;
              schemeWinners.forEach((key, value) { if (value == m.id) wonMonthKey = key; });
              bool isCurrentMonthWinner = wonMonthKey == monthKey;
              bool hasWonInPast = false;
              if (wonMonthKey != null && !isCurrentMonthWinner) {
                try {
                  DateTime winDate = DateFormat('yyyy_MM').parse(wonMonthKey!);
                  if (winDate.isBefore(selectedMonth)) hasWonInPast = true;
                } catch (e) { hasWonInPast = true; }
              }

              // Installment & Balance logic
              double monthlyAmount = _parseNum(scheme['monthlyAmount']);
              final int? totalInstCountFromDb = int.tryParse(scheme['totalMonths']?.toString() ?? '');
              int? expectedInst = wonMonthKey != null ? (schemeWinners.keys.toList().indexOf(wonMonthKey!) + 1) : totalInstCountFromDb;

              final mPayments = allPayments.where((p) => p['memberId'] == m.id);
              double totalPaid = mPayments.fold(0.0, (sum, p) => sum + _parseNum(p['amount']));
              double balance = (expectedInst != null) ? (monthlyAmount * expectedInst) - totalPaid : 0;
              if (balance < 0) balance = 0;

              grandTotalPaid += totalPaid;
              grandTotalBalance += balance;

              Color statusBgColor = isPaid ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2);
              if (hasWonInPast) statusBgColor = const Color(0xFFEFF6FF);

              return DataRow(
                color: isCurrentMonthWinner ? WidgetStateProperty.all(Colors.amber.shade50) : null,
                cells: [
                  DataCell(Text(d['kuriNumber']?.toString() ?? "-")),
                  DataCell(SizedBox(width: 180, child: Row(children: [
                    if (wonMonthKey != null) Icon(Icons.stars, color: isCurrentMonthWinner ? Colors.orange : Colors.blue, size: 16),
                    Expanded(child: Text(d['name'].toString().toUpperCase(), style: TextStyle(fontSize: 11, color: hasWonInPast ? Colors.blue.shade900 : Colors.black))),
                    IconButton(icon: Icon(wonMonthKey != null ? Icons.emoji_events : Icons.emoji_events_outlined, size: 16, color: wonMonthKey != null ? Colors.orange : Colors.grey),
                        onPressed: (schemeWinners.containsKey(monthKey) || hasWonInPast) ? null : () => _confirmWinner(d['schemeId'], m.id, d['name'], isPaid))
                  ]))),
                  DataCell(Text(d['phone'] ?? "-")),
                  DataCell(Text(scheme['schemeName']?.toString().toUpperCase() ?? "N/A", style: const TextStyle(fontSize: 9))),
                  DataCell(Text(currencyFormat.format(monthlyAmount))),
                  DataCell(Text("${mPayments.length} / ${expectedInst ?? '-'}")),
                  DataCell(Text(currencyFormat.format(totalPaid), style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold))),
                  DataCell(Text(currencyFormat.format(balance), style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold))),
                  DataCell(Container(width: double.infinity, height: double.infinity, alignment: Alignment.center, color: statusBgColor,
                      child: (hasWonInPast || isPaid) ? Text(isPaid ? "PAID" : "WON", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)) : _buildPayButton(m.id, d['name'], monthlyAmount, d['schemeId']))),
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
              Expanded(child: SingleChildScrollView(controller: _verticalScroll, child: SingleChildScrollView(scrollDirection: Axis.horizontal,
                  child: DataTable(headingRowHeight: 45, dataRowMaxHeight: 60, headingRowColor: WidgetStateProperty.all(Colors.grey.shade200),
                      border: TableBorder.all(color: Colors.grey.shade300, width: 0.5),
                      columns: const [
                        DataColumn(label: Text("K.NO")), DataColumn(label: Text("NAME / WINNER")), DataColumn(label: Text("PHONE")),
                        DataColumn(label: Text("SCHEME")), DataColumn(label: Text("MONTHLY")), DataColumn(label: Text("INST")),
                        DataColumn(label: Text("PAID")), DataColumn(label: Text("BAL")), DataColumn(label: Text("STATUS")),
                        DataColumn(label: Text("DATE")), DataColumn(label: Text("MODE")), DataColumn(label: Text("COLLECTOR")), DataColumn(label: Text("ENTRY")),
                      ], rows: rows)))),
              if (_isLoadingMore) const LinearProgressIndicator(),
              if (!_hasMore && filteredMembers.isEmpty)
                const Padding(padding: EdgeInsets.all(16), child: Text("No members matching your criteria found", style: TextStyle(color: Colors.grey))),
            ]));
          },
        );
      },
    );
  }

  // --- ACTIONS & HELPERS ---

  void _confirmWinner(String schemeId, String memberId, String name, bool isPaid) {
    if (!isPaid) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Member must pay this month first."), backgroundColor: Colors.red));
      return;
    }
    showDialog(context: context, builder: (context) => AlertDialog(
      title: const Text("Confirm Winner"),
      content: Text("Set $name as winner for ${DateFormat('MMM yyyy').format(selectedMonth)}?"),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCEL")),
        ElevatedButton(onPressed: () async {
          await FirebaseFirestore.instance.collection('schemes').doc(schemeId).update({'winners.$monthKey': memberId});
          Navigator.pop(context);
        }, child: const Text("CONFIRM"))
      ],
    ),
    );
  }

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


}