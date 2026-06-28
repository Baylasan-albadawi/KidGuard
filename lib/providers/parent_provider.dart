// lib/providers/parent_provider.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

class ParentProvider extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseDatabase _db = FirebaseDatabase.instance;

  User? _currentUser;
  bool _loading = false;
  String? _error;

  User? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;
  bool get loading => _loading;
  String? get error => _error;

  ParentProvider() {
    // Initialize with current user if already authenticated
    _currentUser = _auth.currentUser;
    // Listen to future auth state changes
    _auth.authStateChanges().listen((user) {
      _currentUser = user;
      notifyListeners();
    });
  }

  /// Sign up a new parent with email and password
  Future<bool> signUp(String email, String password, String parentName) async {
    try {
      _loading = true;
      _error = null;
      notifyListeners();

      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      await _db.ref('parents/${userCredential.user!.uid}').set({
        'uid': userCredential.user!.uid,
        'email': email,
        'parentName': parentName,
        'createdAt': DateTime.now().toIso8601String(),
        'children': {},
      });

      _currentUser = userCredential.user;
      _loading = false;
      notifyListeners();
      return true;
    } on FirebaseAuthException catch (e) {
      _error = e.message ?? 'Sign up failed';
      _loading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> login(String email, String password) async {
    try {
      _loading = true;
      _error = null;
      notifyListeners();

      final userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      _currentUser = userCredential.user;
      _loading = false;
      notifyListeners();
      return true;
    } on FirebaseAuthException catch (e) {
      _error = e.message ?? 'Login failed';
      _loading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    try {
      await _auth.signOut();
      _currentUser = null;
      _error = null;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<bool> deleteAccount(String password) async {
    try {
      _loading = true;
      _error = null;
      notifyListeners();

      if (_currentUser == null) {
        _error = 'No user logged in';
        _loading = false;
        notifyListeners();
        return false;
      }

      final email = _currentUser!.email;
      if (email != null) {
        await _currentUser!.reauthenticateWithCredential(
          EmailAuthProvider.credential(email: email, password: password),
        );
      }

      final parentRef = _db.ref('parents/${_currentUser!.uid}');
      await parentRef.remove();

      await _currentUser!.delete();

      _currentUser = null;
      _loading = false;
      notifyListeners();
      return true;
    } on FirebaseAuthException catch (e) {
      _error = e.message ?? 'Account deletion failed';
      _loading = false;
      notifyListeners();
      return false;
    }
  }

  Future<Map<String, dynamic>?> getParentProfile() async {
    try {
      if (_currentUser == null) return null;

      final snapshot = await _db.ref('parents/${_currentUser!.uid}').get();
      if (snapshot.exists) {
        return Map<String, dynamic>.from(snapshot.value as Map);
      }
      return null;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return null;
    }
  }

  Future<bool> resetPassword(String email) async {
    try {
      _loading = true;
      _error = null;
      notifyListeners();

      await _auth.sendPasswordResetEmail(email: email);

      _loading = false;
      _error = 'Password reset email sent';
      notifyListeners();
      return true;
    } on FirebaseAuthException catch (e) {
      _error = e.message ?? 'Password reset failed';
      _loading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateParentName(String newName) async {
    try {
      if (_currentUser == null) return false;

      await _db.ref('parents/${_currentUser!.uid}/parentName').set(newName);

      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }
}
