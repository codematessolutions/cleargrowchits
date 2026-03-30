// lib/providers/kuri_provider.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/kuri_model.dart';

class KuriProvider with ChangeNotifier {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Stream to get all Kuris in real-time
  Stream<List<KuriModel>> get kurisStream {
    return _db
        .collection('kuris')
    // 1. Always use orderBy with limit to ensure you get the NEWEST data first
        .orderBy('createdAt', descending: true)
    // 2. Set a reasonable limit (e.g., 20 or 50) for a single screen
        .limit(3)
        .snapshots()
        .map((snapshot) => snapshot.docs
        .map((doc) => KuriModel.fromFirestore(doc))
        .toList(),
    );
  }

  Future<void> addKuri(KuriModel kuri) async {
    // Ensure createdAt is set when adding
    var data = kuri.toMap();
    data['createdAt'] = FieldValue.serverTimestamp();
    await _db.collection('kuris').add(data);
  }

  Future<void> updateKuri({
    required String id,
    required KuriModel updatedKuri,
    required KuriModel oldKuri,
    required String userId,
    required String userName,
  }) async {
    final db = FirebaseFirestore.instance;
    final batch = db.batch();

    // 1. Identify specific changes for the log
    Map<String, dynamic> oldData = oldKuri.toMap();
    Map<String, dynamic> newData = updatedKuri.toMap();
    Map<String, dynamic> changeLog = {};

    newData.forEach((key, value) {
      if (oldData[key].toString() != value.toString()) {
        changeLog[key] = {"from": oldData[key], "to": value};
      }
    });

    // 2. Perform the Update
    batch.update(db.collection('kuris').doc(id), newData);

    // 3. Create Audit Log (Only if changes actually happened)
    if (changeLog.isNotEmpty) {
      batch.set(db.collection('kuri_logs').doc(), {
        'kuriId': id,
        'kuriName': updatedKuri.name,
        'action': 'UPDATE',
        'changedBy': userId,
        'changedByName': userName,
        'timestamp': FieldValue.serverTimestamp(),
        'details': changeLog,
      });
    }

    await batch.commit();
    notifyListeners();
  }

