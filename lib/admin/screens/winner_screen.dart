import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class WinnerScreen extends StatelessWidget {
  const WinnerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text("KURI WINNER HISTORY",
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1,color: Colors.white)),
        backgroundColor: const Color(0xFF1E3A8A),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _getWinners(), // Call the optimized fetcher
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text("Error loading winners: ${snapshot.error}"));
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text("No winners found."));
          }

          final winners = snapshot.data!;

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: winners.length,
            itemBuilder: (context, index) {
              final win = winners[index];

              // Formatting the winMonthKey (e.g., "2025_06" -> "Jun 2025")
              String formattedMonth = win['winMonthKey']?.toString().replaceAll('_', '/') ?? "-";

              return Card(
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey.shade200),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFE0E7FF),
                    child: Icon(Icons.emoji_events, color: Color(0xFF1E3A8A), size: 20),
                  ),
                  title: Text(
                    win['memberName']?.toString().toUpperCase() ?? "UNKNOWN",
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Text("Month: $formattedMonth", style: const TextStyle(fontSize: 12)),
                      Text("Processed by: ${win['processedBy']}",
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                    ],
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text("WINNER",
                          style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 10)),
                      if (win['loggedAt'] != null)
                        Text(
                          DateFormat('dd MMM').format((win['loggedAt'] as Timestamp).toDate()),
                          style: const TextStyle(fontSize: 10, color: Colors.grey),
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
  Future<List<Map<String, dynamic>>> _getWinners() async {
    final querySnapshot = await FirebaseFirestore.instance
        .collection('winner_logs')
        .orderBy('loggedAt', descending: true) // Most recent winners first
        .limit(25)
        .get(const GetOptions(source: Source.serverAndCache));

    return querySnapshot.docs.map((doc) => doc.data()).toList();
  }
}