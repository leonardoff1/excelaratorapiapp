import 'package:json_annotation/json_annotation.dart';

part 'user_services_model.g.dart';

@JsonSerializable(explicitToJson: true)
class UserServicesModel {
  final int id;
  final String? email;
  final String? username;
  final String? phonenumber;

  UserServicesModel({
    required this.id,
    required this.email,
    required this.username,
    required this.phonenumber,
  });

  factory UserServicesModel.fromJson(Map<String, dynamic> json) =>
      _$UserServicesModelFromJson(json);

  Map<String, dynamic> toJson() => _$UserServicesModelToJson(this);
}