  Future<void> deleteKuri(String id) async {
    try {
      // 1. Reference the original document using the correct variable name (_db)
      final docRef = _db.collection('kuris').doc(id);
      final snapshot = await docRef.get();

      if (snapshot.exists) {
        // Map the data and prepare for migration
        final Map<String, dynamic> data = snapshot.data() as Map<String, dynamic>;

        // 2. Add metadata to track when and why it was moved
        data['deletedAt'] = FieldValue.serverTimestamp();
        data['originalId'] = id;
        data['status'] = 'archived';

        // 3. Save to 'deleted_kuris' collection
        // We use .doc(id).set() to keep the same Document ID for easier restoration later
        await _db.collection('deleted_kuris').doc(id).set(data);

        // 4. Finally, remove from the active collection
        await docRef.delete();

        notifyListeners(); // Notify listeners of the change
      }
    } catch (e) {
      debugPrint("Error during Kuri deletion: $e");
      rethrow;
    }
  }
  // Future<void> _generatePDF(
  //     List<DocumentSnapshot> members,
  //     List<DocumentSnapshot> allPayments,
  //     Map<String, Map<String, dynamic>> schemesMap) async {
  //   final pdf = pw.Document();
  //   final currencyFormat = NumberFormat.currency(locale: 'en_IN', symbol: 'Rs.', decimalDigits: 0);
  //
  //   pdf.addPage(
  //     pw.MultiPage(
  //       pageFormat: PdfPageFormat.a4.landscape,
  //       margin: const pw.EdgeInsets.all(20),
  //       build: (pw.Context context) {
  //         return [
  //           pw.Header(
  //             level: 0,
  //             child: pw.Text("Kuri Collection Report - ${monthKey.replaceAll('_', ' ')}",
  //                 style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
  //           ),
  //           pw.SizedBox(height: 10),
  //           pw.Table(
  //             border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
  //             columnWidths: {
  //               0: const pw.FixedColumnWidth(35),  // K.No
  //               1: const pw.FixedColumnWidth(110), // Name
  //               2: const pw.FixedColumnWidth(80),  // Phone
  //               3: const pw.FixedColumnWidth(70),  // Scheme
  //               4: const pw.FixedColumnWidth(60),  // Monthly
  //               5: const pw.FixedColumnWidth(160), // Payment Details / Winner Column
  //               6: const pw.FixedColumnWidth(65),  // Total Paid
  //               7: const pw.FixedColumnWidth(65),  // Balance
  //             },
  //             children: [
  //               // Header Row
  //               pw.TableRow(
  //                 decoration: const pw.BoxDecoration(color: PdfColors.grey200),
  //                 children: [
  //                   _pdfHeaderCell("K.NO"),
  //                   _pdfHeaderCell("NAME"),
  //                   _pdfHeaderCell("PHONE"),
  //                   _pdfHeaderCell("SCHEME"),
  //                   _pdfHeaderCell("MONTHLY"),
  //                   _pdfHeaderCell("PAYMENT DETAILS / WINNER STATUS"),
  //                   _pdfHeaderCell("TOT PAID"),
  //                   _pdfHeaderCell("BALANCE"),
  //                 ],
  //               ),
  //
  //               ...members.map((m) {
  //                 final d = m.data() as Map<String, dynamic>;
  //                 final scheme = schemesMap[d['schemeId']] ?? {};
  //                 final winners = scheme['winners'] as Map<String, dynamic>? ?? {};
  //
  //                 // Identify Winner Status
  //                 String? wonMonthKey;
  //                 winners.forEach((key, value) { if (value == m.id) wonMonthKey = key; });
  //
  //                 bool isCurrentMonthWinner = wonMonthKey == monthKey;
  //                 bool hasWonInPast = false;
  //
  //                 if (wonMonthKey != null && !isCurrentMonthWinner) {
  //                   try {
  //                     // Using your specific monthKey format (adjust if different)
  //                     DateTime winDate = DateFormat('MMM_yyyy').parse(wonMonthKey!);
  //                     if (winDate.isBefore(selectedMonth)) hasWonInPast = true;
  //                   } catch (e) { hasWonInPast = true; }
  //                 }
  //
  //                 // FIXED Payment Lookup to avoid DartError
  //                 final paymentMatch = allPayments.where((p) {
  //                   final pData = p.data() as Map<String, dynamic>;
  //                   return pData['memberId'] == m.id && pData['monthKey'] == monthKey;
  //                 }).toList();
  //                 final currentMonthPayment = paymentMatch.isNotEmpty ? paymentMatch.first : null;
  //
  //                 // Calculations
  //                 double monthlyAmount = _parseNum(scheme['monthlyAmount']);
  //                 int totalInst = int.tryParse(scheme['totalInstallments']?.toString() ?? "10") ?? 10;
  //
  //                 int expectedInst = totalInst;
  //                 if (wonMonthKey != null) {
  //                   expectedInst = winners.keys.toList().indexOf(wonMonthKey!) + 1;
  //                 }
  //
  //                 final mPayments = allPayments.where((p) => (p.data() as Map<String, dynamic>)['memberId'] == m.id);
  //                 double totalPaid = mPayments.fold(0.0, (sum, p) => sum + _parseNum((p.data() as Map<String, dynamic>)['amount']));
  //                 double balance = (monthlyAmount * expectedInst) - totalPaid;
  //                 if (balance < 0) balance = 0;
  //
  //                 // --- PDF SINGLE COLUMN LOGIC ---
  //                 String detailText = "";
  //                 PdfColor detailColor = PdfColors.black;
  //
  //                 if (hasWonInPast) {
  //                   int winIdx = winners.keys.toList().indexOf(wonMonthKey!) + 1;
  //                   detailText = "$winIdx Month Winner";
  //                   detailColor = PdfColors.blue700;
  //                 } else if (currentMonthPayment != null) {
  //                   final pData = currentMonthPayment.data() as Map<String, dynamic>;
  //                   String pDate = pData['paidDate'] != null
  //                       ? DateFormat('dd/MM/yy').format((pData['paidDate'] as Timestamp).toDate()) : "-";
  //                   String pMode = pData['mode'] ?? "Cash";
  //                   String pCollector = pData['collectedBy'] ?? "-";
  //                   detailText = "Date: $pDate | Mode: $pMode | By: $pCollector";
  //                   detailColor = PdfColors.green800;
  //                 } else {
  //                   detailText = "NOT PAID";
  //                   detailColor = PdfColors.red700;
  //                 }
  //
  //                 return pw.TableRow(
  //                   children: [
  //                     _pdfDataCell(d['kuriNumber']?.toString() ?? "-", align: pw.TextAlign.center),
  //                     _pdfDataCell(d['name'].toString().toUpperCase()),
  //                     _pdfDataCell(d['phone'] ?? "-"),
  //                     _pdfDataCell(scheme['schemeName']?.toString().toUpperCase() ?? "-"),
  //                     _pdfDataCell(currencyFormat.format(monthlyAmount)),
  //                     _pdfDataCell(detailText, color: detailColor, fontSize: 8),
  //                     _pdfDataCell(currencyFormat.format(totalPaid)),
  //                     _pdfDataCell(currencyFormat.format(balance)),
  //                   ],
  //                 );
  //               }).toList(),
  //             ],
  //           ),
  //         ];
  //       },
  //     ),
  //   );
  //   await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  // }
}