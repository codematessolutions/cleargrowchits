import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'dailogs/addmemberDailog.dart';

// --- THEME & STATUS COLORS ---
class SchemeTheme {
  static const Color primaryBlue = Color(0xFF1E3A8A);
  static const Color softBlueBg = Color(0xFFF1F5F9);
  static const Color headerGrey = Color(0xFFE2E8F0);
  static const Color colOdd = Color(0xFFF8FAFC);

  //
}

class SchemeDetailScreen extends StatefulWidget {
  final String schemeId;
  final String userId;
  final String userName;
  final String userRole;
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
  });

  @override
  State<SchemeDetailScreen> createState() => _SchemeDetailScreenState();
}

class _SchemeDetailScreenState extends State<SchemeDetailScreen> {
  // --- STATE DATA ---
  final TextEditingController _searchController = TextEditingController();
  String searchQuery = "";
  List<DocumentSnapshot> _allMembers = [];
  List<DocumentSnapshot> _allPayments = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  DocumentSnapshot? _lastDocument;

  Timer? _debounce;

  // --- SUBSCRIPTIONS ---
  StreamSubscription? _paymentSub;

  // --- FILTERS ---
  String selectedStatus = "All";
  String selectedMode = "All";
  String selectedCollector = "All";
  // String searchQuery = "";
  DateTime selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);

  final ScrollController _verticalScroll = ScrollController();

  String get monthKey => DateFormat('yyyy_MM').format(selectedMonth);
  double _parseNum(dynamic val) => val is num ? val.toDouble() : double.tryParse(val.toString()) ?? 0.0;

  @override
  void initState() {
    super.initState();
    _fetchMembers(isInitial: true);
    _initPaymentListener();

    // Infinite Scroll Listener
    _verticalScroll.addListener(() {
      if (_verticalScroll.position.pixels >= _verticalScroll.position.maxScrollExtent - 300) {
        _fetchMembers();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose(); // Add this
    _verticalScroll.dispose();
    _paymentSub?.cancel();
    super.dispose();
  }

  // --- PAGINATED DATA FETCH (20 + 20) ---
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
      Query query = FirebaseFirestore.instance.collection('members')
          .where('schemeId', isEqualTo: widget.schemeId);

      if (searchQuery.isNotEmpty) {
        final searchNum = int.tryParse(searchQuery);
        if (searchNum != null) {
          query = query.where('kuriNumber', isEqualTo: searchNum);
          query = query.orderBy('kuriNumber', descending: false);
        } else {
          // --- NAME SEARCH FIX ---
          String searchUpper = searchQuery.toUpperCase();
          query = query
              .where('name', isGreaterThanOrEqualTo: searchUpper)
              .where('name', isLessThanOrEqualTo: '$searchUpper\uf8ff')
              .orderBy('name'); // Must order by name for range filter
        }
      } else {
        query = query.orderBy('kuriNumber', descending: false);
      }

      query = query.limit(20);

      if (_lastDocument != null) {
        query = query.startAfterDocument(_lastDocument!);
      }

      final snap = await query.get();

      if (mounted) {
        setState(() {
          _allMembers.addAll(snap.docs);
          _hasMore = snap.docs.length == 20;
          if (snap.docs.isNotEmpty) _lastDocument = snap.docs.last;
          _isLoading = false;
          _isLoadingMore = false;
        });

        // This ensures if name search returns nothing in first 20, it keeps looking
        _checkIfNeedMoreData();
      }
    } catch (e) {
      debugPrint("Firestore Error: $e");
      if (mounted) setState(() { _isLoading = false; _isLoadingMore = false; });
    }
  }

  void _checkIfNeedMoreData() {
    // If we already finished the DB or we aren't filtering/searching, stop.
    if (!_hasMore) return;
    if (selectedStatus == "All" && searchQuery.isEmpty) return;

    final filteredDocs = _allMembers.where((mDoc) {
      final d = mDoc.data() as Map<String, dynamic>;

      // Local name check (secondary safety)
      if (searchQuery.isNotEmpty && !d['name'].toString().toUpperCase().contains(searchQuery.toUpperCase())) return false;

      // Local status check
      bool isPaid = _allPayments.any((p) => p['memberId'] == mDoc.id && p['monthKey'] == monthKey);
      if (selectedStatus == "Paid" && !isPaid) return false;
      if (selectedStatus == "Pending" && isPaid) return false;

      return true;
    }).toList();

    // If we found less than 5 people in the current 20, fetch next batch automatically
    if (filteredDocs.length < 5 && _hasMore) {
      _fetchMembers();
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

  // --- WITTY LOADER ---


  String _calculatePaymentStatus(DateTime paidDate) {
    // 1. Get Kuri Date strictly from DB (Remove hardcoded fallback)
    int kuriDay = int.tryParse(widget.kuriData['kuriDate']?.toString() ?? '') ?? 0;

    // 2. Define the "On-Time" deadline (Kuri Date - 2)
    // Ensure it doesn't drop below 1 if Kuri Date is very early
    int lastPayDay = kuriDay > 2 ? (kuriDay - 2) : 1;

    // 3. Define Boundaries for the Selected Month
    DateTime firstOfSelected = DateTime(selectedMonth.year, selectedMonth.month, 1);
    DateTime lastPayDeadline = DateTime(
        selectedMonth.year,
        selectedMonth.month,
        lastPayDay,
        23, 59, 59
    );

    // 4. Status Categorization
    if (paidDate.isBefore(firstOfSelected)) {
      return "Advance";
    }

    if (kuriDay != 0 && paidDate.isBefore(lastPayDeadline.add(const Duration(seconds: 1)))) {
      return "On-Time";
    }

    // If paid after (KuriDate - 2) or if KuriDate is missing in DB
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
          ? buildFunnyLoader()
          : Column(
        children: [
          _buildDetailRibbonFromState(),
          _buildFilterBar(),
          _buildMonthNavigator(),
          _buildMemberTable(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: SchemeTheme.primaryBlue,
        onPressed: () => _showAddMember(),
        child: const Icon(Icons.person_add, color: Colors.white),
      ),
    );
  }

  Widget _buildMemberTable() {
    final currencyFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
    final Map<String, List<DocumentSnapshot>> memberPaymentHistory = {};
    final Map<String, Map<String, dynamic>> currentMonthPaidMap = {};

    // 1. Organize payment data for lookup
    for (var p in _allPayments) {
      final pData = p.data() as Map<String, dynamic>;
      final mid = pData['memberId'].toString();
      memberPaymentHistory.putIfAbsent(mid, () => []).add(p);
      if (pData['monthKey'] == monthKey) currentMonthPaidMap[mid] = pData;
    }

    final monthlyAmount = _parseNum(widget.schemeData['monthlyAmount'] ?? 0);
    final int? totalInstCount = int.tryParse(widget.schemeData['totalMonths']?.toString() ?? '');
    final safeInstCount = totalInstCount ?? 0;
    final totalSchemeValue = monthlyAmount * safeInstCount;

    double grandTotalPaid = 0;
    double grandTotalBalance = 0;

    // 2. Filtering Logic
    final filteredDocs = _allMembers.where((mDoc) {
      final d = mDoc.data() as Map<String, dynamic>;
      if (searchQuery.isNotEmpty) {
        String name = d['name'].toString().toLowerCase();
        String kuri = d['kuriNumber'].toString();
        String target = searchQuery.toLowerCase();
        if (!name.contains(target) && kuri != target) return false;
      }
      final isPaid = currentMonthPaidMap.containsKey(mDoc.id);
      if (selectedStatus != "All") {
        if (selectedStatus == "Paid" && !isPaid) return false;
        if (selectedStatus == "Pending" && isPaid) return false;
      }
      return true;
    }).toList();

    // 3. Generate Table Rows
    final List<DataRow> tableRows = filteredDocs.map((m) {
      final mid = m.id;
      final d = m.data() as Map<String, dynamic>;
      final pMonth = currentMonthPaidMap[mid];
      final isPaid = pMonth != null;
      final mHistory = memberPaymentHistory[mid] ?? [];
      bool isMonthWinner = (widget.schemeData['winners'] != null && widget.schemeData['winners'][monthKey] == mid);

      // Calculations
      final totalPaid = mHistory.fold<double>(0.0, (sum, p) => sum + _parseNum(p['amount']));
      final balance = totalSchemeValue - totalPaid;
      grandTotalPaid += totalPaid;
      grandTotalBalance += balance;

      // --- UPDATED STRICT STATUS LOGIC ---
      Color statusBgColor = const Color(0xFFFEE2E2); // Default: Pending (Light Red)
      String statusLabel = "PENDING";

      if (isPaid && pMonth['paidDate'] != null) {
        DateTime pDate = (pMonth['paidDate'] as Timestamp).toDate();

        // Get Draw Day strictly from schemeData (Remove hardcoded fallback)
        int drawDay = int.tryParse(widget.schemeData['kuriDate']?.toString() ?? '') ?? 0;
        print(drawDay.toString()+"laaaaaaaaas");
        int lastPayDay = drawDay > 2 ? (drawDay - 2) : 1;

        DateTime monthStart = DateTime(selectedMonth.year, selectedMonth.month, 1);
        DateTime lastPayBoundary = DateTime(selectedMonth.year, selectedMonth.month, lastPayDay, 23, 59, 59);

        if (pDate.isBefore(monthStart)) {
          statusBgColor = const Color(0xFFECD907); // Yellow
          statusLabel = "Advance";
        } else if (drawDay != 0 && pDate.isBefore(lastPayBoundary.add(const Duration(seconds: 1)))) {
          statusBgColor = const Color(0xFF54EA89); // Light Green
          statusLabel = "On-Time";
        } else {
          statusBgColor = const Color(0xFFFB923C); // Orange
          statusLabel = "Late";
        }
      }

      return DataRow(
        color: isMonthWinner ? WidgetStateProperty.all(Colors.amber.shade50) : null,
        cells: [
          DataCell(Text(d['kuriNumber']?.toString() ?? "-")),
          DataCell(SizedBox(
            width: 200,
            child: Row(
              children: [
                if (isMonthWinner) const Icon(Icons.stars, color: Colors.orange, size: 18),
                Expanded(child: Text(d['name'].toString().toUpperCase(),
                    style: TextStyle(fontWeight: isMonthWinner ? FontWeight.bold : FontWeight.normal, fontSize: 12))),
                IconButton(
                  icon: Icon(isMonthWinner ? Icons.emoji_events : Icons.emoji_events_outlined,
                      size: 18, color: isMonthWinner ? Colors.orange : Colors.grey),
                  onPressed: () => _confirmWinner(mid, d['name'], isPaid),
                ),
              ],
            ),
          )),
          DataCell(Text(d['phone'] ?? "-")),
          DataCell(Text(d['place'] ?? "-")),
          DataCell(Text(currencyFormat.format(monthlyAmount))),
          DataCell(Text("${mHistory.length}/${totalInstCount ?? '-'}")),
          DataCell(Text(currencyFormat.format(totalPaid), style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold))),
          DataCell(Text(currencyFormat.format(balance), style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold))),
          DataCell(Container(
            width: double.infinity, height: double.infinity, alignment: Alignment.center, color: statusBgColor,
            child: isPaid
                ? Text(statusLabel.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold))
                : _buildPayButton(mid, d['name']),
          )),
          DataCell(Text(isPaid && pMonth['paidDate'] != null ? DateFormat('dd-MM-yy').format((pMonth['paidDate'] as Timestamp).toDate()) : "-")),
          DataCell(Text(isPaid ? (pMonth['mode'] ?? "Cash") : "-", style: const TextStyle(fontSize: 11))),
          DataCell(Text(isPaid ? (pMonth['collectedBy'] ?? "-") : "-", style: const TextStyle(fontSize: 11))),
          DataCell(_buildEntryInfoCell(isPaid, pMonth)),
        ],
      );
    }).toList();

    if (tableRows.isNotEmpty) {
      tableRows.add(_buildGrandTotalRow(grandTotalPaid, grandTotalBalance, currencyFormat));
    }

    return Expanded(
      child: Scrollbar(
        controller: _verticalScroll,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: _verticalScroll,
          child: Column(
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowHeight: 45,
                  dataRowMaxHeight: 55,
                  headingRowColor: WidgetStateProperty.all(Colors.grey.shade200),
                  columns: _buildTableColumns(),
                  rows: tableRows,
                ),
              ),
              if (_isLoadingMore) const Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
        ),
      ),
    );
  }

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
          _searchController.clear(); // Clear text field UI
          setState(() {
            selectedStatus = "All";
            selectedMode = "All";
            searchQuery = "";
          });
          _fetchMembers(isInitial: true); // Reset to Kuri No 1
        },
        icon: const Icon(Icons.refresh, size: 18, color: Colors.grey)
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

  Widget _buildEntryInfoCell(bool isPaid, Map<String, dynamic>? pMonth) {
    if (!isPaid || pMonth == null || pMonth['paidAt'] == null) return const Text("-");
    return Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(DateFormat('dd/MM/yy hh:mm a').format((pMonth['paidAt'] as Timestamp).toDate()), style: const TextStyle(fontSize: 10)),
      Text("By: ${pMonth['addedByName'] ?? '-'}", style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
    ]);
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
      DataColumn(label: Text("K.NO")), DataColumn(label: Text("NAME")), DataColumn(label: Text("PHONE")),
      DataColumn(label: Text("PLACE")), DataColumn(label: Text("MONTHLY")), DataColumn(label: Text("INST")),
      DataColumn(label: Text("PAID")), DataColumn(label: Text("BAL")), DataColumn(label: Text("STATUS")),
      DataColumn(label: Text("DATE")), DataColumn(label: Text("MODE")), DataColumn(label: Text("COLLECTOR")), DataColumn(label: Text("ENTRY")),
    ];
  }

  void _confirmWinner(String memberId, String name, bool isPaid) {
    // 1. Eligibility Check
    if (!isPaid) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Member must pay first to be eligible."), backgroundColor: Colors.red)
      );
      return;
    }

    // 2. Draw Date Check
    int drawDay = int.tryParse(widget.schemeData['kuriDate']?.toString() ?? '') ?? 0;
    DateTime now = DateTime.now();
    if (selectedMonth.year == now.year && selectedMonth.month == now.month) {
      if (now.day < drawDay) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Draw date is Day $drawDay. Cannot mark winner yet."), backgroundColor: Colors.orange)
        );
        return;
      }
    }

    // --- REPLACEMENT LOGIC CHECK ---
    // Check if someone else is already the winner for this specific month
    final existingWinners = widget.schemeData['winners'] as Map<String, dynamic>? ?? {};
    bool isReplacement = existingWinners.containsKey(monthKey);
    String oldWinnerId = existingWinners[monthKey] ?? "";

    // If the clicked member is ALREADY the winner, just show a message and return
    if (isReplacement && oldWinnerId == memberId) {
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
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20, offset: const Offset(0, 10))
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // --- Top Banner (Red for Replace, Orange for New) ---
              Container(
                height: 140,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: isReplacement ? Colors.red.shade50 : Colors.orange.shade50,
                  borderRadius: const BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
                ),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: isReplacement ? Colors.red.shade100 : Colors.orange.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                        isReplacement ? Icons.published_with_changes_rounded : Icons.emoji_events_rounded,
                        size: 60,
                        color: isReplacement ? Colors.red.shade800 : Colors.orange.shade800
                    ),
                  ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(32, 24, 32, 32),
                child: Column(
                  children: [
                    Text(
                      isReplacement ? "REPLACE MONTHLY WINNER" : "CONFIRM MONTHLY WINNER",
                      style: TextStyle(
                        letterSpacing: 1.2,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isReplacement ? Colors.red.shade800 : Colors.orange.shade800,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      name.toUpperCase(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A)),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Month: ${DateFormat('MMMM yyyy').format(selectedMonth)}",
                      style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                    ),

                    // --- Warning Note for Replacement ---
                    if (isReplacement) ...[
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.red.shade100),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.warning_amber_rounded, color: Colors.red.shade800, size: 20),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                "A winner already exists for this month. Confirming will replace the previous winner.",
                                style: TextStyle(color: Color(0xFFB71C1C), fontSize: 12, fontWeight: FontWeight.w500),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // --- Action Buttons ---
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
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () => Navigator.pop(context),
                        child: const Text("CANCEL", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isReplacement ? Colors.red.shade800 : Colors.orange.shade800,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () async {
                          try {
                            final batch = FirebaseFirestore.instance.batch();
                            final schemeRef = FirebaseFirestore.instance.collection('schemes').doc(widget.schemeId);
                            final winnerDocId = "${widget.schemeId}_$monthKey";
                            final winnerRef = FirebaseFirestore.instance.collection('winners').doc(winnerDocId);
                            final logRef = FirebaseFirestore.instance.collection('winner_logs').doc();

                            Map<String, dynamic> winnerData = {
                              'schemeId': widget.schemeId,
                              'schemeName': widget.schemeData['schemeName'],
                              'monthKey': monthKey,
                              'memberId': memberId,
                              'memberName': name,
                              'updatedAt': FieldValue.serverTimestamp(),
                              'updatedBy': widget.userName,
                              'isReplacement': isReplacement,
                              'oldWinnerId': oldWinnerId,
                            };

                            // --- Batch Commit ---
                            batch.update(schemeRef, {'winners.$monthKey': memberId});
                            batch.set(winnerRef, winnerData);
                            batch.set(logRef, { ...winnerData, 'action': isReplacement ? 'REPLACED' : 'ASSIGNED' });

                            await batch.commit();

                            setState(() {
                              widget.schemeData['winners'] ??= {};
                              widget.schemeData['winners'][monthKey] = memberId;
                            });

                            if (context.mounted) Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(isReplacement ? "Winner replaced & logged!" : "Winner assigned & logged!"))
                            );
                          } catch (e) {
                            debugPrint("Winner Error: $e");
                          }
                        },
                        child: Text(
                            isReplacement ? "CONFIRM REPLACE" : "CONFIRM WINNER",
                            style: const TextStyle(fontWeight: FontWeight.bold)
                        ),
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

  Widget _buildPayButton(String id, String name) {
    return ElevatedButton(onPressed: () => _showMarkPaymentDialog(id, name), style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, minimumSize: const Size(40, 25)), child: const Text("PAY", style: TextStyle(fontSize: 10, color: Colors.white)));
  }

  void _showMarkPaymentDialog(String mid, String name) async {
    final adminSnap = await FirebaseFirestore.instance.collection('staff_admins').orderBy('name').get();
    Map<String, String> adminIdMap = {for (var doc in adminSnap.docs) doc['name'].toString(): doc.id};
    List<String> adminNames = adminIdMap.keys.toList();

    showDialog(context: context, builder: (c) => MarkPaymentDialog(
      memberName: name, fullAmount: _parseNum(widget.schemeData['monthlyAmount']), adminList: adminNames,
      onConfirm: (splits, _) async {
        List<Map<String, dynamic>> processedSplits = splits.map((s) => {'mode': s['mode'], 'amount': s['amount'], 'collector': s['collector'], 'collectorId': adminIdMap[s['collector']] ?? "unknown", 'date': Timestamp.fromDate(s['date'])}).toList();
        await FirebaseFirestore.instance.collection('payments').add({
          'kuriId': widget.schemeData['kuriId'], 'schemeId': widget.schemeId, 'memberId': mid, 'monthKey': monthKey, 'amount': widget.schemeData['monthlyAmount'],
          'paymentSplits': processedSplits, 'collectedBy': splits.map((s) => s['collector']).join(", "), 'mode': splits.map((s) => s['mode']).join(", "),
          'paidDate': Timestamp.fromDate(splits.last['date']), 'paidAt': FieldValue.serverTimestamp(), 'status': _calculatePaymentStatus(splits.last['date']), 'addedById': widget.userId, 'addedByName': widget.userName,
        });

      },
    ));
  }

  Future<void> _showAddMember() async {
    final saved = await  showDialog(context: context, builder: (context) => AddMemberDialog(
      schemeId: widget.schemeId, kuriId: widget.schemeData["kuriId"], kuriName: widget.schemeData["kuriName"] ?? "Kuri", schemeName: widget.schemeData["schemeName"], userId: widget.userId, userName: widget.userName,
    ));
    // Only refresh if 'true' was returned
    if (saved == true) {
      _fetchMembers(isInitial: true);
    }
  }

}




