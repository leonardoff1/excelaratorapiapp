// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user_services_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

UserServicesModel _$UserServicesModelFromJson(Map<String, dynamic> json) =>
    UserServicesModel(
      id: (json['id'] as num).toInt(),
      email: json['email'] as String?,
      username: json['username'] as String?,
      phonenumber: json['phonenumber'] as String?,
    );

Map<String, dynamic> _$UserServicesModelToJson(UserServicesModel instance) =>
    <String, dynamic>{
      'id': instance.id,
      'email': instance.email,
      'username': instance.username,
      'phonenumber': instance.phonenumber,
    };
