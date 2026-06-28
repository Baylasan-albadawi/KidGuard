import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/firebase_service.dart';
import '../services/sim800l_service.dart';
import '../services/notification_service.dart';

class AlertProvider extends ChangeNotifier {
  final FirebaseService _firebaseService = FirebaseService();
  final Sim800lService _sim800lService = Sim800lService();

  final Map<String, List<Alert>> _alertsMap = {};
  final Set<String> _listeningChildren = {};
  final Set<String> _notifiedIds = {};
  final Set<String> _initialLoaded = {};
  final Set<String> _notifiedTransactionIds = {};
  bool _transactionsInitialized = false;
  bool _sending = false;

  AlertProvider() {
    _setupGlobalAlertListening();
    _listenToCanteenTransactions();
  }

  void _setupGlobalAlertListening() {
    _firebaseService.getChildrenStream().listen(
      (children) {
        for (final child in children) {
          if (!_listeningChildren.contains(child.childId)) {
            listenToAlertsForChild(child.childId);
          }
        }
      },
      onError: (e) {
        debugPrint('❌ AlertProvider: Failed to listen to children: $e');
      },
    );
  }

  List<Alert> getAlertsForChild(String childId) => _alertsMap[childId] ?? [];
  bool get sending => _sending;

  List<Alert> get allAlerts {
    final all = _alertsMap.values.expand((list) => list).toList();
    all.sort((a, b) => b.time.compareTo(a.time));
    return all;
  }

  int get unreadCount => allAlerts.where((a) => !a.read).length;

  void listenToAlertsForChild(String childId) {
    if (_listeningChildren.contains(childId)) return;
    _listeningChildren.add(childId);

    _firebaseService.getAlertsStream(childId).listen(
      (alerts) {
        if (!_initialLoaded.contains(childId)) {
          for (final a in alerts) {
            _notifiedIds.add(a.alertId);
          }
          _initialLoaded.add(childId);
        } else {
          for (final alert in alerts) {
            if (!alert.read && !_notifiedIds.contains(alert.alertId)) {
              _notifiedIds.add(alert.alertId);
              _showAlertNotification(alert);
            }
          }
        }
        _alertsMap[childId] = alerts;
        notifyListeners();
      },
      onError: (e) {
        debugPrint(
            '❌ AlertProvider: Error listening to alerts for $childId: $e');
      },
    );
  }

  void _listenToCanteenTransactions() {
    _firebaseService.getTransactionsStream().listen(
      (purchases) {
        if (!_transactionsInitialized) {
          for (final p in purchases) {
            _notifiedTransactionIds.add(p.purchaseId);
          }
          _transactionsInitialized = true;
          return;
        }
        for (final p in purchases) {
          if (_notifiedTransactionIds.contains(p.purchaseId)) continue;
          _notifiedTransactionIds.add(p.purchaseId);
          if (p.result == 'denied') {
            final itemLabel = p.productName.isEmpty ? 'Item' : p.productName;
            NotificationService.showAlert(
              title: 'Purchase Blocked — ${p.childName}',
              body: '$itemLabel was blocked at the canteen. ${p.reason}',
              id: p.purchaseId.hashCode,
            );
          }
        }
      },
      onError: (e) =>
          debugPrint('AlertProvider: transactions listener error: $e'),
    );
  }

  void _showAlertNotification(Alert alert) {
    final isSevere = alert.type == 'severe' ||
        alert.message.toLowerCase().contains('severe') ||
        alert.message.toLowerCase().contains('critical');
    NotificationService.showAlert(
      title: isSevere ? '🚨 SEVERE Alert' : '⚠️ KidGuard Alert',
      body: alert.message,
      id: alert.alertId.hashCode,
      severe: isSevere,
    );
  }

  Future<void> createAlert({
    required String childId,
    required String type,
    required String message,
  }) async {
    final alert = Alert(
      alertId: '',
      childId: childId,
      type: type,
      message: message,
      time: DateTime.now(),
    );
    await _firebaseService.createAlert(alert);
  }

  Future<bool> sendSMS(String phoneNumber, String message) async {
    _sending = true;
    notifyListeners();
    final result = await _sim800lService.sendSMS(phoneNumber, message);
    _sending = false;
    notifyListeners();
    return result;
  }

  Future<void> markRead(String childId, String alertId) async {
    await _firebaseService.markAlertRead(childId, alertId);
    final alerts = _alertsMap[childId];
    if (alerts != null) {
      for (final a in alerts) {
        if (a.alertId == alertId) a.read = true;
      }
      notifyListeners();
    }
  }
}
