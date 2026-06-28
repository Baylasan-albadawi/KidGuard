// lib/models/models.dart

import '../allergen_catalog.dart';

String _productCategory(Map<dynamic, dynamic> map) {
  for (final k in ['cat', 'category']) {
    final v = map[k]?.toString().trim();
    if (v != null && v.isNotEmpty) return v;
  }
  return 'General';
}

class Child {
  final String childId;
  final String name;
  final DateTime? birthdate;
  final int? storedAge;
  final String wristbandId;
  final String parentPhone;
  final double balance;
  final List<String> allergens;

  Child({
    required this.childId,
    required this.name,
    this.birthdate,
    this.storedAge,
    required this.wristbandId,
    required this.parentPhone,
    this.balance = 0,
    this.allergens = const [],
  });

  /// Age in whole years from [birthdate], or legacy [storedAge] when birthdate is absent.
  int get age {
    final bd = birthdate;
    if (bd != null) {
      final now = DateTime.now();
      var years = now.year - bd.year;
      if (now.month < bd.month || (now.month == bd.month && now.day < bd.day)) {
        years--;
      }
      return years.clamp(0, 120);
    }
    return storedAge ?? 0;
  }

  static DateTime? _parseBirthdate(dynamic raw) {
    if (raw == null) return null;
    if (raw is int) {
      return DateTime.fromMillisecondsSinceEpoch(raw);
    }
    if (raw is num) {
      return DateTime.fromMillisecondsSinceEpoch(raw.toInt());
    }
    final s = raw.toString().trim();
    if (s.isEmpty) return null;
    final parsed = DateTime.tryParse(s);
    if (parsed != null) return parsed;
    final parts = s.split('-');
    if (parts.length == 3) {
      final y = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      final d = int.tryParse(parts[2]);
      if (y != null && m != null && d != null) {
        return DateTime(y, m, d);
      }
    }
    return null;
  }

  factory Child.fromMap(Map<String, dynamic> map, String id) {
    final rawAllergens = map['allergens'];
    final bandRaw = map['wristbandId']?.toString().trim();
    final rfidRaw = map['rfid']?.toString().trim();
    final wrist = (bandRaw != null && bandRaw.isNotEmpty)
        ? bandRaw
        : (rfidRaw != null && rfidRaw.isNotEmpty ? rfidRaw : '');
    final birthdate = _parseBirthdate(map['birthdate']);
    final legacyAge = map['age'];
    final storedAge = legacyAge is int
        ? legacyAge
        : legacyAge is num
            ? legacyAge.toInt()
            : int.tryParse(legacyAge?.toString() ?? '');
    return Child(
      childId: id,
      name: map['name'] ?? '',
      birthdate: birthdate,
      storedAge: birthdate == null ? storedAge : null,
      wristbandId: wrist,
      parentPhone:
          map['parentPhone']?.toString() ?? map['parentNo']?.toString() ?? '',
      balance: (map['balance'] ?? 0).toDouble(),
      allergens: rawAllergens is List
          ? rawAllergens.map((e) => e.toString()).toList()
          : const [],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      if (birthdate != null)
        'birthdate': birthdate!.toIso8601String().split('T').first,
      'age': age,
      'wristbandId': wristbandId,
      if (wristbandId.isNotEmpty) 'rfid': wristbandId,
      'parentPhone': parentPhone,
      if (parentPhone.isNotEmpty) 'parentNo': parentPhone,
      'balance': balance,
      'allergens': allergens,
    };
  }
}

class WristbandData {
  final String childId;
  final int heartRate;
  final int spO2;
  final double temperature;
  final bool panicPressed;
  final DateTime timestamp;
  final bool connected;
  final String state; // NORMAL, MILD, SEVERE

  WristbandData({
    required this.childId,
    required this.heartRate,
    this.spO2 = 0,
    this.temperature = 0,
    required this.panicPressed,
    required this.timestamp,
    required this.connected,
    this.state = 'OFFLINE',
  });

