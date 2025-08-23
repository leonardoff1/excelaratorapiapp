import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:excelaratorapi/service/company_service.dart';

class UserModel extends ChangeNotifier {
  String? firstName;
  String? lastName;
  String? email;
  String? companyId;
  String? userURL;
  bool? isPreparer;
  String? subscriptionPlan;
  DateTime? trialEndDate;
  bool? isAdmin;
  bool? admin;

  bool get isTrialActive => trialEndDate?.isAfter(DateTime.now()) ?? false;

  static const String userBoxName = 'user';

  /// **Constructor**
  UserModel({
    this.firstName,
    this.lastName,
    this.email,
    this.companyId,
    this.userURL,
    this.isPreparer,
    this.subscriptionPlan,
    this.trialEndDate,
    this.isAdmin,
    this.admin,
  });

  /// **Factory Constructor to Deserialize JSON → `UserModel`**
  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      firstName: json['firstName'],
      lastName: json['lastName'],
      email: json['email'],
      companyId: json['companyId'],
      userURL: json['userURL'],
      isPreparer: json['isPreparer'],
      subscriptionPlan: json['subscriptionPlan'],
      trialEndDate:
          json['trialEndDate'] != null
              ? (json['trialEndDate'] is Timestamp
                  ? json['trialEndDate']
                      .toDate() // Firestore Timestamp conversion
                  : DateTime.tryParse(
                    json['trialEndDate'],
                  )) // String conversion
              : null,
    );
  }

  /// **Convert `UserModel` → JSON**
  Map<String, dynamic> toJson() {
    return {
      'firstName': firstName,
      'lastName': lastName,
      'email': email,
      'companyId': companyId,
      'userURL': userURL,
      'isPreparer': isPreparer,
      'subscriptionPlan': subscriptionPlan,
      'trialEndDate':
          trialEndDate?.toIso8601String(), // Convert DateTime to String
    };
  }

  /// **Set user data and notify listeners**
  void setUser(Map<String, dynamic> userData) {
    firstName = userData['firstName'];
    lastName = userData['lastName'];
    email = userData['email'];
    companyId = userData['companyId'];
    userURL = userData['userURL'];
    isPreparer = userData['isPreparer'];
    subscriptionPlan = userData['subscriptionPlan'];
    isAdmin = userData['isAdmin'];
    admin = userData['admin'];
    trialEndDate =
        userData['trialEndDate'] != null
            ? (userData['trialEndDate'] is Timestamp
                ? userData['trialEndDate'].toDate()
                : DateTime.tryParse(userData['trialEndDate']))
            : null;
    notifyListeners();
  }

  /// **Fetch User Data from Firestore & Store in Hive**
  Future<void> fetchUserData() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      var userDataSnapshot =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();

      if (userDataSnapshot.exists) {
        // Convert Firestore data into a `UserModel`
        setUser(userDataSnapshot.data()!);
        userURL = await CompanyService().getCompanyURLByCompanyId(companyId!);
        print('🌐 User Company URL: $userURL');
      }
    }
  }
}
