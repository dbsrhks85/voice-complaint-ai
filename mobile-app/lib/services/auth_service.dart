import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';

import '../models/auth_session.dart';

class AuthService {
  AuthService({required String serverUrl})
    : _dio = Dio(BaseOptions(baseUrl: serverUrl));

  static const _accessTokenKey = 'auth.accessToken';
  static const _refreshTokenKey = 'auth.refreshToken';

  final Dio _dio;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  AuthSession? _session;

  AuthSession? get session => _session;
  String? get accessToken => _session?.accessToken;
  String? get refreshToken => _session?.refreshToken;

  Future<AuthSession> loginWithKakao() async {
    final token = await _loginToKakao();
    final scopedAccessToken = await _requestNicknameScopeIfNeeded();

    final response = await _dio.post(
      '/auth/kakao',
      data: FormData.fromMap({
        'kakao_access_token': scopedAccessToken ?? token.accessToken,
      }),
      options: Options(receiveTimeout: const Duration(seconds: 15)),
    );
    final session = AuthSession.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
    await _saveSession(session);
    return session;
  }

  Future<AuthSession?> restoreSession() async {
    final storedRefreshToken = await _storage.read(key: _refreshTokenKey);
    if (storedRefreshToken == null || storedRefreshToken.isEmpty) return null;
    return refreshSession(refreshTokenOverride: storedRefreshToken);
  }

  Future<AuthSession?> refreshSession({String? refreshTokenOverride}) async {
    final token = refreshTokenOverride ?? _session?.refreshToken;
    if (token == null || token.isEmpty) return null;

    try {
      final response = await _dio.post(
        '/auth/refresh',
        data: FormData.fromMap({'refresh_token': token}),
        options: Options(receiveTimeout: const Duration(seconds: 15)),
      );
      final session = AuthSession.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
      await _saveSession(session);
      return session;
    } catch (e) {
      debugPrint('세션 복원/갱신 실패: $e');
      await clearLocalSession();
      return null;
    }
  }

  Future<void> logout() async {
    final access = _session?.accessToken;
    final refresh = _session?.refreshToken;

    if (access != null && access.isNotEmpty) {
      try {
        await _dio.post(
          '/auth/logout',
          data: FormData.fromMap({'refresh_token': refresh ?? ''}),
          options: Options(
            headers: {'Authorization': 'Bearer $access'},
            receiveTimeout: const Duration(seconds: 10),
          ),
        );
      } catch (e) {
        debugPrint('서버 로그아웃 실패: $e');
      }
    }

    try {
      await UserApi.instance.logout();
    } catch (e) {
      debugPrint('카카오 로그아웃 실패: $e');
    }

    await clearLocalSession();
  }

  Future<void> clearLocalSession() async {
    _session = null;
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
  }

  Future<void> _saveSession(AuthSession session) async {
    _session = session;
    await _storage.write(key: _accessTokenKey, value: session.accessToken);
    await _storage.write(key: _refreshTokenKey, value: session.refreshToken);
  }

  Future<dynamic> _loginToKakao() async {
    if (await isKakaoTalkInstalled()) {
      return UserApi.instance.loginWithKakaoTalk();
    }
    return UserApi.instance.loginWithKakaoAccount();
  }

  Future<String?> _requestNicknameScopeIfNeeded() async {
    try {
      final user = await UserApi.instance.me(
        properties: ['kakao_account.profile'],
      );
      final nickname =
          user.kakaoAccount?.profile?.nickname?.trim() ??
          user.properties?['nickname']?.trim();
      final needsNicknameConsent =
          user.kakaoAccount?.profileNicknameNeedsAgreement == true ||
          user.kakaoAccount?.profileNeedsAgreement == true;

      if ((nickname == null || nickname.isEmpty) && needsNicknameConsent) {
        final token = await UserApi.instance.loginWithNewScopes([
          'profile_nickname',
        ]);
        return token.accessToken;
      }
    } catch (e) {
      debugPrint('카카오 닉네임 동의 확인 실패: $e');
    }
    return null;
  }
}