  factory WristbandData.fromMap(Map<dynamic, dynamic> map,
      {String fallbackChildId = ''}) {
    final state = map['state']?.toString().toUpperCase() ?? '';
    final hrRaw = map['heartRate'] ?? map['hr'];
    final hr = hrRaw is num
        ? hrRaw.round()
        : int.tryParse(hrRaw?.toString() ?? '') ?? 0;

    // SpO2 parsing
    final spo2Raw = map['spo2'];
    final spo2 = spo2Raw is num
        ? spo2Raw.round()
        : int.tryParse(spo2Raw?.toString() ?? '') ?? 0;

    // Temperature parsing
    final tempRaw = map['temp'];
    final temp = tempRaw is num
        ? tempRaw.toDouble()
        : double.tryParse(tempRaw?.toString() ?? '') ?? 0.0;

    final panic = map['panicPressed'] == true ||
        state == 'SOS' ||
        state == 'SEVERE' ||
        state == 'MILD';
    final ts = _parseTimestamp(map['timestamp'] ?? map['ts']);
    final explicitConnected = map['connected'];
    final connected = explicitConnected is bool
        ? explicitConnected
        : state.isNotEmpty && state != 'OFFLINE' && hr > 0;

    return WristbandData(
      childId: map['childId']?.toString() ?? fallbackChildId,
      heartRate: hr,
      spO2: spo2,
      temperature: temp,
      panicPressed: panic,
      timestamp: ts,
      connected: connected,
      state: state,
    );
  }

  static DateTime _parseTimestamp(dynamic raw) {
    if (raw == null) return DateTime.now();
    if (raw is num) {
      final ms = raw > 1e12 ? raw.toInt() : (raw * 1000).toInt();
      return DateTime.fromMillisecondsSinceEpoch(ms);
    }
    if (raw is Map) return DateTime.now();
    return DateTime.now();
  }

  String get status {
    if (!connected) return 'offline';
    if (panicPressed) return 'alert';
    if (heartRate > 120) return 'alert';
    return 'safe';
  }
}

class Alert {
  final String alertId;
  final String childId;
  final String type; // 'panic' | 'heartrate'
  final String message;
  final DateTime time;
  bool read;

  Alert({
    required this.alertId,
    required this.childId,
    required this.type,
    required this.message,
    required this.time,
    this.read = false,
  });

  factory Alert.fromMap(Map<dynamic, dynamic> map, String id) {
    return Alert(
      alertId: id,
      childId: map['childId']?.toString() ?? '',
      type: map['type']?.toString() ?? '',
      message: map['message']?.toString() ?? '',
      time: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] ?? 0),
      read: map['read'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'childId': childId,
      'type': type,
      'message': message,
      'timestamp': time.millisecondsSinceEpoch,
      'read': read,
    };
  }
}

class Product {
  final String productId;
  final String name;
  final double price;
  final List<String> allergens;
  final bool active;
  final String emoji;
  final String cat;
  final int allergenMask;

  Product({
    required this.productId,
    required this.name,
    required this.price,
    this.allergens = const [],
    this.active = true,
    this.emoji = '',
    this.cat = 'General',
    this.allergenMask = 0,
  });

  factory Product.fromMap(Map<dynamic, dynamic> map, String id) {
    final rawAllergens = map['allergens'];
    final list = rawAllergens is List
        ? rawAllergens.map((e) => e.toString()).toList()
        : const <String>[];
    final storedMask = map['allergenMask'];
    final mask = storedMask is int
        ? storedMask
        : storedMask is num
            ? storedMask.toInt()
            : AllergenCatalog.maskFromLabels(list);
    return Product(
      productId: id,
      name: map['name']?.toString() ?? '',
      price: (map['price'] ?? 0).toDouble(),
      allergens: list,
      active: map['active'] ?? true,
      emoji: map['emoji']?.toString() ?? '',
      cat: _productCategory(map),
      allergenMask: mask,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'price': price,
      'allergens': allergens,
      'active': active,
      'emoji': emoji,
      'cat': cat,
      'allergenMask': allergenMask,
    };
  }

