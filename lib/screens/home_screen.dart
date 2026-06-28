import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/parent_provider.dart';
import '../providers/child_provider.dart';
import '../providers/alert_provider.dart';
import '../models/models.dart';
import '../services/firebase_service.dart';
import 'child_details_screen.dart';
import 'add_child_screen.dart';
import 'alerts_screen.dart';

// ─── Shared colours ────────────────────────────────────────────────────────
const _bg = Color(0xFFFFF8F0);
const _blue = Color(0xFF4A90D9);
const _green = Color(0xFF4CAF50);
const _red = Color(0xFFE53935);
const _orange = Color(0xFFFF9800);
const _purple = Color(0xFF9C27B0);
const _teal = Color(0xFF009688);
const _grey = Color(0xFF888888);
const _dark = Color(0xFF1A1A2E);
const _card = Colors.white;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _idx = 0;

  static const _tabs = [
    _DashboardTab(),
    _AllergensTab(),
    _PurchasesTab(),
    AlertsScreen(),
    _SettingsTab(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _idx, children: _tabs),
      bottomNavigationBar: Consumer<AlertProvider>(
        builder: (_, alertP, __) => Container(
          decoration: const BoxDecoration(
            color: _card,
            border: Border(top: BorderSide(color: Color(0xFFEEEEEE))),
          ),
          child: NavigationBar(
            backgroundColor: _card,
            elevation: 0,
            selectedIndex: _idx,
            onDestinationSelected: (i) => setState(() => _idx = i),
            indicatorColor: _blue.withValues(alpha: 0.12),
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            destinations: [
              const NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home_rounded, color: _blue),
                label: 'Dashboard',
              ),
              const NavigationDestination(
                icon: Icon(Icons.checklist_outlined),
                selectedIcon: Icon(Icons.checklist_rounded, color: _blue),
                label: 'Allergens',
              ),
              const NavigationDestination(
                icon: Icon(Icons.receipt_long_outlined),
                selectedIcon: Icon(Icons.receipt_long_rounded, color: _orange),
                label: 'Purchases',
              ),
              NavigationDestination(
                icon: Badge(
                  isLabelVisible: alertP.unreadCount > 0,
                  label: Text('${alertP.unreadCount}'),
                  child: const Icon(Icons.notifications_outlined),
                ),
                selectedIcon: Badge(
                  isLabelVisible: alertP.unreadCount > 0,
                  label: Text('${alertP.unreadCount}'),
                  child: const Icon(Icons.notifications_rounded, color: _blue),
                ),
                label: 'Alerts',
              ),
              const NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings_rounded, color: _blue),
                label: 'Settings',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Dashboard Tab ──────────────────────────────────────────────────────────
class _DashboardTab extends StatelessWidget {
  const _DashboardTab();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text('Welcome back 👋',
                style: TextStyle(
                    fontSize: 12, color: _grey, fontWeight: FontWeight.w500)),
            Text('Dashboard',
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w800, color: _dark)),
          ],
        ),
        toolbarHeight: 68,
        actions: [
          GestureDetector(
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const AddChildScreen())),
            child: Container(
              margin: const EdgeInsets.only(right: 16),
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _blue.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.add_rounded, color: _blue, size: 24),
            ),
          ),
        ],
      ),
      body: Consumer<ChildProvider>(
        builder: (context, provider, _) {
          if (provider.loading) {
            return const Center(child: CircularProgressIndicator(color: _blue));
          }
          if (provider.error != null) {
            return _ErrorState(message: provider.error!);
          }
          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              const SizedBox(height: 4),
              _StatsRow(children: provider.children, provider: provider),
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('My Children 👦👧',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: _dark)),
                  Text('${provider.children.length} registered',
                      style: const TextStyle(fontSize: 12, color: _grey)),
                ],
              ),
              const SizedBox(height: 12),
              if (provider.children.isEmpty)
                _EmptyState(
                  emoji: '🧒',
                  title: 'No children yet!',
                  subtitle: 'Tap + to add your first child',
                  onAction: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const AddChildScreen())),
                  actionLabel: 'Add Child',
                )
              else ...[
                ...provider.children.map((child) => _ChildCard(
                      child: child,
                      wristband: provider.getWristband(child.childId),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => ChildDetailsScreen(child: child)),
                      ),
                    )),
                const SizedBox(height: 12),
                _AddMoreButton(
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const AddChildScreen())),
                ),
              ],
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }
}

