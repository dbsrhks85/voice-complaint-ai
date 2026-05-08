import 'package:dio/dio.dart';

import 'auth_service.dart';

class ApiClient {
  ApiClient({required String baseUrl, required AuthService authService})
    : _authService = authService,
      dio = Dio(BaseOptions(baseUrl: baseUrl)) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final token = _authService.accessToken;
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (error, handler) async {
          final statusCode = error.response?.statusCode;
          final alreadyRetried =
              error.requestOptions.extra['authRetry'] == true;
          if (statusCode == 401 && !alreadyRetried) {
            final session = await _authService.refreshSession();
            if (session != null) {
              final retryOptions = error.requestOptions;
              retryOptions.extra['authRetry'] = true;
              retryOptions.headers['Authorization'] =
                  'Bearer ${session.accessToken}';
              try {
                final response = await dio.fetch(retryOptions);
                handler.resolve(response);
                return;
              } catch (_) {
                // Fall through to the original error.
              }
            }
          }
          handler.next(error);
        },
      ),
    );
  }

  final AuthService _authService;
  final Dio dio;
}
