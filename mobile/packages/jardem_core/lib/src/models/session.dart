import 'json.dart';

class User {
  const User({required this.id, this.role = 'citizen', this.name = '', this.phone = '', this.unitId});

  factory User.fromJson(Json j) => User(
    id: str(j, 'id'),
    role: str(j, 'role', 'citizen'),
    name: str(j, 'name'),
    phone: str(j, 'phone'),
    unitId: strOrNull(j, 'unit_id'),
  );

  final String id;

  /// citizen / responder / dispatcher.
  final String role;
  final String name;
  final String phone;
  final String? unitId;

  Json toJson() => {'id': id, 'role': role, 'name': name, 'phone': phone, 'unit_id': unitId};
}

class Session {
  const Session({required this.token, required this.user});

  factory Session.fromJson(Json j) => Session(token: str(j, 'token'), user: User.fromJson(asJson(j['user'])));

  final String token;
  final User user;

  bool get isValid => token.isNotEmpty && user.id.isNotEmpty;

  Json toJson() => {'token': token, 'user': user.toJson()};
}
