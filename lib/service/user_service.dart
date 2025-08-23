import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:excelaratorapi/model/user_services_model.dart';
import 'package:excelaratorapi/service/user_manager.dart';

class UserService {
  String get _baseUrl {
    if (UserManager.currentUser?.userURL == null) {
      throw Exception(
        "User URL is null! Ensure user is initialized before calling this service.",
      );
    }
    return "${UserManager.currentUser!.userURL}/api/users";
  }

  Future<List<UserServicesModel>> fetchUsers() async {
    final response = await http.get(Uri.parse(_baseUrl));

    // print(response.body);
    if (response.statusCode == 200) {
      List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => UserServicesModel.fromJson(json)).toList();
    } else {
      throw Exception("Failed to load users");
    }
  }
}
