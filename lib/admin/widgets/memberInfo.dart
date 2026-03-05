import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

Widget memberInfo(String name, dynamic phone) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Text(name.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
      Text(phone?.toString() ?? "No Phone", style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
    ],
  );
}