// ─── Stats Row ──────────────────────────────────────────────────────────────
class _StatsRow extends StatelessWidget {
  final List<Child> children;
  final ChildProvider provider;
  const _StatsRow({required this.children, required this.provider});

  @override
  Widget build(BuildContext context) {
    final safe = children
        .where((c) => provider.getChildStatus(c.childId) == 'safe')
        .length;
    final alerts = children
        .where((c) => provider.getChildStatus(c.childId) == 'alert')
        .length;
    return Row(children: [
      _StatCard(
          label: 'Total', value: children.length, emoji: '👶', color: _blue),
      const SizedBox(width: 10),
      _StatCard(label: 'Safe', value: safe, emoji: '✅', color: _green),
      const SizedBox(width: 10),
      _StatCard(label: 'Alerts', value: alerts, emoji: '⚠️', color: _red),
    ]);
  }
}

class _StatCard extends StatelessWidget {
  final String label, emoji;
  final int value;
  final Color color;
  const _StatCard(
      {required this.label,
      required this.value,
      required this.emoji,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(children: [
          Text(emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(height: 4),
          Text('$value',
              style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: color,
                  height: 1.1)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(
                  fontSize: 11, color: _grey, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

// ─── Child Card ─────────────────────────────────────────────────────────────
class _ChildCard extends StatelessWidget {
  final Child child;
  final WristbandData? wristband;
  final VoidCallback onTap;
  const _ChildCard(
      {required this.child, required this.wristband, required this.onTap});

  String get _safeName {
    final n = child.name.trim();
    return n.isEmpty ? 'Unknown child' : n;
  }

  String get _avatarLetter {
    final n = _safeName.trim();
    return n.isNotEmpty ? n[0].toUpperCase() : '?';
  }

  Color get _statusColor {
    switch (wristband?.status ?? 'offline') {
      case 'safe':
        return _green;
      case 'alert':
        return _red;
      default:
        return _grey;
    }
  }

  String get _statusLabel {
    switch (wristband?.status ?? 'offline') {
      case 'safe':
        return 'Safe';
      case 'alert':
        return 'Alert!';
      default:
        return 'Offline';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAlert = wristband?.status == 'alert';
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(20),
          border: isAlert
              ? Border.all(color: _red.withValues(alpha: 0.4), width: 1.5)
              : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              // Avatar circle
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: _blue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                  child: Text(_avatarLetter,
                      style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: _blue)),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_safeName,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                color: _dark)),
                        _StatusPill(label: _statusLabel, color: _statusColor),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text('Age ${child.age} · ${child.wristbandId}',
                        style: const TextStyle(color: _grey, fontSize: 12)),
                    if (wristband != null && wristband!.connected) ...[
                      const SizedBox(height: 10),
                      _VitalSignsRow(wristband: wristband!),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded,
                  color: Color(0xFFCCCCCC), size: 22),
            ]),
            if (isAlert) ...[
              const SizedBox(height: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: _red.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(children: [
                  Text('🚨', style: TextStyle(fontSize: 16)),
                  SizedBox(width: 8),
                  Text('Emergency alert — tap to view details',
                      style: TextStyle(
                          color: _red,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(label,
            style: TextStyle(
                color: color, fontSize: 11, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

class _AddMoreButton extends StatelessWidget {
  final VoidCallback onTap;
  const _AddMoreButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _blue.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _blue.withValues(alpha: 0.2)),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_circle_outline_rounded, color: _blue, size: 20),
            SizedBox(width: 8),
            Text('Add New Child',
                style: TextStyle(
                    color: _blue, fontWeight: FontWeight.w700, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}

// ─── Allergens Tab ──────────────────────────────────────────────────────────
class _AllergensTab extends StatelessWidget {
  const _AllergensTab();

  static const _allergens = [
    ('🥜', 'Peanuts'),
    ('🥛', 'Milk'),
    ('🥚', 'Eggs'),
    ('🐟', 'Fish'),
    ('🌾', 'Wheat'),
    ('🌳', 'Tree Nuts'),
    ('🫘', 'Soy'),
    ('🦐', 'Shellfish'),
    ('🌿', 'Sesame'),
  ];

  @override
  Widget build(BuildContext context) {
    return Consumer<ChildProvider>(
      builder: (context, provider, _) {
        return Scaffold(
          backgroundColor: _bg,
          appBar: AppBar(
            backgroundColor: _bg,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Allergens',
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: _dark)),
                Text(
                  provider.children.isEmpty
                      ? 'No child yet — add one first'
                      : 'Allergen profile',
                  style: const TextStyle(
                      fontSize: 12, color: _grey, fontWeight: FontWeight.w500),
                ),
              ],
            ),
            toolbarHeight: 68,
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Icon(Icons.checklist_rounded,
                    color: _blue.withValues(alpha: 0.7), size: 26),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 10)
                  ],
                ),
                child: const Text(
                  'Pick what your child must avoid. The wristband/POS can block unsafe purchases using this list.',
                  style: TextStyle(color: _grey, fontSize: 14, height: 1.6),
                ),
              ),
              const SizedBox(height: 20),
              if (provider.children.isEmpty)
                _EmptyState(
                  emoji: '🛡️',
                  title: 'No child registered yet',
                  subtitle:
                      'Add a child first to set up their allergen profile',
                )
              else ...[
                const Text('Common Allergens',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _dark)),
                const SizedBox(height: 12),
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.1,
                  children: _allergens
                      .map((a) => _AllergenChip(
                            emoji: a.$1,
                            label: a.$2,
                          ))
                      .toList(),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _AllergenChip extends StatefulWidget {
  final String emoji, label;
  const _AllergenChip({required this.emoji, required this.label});

  @override
  State<_AllergenChip> createState() => _AllergenChipState();
}

class _AllergenChipState extends State<_AllergenChip> {
  bool _selected = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _selected = !_selected),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: _selected ? _red.withValues(alpha: 0.1) : _card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _selected
                ? _red.withValues(alpha: 0.5)
                : const Color(0xFFEEEEEE),
            width: _selected ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)
          ],
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(widget.emoji, style: const TextStyle(fontSize: 26)),
          const SizedBox(height: 4),
          Text(widget.label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: _selected ? _red : _dark,
              )),
        ]),
      ),
    );
  }
}

// ─── Purchases Tab ──────────────────────────────────────────────────────────
class _PurchasesTab extends StatefulWidget {
  const _PurchasesTab();

  @override
  State<_PurchasesTab> createState() => _PurchasesTabState();
}

class _PurchasesTabState extends State<_PurchasesTab> {
  // Created once in initState so StreamBuilder never gets a new stream on rebuild
  late final Stream<List<Purchase>> _purchasesStream;

  @override
  void initState() {
    super.initState();
    _purchasesStream = FirebaseService().getPurchasesStream();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ChildProvider>(
      builder: (context, provider, _) {
        return Scaffold(
          backgroundColor: _bg,
          appBar: AppBar(
            backgroundColor: _bg,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Purchases',
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: _dark)),
                Text(
                  provider.children.isEmpty
                      ? 'No child yet — add one first'
                      : 'Purchase history',
                  style: const TextStyle(
                      fontSize: 12, color: _grey, fontWeight: FontWeight.w500),
                ),
              ],
            ),
            toolbarHeight: 68,
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Icon(Icons.receipt_long_rounded,
                    color: _orange.withValues(alpha: 0.8), size: 26),
              ),
            ],
          ),
          body: provider.children.isEmpty
              ? const _EmptyState(
                  emoji: '🧾',
                  title: 'No purchases yet!',
                  subtitle:
                      'Canteen transactions will show up here once a child is registered',
                )
              : StreamBuilder<List<Purchase>>(
                  stream: _purchasesStream,
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(
                        child: CircularProgressIndicator(color: _orange),
                      );
                    }

