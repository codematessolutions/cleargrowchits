import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

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
  String kuriNumberQuery = "";
  String searchQuery = "";
  String selectedStatus = "All";
  DateTime selectedMonth = DateTime.now();
  String get monthKey => DateFormat('yyyy_MM').format(selectedMonth);

  final ScrollController _verticalScroll = ScrollController();
  late TextEditingController _nameController;
  late TextEditingController _numberController;

  @override
  void initState() {
    super.initState();

    _nameController = TextEditingController();
    _numberController = TextEditingController();

    // Initial fetch
    _fetchMembers(isInitial: true);

    _verticalScroll.addListener(() {
      // Check if we are near the bottom (200 pixels remaining)
      // This is more reliable than 90% for long tables
      double maxScroll = _verticalScroll.position.maxScrollExtent;
      double currentScroll = _verticalScroll.position.pixels;
      double delta = 200.0; // Trigger load when 200px from bottom

      if (maxScroll - currentScroll <= delta) {
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
    if (_isLoadingMore || (_isLoading && !isInitial)) return;

    if (isInitial) {
      setState(() {
        _isLoading = true;
        _allMembers = [];
        _lastDocument = null;
        _hasMore = true;
      });
    } else {
      if (!_hasMore) return;
      setState(() => _isLoadingMore = true);
    }

    try {
      Query query = FirebaseFirestore.instance
          .collection('enrollments')
          .where('kuriId', isEqualTo: widget.kuriId);

      // 1. PRIORITIZE KURI NUMBER SEARCH (Exact or Prefix)
      if (kuriNumberQuery.isNotEmpty) {
        // padLeft ensures "1" matches "001" if that's how you store it
        String formattedNum = kuriNumberQuery.padLeft(3, '0');
        query = query
            .where('kuriNumber', isGreaterThanOrEqualTo: formattedNum)
            .where('kuriNumber', isLessThanOrEqualTo: '$formattedNum\uf8ff')
            .orderBy('kuriNumber');
      }
      // 2. FALLBACK TO NAME SEARCH
      else if (searchQuery.isNotEmpty) {
        String searchUpper = searchQuery.toUpperCase();
        query = query
            .where('name', isGreaterThanOrEqualTo: searchUpper)
            .where('name', isLessThanOrEqualTo: '$searchUpper\uf8ff')
            .orderBy('name');
      }
      // 3. DEFAULT SORTING
      else {
        query = query.orderBy('kuriNumber', descending: false);
      }

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
        });
      }
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
                        ElevatedButton.icon(
                          onPressed: _isLoading ? null : () async {
                            await _generateFullKuriPDF();
                          },
                          icon: _isLoading
                              ? const SizedBox(width: 10, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.download_rounded, size: 18),
                          label: const Text("GENERATE & DOWNLOAD PDF"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red.shade800,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            elevation: 2,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        )
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
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          // 1. NAME SEARCH
          Expanded(
            flex: 4,
            child: _searchField(
              controller: _nameController,
              hint: "Search Name...",
              icon: Icons.person_outline,
              onChanged: (val) => searchQuery = val,
              onSubmitted: (val) {
                searchQuery = val;
                _fetchMembers(isInitial: true);
              },
            ),
          ),

          const SizedBox(width: 12),

          // 2. KURI NUMBER SEARCH
          Expanded(
            flex: 2,
            child: _searchField(
              controller: _numberController,
              hint: "K.No (001)",
              icon: Icons.pin_outlined,
              onChanged: (val) => kuriNumberQuery = val,
              onSubmitted: (val) {
                kuriNumberQuery = val;
                _fetchMembers(isInitial: true);
              },
            ),
          ),

          const SizedBox(width: 16),

          // 3. STATUS DROPDOWN
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: selectedStatus,
                onChanged: (val) => setState(() => selectedStatus = val!),
                items: ["All", "Paid", "Pending"]
                    .map((s) => DropdownMenuItem(
                    value: s,
                    child: Text(s, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))
                )).toList(),
              ),
            ),
          ),

          const SizedBox(width: 12),

          // 4. RESET BUTTON
          Tooltip(
            message: "Reset all filters",
            child: InkWell(
              onTap: _resetSearch,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                height: 40,
                width: 40,
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: const Icon(Icons.refresh_rounded, color: Colors.blueGrey, size: 20),
              ),
            ),
          ),
        ],
      ),
    );
  }

