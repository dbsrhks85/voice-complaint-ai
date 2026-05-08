class AppUser {
  const AppUser({
    required this.id,
    required this.kakaoId,
    required this.nickname,
    required this.role,
  });

  final int id;
  final String kakaoId;
  final String nickname;
  final String role;

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: int.parse(json['id'].toString()),
      kakaoId: json['kakao_id']?.toString() ?? '',
      nickname: json['nickname']?.toString() ?? '사용자',
      role: json['role']?.toString() ?? 'user',
    );
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'kakao_id': kakaoId, 'nickname': nickname, 'role': role};
  }
}
