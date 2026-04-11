import 'package:crm/features/order_import.dart';
import 'package:dio/dio.dart';
import 'package:google_sign_in/google_sign_in.dart';

class GoogleSheetsLoadResult {
  const GoogleSheetsLoadResult({
    required this.payload,
    this.errorMessage,
  });

  final String? payload;
  final String? errorMessage;

  bool get isSuccess => payload != null && payload!.trim().isNotEmpty;
}

class GoogleSheetsAuthLoader {
  GoogleSheetsAuthLoader._();

  static final GoogleSheetsAuthLoader instance = GoogleSheetsAuthLoader._();

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: const [
      'email',
      'https://www.googleapis.com/auth/spreadsheets.readonly',
      'https://www.googleapis.com/auth/drive.readonly',
    ],
  );

  Future<GoogleSheetsLoadResult> loadViaGoogleAuth(List<Uri> uris) async {
    final account = await _ensureSignedIn();
    if (account == null) {
      return const GoogleSheetsLoadResult(
        payload: null,
        errorMessage: 'Вход через Google отменён. Импорт прерван.',
      );
    }

    final auth = await account.authentication;
    final token = auth.accessToken;
    if (token == null || token.isEmpty) {
      return const GoogleSheetsLoadResult(
        payload: null,
        errorMessage: 'Google не выдал токен доступа. Повторите вход.',
      );
    }

    for (final linkUri in uris) {
      try {
        final response = await Dio().getUri<String>(
          linkUri,
          options: Options(
            responseType: ResponseType.plain,
            followRedirects: true,
            validateStatus: (status) => status != null && status >= 200 && status < 400,
            headers: {
              'Authorization': 'Bearer $token',
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124 Safari/537.36',
              'Accept':
                  'text/csv,text/tab-separated-values,text/plain,application/json,text/html;q=0.9,*/*;q=0.8',
            },
          ),
        );
        final body = response.data?.trim();
        final normalizedBody =
            body == null ? null : normalizeImportedTablePayload(body);
        if (normalizedBody != null && normalizedBody.isNotEmpty) {
          return GoogleSheetsLoadResult(payload: normalizedBody);
        }
      } on DioException {
        continue;
      }
    }

    return const GoogleSheetsLoadResult(
      payload: null,
      errorMessage:
          'После входа через Google таблица всё равно недоступна. Проверьте, что выбранный аккаунт имеет доступ к файлу.',
    );
  }

  Future<GoogleSignInAccount?> _ensureSignedIn() async {
    GoogleSignInAccount? account = _googleSignIn.currentUser;
    account ??= await _googleSignIn.signInSilently();
    account ??= await _googleSignIn.signIn();
    return account;
  }
}
