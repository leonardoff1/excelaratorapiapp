import 'package:excelaratorapi/model/user_model.dart';

class UserManager {
  static UserModel? currentUser; // ✅ Make it static

  /// **Initialize and Load User Data**
  static Future<void> initializeUser() async {
    currentUser = UserModel();
    await currentUser!.fetchUserData(); // Load user from Firestore & Hive

    print('Current UR: ${currentUser!.userURL}');
  }
}
