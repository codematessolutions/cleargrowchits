import 'package:cloud_firestore/cloud_firestore.dart';

class KuriModel {
  String? id;
  final String name;
  final dynamic startMonth; // Stored as Timestamp
  final dynamic endMonth;   // NEW: Stored as Timestamp
  final int totalMonths;
  final double monthlyAmount;
  final double totalAmount;
  final int kuriDate;

  final String addedById;
  final String addedByName;
  final String addedByPhone;
  final String userRole;
  final DateTime? createdAt;

  KuriModel({
    this.id,
    required this.name,
    required this.startMonth,
    required this.endMonth,
    required this.totalMonths,
    required this.monthlyAmount,
    required this.totalAmount,
    required this.kuriDate,
    required this.addedById,
    required this.addedByName,
    required this.addedByPhone,
    required this.userRole,
    this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      // Ensure both are saved as native Firestore Timestamps
      'startMonth': startMonth is DateTime ? Timestamp.fromDate(startMonth) : startMonth,
      'endMonth': endMonth is DateTime ? Timestamp.fromDate(endMonth) : endMonth,
      'totalMonths': totalMonths,
      'monthlyAmount': monthlyAmount,
      'totalAmount': totalAmount,
      'kuriDate': kuriDate,
      'addedById': addedById,
      'addedByName': addedByName,
      'addedByPhone': addedByPhone,
      'createdAt': createdAt ?? FieldValue.serverTimestamp(),
    };
  }

  factory KuriModel.fromFirestore(DocumentSnapshot doc) {
    Map data = doc.data() as Map;
    return KuriModel(
      id: doc.id,
      name: data['name'] ?? '',
      startMonth: data['startMonth'],
      endMonth: data['endMonth'],
      totalMonths: data['totalMonths'] ?? 0,
      monthlyAmount: (data['monthlyAmount'] ?? 0).toDouble(),
      totalAmount: (data['totalAmount'] ?? 0).toDouble(),
      kuriDate: data['kuriDate'] ?? 10,
      addedById: data['addedById'] ?? '',
      addedByName: data['addedByName'] ?? '',
      addedByPhone: data['addedByPhone'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      userRole:  data['userRole'] ?? '',
    );
  }
}