import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class SchemeTheme {
  static const primaryBlue = Color(0xFF1E3A8A);
}

class SelectFromMasterDialog extends StatefulWidget {
  final String kuriId;
  final String kuriName;
  final String userId;
  final String userName;
  final Map<String, dynamic> kuriData; // Used to get dynamic start/end dates

  const SelectFromMasterDialog({
    super.key,
    required this.kuriId,
    required this.kuriName,
    required this.userId,
    required this.userName,
    required this.kuriData,
  });

  @override
  State<SelectFromMasterDialog> createState() => _SelectFromMasterDialogState();
}

class _SelectFromMasterDialogState extends State<SelectFromMasterDialog> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _remarkController = TextEditingController();

  // Inside _SelectFromMasterDialogState
   bool _isCustomNumber = false;
  final TextEditingController _customNumberController = TextEditingController();

  List<DocumentSnapshot> _searchResults = [];
  final List<DocumentSnapshot> _selectedMembers = [];

  bool _isSearching = false;
  bool _isSaving = false;

  late DateTime kuriStartDate;
  late DateTime kuriEndDate;
  late DateTime selectedJoiningMonth;

  @override
  void initState() {
    super.initState();
    // Dynamic date parsing from your Kuri configuration

    kuriStartDate = _parseDate(widget.kuriData['startMonth']) ?? DateTime(2025, 3);
    kuriEndDate = _parseDate(widget.kuriData['endMonth']) ?? DateTime(2025, 12);
    // kuriStartDate = _parseDate(widget.kuriData['startDate']) ?? DateTime(2025, 3);
    // kuriEndDate = _parseDate(widget.kuriData['endDate']) ?? DateTime(2025, 12);

    // Initialize joining month to Kuri start month
    selectedJoiningMonth = kuriStartDate;
  }

  // Helper to handle both Timestamp and String (yyyy_MM) formats
  DateTime? _parseDate(dynamic date) {
    if (date == null) return null;
    if (date is Timestamp) return date.toDate();
    if (date is String) {
      try {
        return DateFormat('yyyy_MM').parse(date);
      } catch (e) {
        return null;
      }
    }
    return null;
  }

  // LOGIC: (End Year - Start Year) * 12 + (End Month - Start Month) + 1
  int get calculatedInstallments {
    int months = ((kuriEndDate.year - selectedJoiningMonth.year) * 12) +
        (kuriEndDate.month - selectedJoiningMonth.month) + 1;
    return months > 0 ? months : 0;
  }

  Future<void> _performSearch() async {
    String term = _searchController.text.trim();
    if (term.isEmpty) return;

    setState(() => _isSearching = true);
    try {
      var snapshot = await FirebaseFirestore.instance.collection('master_members').get();
      setState(() {
        _searchResults = snapshot.docs.where((doc) {
          String name = (doc['name'] ?? "").toString().toLowerCase();
          String phone = (doc['phone'] ?? "").toString();
          return name.contains(term.toLowerCase()) || phone.contains(term);
        }).toList();
      });
    } catch (e) {
      debugPrint("Search error: $e");
    } finally {
      setState(() => _isSearching = false);
    }
  }
  void _showMessage(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.redAccent : Colors.green,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(10),
      ),
    );
  }
  Future<void> _saveMembers() async {
    // 1. Mandatory Field Validations
    String amountStr = _amountController.text.trim();
    String customNumStr = _customNumberController.text.trim();

    if (_selectedMembers.isEmpty) {
      _showMessage("Please select at least one member", isError: true);
      return;
    }


    if (amountStr.isEmpty) {
      _showMessage("Amount is mandatory", isError: true);
      return;
    }


    // Double check amount is valid number
    double? enteredAmount = double.tryParse(amountStr);
    if (enteredAmount == null || enteredAmount <= 0) {
      _showMessage("Please enter a valid amount", isError: true);
      return;
    }

    // Check if Start Month is selected (if you initialized it as null)
    // If selectedJoiningMonth defaults to 'now', it will always have a value,
    // but it's good practice to verify against kuriStartDate bounds.
    if (selectedJoiningMonth.isBefore(DateTime(kuriStartDate.year, kuriStartDate.month, 1))) {
      _showMessage("Please select a valid Start Month", isError: true);
      return;
    }

    if (_isCustomNumber && customNumStr.isEmpty) {
      _showMessage("Please enter a custom starting Kuri Number", isError: true);
      return;
    }

    setState(() => _isSaving = true);
    final db = FirebaseFirestore.instance;

    try {
      // 2. Find Current Top Number for Auto-increment
      final topNumberQuery = await db.collection('enrollments')
          .where('kuriId', isEqualTo: widget.kuriId)
          .orderBy('kuriNumber', descending: true)
          .limit(1)
          .get();

      int currentMaxNumber = 0;
      if (topNumberQuery.docs.isNotEmpty) {
        currentMaxNumber = int.tryParse(topNumberQuery.docs.first['kuriNumber'].toString()) ?? 0;
      }

      // 3. Range Conflict Check for Custom Numbers
      if (_isCustomNumber) {
        int customStartNum = int.tryParse(customNumStr) ?? 0;
        List<String> rangeToCheck = [];
        for (int i = 0; i < _selectedMembers.length; i++) {
          // We pad here to match the unique format in DB
          rangeToCheck.add((customStartNum + i).toString().padLeft(3, '0'));
        }

        final conflictCheck = await db.collection('enrollments')
            .where('kuriId', isEqualTo: widget.kuriId)
            .where('kuriNumber', whereIn: rangeToCheck)
            .get();

        if (conflictCheck.docs.isNotEmpty) {
          String taken = conflictCheck.docs.map((d) => d['kuriNumber']).join(", ");
          _showMessage("Conflict: Number(s) [$taken] already assigned.", isError: true);
          setState(() => _isSaving = false);
          return;
        }

      }

      // 4. Batch Enrollment
      final batch = db.batch();
      int customStartNum = int.tryParse(customNumStr) ?? 0;

      for (int i = 0; i < _selectedMembers.length; i++) {
        final memberDoc = _selectedMembers[i];
        final data = memberDoc.data() as Map<String, dynamic>;

        // Format the number with padding (e.g., 001, 002)
        String finalKuriNumber;
        if (_isCustomNumber) {
          finalKuriNumber = (customStartNum + i).toString().padLeft(3, '0');
        } else {
          finalKuriNumber = (currentMaxNumber + i + 1).toString().padLeft(3, '0');
        }

        final String uniqueId = "${widget.kuriId}_${memberDoc.id}_${DateTime.now().millisecondsSinceEpoch}_$i";

        batch.set(db.collection('enrollments').doc(uniqueId), {
          'kuriId': widget.kuriId,
          'kuriName': widget.kuriName,
          'masterId': memberDoc.id,
          'name': data['name'],
          'phone': data['phone'],
          'place': data['place'],
          'kuriNumber': finalKuriNumber,
          'monthlyAmount': enteredAmount,
          'totalMonths': calculatedInstallments,
          'joiningMonth': DateFormat('yyyy_MM').format(selectedJoiningMonth),
          'kuriEndDate': Timestamp.fromDate(kuriEndDate),
          'kuriStartDate': Timestamp.fromDate(kuriStartDate),
          'enrolledAt': FieldValue.serverTimestamp(),
          'addedBy': widget.userId,
          'addedByName': widget.userName,
        });
      }

      await batch.commit();
      if (mounted) Navigator.pop(context, true);

    } catch (e) {
      _showMessage("Error: $e", isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _createAndEnroll400Members() async {
    setState(() => _isSaving = true);

    final db = FirebaseFirestore.instance;
    final batch = db.batch();

    try {
      // 1. Get the current count to ensure Kuri Numbers continue correctly
      AggregateQuerySnapshot countSnapshot = await db
          .collection('enrollments')
          .where('kuriId', isEqualTo: widget.kuriId)
          .count()
          .get();

      int currentTotal = countSnapshot.count ?? 0;

      // 2. Loop exactly 400 times to create manual data
      for (int i = 1; i <= 400; i++) {
        currentTotal++; // Sequential Kuri Number (e.g., 001, 002...)

        // Generate manual dummy data
        final String dummyName = "TEST MEMBER $currentTotal";
        final String dummyPhone = "90000${currentTotal.toString().padLeft(5, '0')}";
        final String dummyPlace = "Test City";

        // Unique ID for the enrollment
        final String uniqueId = "${widget.kuriId}_TEST_$currentTotal";

        final docRef = db.collection('enrollments').doc(uniqueId);

        batch.set(docRef, {
          'kuriId': widget.kuriId,
          'kuriName': widget.kuriName,
          'masterId': "TEST_MASTER_$currentTotal", // Manual master ID
          'name': dummyName,
          'phone': dummyPhone,
          'place': dummyPlace,
          'kuriNumber': currentTotal.toString().padLeft(3, '0'),
          'remark': "Bulk Test Member",
          'monthlyAmount': double.tryParse(_amountController.text) ?? 5000.0,
          'totalMonths': calculatedInstallments,
          'joiningMonth': DateFormat('yyyy_MM').format(selectedJoiningMonth),
          'kuriEndDate': Timestamp.fromDate(kuriEndDate),
          'enrolledAt': FieldValue.serverTimestamp(),
          'addedBy': widget.userId,
          'addedByName': widget.userName,
          'isTestMember': true, // CRITICAL: Tag for bulk deletion later
        });
      }

      // 3. Commit the batch
      // Since 400 < 500 (Firestore limit), one batch is perfect.
      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Successfully created 400 test members!"))
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint("Manual Bulk Save Error: $e");
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Get the maximum allowed amount from your Kuri Data
    // Assuming it is stored as 'monthlyAmount' or similar in kuriData
    double maxAllowedAmount = double.tryParse(widget.kuriData['monthlyAmount']?.toString() ?? '0') ?? 0.0;

    // Parse the current input
    double enteredAmount = double.tryParse(_amountController.text) ?? 0.0;

    // Validation flag
    bool isAmountInvalid = enteredAmount > maxAllowedAmount;

    return AlertDialog(
      title: const Text("Enroll Members",
          style: TextStyle(fontWeight: FontWeight.bold, color: SchemeTheme.primaryBlue)),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _amountController,
                    keyboardType: TextInputType.number,
                    onChanged: (val) => setState(() {}), // Trigger rebuild to show/hide error
                    decoration: InputDecoration(
                        labelText: "Amount",
                        prefixText: "₹",
                        // SHOW ERROR MESSAGE HERE
                        errorText: isAmountInvalid
                            ? "Max allowed: ₹$maxAllowedAmount"
                            : null,
                        border: const OutlineInputBorder()
                    ),
                  ),
                ),

                const SizedBox(width: 10),
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      final DateTime? picked = await showDatePicker(
                        context: context,
                        initialDate: selectedJoiningMonth,
                        firstDate: kuriStartDate,
                        lastDate: kuriEndDate,
                      );
                      if (picked != null) setState(() => selectedJoiningMonth = picked);
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                          labelText: "Start Month",
                          border: OutlineInputBorder()
                      ),
                      child: Text(DateFormat('MMM yyyy').format(selectedJoiningMonth)),
                    ),
                  ),
                ),
              ],
            ),
            // Add this inside the dialog's Column
            SizedBox(height: 10,),
            Row(
              children: [
                Checkbox(
                  value: _isCustomNumber,
                  onChanged: (val) => setState(() => _isCustomNumber = val ?? false),
                ),
                const Text("Use Custom Kuri Number?", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(width: 10),
                if (_isCustomNumber)
                  Expanded(
                    child: TextField(
                      controller: _customNumberController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        hintText: "e.g. 055",
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            const SizedBox(height: 12),
            // Result indicator (e.g., 10 Months)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8)
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.info_outline, size: 18, color: Colors.blue),
                  const SizedBox(width: 10),
                  Text(
                    "Duration: $calculatedInstallments Months (Ends ${DateFormat('MMM yyyy').format(kuriEndDate)})",
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
                  ),
                ],
              ),
            ),
            const Divider(height: 30),
            // Search field
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: "Search Name or Phone",
                suffixIcon: IconButton(icon: const Icon(Icons.search), onPressed: _performSearch),
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => _performSearch(),
            ),
            if (_isSearching) const LinearProgressIndicator(),
            // Results list
            const SizedBox(height: 10),
            Flexible(
              child: _searchResults.isEmpty
                  ? const Padding(padding: EdgeInsets.all(20), child: Text("Search for members to add"))
                  : ListView.builder(
                shrinkWrap: true,
                itemCount: _searchResults.length,
                itemBuilder: (context, index) {
                  final doc = _searchResults[index];
                  final isSelected = _selectedMembers.contains(doc);
                  return CheckboxListTile(
                    title: Text(doc['name'].toString().toUpperCase()),
                    subtitle: Text("${doc['phone']} | ${doc['place']}"),
                    value: isSelected,
                    onChanged: (val) {
                      setState(() {
                        val == true ? _selectedMembers.add(doc) : _selectedMembers.remove(doc);
                      });
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            // TextField(
            //   controller: _remarkController,
            //   decoration: const InputDecoration(labelText: "Remark (Optional)", border: OutlineInputBorder()),
            // ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCEL")),
        ElevatedButton(
          // onPressed: (_selectedMembers.isEmpty || _isSaving) ? null : _createAndEnroll400Members,
          onPressed: (_selectedMembers.isEmpty || _isSaving) ? null : _saveMembers,
          style: ElevatedButton.styleFrom(backgroundColor: SchemeTheme.primaryBlue),
          child: _isSaving
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : Text("ENROLL (${_selectedMembers.length})",style: TextStyle(color: Colors.white),),
        ),
      ],
    );
  }
}

class MarkPaymentDialog extends StatefulWidget {
  final String memberName;
  final double fullAmount;
  final List<String> adminList;
  final Function(List<Map<String, dynamic>> splits, DateTime date) onConfirm;

  const MarkPaymentDialog({
    super.key,
    required this.memberName,
    required this.fullAmount,
    required this.adminList,
    required this.onConfirm,
  });

  @override
  State<MarkPaymentDialog> createState() => _MarkPaymentDialogState();
}

class _MarkPaymentDialogState extends State<MarkPaymentDialog> {
  // Logic remains exactly as you provided
  bool _isSaving = false; // NEW: Track saving state to prevent double pops

  List<Map<String, dynamic>> splits = [
    {
      "mode": null,
      "amount": 0.0,
      "collector": null,
      "date": DateTime.now()
    }
  ];

  double get totalEntered => splits.fold(0.0, (sum, item) => sum + (item['amount'] as double));

  @override
  Widget build(BuildContext context) {
    bool isTotalMatched = totalEntered.toInt() == widget.fullAmount.toInt();
    bool areFieldsFilled = !splits.any((s) => s['collector'] == null || s['mode'] == null || s['amount'] <= 0);
    // Modified to include _isSaving check
    bool isComplete = isTotalMatched && areFieldsFilled && !_isSaving;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 850,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 40,
              offset: const Offset(0, 15),
            )
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- HEADER ---
            Container(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 32),
              decoration: const BoxDecoration(
                color: Color(0xFFF8FAFC),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
                border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E3A8A).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.receipt_long_rounded, color: Color(0xFF1E3A8A), size: 28),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.memberName.toUpperCase(),
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Color(0xFF1E293B)),
                      ),
                      const Text("Update payment settlement", style: TextStyle(fontSize: 12, color: Colors.blueGrey)),
                    ],
                  ),
                  const Spacer(),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text("DUE AMOUNT", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                      Text(
                        "₹${widget.fullAmount.toInt()}",
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 24, color: Color(0xFF1E3A8A)),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // --- TABLE HEADERS ---
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 24, 32, 8),
              child: Row(
                children: [
                  _headerTxt("DATE", 130),
                  const SizedBox(width: 8),
                  _headerTxt("AMOUNT", 110),
                  const SizedBox(width: 8),
                  Expanded(child: _headerTxt("PAYMENT MODE", 0)),
                  const SizedBox(width: 8),
                  Expanded(child: _headerTxt("COLLECTOR", 0)),
                  const SizedBox(width: 48),
                ],
              ),
            ),

            // --- SPLIT LIST ---
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  children: splits.asMap().entries.map((entry) => _buildSplitRow(entry.key)).toList(),
                ),
              ),
            ),

            // --- ADD BUTTON ---
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                  side: BorderSide(color: Colors.blue.shade200),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _isSaving ? null : () => setState(() => splits.add({
                  "mode": null, "amount": 0.0, "collector": null, "date": DateTime.now()
                })),
                icon: const Icon(Icons.add_circle_outline, size: 20),
                label: const Text("ADD ANOTHER DATE / SPLIT", style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),

            // --- FOOTER SECTION ---
            Container(
              padding: const EdgeInsets.all(32),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
                color: Color(0xFFF8FAFC),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(24),
                  bottomRight: Radius.circular(24),
                ),
              ),
              child: Column(
                children: [
                  _buildSummaryBar(isTotalMatched),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: _isSaving ? null : () => Navigator.pop(context),
                        child: const Text("CANCEL", style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.bold, fontSize: 14)),
                      ),
                      const SizedBox(width: 20),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1E3A8A),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        onPressed: isComplete ? () async {
                          setState(() => _isSaving = true); // Set saving to true
                          // Calling the logic provided in _showMarkPaymentDialog
                          await widget.onConfirm(splits, splits.first['date']);
                          // Logic for popping is now handled inside _showMarkPaymentDialog callback
                        } : null,
                        child: _isSaving
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Text("CONFIRM PAYMENT", style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.8)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _headerTxt(String label, double width) {
    return SizedBox(
      width: width > 0 ? width : null,
      child: Text(
        label,
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Color(0xFF94A3B8), letterSpacing: 1.1),
      ),
    );
  }

  Widget _buildSplitRow(int index) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. DATE PICKER
          SizedBox(
            width: 130,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: _isSaving ? null : () async {
                DateTime? p = await showDatePicker(
                  context: context,
                  initialDate: splits[index]['date'],
                  firstDate: DateTime(2024),
                  lastDate: DateTime.now(),
                );
                if (p != null) setState(() => splits[index]['date'] = p);
              },
              child: Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.white,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_month_rounded, size: 16, color: Colors.blue),
                    const SizedBox(width: 8),
                    Text(
                      DateFormat('dd-MM-yy').format(splits[index]['date']),
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // 2. AMOUNT
          SizedBox(
            width: 110,
            child: _inputWrapper(TextFormField(
              enabled: !_isSaving,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              decoration: const InputDecoration(
                prefixText: "₹ ",
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 14, horizontal: 12),
              ),
              onChanged: (v) => setState(() => splits[index]['amount'] = double.tryParse(v) ?? 0.0),
            )),
          ),
          const SizedBox(width: 8),

          // 3. MODE
          Expanded(
            child: _inputWrapper(DropdownButtonFormField<String>(
              value: splits[index]['mode'],
              isDense: true,
              hint: const Text("Select Mode", style: TextStyle(fontSize: 13)),
              decoration: const InputDecoration(border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 12)),
              items: ["Cash", "GPay"].map((e) => DropdownMenuItem(
                value: e,
                child: Text(e, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              )).toList(),
              onChanged: _isSaving ? null : (v) => setState(() => splits[index]['mode'] = v),
              validator: (v) => v == null ? "Required" : null,
            )),
          ),
          const SizedBox(width: 8),

          // 4. COLLECTOR
          Expanded(
            child: _inputWrapper(DropdownButtonFormField<String>(
              value: splits[index]['collector'],
              isDense: true,
              hint: const Text("Select Collector", style: TextStyle(fontSize: 13)),
              decoration: const InputDecoration(border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 12)),
              items: widget.adminList.map((e) => DropdownMenuItem(
                value: e,
                child: Text(e, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              )).toList(),
              onChanged: _isSaving ? null : (v) => setState(() => splits[index]['collector'] = v),
            )),
          ),

          // DELETE
          SizedBox(
            width: 48,
            child: (splits.length > 1 && !_isSaving)
                ? IconButton(
              onPressed: () => setState(() => splits.removeAt(index)),
              icon: const Icon(Icons.delete_sweep_rounded, color: Colors.redAccent, size: 24),
            )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  // Visual wrapper to keep all inputs looking identical
  Widget _inputWrapper(Widget child) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(12),
        color: Colors.white,
      ),
      child: child,
    );
  }

  Widget _buildSummaryBar(bool isMatch) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        color: isMatch ? const Color(0xFFF0FDF4) : const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isMatch ? const Color(0xFFBBF7D0) : const Color(0xFFFECACA)),
      ),
      child: Row(
        children: [
          Icon(isMatch ? Icons.check_circle_rounded : Icons.error_outline_rounded,
              color: isMatch ? Colors.green.shade600 : Colors.red.shade600, size: 28),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "TOTAL ENTERED: ₹${totalEntered.toInt()}",
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: isMatch ? Colors.green.shade900 : Colors.red.shade900),
              ),
              Text(
                isMatch ? "Ready to confirm." : "Short of target by ₹${(widget.fullAmount - totalEntered).toInt()}",
                style: TextStyle(fontSize: 12, color: isMatch ? Colors.green.shade700 : Colors.red.shade700),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
Widget buildFunnyLoader() {
  final messages = [
    "Counting your members... 🏃‍♂️",
    "Fetching first 20 records... ✨",
    "Polishing the table... 🪄",
    "Almost there! Hang tight... 🧐",
  ];

  return StreamBuilder<int>(
    stream: Stream.periodic(const Duration(seconds: 2), (i) => i % messages.length),
    builder: (context, snapshot) {
      int index = snapshot.data ?? 0;
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: SchemeTheme.primaryBlue),
            const SizedBox(height: 20),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 500),
              child: Text(messages[index], key: ValueKey(index),
                  style: const TextStyle(color: SchemeTheme.primaryBlue, fontStyle: FontStyle.italic, fontWeight: FontWeight.w500)),
            ),
          ],
        ),
      );
    },
  );



}


