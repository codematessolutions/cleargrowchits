import 'dart:ui';

import 'package:flutter/material.dart';

List<DataColumn> buildColumns() {
  const style = TextStyle(fontWeight: FontWeight.w900, fontSize: 11, color: Color(0xFF64748B));
  return const [
    DataColumn(label: Text("#", style: style)),
    DataColumn(label: Text("MEMBER", style: style)),
    DataColumn(label: Text("WIN", style: style)),
    DataColumn(label: Text("STATUS", style: style)),
    DataColumn(label: Text("MONTHLY", style: style)),
    DataColumn(label: Text("INSTALLMENT", style: style)),
    DataColumn(label: Text("TOTAL PAID", style: style)),
    DataColumn(label: Text("TOTAL BALANCE", style: style)),
    DataColumn(label: Text("ACTION", style: style)),
  ];
}