                    final purchases = snapshot.data!;
                    if (purchases.isEmpty) {
                      return const _EmptyState(
                        emoji: '🛒',
                        title: 'No purchases yet',
                        subtitle:
                            'Approved and denied canteen transactions will appear here',
                      );
                    }

                    return ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: purchases.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final purchase = purchases[index];
                        final approved = purchase.result == 'approved';
                        return Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: _card,
                            borderRadius: BorderRadius.circular(16),
                            border: approved
                                ? null
                                : Border.all(
                                    color: _red.withValues(alpha: 0.25)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.04),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: (approved ? _green : _red)
                                      .withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Center(
                                  child: Text(approved ? '✅' : '⛔',
                                      style: const TextStyle(fontSize: 18)),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      purchase.productName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                        color: _dark,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${purchase.childName} · ${purchase.price.toStringAsFixed(2)} NIS',
                                      style: const TextStyle(
                                          fontSize: 12, color: _grey),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      purchase.reason,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: approved ? _green : _red,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
        );
      },
    );
  }
}

// ─── Settings Tab ───────────────────────────────────────────────────────────
class _SettingsTab extends StatelessWidget {

  const _SettingsTab();

  @override
  Widget build(BuildContext context) {
    return Consumer2<ChildProvider, ParentProvider>(
      builder: (context, childProvider, parentProvider, _) {
        return Scaffold(
          backgroundColor: _bg,
          appBar: AppBar(
            backgroundColor: _bg,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Settings',
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: _dark)),
                Text(
                  parentProvider.currentUser?.email ?? 'KidGuard settings',
                  style: const TextStyle(
                      fontSize: 12, color: _grey, fontWeight: FontWeight.w500),
                ),
              ],
            ),
            toolbarHeight: 68,
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Icon(Icons.tune_rounded,
                    color: _blue.withValues(alpha: 0.7), size: 26),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Parent Account Section
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 10)
                  ],
                ),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Parent Account 👤',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: _dark)),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: _blue.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.person_rounded,
                                color: _blue, size: 24),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  parentProvider.currentUser?.email ??
                                      'Not logged in',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: _dark,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Parent Email',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: _grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ]),
              ),
              const SizedBox(height: 14),

              // App Settings
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 10)
                  ],
                ),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('About 📖',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: _dark)),
                      const SizedBox(height: 8),
                      const Text(
                        'KidGuard is a simple parent app for allergy-safe canteen purchases and wristband alerts.',
                        style:
                            TextStyle(color: _grey, fontSize: 14, height: 1.6),
                      ),
                    ]),
              ),
              const SizedBox(height: 14),

              _SettingsTile(
                icon: Icons.notifications_outlined,
                label: 'Notifications',
                color: _purple,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AlertsScreen()),
                ),
              ),
              _SettingsTile(
                icon: Icons.language_outlined,
                label: 'Language',
                color: _teal,
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (_) => const AlertDialog(
                    title: Text('Language'),
                    content: Text(
                        'Language switching will be added in a future update.'),
                  ),
                ),
              ),
              _SettingsTile(
                icon: Icons.info_outline_rounded,
                label: 'App version 1.0.0',
                color: _grey,
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (_) => const AlertDialog(
                    title: Text('KidGuard'),
                    content: Text('App version 1.0.0'),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Logout
              _SettingsTile(
                icon: Icons.logout_rounded,
                label: 'Logout',
                color: const Color(0xFFFF9800),
                onTap: () => _showLogoutDialog(context, parentProvider),
              ),

              // Delete Account
              _SettingsTile(
                icon: Icons.delete_outline_rounded,
                label: 'Delete Account',
                color: _red,
                onTap: () => _showDeleteAccountDialog(context, parentProvider),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showLogoutDialog(BuildContext context, ParentProvider provider) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              provider.logout();
              Navigator.pop(ctx);
              Navigator.of(context).pushNamedAndRemoveUntil(
                '/',
                (route) => false,
              );
            },
            child: const Text('Logout', style: TextStyle(color: _orange)),
          ),
        ],
      ),
    );
  }

  void _showDeleteAccountDialog(BuildContext context, ParentProvider provider) {
    final passwordCtrl = TextEditingController();
    bool obscurePassword = true;

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (_, setState) => AlertDialog(
          title: const Text('Delete Account'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This action cannot be undone. All your data will be permanently deleted.',
                style: TextStyle(color: _red, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              const Text('Enter your password to confirm:'),
              const SizedBox(height: 12),
              TextField(
                controller: passwordCtrl,
                obscureText: obscurePassword,
                decoration: InputDecoration(
                  hintText: 'Your password',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                  suffixIcon: IconButton(
                    icon: Icon(
                      obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                    onPressed: () =>
                        setState(() => obscurePassword = !obscurePassword),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                if (passwordCtrl.text.isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Please enter your password')),
                  );
                  return;
                }

                final success = await provider.deleteAccount(passwordCtrl.text);
                if (success && ctx.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Account deleted successfully')),
                  );
                  Navigator.of(context).pushNamedAndRemoveUntil(
                    '/',
                    (route) => false,
                  );
                } else if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(
                        content: Text(provider.error ?? 'Deletion failed')),
                  );
                }
              },
              child: const Text('Delete', style: TextStyle(color: _red)),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  const _SettingsTile({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)
            ],
          ),
          child: Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 14),
            Text(
              label,
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600, color: _dark),
            ),
            const Spacer(),
            const Icon(Icons.chevron_right_rounded,
                color: Color(0xFFCCCCCC), size: 20),
          ]),
        ),
      ),
    );
  }
}

