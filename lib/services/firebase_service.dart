import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

import '../allergen_catalog.dart';
import '../models/models.dart';

String _normalizeRfid(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ');

String _normalizePhone(String phone) {
  var p = phone.trim();
  if (p.isEmpty) return '';
  if (!p.startsWith('+') && !p.startsWith('00')) {
    p = '+$p';
  }
  return p;
}

Map<String, Child> _snapshotChildren(DataSnapshot snapshot) {
  final raw = snapshot.value;
  if (raw == null) return {};
  final map = Map<Object?, Object?>.from(raw as Map<Object?, Object?>);
  final out = <String, Child>{};
  for (final e in map.entries) {
    final key = e.key.toString();
    final v = e.value;
    if (v is! Map) continue;
    out[key] = Child.fromMap(Map<String, dynamic>.from(v), key);
  }
  return out;
}

Child? _preferStudents(
    String id, Map<String, Child> students, Map<String, Child> children) {
  if (students.containsKey(id)) return students[id];
  return children[id];
}

class FirebaseService {
  static final bool _isWindowsDesktop =
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  final FirebaseDatabase _db = FirebaseDatabase.instance;

  static final Map<String, Child> _childrenLocal = {};
  static final Map<String, WristbandData> _wristbandsLocal = {};
  static final Map<String, List<Alert>> _alertsLocal = {};
  static final Map<String, Product> _productsLocal = {
    'prod_1': Product(
      productId: 'prod_1',
      name: 'Cheese Sandwich',
      price: 4,
      allergens: const ['Milk', 'Wheat'],
      emoji: '🥪',
      cat: 'Sandwiches',
      allergenMask: AllergenCatalog.maskFromLabels(const ['Milk', 'Wheat']),
    ),
    'prod_2': Product(
      productId: 'prod_2',
      name: 'Apple Juice',
      price: 3,
      emoji: '🍎',
      cat: 'Drinks',
    ),
  };
  static final Map<String, List<Purchase>> _purchasesLocal = {};
  static final Map<String, PosScan> _posScansLocal = {};

  static final StreamController<List<Child>> _childrenCtrl =
      StreamController<List<Child>>.broadcast();
  static final StreamController<List<Product>> _productsCtrl =
      StreamController<List<Product>>.broadcast();
  static final StreamController<List<Purchase>> _purchasesCtrl =
      StreamController<List<Purchase>>.broadcast();
  static final Map<String, StreamController<WristbandData?>> _wristbandCtrls =
      {};
  static final Map<String, StreamController<List<Alert>>> _alertCtrls = {};
  static final Map<String, StreamController<PosScan?>> _posScanCtrls = {};

  Stream<List<Child>>? _studentsChildrenMergeMemo;
  final Map<String, Stream<PosScan?>> _posMergedMemo = {};

  FirebaseService() {
    if (_isWindowsDesktop) {
      _emitChildrenLocal();
      _emitProductsLocal();
      _emitPurchasesLocal();
    }
  }

  void _emitChildrenLocal() =>
      _childrenCtrl.add(_childrenLocal.values.toList());
  void _emitProductsLocal() =>
      _productsCtrl.add(_productsLocal.values.toList());

  void _emitPurchasesLocal() {
    final all = <Purchase>[];
    for (final childPurchases in _purchasesLocal.values) {
      all.addAll(childPurchases);
    }
    all.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    _purchasesCtrl.add(all);
  }

  // ─── Children ───────────────────────────────────────────────
  Stream<List<Child>> getChildrenStream() {
    if (_isWindowsDesktop) {
      return _childrenCtrl.stream;
    }
    _studentsChildrenMergeMemo ??= _studentsAndLegacyChildrenStream();
    return _studentsChildrenMergeMemo!;
  }

  /// Canteen website uses `/students`; older builds used `/children`. We merge both.
  Stream<List<Child>> _studentsAndLegacyChildrenStream() {
    var students = <String, Child>{};
    var children = <String, Child>{};
    StreamSubscription? subS;
    StreamSubscription? subC;
    var started = false;

    late final StreamController<List<Child>> controller;
    controller = StreamController<List<Child>>.broadcast(
      onListen: () {
        if (started) return;
        started = true;

        void emit() {
          final ids = {...students.keys, ...children.keys};
          final list = ids
              .map((id) => _preferStudents(id, students, children))
              .whereType<Child>()
              .toList();
          list.sort((a, b) => a.name.compareTo(b.name));
          if (!controller.isClosed) controller.add(list);
        }

        subS = _db.ref('students').onValue.listen((event) {
          students = _snapshotChildren(event.snapshot);
          emit();
        }, onError: controller.addError);
        subC = _db.ref('children').onValue.listen((event) {
          children = _snapshotChildren(event.snapshot);
          emit();
        }, onError: controller.addError);
      },
      onCancel: () {
        subS?.cancel();
        subC?.cancel();
        subS = null;
        subC = null;
        started = false;
      },
    );

    return controller.stream;
  }

  Future<String> addChild(Child child) async {
    if (_isWindowsDesktop) {
      final id = 'child_${DateTime.now().millisecondsSinceEpoch}';
      _childrenLocal[id] = Child(
        childId: id,
        name: child.name,
        birthdate: child.birthdate,
        storedAge: child.storedAge,
        wristbandId: child.wristbandId,
        parentPhone: child.parentPhone,
        balance: child.balance,
        allergens: child.allergens,
      );
      _wristbandsLocal[id] = WristbandData(
        childId: id,
        heartRate: 0,
        panicPressed: false,
        timestamp: DateTime.now(),
        connected: false,
      );
      _emitChildrenLocal();
      return id;
    }
    final ref = _db.ref('students').push();
    final childId = ref.key!;
    final map = child.toMap();
    await ref.set(map);
    await _provisionDeviceNodes(childId, child, map);
    return childId;
  }

  Future<void> _provisionDeviceNodes(
    String childId,
    Child child,
    Map<String, dynamic> profile,
  ) async {
    final phone = _normalizePhone(child.parentPhone);
    final updates = <Future<void>>[
      _db.ref('children/$childId').set(profile),
      _db.ref('sensor_data/$childId').set({
        'childId': childId,
        'name': child.name,
        'wristbandId': child.wristbandId,
        'state': 'OFFLINE',
        'hr': 0,
        'spo2': 0,
        'temp': 0,
      }),
      _db.ref('wristbands/$childId').set({
        'childId': childId,
        'heartRate': 0,
        'panicPressed': false,
        'connected': false,
        'timestamp': ServerValue.timestamp,
      }),
    ];
    if (phone.isNotEmpty) {
      updates.add(_db.ref('children/$childId/parentNo').set(phone));
      updates.add(_db.ref('children/$childId/parentPhone').set(phone));
    }
    await Future.wait(updates);
  }

  Future<void> deleteChild(String childId) async {
    if (_isWindowsDesktop) {
      _childrenLocal.remove(childId);
      _wristbandsLocal.remove(childId);
      _alertsLocal.remove(childId);
      _purchasesLocal.remove(childId);
      _emitChildrenLocal();
      return;
    }
    await Future.wait([
      _db.ref('students/$childId').remove(),
      _db.ref('children/$childId').remove(),
      _db.ref('sensor_data/$childId').remove(),
      _db.ref('wristbands/$childId').remove(),
      _db.ref('alerts/$childId').remove(),
      _db.ref('purchases/$childId').remove(),
      _db.ref(childId).remove(),
    ]);
  }

  /// Direct lookup for `/pos/scan` payloads that carry only Firebase child keys (`c1`, push ids, …).
  Future<Child?> getChildById(String childId) async {
    if (_isWindowsDesktop) {
      return _childrenLocal[childId];
    }
    final s = await _db.ref('students/$childId').get();
    if (s.exists && s.value != null && s.value is Map) {
      return Child.fromMap(Map<String, dynamic>.from(s.value as Map), childId);
    }
    final c = await _db.ref('children/$childId').get();
    if (c.exists && c.value != null && c.value is Map) {
      return Child.fromMap(Map<String, dynamic>.from(c.value as Map), childId);
    }
    return null;
  }

  Future<Child?> getChildByWristbandId(String wristbandRaw) async {
    if (_isWindowsDesktop) {
      final needle = _normalizeRfid(wristbandRaw);
      if (needle.isEmpty) return null;
      for (final child in _childrenLocal.values) {
        if (_normalizeRfid(child.wristbandId) == needle) return child;
      }
      return null;
    }
    final needle = _normalizeRfid(wristbandRaw);
    if (needle.isEmpty) return null;

    Future<Child?> findInRoot(String root) async {
      final snapshot = await _db.ref(root).get();
      if (!snapshot.exists || snapshot.value == null) return null;
      final raw = snapshot.value!;
      if (raw is! Map) return null;
      for (final e in raw.entries) {
        final id = e.key.toString();
        final v = e.value;
        if (v is! Map) continue;
        final map = Map<String, dynamic>.from(v);
        final child = Child.fromMap(map, id);
        final w = _normalizeRfid(child.wristbandId);
        if (w == needle ||
            w.replaceAll(' ', '').toLowerCase() ==
                needle.replaceAll(' ', '').toLowerCase()) {
          return child;
        }
      }
      return null;
    }

    return await findInRoot('students') ?? await findInRoot('children');
  }

  // ─── Wristband / sensor telemetry ───────────────────────────
  Stream<WristbandData?> getWristbandStream(String childId) {
    if (_isWindowsDesktop) {
      _wristbandCtrls.putIfAbsent(
        childId,
        () => StreamController<WristbandData?>.broadcast(),
      );
      _wristbandCtrls[childId]!.add(_wristbandsLocal[childId]);
      return _wristbandCtrls[childId]!.stream;
    }
    return _mergedWristbandStream(childId);
  }

  Stream<WristbandData?> _mergedWristbandStream(String childId) {
    WristbandData? fromSensor;
    WristbandData? fromLegacy;
    WristbandData? fromStudent;
    StreamSubscription? subSensor;
    StreamSubscription? subLegacy;
    StreamSubscription? subStudent;
    var started = false;

    late final StreamController<WristbandData?> controller;
    controller = StreamController<WristbandData?>.broadcast(
      onListen: () {
        if (started) return;
        started = true;

        void emit() {
          final pick = fromSensor ?? fromLegacy ?? fromStudent;
          if (!controller.isClosed) controller.add(pick);
        }

        subSensor = _db.ref('sensor_data/$childId').onValue.listen((event) {
          final data = event.snapshot.value;
          if (data is Map) {
            fromSensor = WristbandData.fromMap(data, fallbackChildId: childId);
          } else {
            fromSensor = null;
          }
          emit();
        }, onError: (e) {
          debugPrint('⚠️ sensor_data listener error: $e');
        });

        subLegacy = _db.ref('wristbands/$childId').onValue.listen((event) {
          final data = event.snapshot.value;
          if (data is Map) {
            fromLegacy = WristbandData.fromMap(data, fallbackChildId: childId);
          } else {
            fromLegacy = null;
          }
          emit();
        }, onError: (e) {
          debugPrint('⚠️ wristbands listener error: $e');
        });

        // Listen to /students/{childId} for vitals (hr, spo2, temp, state)
        subStudent = _db.ref('students/$childId').onValue.listen((event) {
          final data = event.snapshot.value;
          if (data is Map) {
            fromStudent = WristbandData.fromMap(data, fallbackChildId: childId);
          } else {
            fromStudent = null;
          }
          emit();
        }, onError: (e) {
          debugPrint('⚠️ students listener error: $e');
        });
      },
      onCancel: () {
        subSensor?.cancel();
        subLegacy?.cancel();
        subStudent?.cancel();
        subSensor = null;
        subLegacy = null;
        subStudent = null;
        started = false;
      },
    );

    return controller.stream;
  }

  // ─── Alerts ─────────────────────────────────────────────────
  Stream<List<Alert>> getAlertsStream(String childId) {
    if (_isWindowsDesktop) {
      _alertCtrls.putIfAbsent(
        childId,
        () => StreamController<List<Alert>>.broadcast(),
      );
      _alertCtrls[childId]!.add(_alertsLocal[childId] ?? []);
      return _alertCtrls[childId]!.stream;
    }
    return _db
        .ref('alerts/$childId')
        .orderByChild('timestamp')
        .onValue
        .map((event) {
      final data = event.snapshot.value as Map<dynamic, dynamic>?;
      if (data == null) return [];
      final alerts = data.entries
          .map((e) =>
              Alert.fromMap(e.value as Map<dynamic, dynamic>, e.key.toString()))
          .toList();
      alerts.sort((a, b) => b.time.compareTo(a.time));
      return alerts;
    });
  }

  Future<void> createAlert(Alert alert) async {
    if (_isWindowsDesktop) {
      final id = 'alert_${DateTime.now().millisecondsSinceEpoch}';
      final withId = Alert(
        alertId: id,
        childId: alert.childId,
        type: alert.type,
        message: alert.message,
        time: alert.time,
        read: alert.read,
      );
      _alertsLocal.putIfAbsent(alert.childId, () => []);
      _alertsLocal[alert.childId]!.insert(0, withId);
      _alertCtrls[alert.childId]?.add(_alertsLocal[alert.childId]!);
      return;
    }
    final ref = _db.ref('alerts/${alert.childId}').push();
    await ref.set(alert.toMap());
  }

  Future<void> markAlertRead(String childId, String alertId) async {
    if (_isWindowsDesktop) {
      final alerts = _alertsLocal[childId];
      if (alerts == null) return;
      for (final alert in alerts) {
        if (alert.alertId == alertId) {
          alert.read = true;
        }
      }
      _alertCtrls[childId]?.add(alerts);
      return;
    }
    await _db.ref('alerts/$childId/$alertId/read').set(true);
  }

  // ─── Products ───────────────────────────────────────────────
  Stream<List<Product>> getProductsStream() {
    if (_isWindowsDesktop) {
      return _productsCtrl.stream;
    }
    return _db.ref('products').onValue.map((event) {
      final data = event.snapshot.value as Map<dynamic, dynamic>?;
      if (data == null) return [];

      final products = data.entries
          .map((e) => Product.fromMap(
              e.value as Map<dynamic, dynamic>, e.key.toString()))
          .where((product) => product.active)
          .toList();

      products.sort((a, b) {
        final c = a.cat.compareTo(b.cat);
        if (c != 0) return c;
        return a.name.compareTo(b.name);
      });
      return products;
    });
  }

  Future<void> saveProduct(Product product) async {
    if (_isWindowsDesktop) {
      final id = product.productId.isEmpty
          ? 'prod_${DateTime.now().millisecondsSinceEpoch}'
          : product.productId;
      _productsLocal[id] = Product(
        productId: id,
        name: product.name,
        price: product.price,
        allergens: product.allergens,
        active: product.active,
        emoji: product.emoji,
        cat: product.cat,
        allergenMask: product.allergenMask != 0
            ? product.allergenMask
            : AllergenCatalog.maskFromLabels(product.allergens),
      );
      _emitProductsLocal();
      return;
    }
    final map = product.toMap();
    map['allergenMask'] = product.allergenMask != 0
        ? product.allergenMask
        : AllergenCatalog.maskFromLabels(product.allergens);
    if (product.productId.isEmpty) {
      await _db.ref('products').push().set(map);
      return;
    }
    await _db.ref('products/${product.productId}').set(map);
  }

  Future<Product?> getProduct(String productId) async {
    if (_isWindowsDesktop) {
      return _productsLocal[productId];
    }
    final snapshot = await _db.ref('products/$productId').get();
    if (!snapshot.exists || snapshot.value == null) return null;
    return Product.fromMap(
        snapshot.value as Map<dynamic, dynamic>, snapshot.key ?? productId);
  }

  // ─── Purchases ──────────────────────────────────────────────
  Stream<List<Purchase>> getPurchasesStream({String? childId}) {
    if (_isWindowsDesktop) {
      if (childId == null) {
        return _purchasesCtrl.stream;
      }
      return _purchasesCtrl.stream.map(
        (all) => all.where((purchase) => purchase.childId == childId).toList(),
      );
    }

    // Merge /purchases (nested by childId) and /transactions (flat)
    // so data from both the Flutter POS and ESP32 canteen appears
    final purchasesRef =
        childId == null ? _db.ref('purchases') : _db.ref('purchases/$childId');
    final transactionsRef = _db.ref('transactions');

    List<Purchase> fromPurchases = [];
    List<Purchase> fromTransactions = [];

    late final StreamController<List<Purchase>> ctrl;
    ctrl = StreamController<List<Purchase>>.broadcast(
      onListen: () {
        void emit() {
          final seen = <String>{};
          final all = [...fromPurchases, ...fromTransactions]
              .where((p) => seen.add(p.purchaseId.isEmpty
                  ? '${p.childId}_${p.timestamp.millisecondsSinceEpoch}'
                  : p.purchaseId))
              .toList();
          all.sort((a, b) => b.timestamp.compareTo(a.timestamp));
          if (!ctrl.isClosed) ctrl.add(all);
        }

        purchasesRef.onValue.listen((event) {
          final data = event.snapshot.value as Map<dynamic, dynamic>?;
          fromPurchases = [];
          if (data != null) {
            if (childId == null) {
              for (final ce in data.entries) {
                final cp = ce.value as Map<dynamic, dynamic>?;
                if (cp == null) continue;
                for (final pe in cp.entries) {
                  try {
                    fromPurchases.add(Purchase.fromMap(
                        pe.value as Map<dynamic, dynamic>,
                        pe.key.toString()));
                  } catch (_) {}
                }
              }
            } else {
              for (final pe in data.entries) {
                try {
                  fromPurchases.add(Purchase.fromMap(
                      pe.value as Map<dynamic, dynamic>,
                      pe.key.toString()));
                } catch (_) {}
              }
            }
          }
          emit();
        }, onError: (_) => emit());

        // Also listen to flat /transactions (ESP32 canteen may write here)
        transactionsRef.onValue.listen((event) {
          final data = event.snapshot.value as Map<dynamic, dynamic>?;
          fromTransactions = [];
          if (data != null) {
            for (final e in data.entries) {
              try {
                final p = Purchase.fromMap(
                    e.value as Map<dynamic, dynamic>, e.key.toString());
                if (childId == null || p.childId == childId) {
                  fromTransactions.add(p);
                }
              } catch (_) {}
            }
          }
          emit();
        }, onError: (_) => emit());
      },
    );

    return ctrl.stream;
  }

  /// Flat stream of all /transactions (written by the HTML canteen).
  Stream<List<Purchase>> getTransactionsStream() {
    if (_isWindowsDesktop) return Stream.value([]);
    return _db.ref('transactions').onValue.map((event) {
      final data = event.snapshot.value as Map<dynamic, dynamic>?;
      if (data == null) return [];
      final purchases = <Purchase>[];
      for (final e in data.entries) {
        try {
          purchases.add(Purchase.fromMap(
              e.value as Map<dynamic, dynamic>, e.key.toString()));
        } catch (_) {}
      }
      return purchases;
    });
  }

  Future<void> _logPurchase(Purchase purchase) async {
    if (_isWindowsDesktop) {
      _purchasesLocal.putIfAbsent(purchase.childId, () => []);
      _purchasesLocal[purchase.childId]!.insert(0, purchase);
      _emitPurchasesLocal();
      return;
    }
    final ref = _db.ref('purchases/${purchase.childId}').push();
    await ref.set(purchase.toMap());
  }

  Future<void> _setBalancesForChild(Child child, double balance) async {
    if (_isWindowsDesktop) return;
    final s = await _db.ref('students/${child.childId}').get();
    if (s.exists)
      await _db.ref('students/${child.childId}/balance').set(balance);
    final l = await _db.ref('children/${child.childId}').get();
    if (l.exists)
      await _db.ref('children/${child.childId}/balance').set(balance);
  }

  Future<PurchaseDecision> processPurchase({
    required String wristbandId,
    required String productId,
  }) async {
    final child = await getChildByWristbandId(wristbandId);
    if (child == null) {
      return const PurchaseDecision(
        approved: false,
        message: 'Unknown wristband. Please scan a registered child band.',
      );
    }

    final product = await getProduct(productId);
    if (product == null) {
      return PurchaseDecision(
        approved: false,
        message: 'Selected product was not found.',
        child: child,
      );
    }

    if (product.conflictsWithChild(child)) {
      final matched = product.conflictMatches(child);
      final cm = AllergenCatalog.maskFromLabels(child.allergens);
      final pm = product.allergenMask != 0
          ? product.allergenMask
          : AllergenCatalog.maskFromLabels(product.allergens);
      final blockedLine = matched.isNotEmpty
          ? matched.join(', ')
          : AllergenCatalog.labelsFromMask(cm & pm).join(', ');
      final denyReason = blockedLine.isEmpty
          ? 'Blocked: allergen conflict'
          : 'Blocked: contains $blockedLine';
      await _logPurchase(
        Purchase(
          purchaseId: '',
          childId: child.childId,
          childName: child.name,
          productId: product.productId,
          productName: product.name,
          price: product.price,
          result: 'denied',
          reason: denyReason,
          timestamp: DateTime.now(),
        ),
      );
      // Fire an alert so the parent gets a push notification
      await createAlert(Alert(
        alertId: '',
        childId: child.childId,
        type: 'allergen',
        message: 'Allergen alert: ${child.name} tried to buy'
            ' "${product.name}". $denyReason',
        time: DateTime.now(),
      ));
      return PurchaseDecision(
        approved: false,
        message: blockedLine.isEmpty
            ? 'Blocked: allergens match this child\'s profile.'
            : 'Blocked: contains $blockedLine.',
        child: child,
        product: product,
      );
    }

    if (child.balance < product.price) {
      await _logPurchase(
        Purchase(
          purchaseId: '',
          childId: child.childId,
          childName: child.name,
          productId: product.productId,
          productName: product.name,
          price: product.price,
          result: 'denied',
          reason: 'Blocked: insufficient balance',
          timestamp: DateTime.now(),
        ),
      );
      return PurchaseDecision(
        approved: false,
        message: 'Blocked: insufficient balance.',
        child: child,
        product: product,
      );
    }

    final updatedBalance = child.balance - product.price;
    if (_isWindowsDesktop) {
      _childrenLocal[child.childId] = Child(
        childId: child.childId,
        name: child.name,
        birthdate: child.birthdate,
        storedAge: child.storedAge,
        wristbandId: child.wristbandId,
        parentPhone: child.parentPhone,
        balance: updatedBalance,
        allergens: child.allergens,
      );
      _emitChildrenLocal();
    } else {
      await _setBalancesForChild(child, updatedBalance);
    }
    await _logPurchase(
      Purchase(
        purchaseId: '',
        childId: child.childId,
        childName: child.name,
        productId: product.productId,
        productName: product.name,
        price: product.price,
        result: 'approved',
        reason: 'Approved',
        timestamp: DateTime.now(),
      ),
    );

    return PurchaseDecision(
      approved: true,
      message:
          'Purchase approved. New balance: ${updatedBalance.toStringAsFixed(2)}',
      child: child,
      product: product,
    );
  }

  PosScan? _parsePosScan(DatabaseEvent event) {
    final data = event.snapshot.value;
    if (data == null) return null;
    final map = Map<dynamic, dynamic>.from(data as Map<dynamic, dynamic>);
    return PosScan.fromMap(map);
  }

  Future<PosScan?> _resolvePosScanChild(PosScan? raw) async {
    if (raw == null) return null;
    if (raw.childId != null &&
        raw.childId!.isNotEmpty &&
        raw.wristbandId.isEmpty) {
      final c = await getChildById(raw.childId!);
      if (c != null) {
        return PosScan(
          childId: raw.childId,
          wristbandId: c.wristbandId,
          productId: raw.productId,
          timestamp: raw.timestamp,
        );
      }
    }
    return raw;
  }

  // ─── POS Scan Bridge ────────────────────────────────────────
  /// Matches the static site (`/pos/scan`) plus terminal-specific RFID bridge (`pos_scans/{terminal}`).
  Stream<PosScan?> getPosScanStream(String terminalId) {
    if (_isWindowsDesktop) {
      _posScanCtrls.putIfAbsent(
        terminalId,
        () => StreamController<PosScan?>.broadcast(),
      );
      _posScanCtrls[terminalId]!.add(_posScansLocal[terminalId]);
      return _posScanCtrls[terminalId]!.stream;
    }
    return _posMergedMemo.putIfAbsent(terminalId, () {
      return _mergedRawPosBridge(terminalId).asyncMap(_resolvePosScanChild);
    });
  }

  Stream<PosScan?> _mergedRawPosBridge(String terminalId) {
    PosScan? fromGlobal;
    PosScan? fromTerm;
    StreamSubscription? s1;
    StreamSubscription? s2;
    var started = false;

    late final StreamController<PosScan?> ctrl;
    ctrl = StreamController<PosScan?>.broadcast(
      onListen: () {
        if (started) return;
        started = true;

        void emitMerged() {
          if (fromGlobal == null && fromTerm == null) {
            if (!ctrl.isClosed) ctrl.add(null);
            return;
          }
          if (fromGlobal == null) {
            if (!ctrl.isClosed) ctrl.add(fromTerm);
            return;
          }
          if (fromTerm == null) {
            if (!ctrl.isClosed) ctrl.add(fromGlobal);
            return;
          }
          final pick = fromGlobal!.timestamp.isAfter(fromTerm!.timestamp)
              ? fromGlobal
              : fromTerm;
          if (!ctrl.isClosed) ctrl.add(pick);
        }

        s1 = _db.ref('pos/scan').onValue.listen((e) {
          fromGlobal = _parsePosScan(e);
          emitMerged();
        }, onError: ctrl.addError);
        s2 = _db.ref('pos_scans/$terminalId').onValue.listen((e) {
          fromTerm = _parsePosScan(e);
          emitMerged();
        }, onError: ctrl.addError);
      },
      onCancel: () {
        s1?.cancel();
        s2?.cancel();
        s1 = null;
        s2 = null;
        started = false;
      },
    );

    return ctrl.stream;
  }

  Future<void> setPosScan(String terminalId, PosScan scan) async {
    if (_isWindowsDesktop) {
      _posScansLocal[terminalId] = scan;
      _posScanCtrls[terminalId]?.add(scan);
      return;
    }
    final map = scan.toMap();
    await _db.ref('pos_scans/$terminalId').set(map);
    await _db.ref('pos/scan').set(map);
  }

  Future<void> clearPosScan(String terminalId) async {
    if (_isWindowsDesktop) {
      _posScansLocal.remove(terminalId);
      _posScanCtrls[terminalId]?.add(null);
      return;
    }
    await _db.ref('pos_scans/$terminalId').remove();
    await _db.ref('pos/scan').remove();
  }
}
