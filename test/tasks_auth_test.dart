import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:kalendarz_5min/tasks.dart';

class _SignInPlatform extends GoogleSignInPlatform {
  final requests = <AuthorizationRequestDetails>[];
  int signIns = 0;
  int lightweightSignIns = 0;
  bool authorized = true;

  @override
  bool supportsAuthenticate() => true;

  @override
  bool authorizationRequiresUserInteraction() => true;

  @override
  Future<ServerAuthorizationTokenData?> serverAuthorizationTokensForScopes(
    ServerAuthorizationTokensForScopesParameters params,
  ) async => throw UnimplementedError();

  @override
  Future<void> disconnect(DisconnectParams params) async {}

  @override
  Future<void> init(InitParameters params) async {}

  @override
  Future<AuthenticationResults> authenticate(
    AuthenticateParameters params,
  ) async {
    signIns++;
    return const AuthenticationResults(
      user: GoogleSignInUserData(id: 'account-id', email: 'test@example.com'),
      authenticationTokens: AuthenticationTokenData(idToken: 'id-token'),
    );
  }

  @override
  Future<AuthenticationResults?> attemptLightweightAuthentication(
    AttemptLightweightAuthenticationParameters params,
  ) async {
    lightweightSignIns++;
    throw StateError('Background requests must never invoke sign-in UI');
  }

  @override
  Future<ClientAuthorizationTokenData?> clientAuthorizationTokensForScopes(
    ClientAuthorizationTokensForScopesParameters params,
  ) async {
    requests.add(params.request);
    return authorized
        ? const ClientAuthorizationTokenData(accessToken: 'access-token')
        : null;
  }

  @override
  Future<void> signOut(SignOutParams params) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('calendar/android');
  late _SignInPlatform platform;
  late GoogleSignInPlatform original;
  Map<String, String>? account;

  setUp(() {
    original = GoogleSignInPlatform.instance;
    platform = _SignInPlatform();
    GoogleSignInPlatform.instance = platform;
    account = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'taskClientId':
              return 'test-client.apps.googleusercontent.com';
            case 'taskAccount':
              return account;
            case 'setTaskAccount':
              account = Map<String, String>.from(call.arguments as Map);
              return null;
            case 'clearTaskAccount':
              account = null;
              return null;
          }
          return null;
        });
  });

  tearDown(() {
    GoogleSignInPlatform.instance = original;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'startup without a stored account never launches authentication',
    () async {
      final auth = TasksAuth();
      await expectLater(auth.token(), throwsA(isA<TasksFailure>()));
      expect(platform.signIns, 0);
      expect(platform.lightweightSignIns, 0);
      expect(platform.requests, isEmpty);
    },
  );

  test('stored account restores Tasks access without sign-in UI', () async {
    account = {'id': 'saved-id', 'email': 'saved@example.com'};
    final auth = TasksAuth();
    expect(await auth.token(), 'access-token');
    expect(auth.email, 'saved@example.com');
    final request = platform.requests.single;
    expect(request.email, 'saved@example.com');
    expect(request.userId, 'saved-id');
    expect(request.promptIfUnauthorized, isFalse);
    expect(platform.signIns, 0);
    expect(platform.lightweightSignIns, 0);
  });

  test(
    'missing consent leaves background authorization silent on every retry',
    () async {
      account = {'id': 'saved-id', 'email': 'saved@example.com'};
      platform.authorized = false;
      final auth = TasksAuth();
      for (var attempt = 0; attempt < 3; attempt++) {
        await expectLater(auth.token(), throwsA(isA<TasksFailure>()));
      }
      expect(
        platform.requests.every((request) => !request.promptIfUnauthorized),
        isTrue,
      );
      expect(platform.signIns, 0);
      expect(platform.lightweightSignIns, 0);
    },
  );

  test('explicit connect persists the account across app restarts and disconnect clears it', () async {
    final auth = TasksAuth();
    await auth.connect();
    expect(platform.signIns, 1);
    expect(account, {'id': 'account-id', 'email': 'test@example.com'});
    expect(platform.requests.single.promptIfUnauthorized, isTrue);
    platform.requests.clear();
    final restarted = TasksAuth();
    expect(await restarted.token(), 'access-token');
    expect(platform.signIns, 1);
    expect(platform.lightweightSignIns, 0);
    expect(platform.requests.single.promptIfUnauthorized, isFalse);
    await restarted.disconnect();
    expect(account, isNull);
    expect(restarted.email, isNull);
    await expectLater(TasksAuth().token(), throwsA(isA<TasksFailure>()));
    expect(platform.signIns, 1);
  });
}