// Updated Helper with Controller support
  Widget _searchField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    required Function(String) onChanged,
    required Function(String) onSubmitted
  }) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: Icon(icon, size: 18, color: Colors.grey),
          suffixIcon: IconButton(
            icon: const Icon(Icons.search, size: 18, color: Colors.blue),
            onPressed: () => _fetchMembers(isInitial: true),
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.only(top: 5),
        ),
      ),
    );
  }

  void _resetSearch() {
    setState(() {
      // Clear search strings
      searchQuery = "";
      kuriNumberQuery = "";

      // Reset dropdown
      selectedStatus = "All";

      // Clear the physical text in the UI
      _nameController.clear();
      _numberController.clear();

      // Reset pagination variables
      _allMembers = [];
      _lastDocument = null;
      _hasMore = true;
    });

    // Re-fetch the original list
    _fetchMembers(isInitial: true);
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

    return Expanded(
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(
          dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse, PointerDeviceKind.trackpad},
        ),
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('payments')
              .where('kuriId', isEqualTo: widget.kuriId)
              .snapshots(),
          builder: (context, pSnap) {
            if (!pSnap.hasData) return const Center(child: CircularProgressIndicator());

            final allPayments = pSnap.data!.docs;

            // Map for current selected month view
            Map<String, Map<String, dynamic>> currentMonthPaidMap = {
              for (var doc in allPayments.where((p) => p['monthKey'] == monthKey))
                doc['memberId'].toString(): doc.data() as Map<String, dynamic>
            };

            List<DocumentSnapshot> filteredList = _allMembers.where((mDoc) {
              final mid = mDoc.id;
              final isPaid = currentMonthPaidMap.containsKey(mid);
              if (selectedStatus == "Paid" && !isPaid) return false;
              if (selectedStatus == "Pending" && isPaid) return false;
              return true;
            }).toList();

            return Column(
              children: [
                Expanded(
                  child: Scrollbar(
                    controller: _verticalScroll,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: _verticalScroll,
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            DataTable(
                              headingRowHeight: 45,
                              dataRowMaxHeight: 70,
                              columnSpacing: 35,
                              headingRowColor: WidgetStateProperty.all(Colors.grey.shade100),
                              border: TableBorder.all(color: Colors.grey.shade300, width: 0.5),
                              columns: const [
                                DataColumn(label: Text("K.NO")),
                                DataColumn(label: Text("NAME & PHONE")),
                                DataColumn(label: Text("PLACE")),
                                DataColumn(label: Text("MONTHLY")),
                                DataColumn(label: Text("INST")),
                                DataColumn(label: Text("PAID")),
                                DataColumn(label: Text("BAL")),
                                DataColumn(label: Text("STATUS")),
                                DataColumn(label: Text("DATE")),
                                DataColumn(label: Text("MODE & SPLITS")),
                                DataColumn(label: Text("COLLECTOR")),
                                DataColumn(label: Text("ENTRY")),
                                DataColumn(label: Text("ACTION")),
                              ],
                              rows: filteredList.map((m) {
                                final d = m.data() as Map<String, dynamic>;
                                final mid = m.id;
                                final isPaid = currentMonthPaidMap.containsKey(mid);
                                final pMonth = isPaid ? currentMonthPaidMap[mid] : null;

                                double monthlyAmount = _parseNum(d['monthlyAmount']);
                                int totalMonths = int.tryParse(d['totalMonths']?.toString() ?? '0') ?? 0;
                                String? winnerMonth = d['winnerMonth'];
                                bool hasWon = winnerMonth != null;

                                final mPayments = allPayments.where((p) => p['memberId'] == mid).toList();
                                int displayPaidCount = mPayments.length;
                                int displayTotalCount = hasWon ? mPayments.length : totalMonths;

                                double totalPaid = mPayments.fold(0.0, (sum, p) => sum + _parseNum((p.data() as Map<String, dynamic>)['amount']));
                                double balance = hasWon ? 0.0 : (monthlyAmount * totalMonths) - totalPaid;

                                return DataRow(
                                  color: hasWon ? WidgetStateProperty.all(Colors.amber.shade50) : null,
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
                                    DataCell(Text("$displayPaidCount/$displayTotalCount",
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: hasWon ? FontWeight.bold : FontWeight.normal,
                                          color: hasWon ? Colors.blue.shade900 : Colors.black,
                                        ))),
                                    DataCell(Text(currencyFormat.format(totalPaid), style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 11))),
                                    DataCell(Text(currencyFormat.format(balance < 0 ? 0 : balance),
                                        style: TextStyle(color: balance > 0 ? Colors.red : Colors.green, fontWeight: FontWeight.bold, fontSize: 11))),

                                    // STATUS BADGE
                                    DataCell(_buildStatusBadge(isPaid, pMonth, winnerMonth)),

                                    // DATE CELL with custom color
                                    DataCell(Text(
                                        isPaid ? DateFormat('dd-MM-yy').format((pMonth!['paidDate'] as Timestamp).toDate()) : "-",
                                        style: const TextStyle(fontSize: 11, color: Colors.blueGrey, fontWeight: FontWeight.w500)
                                    )),

                                    // MODE & SPLITS CELL
                                    DataCell(isPaid ? Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(pMonth!['mode']?.toString() ?? "-", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.purple)),
                                        if (pMonth['splitAmounts'] != null && pMonth['splitAmounts'].toString().isNotEmpty)
                                          Text("₹${pMonth['splitAmounts']}", style: const TextStyle(fontSize: 9, color: Colors.blueGrey, fontStyle: FontStyle.italic)),
                                      ],
                                    ) : const Text("-")),

                                    // COLLECTOR CELL
                                    DataCell(Text(isPaid ? pMonth!['collectedBy'] ?? "-" : "-", style: const TextStyle(fontSize: 10, color: Colors.teal))),

                                    // ENTRY BY CELL
                                    DataCell(isPaid ? Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(pMonth!['addedByName']?.toString().toUpperCase() ?? "-", style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.brown)),
                                        if (pMonth['paidAt'] != null)
                                          Text(DateFormat('dd-MMM hh:mm').format((pMonth['paidAt'] as Timestamp).toDate()), style: const TextStyle(fontSize: 8, color: Colors.grey)),
                                      ],
                                    ) : const Text("-")),

                                    DataCell(Row(
                                      children: [
                                        if (!hasWon && !isPaid) ...[
                                          _buildPayButton(mid, d['name'], d['masterId'] ?? mid, monthlyAmount),
                                          IconButton(
                                            icon: const Icon(Icons.message_outlined, color: Colors.green, size: 18),
                                            onPressed: () => _sendWhatsAppReminder(d['phone'] ?? "", d['name'] ?? "Member", balance),
                                          ),
                                        ],
                                        if (hasWon)
                                          const Padding(
                                            padding: EdgeInsets.only(left: 8.0),
                                            child: Icon(Icons.stars, color: Colors.orange, size: 22),
                                          )
                                        else
                                          IconButton(
                                            icon: Icon(Icons.emoji_events_outlined, color: isPaid ? Colors.blue : Colors.grey.shade400),
                                            onPressed: () => _markAsWinner(mid, d['name'], isPaid, pMonth),
                                          ),
                                      ],
                                    )),
                                  ],
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

// --- FIXED 5-STATUS BADGE LOGIC ---
  Widget _buildStatusBadge(bool isPaid, Map<String, dynamic>? pMonth, String? winnerMonth) {
    Color bgColor = Colors.grey.shade200;
    Color textColor = Colors.grey.shade700;
    String label = "Pending";

    if (winnerMonth != null) {
      return _badgeContainer("WINNER ($winnerMonth)", Colors.orange.shade100, Colors.orange.shade900);
    }

    if (isPaid && pMonth != null) {
      DateTime pDate = (pMonth['paidDate'] as Timestamp).toDate();

      // Split monthKey (e.g., "2026_04")
      List<String> parts = pMonth['monthKey'].split('_');
      int targetYear = int.parse(parts[0]);
      int targetMonth = int.parse(parts[1]);

      // RULE 2: ADVANCE CHECK (Paid date month < Target monthKey month)
      if (pDate.year < targetYear || (pDate.year == targetYear && pDate.month < targetMonth)) {
        return _badgeContainer("ADVANCE", Colors.blue.shade100, Colors.blue.shade900);
      }

      // DATE CALCULATIONS
      int drawDay = int.tryParse(widget.kuriData['kuriDate']?.toString() ?? '8') ?? 8;
      DateTime drawDate = DateTime(targetYear, targetMonth, drawDay);
      DateTime lastPaymentDate = drawDate.subtract(const Duration(days: 2));

      DateTime pDay = DateTime(pDate.year, pDate.month, pDate.day);
      DateTime dDay = DateTime(drawDate.year, drawDate.month, drawDate.day);
      DateTime deadLineDay = DateTime(lastPaymentDate.year, lastPaymentDate.month, lastPaymentDate.day);

      if (pDay.isBefore(deadLineDay) || pDay.isAtSameMomentAs(deadLineDay)) {
        label = "ON-TIME";
        bgColor = Colors.green.shade100;
        textColor = Colors.green.shade900;
      }
      else if (pDay.isAfter(deadLineDay) && (pDay.isBefore(dDay) || pDay.isAtSameMomentAs(dDay))) {
        label = "LATE (CHANCE)";
        bgColor = Colors.amber.shade100;
        textColor = Colors.amber.shade900;
      }
      else {
        label = "LATE (NO CHANCE)";
        bgColor = Colors.red.shade100;
        textColor = Colors.red.shade900;
      }
    }

    return _badgeContainer(label, bgColor, textColor);
  }

  Widget _badgeContainer(String label, Color bg, Color text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: text.withOpacity(0.2), width: 0.5),
      ),
      child: Text(
        label,
        style: TextStyle(color: text, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.5),
      ),
    );
  }
  // --- UPDATED WINNER ACTION ---

  void _sendWhatsAppReminder(String phone, String name, double balance) async {
    // Clean the phone number (remove spaces, plus signs, etc.)
    String cleanPhone = phone.replaceAll(RegExp(r'[^0-9]'), '');

    // Add country code if not present (assuming +91 for India)
    if (!cleanPhone.startsWith('91')) cleanPhone = '91$cleanPhone';

    String message = "Hi $name, this is a reminder regarding your Kuri payment. "
        "Your pending balance for ${DateFormat('MMMM yyyy').format(selectedMonth)} is ₹${balance.toInt()}. "
        "Please make the payment to stay eligible for the draw. Thank you!";

    // Encode the URL for the web
    String url = "https://wa.me/$cleanPhone?text=${Uri.encodeComponent(message)}";

    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } else {
      debugPrint("Could not launch WhatsApp");
    }
  }
  void _markAsWinner(String mid, String name, bool isPaid, Map<String, dynamic>? pMonth) async {
    // 1. Initial Validation
    if (!isPaid || pMonth == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Validation Error: Only members with a 'Paid' status for this month can be marked as winners."),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // 2. Draw Date Enforcement
    // Fetches the set draw date (e.g., 10th) from the Kuri settings
    int drawDay = int.tryParse(widget.kuriData['kuriDate']?.toString() ?? '10') ?? 10;
    DateTime now = DateTime.now();

    // Logic: Is today's date >= Draw Date for the selected month/year?
    bool isDrawDateReached = (now.year > selectedMonth.year) ||
        (now.year == selectedMonth.year && now.month > selectedMonth.month) ||
        (now.year == selectedMonth.year && now.month == selectedMonth.month && now.day >= drawDay);

    if (!isDrawDateReached) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Draw Lock: Winners for ${monthKey} cannot be assigned until the $drawDay-th."),
          backgroundColor: Colors.orange.shade900,
        ),
      );
      return;
    }

    // 3. Confirmation Dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Confirm Kuri Winner"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Are you sure you want to mark $name as the winner?"),
            const SizedBox(height: 10),
            const Text("• This will lock their record for this month.", style: TextStyle(fontSize: 12, color: Colors.grey)),
            const Text("• A permanent audit log will be created.", style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text("CANCEL"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700),
            onPressed: () async {
              // Close the confirmation dialog
              Navigator.pop(dialogContext);

              // Show non-dismissible loading
              _showLoadingDialog("Finalizing Winner & Creating Logs...");

              final db = FirebaseFirestore.instance;
              final batch = db.batch();

              // --- DATABASE UPDATES ---

              // A. Update Member Enrollment
              final enrollmentRef = db.collection('enrollments').doc(mid);
              batch.update(enrollmentRef, {
                'winnerMonth': monthKey, // Mark as winner for THIS month
                'winDate': FieldValue.serverTimestamp(),
                'isCompleted': true, // Removes from pending lists
              });

              // B. Update Kuri Summary Metadata
              final kuriRef = db.collection('kuris').doc(widget.kuriId);
              batch.update(kuriRef, {
                'lastWinnerName': name,
                'lastWinnerMonth': monthKey,
                'totalWinners': FieldValue.increment(1),
              });

              // C. Create Permanent Audit Log
              final logRef = db.collection('winner_logs').doc();
              batch.set(logRef, {
                'kuriId': widget.kuriId,
                'kuriName': widget.kuriName ?? 'Kuri',
                'memberId': mid,
                'memberName': name,
                'winMonthKey': monthKey,
                'loggedAt': FieldValue.serverTimestamp(),
                // Administrative Details
                'processedBy': widget.userName,
                'adminId': widget.userId,
                // Financial Snapshot
                'paymentId': pMonth['paymentId'] ?? 'N/A',
                'amountAtWin': pMonth['amount'] ?? 0,
              });

              try {
                await batch.commit();

                // --- SAFETY CHECK AFTER DATABASE CALL ---
                if (!mounted) return;
                Navigator.of(context).pop(); // Close loading dialog

                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Winner successfully assigned and logged."), backgroundColor: Colors.green)
                );

                // Refresh UI
                _fetchMembers(isInitial: true);

              } catch (e) {
                if (!mounted) return;
                Navigator.of(context).pop(); // Close loading dialog

                debugPrint("Winner Logging Error: $e");
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Failed to update winner: $e"), backgroundColor: Colors.red)
                );
              }
            },
            child: const Text("CONFIRM WINNER", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

// Utility to ensure UI remains responsive but locked during database writes
  void _showLoadingDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(strokeWidth: 3),
            const SizedBox(width: 20),
            Expanded(child: Text(message, style: const TextStyle(fontSize: 14))),
          ],
        ),
      ),
    );
  }

