import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}

class MockGoTrueClient extends Mock implements GoTrueClient {}

class MockSupabaseStorageClient extends Mock
    implements SupabaseStorageClient {}

class MockStorageFileApi extends Mock implements StorageFileApi {}

class MockFunctionsClient extends Mock implements FunctionsClient {}

class MockAuthSession extends Mock implements Session {}

class MockUser extends Mock implements User {}

void registerFallbacks() {
  registerFallbackValue(MockUser());
  registerFallbackValue(MockAuthSession());
  registerFallbackValue(MockStorageFileApi());
  registerFallbackValue(MockFunctionsClient());
}

MockSupabaseClient createMockSupabaseClient() {
  final client = MockSupabaseClient();
  final auth = MockGoTrueClient();
  final storage = MockSupabaseStorageClient();
  final functions = MockFunctionsClient();

  when(() => client.auth).thenReturn(auth);
  when(() => client.storage).thenReturn(storage);
  when(() => client.functions).thenReturn(functions);

  return client;
}

void stubAuthUser(MockGoTrueClient auth,
    {String uid = '00000000-0000-4000-a000-000000000001',
    String email = 'test@turno.app'}) {
  final user = MockUser();
  final session = MockAuthSession();
  when(() => user.id).thenReturn(uid);
  when(() => user.email).thenReturn(email);
  when(() => auth.currentUser).thenReturn(user);
  when(() => auth.currentSession).thenReturn(session);
}
