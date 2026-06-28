// lib/providers/child_provider.dart

import 'dart:async';

import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/firebase_service.dart';
import '../services/notification_service.dart';

class ChildProvider extends ChangeNotifier {
  final FirebaseService _firebaseService = FirebaseService();

  List<Child> _children = [];
  final Map<String, WristbandData> _wristbandData = {};
  final Map<String, StreamSubscription<WristbandData?>> _wristbandSubscriptions = {};
  final Map<String, String> _lastKnownStates = {}; // childId -> last notified state
  StreamSubscription<List<Child>>? _childrenSubscription;
  Timer? _loadTimeout;
  bool _loading = false;
  String? _error;

  List<Child> get children => _children;
  Map<String, WristbandData> get wristbandData => _wristbandData;
  bool get loading => _loading;
  String? get error => _error;

  WristbandData? getWristband(String childId) => _wristbandData[childId];

  void loadChildren() {
    _childrenSubscription?.cancel();
    _loadTimeout?.cancel();
    _loading = true;
    _error = null;
    notifyListeners();

    _loadTimeout = Timer(const Duration(seconds: 8), () {
      if (_loading) {
        _loading = false;
        _error =
            'Could not reach Firebase. Finish Firebase setup or check your internet/database rules.';
        notifyListeners();
      }
    });

    _childrenSubscription = _firebaseService.getChildrenStream().listen(
      (children) {
        _loadTimeout?.cancel();
        _children = children;
        _loading = false;
        _error = null;
        for (final child in children) {
          _listenToWristband(child.childId);
        }
        notifyListeners();
      },
      onError: (e) {
        _loadTimeout?.cancel();
        _error = e.toString();
        _loading = false;
        notifyListeners();
      },
    );
  }

  void _listenToWristband(String childId) {
    if (_wristbandSubscriptions.containsKey(childId)) return;

    _wristbandSubscriptions[childId] =
        _firebaseService.getWristbandStream(childId).listen((data) {
      if (data != null) {
        final prevState = _lastKnownStates[childId];
        final newState = data.state.toUpperCase();

        // Notify on first MILD / SEVERE reading, or when state transitions in
        if (newState != prevState) {
          final childName = _children
              .where((c) => c.childId == childId)
              .map((c) => c.name)
              .firstOrNull ?? 'Your child';

          if (newState == 'SEVERE') {
            NotificationService.showAlert(
              title: '🚨 SEVERE Alert — $childName',
              body: 'Critical health state detected! HR: ${data.heartRate} bpm, SpO₂: ${data.spO2}%, Temp: ${data.temperature.toStringAsFixed(1)}°C',
              id: childId.hashCode,
              severe: true,
            );
          } else if (newState == 'MILD') {
            NotificationService.showAlert(
              title: '⚠️ MILD Alert — $childName',
              body: 'Mild allergic reaction detected. HR: ${data.heartRate} bpm, SpO₂: ${data.spO2}%, Temp: ${data.temperature.toStringAsFixed(1)}°C',
              id: childId.hashCode,
            );
          }
          _lastKnownStates[childId] = newState;
        }

        _wristbandData[childId] = data;
        notifyListeners();
      }
    });
  }

  Future<String> addChild(Child child) async {
    final childId = await _firebaseService.addChild(child);
    _listenToWristband(childId);
    return childId;
  }

  Future<void> deleteChild(String childId) async {
    await _wristbandSubscriptions[childId]?.cancel();
    _wristbandSubscriptions.remove(childId);
    _wristbandData.remove(childId);
    _lastKnownStates.remove(childId);
    await _firebaseService.deleteChild(childId);
    notifyListeners();
  }

  String getChildStatus(String childId) {
    return _wristbandData[childId]?.status ?? 'offline';
  }

  int get totalAlerts {
    return _children.where((c) => getChildStatus(c.childId) == 'alert').length;
  }

  @override
  void dispose() {
    _loadTimeout?.cancel();
    _childrenSubscription?.cancel();
    for (final subscription in _wristbandSubscriptions.values) {
      subscription.cancel();
    }
    super.dispose();
  }
}