// Ensure you have a matching _showLoadingDialog or use this one

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






  Future<void> _generateFullKuriPDF() async {
    final StreamController<double> progressController = StreamController<double>.broadcast();
    _showProgressDialog(progressController.stream);

    try {
      final pdf = pw.Document();
      final font = pw.Font.helvetica();
      final db = FirebaseFirestore.instance;

      final results = await Future.wait([
        db.collection('enrollments').where('kuriId', isEqualTo: widget.kuriId).orderBy('kuriNumber').get(),
        db.collection('payments').where('kuriId', isEqualTo: widget.kuriId).get(),
      ]);

      final enrollDocs = (results[0] as QuerySnapshot).docs;
      final allPayments = (results[1] as QuerySnapshot).docs;
      final List<List<String>> dataRows = [];

      double parse(dynamic v) => double.tryParse(v?.toString() ?? '0') ?? 0.0;

      for (int i = 0; i < enrollDocs.length; i++) {
        if (progressController.isClosed) break;
        progressController.add(i / enrollDocs.length);

        if (i % 15 == 0) await Future.delayed(const Duration(milliseconds: 1));

        final d = enrollDocs[i].data() as Map<String, dynamic>;
        final mid = enrollDocs[i].id;

        double monthlyAmount = parse(d['monthlyAmount']);
        int totalMonths = int.tryParse(d['totalMonths']?.toString() ?? '0') ?? 0;
        final mPayments = allPayments.where((p) => p['memberId'] == mid).toList();
        double totalPaid = mPayments.fold(0.0, (sum, p) => sum + parse(p['amount']));

        final pMonthDoc = mPayments.cast<DocumentSnapshot?>().firstWhere(
              (p) => (p?.data() as Map<String, dynamic>)['monthKey'] == monthKey,
          orElse: () => null,
        );

        // --- 1. WINNER LOGIC ---
        String? winnerMonth = d['winnerMonth'];
        bool hasWon = winnerMonth != null;
        double balance = hasWon ? 0.0 : (monthlyAmount * totalMonths) - totalPaid;

        String status = "Pending";
        String details = "-";

        // --- 2. STATUS LOGIC (Priority Order) ---
        if (hasWon) {
          status = "WINNER ($winnerMonth)";
        }

        if (pMonthDoc != null) {
          final pData = pMonthDoc.data() as Map<String, dynamic>;
          details = "${pData['mode'] ?? 'Cash'} | ${pData['collectedBy'] ?? '-'}";

          if (!hasWon) {
            DateTime pDate = (pData['paidDate'] as Timestamp).toDate();
            List<String> parts = pData['monthKey'].split('_');
            int targetYear = int.parse(parts[0]);
            int targetMonth = int.parse(parts[1]);

            // RULE: Advance
            if (pDate.year < targetYear || (pDate.year == targetYear && pDate.month < targetMonth)) {
              status = "Advance";
            } else {
              int drawDay = int.tryParse(widget.kuriData['kuriDate']?.toString() ?? '8') ?? 8;
              DateTime drawDate = DateTime(targetYear, targetMonth, drawDay);
              DateTime lastOnTime = drawDate.subtract(const Duration(days: 2));

              DateTime pDay = DateTime(pDate.year, pDate.month, pDate.day);
              DateTime dDay = DateTime(drawDate.year, drawDate.month, drawDate.day);
              DateTime otDay = DateTime(lastOnTime.year, lastOnTime.month, lastOnTime.day);

              if (pDay.isBefore(otDay) || pDay.isAtSameMomentAs(otDay)) {
                status = "On-Time";
              } else if (pDay.isBefore(dDay) || pDay.isAtSameMomentAs(dDay)) {
                status = "Late (Chance)";
              } else {
                status = "Late (No Ch)";
              }
            }
          }
        }

        // COMBINING NAME, PHONE, PLACE
        String memberInfo = "${d['name'].toString().toUpperCase()}\n${d['phone'] ?? '-'}\n${d['place'] ?? '-'}";

        dataRows.add([
          d['kuriNumber']?.toString() ?? "-",
          memberInfo, // Combined column
          monthlyAmount.toStringAsFixed(0),
          "${mPayments.length}/${hasWon ? mPayments.length : totalMonths}",
          totalPaid.toStringAsFixed(0),
          balance.toStringAsFixed(0),
          status,
          details,
        ]);
      }

      progressController.add(1.0);
      await Future.delayed(const Duration(milliseconds: 100));

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(15),
          maxPages: 1000,
          theme: pw.ThemeData.withFont(base: font, bold: font),
          header: (context) => pw.Header(
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text("${widget.kuriName} - FULL REPORT", style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                pw.Text("MONTH: $monthKey", style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
              ],
            ),
          ),
          build: (context) => [
            pw.TableHelper.fromTextArray(
              headers: ['K.NO', 'MEMBER DETAILS', 'MNTLY', 'INST', 'PAID', 'BAL', 'STATUS', 'PAYMENT DETAILS'],
              data: dataRows,
              headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
              cellStyle: const pw.TextStyle(fontSize: 7),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
              columnWidths: {
                0: const pw.FixedColumnWidth(25),
                1: const pw.FixedColumnWidth(25), // Wider for Name+Phone+Place
                3: const pw.FixedColumnWidth(25),
                6: const pw.FixedColumnWidth(25),
                7: const pw.FixedColumnWidth(25),
              },
            ),
          ],
        ),
      );

      if (Navigator.canPop(context)) Navigator.of(context).pop();
      await Printing.layoutPdf(name: '${widget.kuriName}_$monthKey.pdf', onLayout: (format) async => pdf.save());

    } catch (e) {
      if (Navigator.canPop(context)) Navigator.of(context).pop();
      debugPrint("PDF ERROR: $e");
    } finally {
      if (!progressController.isClosed) await progressController.close();
    }
  }

  void _showProgressDialog(Stream<double> progressStream) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StreamBuilder<double>(
        stream: progressStream,
        initialData: 0.0,
        builder: (context, snapshot) {
          double progress = snapshot.data ?? 0.0;
          return AlertDialog(
            title: const Text("Generating PDF Report"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(
                  value: progress,
                  minHeight: 10,
                  backgroundColor: Colors.grey[200],
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
                ),
                const SizedBox(height: 20),
                Text("${(progress * 100).toStringAsFixed(0)}% Completed"),
                const SizedBox(height: 5),
                const Text("Processing members... Please wait.", style: TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          );
        },
      ),
    );
  }

}
