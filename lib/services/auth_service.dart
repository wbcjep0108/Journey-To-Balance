import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

abstract class AuthService {
  factory AuthService() = FirebaseAuthService;

  User? get currentUser;
  bool get usesPasswordProvider;
  bool get usesGoogleProvider;

  Future<User?> signInWithGoogle();
  Future<UserCredential> signInWithEmail(String email, String password);
  Future<UserCredential> createAccount(String email, String password);
  Future<void> sendPasswordResetEmail(String email);
  Future<void> resendVerificationEmail();
  Future<void> reauthenticateWithPassword(String password);
  Future<void> reauthenticateWithGoogle();
  Future<void> signOut();
}

class FirebaseAuthService implements AuthService {
  FirebaseAuthService({FirebaseAuth? auth, GoogleSignIn? googleSignIn})
    : _auth = auth ?? FirebaseAuth.instance,
      _googleSignIn = googleSignIn ?? GoogleSignIn();

  final FirebaseAuth _auth;
  final GoogleSignIn _googleSignIn;

  @override
  User? get currentUser => _auth.currentUser;

  @override
  bool get usesPasswordProvider => _hasProvider('password');

  @override
  bool get usesGoogleProvider => _hasProvider('google.com');

  bool _hasProvider(String providerId) {
    return currentUser?.providerData.any(
          (provider) => provider.providerId == providerId,
        ) ==
        true;
  }

  Future<AuthCredential?> _googleCredential() async {
    final googleUser = await _googleSignIn.signIn();
    if (googleUser == null) return null;

    final googleAuth = await googleUser.authentication;
    return GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
  }

  @override
  Future<User?> signInWithGoogle() async {
    final credential = await _googleCredential();
    if (credential == null) return null;
    return (await _auth.signInWithCredential(credential)).user;
  }

  @override
  Future<UserCredential> signInWithEmail(String email, String password) {
    return _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  @override
  Future<UserCredential> createAccount(String email, String password) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    await credential.user?.sendEmailVerification();
    return credential;
  }

  @override
  Future<void> sendPasswordResetEmail(String email) {
    return _auth.sendPasswordResetEmail(email: email);
  }

  @override
  Future<void> resendVerificationEmail() async {
    final user = currentUser;
    if (user != null && !user.emailVerified) {
      await user.sendEmailVerification();
    }
  }

  @override
  Future<void> reauthenticateWithPassword(String password) async {
    final user = currentUser;
    final email = user?.email;
    if (user == null || email == null || !usesPasswordProvider) {
      throw FirebaseAuthException(code: 'operation-not-allowed');
    }
    await user.reauthenticateWithCredential(
      EmailAuthProvider.credential(email: email, password: password),
    );
  }

  @override
  Future<void> reauthenticateWithGoogle() async {
    final user = currentUser;
    if (user == null || !usesGoogleProvider) {
      throw FirebaseAuthException(code: 'operation-not-allowed');
    }
    final credential = await _googleCredential();
    if (credential == null) {
      throw FirebaseAuthException(code: 'cancelled-popup-request');
    }
    await user.reauthenticateWithCredential(credential);
  }

  @override
  Future<void> signOut() async {
    if (usesGoogleProvider) {
      try {
        await _googleSignIn.signOut();
      } catch (_) {
        // Firebase remains the source of truth for the signed-in session.
      }
    }
    await _auth.signOut();
  }
}

String friendlyAuthError(Object error) {
  if (error is! FirebaseAuthException) {
    return 'Something went wrong. Please try again.';
  }

  switch (error.code) {
    case 'invalid-credential':
    case 'wrong-password':
    case 'user-not-found':
      return 'Incorrect email or password';
    case 'email-already-in-use':
      return 'This email is already registered. Try logging in, or use Continue with Google.';
    case 'weak-password':
      return 'Use a stronger password with at least 8 characters.';
    case 'invalid-email':
      return 'Enter a valid email address.';
    case 'too-many-requests':
      return 'Too many attempts. Please try again later.';
    case 'network-request-failed':
    case 'network-error':
      return 'No internet connection.';
    default:
      return 'Something went wrong. Please try again.';
  }
}
