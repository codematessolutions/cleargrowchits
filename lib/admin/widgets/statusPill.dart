import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

Widget statusPill(bool isPaid) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: isPaid ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(isPaid ? "PAID" : "PENDING",
        style: TextStyle(
            color: isPaid ? Colors.green.shade700 : Colors.red.shade700,
            fontSize: 9,
            fontWeight: FontWeight.bold)),
  );
}