// ─── Shared Widgets ─────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final String emoji, title, subtitle;
  final VoidCallback? onAction;
  final String? actionLabel;
  const _EmptyState({
    required this.emoji,
    required this.title,
    required this.subtitle,
    this.onAction,
    this.actionLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 60)),
            const SizedBox(height: 16),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 17, color: _dark)),
            const SizedBox(height: 8),
            Text(subtitle,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(color: _grey, fontSize: 13, height: 1.5)),
            if (onAction != null) ...[
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(actionLabel ?? 'Add'),
                style: ElevatedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Vital Signs Row ────────────────────────────────────────────────────────
class _VitalSignsRow extends StatelessWidget {
  final WristbandData wristband;
  const _VitalSignsRow({required this.wristband});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _VitalCard(
          icon: '❤️',
          label: 'HR',
          value: '${wristband.heartRate}',
          unit: 'bpm',
          color: wristband.heartRate > 120 ? _red : _green,
        ),
        _VitalCard(
          icon: '🫁',
          label: 'SpO₂',
          value: '${wristband.spO2}',
          unit: '%',
          color: wristband.spO2 < 95 ? _red : _green,
        ),
        _VitalCard(
          icon: '🌡️',
          label: 'Temp',
          value: wristband.temperature.toStringAsFixed(1),
          unit: '°C',
          color: wristband.temperature > 37.5 ? _red : _green,
        ),
      ],
    );
  }
}

class _VitalCard extends StatelessWidget {
  final String icon, label, value, unit;
  final Color color;
  const _VitalCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(icon, style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 2),
            Text(
              value,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            Text(
              '$label $unit',
              style: const TextStyle(fontSize: 8, color: _grey),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Error State ────────────────────────────────────────────────────────────
class _ErrorState extends StatelessWidget {
  final String message;
  const _ErrorState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Text('😬', style: TextStyle(fontSize: 52)),
        const SizedBox(height: 12),
        Text(message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _grey, fontSize: 13)),
      ]),
    );
  }
}