  bool conflictsWithChild(Child child) {
    final childMask = AllergenCatalog.maskFromLabels(child.allergens);
    if (AllergenCatalog.bitmaskConflicts(
        childMask: childMask, productMask: allergenMask)) {
      return true;
    }
    return AllergenCatalog.intersectsLists(child.allergens, allergens);
  }

  List<String> conflictMatches(Child child) =>
      AllergenCatalog.matchingLabels(child.allergens, allergens);
}

class Purchase {
  final String purchaseId;
  final String childId;
  final String childName;
  final String productId;
  final String productName;
  final double price;
  final String result;
  final String reason;
  final DateTime timestamp;

  Purchase({
    required this.purchaseId,
    required this.childId,
    required this.childName,
    required this.productId,
    required this.productName,
    required this.price,
    required this.result,
    required this.reason,
    required this.timestamp,
  });

  factory Purchase.fromMap(Map<dynamic, dynamic> map, String id) {
    // Support both /purchases (Flutter POS) and /transactions (HTML canteen) formats.
    // Canteen writes: approved(bool), total(price), items[](products), timestamp(ISO string).
    // POS writes: result(string), price, productName, timestamp(ms int).

    // result
    String result;
    if (map['result'] != null) {
      result = map['result'].toString();
    } else {
      result = (map['approved'] == true) ? 'approved' : 'denied';
    }

    // price
    final rawPrice = map['price'] ?? map['total'];
    final price = rawPrice != null ? (rawPrice as num).toDouble() : 0.0;

    // productName
    String productName = map['productName']?.toString() ?? '';
    if (productName.isEmpty) {
      final items = map['items'];
      if (items is List && items.isNotEmpty) {
        final first = items.first;
        if (first is Map) {
          productName = first['name']?.toString() ?? '';
          if (items.length > 1) productName += ' +${items.length - 1} more';
        }
      }
    }

    // timestamp: milliseconds int (POS) OR ISO string (canteen)
    DateTime timestamp;
    final tsRaw = map['timestamp'];
    if (tsRaw is int) {
      timestamp = DateTime.fromMillisecondsSinceEpoch(tsRaw);
    } else if (tsRaw is num) {
      timestamp = DateTime.fromMillisecondsSinceEpoch(tsRaw.toInt());
    } else if (tsRaw is String && tsRaw.isNotEmpty) {
      timestamp = DateTime.tryParse(tsRaw) ?? DateTime.now();
    } else {
      timestamp = DateTime.now();
    }

    return Purchase(
      purchaseId: id,
      childId: map['childId']?.toString() ?? '',
      childName: map['childName']?.toString() ?? '',
      productId: map['productId']?.toString() ?? '',
      productName: productName,
      price: price,
      result: result,
      reason: map['reason']?.toString() ?? '',
      timestamp: timestamp,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'childId': childId,
      'childName': childName,
      'productId': productId,
      'productName': productName,
      'price': price,
      'result': result,
      'reason': reason,
      'timestamp': timestamp.millisecondsSinceEpoch,
    };
  }
}

class PurchaseDecision {
  final bool approved;
  final String message;
  final Child? child;
  final Product? product;

  const PurchaseDecision({
    required this.approved,
    required this.message,
    this.child,
    this.product,
  });
}

class PosScan {
  final String? childId;
  final String wristbandId;
  final String? productId;
  final DateTime timestamp;

  const PosScan({
    this.childId,
    required this.wristbandId,
    required this.timestamp,
    this.productId,
  });

  factory PosScan.fromMap(Map<dynamic, dynamic> map) {
    final band = map['wristbandId']?.toString().trim();
    final rfid = map['rfid']?.toString().trim();
    return PosScan(
      childId: map['childId']?.toString(),
      wristbandId: (band != null && band.isNotEmpty) ? band : (rfid ?? ''),
      productId: map['productId']?.toString(),
      timestamp: DateTime.fromMillisecondsSinceEpoch(
          map['timestamp'] ?? DateTime.now().millisecondsSinceEpoch),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (childId != null) 'childId': childId,
      'wristbandId': wristbandId,
      'productId': productId,
      'timestamp': timestamp.millisecondsSinceEpoch,
    };
  }
}
