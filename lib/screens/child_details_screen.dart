// lib/screens/child_details_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../providers/child_provider.dart';
import '../providers/alert_provider.dart';

class ChildDetailsScreen extends StatefulWidget {
  final Child child;
  const ChildDetailsScreen({super.key, required this.child});

  @override
  State<ChildDetailsScreen> createState() => _ChildDetailsScreenState();
}

class _ChildDetailsScreenState extends State<ChildDetailsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    // Start listening to alerts for this child
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context
          .read<AlertProvider>()
          .listenToAlertsForChild(widget.child.childId);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<ChildProvider, AlertProvider>(
      builder: (context, childP, alertP, _) {
        final wristband = childP.getWristband(widget.child.childId);
        final isAlert = wristband?.status == 'alert';
        final heartColor =
            isAlert ? const Color(0xFFFF1744) : const Color(0xFF00E676);

        return Scaffold(
          backgroundColor: const Color(0xFF0A0E1A),
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.child.name),
                Text(widget.child.wristbandId,
                    style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF6B7A99),
                        fontWeight: FontWeight.w400)),
              ],
            ),
            actions: [
              IconButton(
                tooltip: 'Delete child',
                onPressed: () => _confirmDelete(context),
                icon: const Icon(Icons.delete_outline_rounded,
                    color: Color(0xFFFF1744)),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: _StatusChip(
                  label: isAlert
                      ? 'Alert!'
                      : wristband?.connected == true
                          ? 'Safe'
                          : 'Offline',
                  color: isAlert
                      ? const Color(0xFFFF1744)
                      : wristband?.connected == true
                          ? const Color(0xFF00E676)
                          : const Color(0xFF6B7A99),
                ),
              ),
            ],
            bottom: TabBar(
              controller: _tabController,
              indicatorColor: const Color(0xFF00D4FF),
              labelColor: const Color(0xFF00D4FF),
              unselectedLabelColor: const Color(0xFF6B7A99),
              tabs: const [
                Tab(text: 'Info'),
                Tab(text: 'Alerts'),
                Tab(text: 'Wristband'),
              ],
            ),
          ),
          body: Column(
            children: [
              // Heart rate header
              Container(
                color: const Color(0xFF111827),
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _PulsingHeart(color: heartColor),
                    const SizedBox(width: 20),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          wristband != null ? '${wristband.heartRate}' : '--',
                          style: TextStyle(
                              fontSize: 48,
                              fontWeight: FontWeight.w900,
                              color: heartColor,
                              height: 1,
                              letterSpacing: -2),
                        ),
                        const Text('bpm — heart rate',
                            style: TextStyle(
                                color: Color(0xFF6B7A99), fontSize: 12)),
                        if (isAlert)
                          const Padding(
                            padding: EdgeInsets.only(top: 4),
                            child: Text('⚠️ Elevated — check on child',
                                style: TextStyle(
                                    color: Color(0xFFFF1744),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700)),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _InfoTab(
                        child: widget.child,
                        wristband: wristband,
                        alertP: alertP),
                    _AlertsTab(childId: widget.child.childId, alertP: alertP),
                    _WristbandTab(child: widget.child, wristband: wristband),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111827),
        title: const Text('Delete child?'),
        content: Text(
          'Remove ${widget.child.name} and all Firebase data (vitals, alerts, purchases)? This cannot be undone.',
          style: const TextStyle(color: Color(0xFF6B7A99)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete',
                style: TextStyle(color: Color(0xFFFF1744))),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await context.read<ChildProvider>().deleteChild(widget.child.childId);
    if (context.mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${widget.child.name} removed')),
      );
    }
  }
}

class _InfoTab extends StatelessWidget {
  final Child child;
  final WristbandData? wristband;
  final AlertProvider alertP;
  const _InfoTab(
      {required this.child, required this.wristband, required this.alertP});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _InfoRow(icon: '👤', label: 'Full Name', value: child.name),
        _InfoRow(
          icon: '🎂',
          label: 'Age',
          value: child.birthdate != null
              ? '${child.age} years old (born ${child.birthdate!.toIso8601String().split('T').first})'
              : '${child.age} years old',
        ),
        _InfoRow(
            icon: '❤️',
            label: 'Heart Rate',
            value:
                wristband != null ? '${wristband!.heartRate} bpm' : 'No data'),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String icon, label, value;
  const _InfoRow(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1E2A3A)),
      ),
      child: Row(
        children: [
          Text(icon, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style:
                      const TextStyle(fontSize: 11, color: Color(0xFF6B7A99))),
              const SizedBox(height: 2),
              Text(value,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }
}

class _AlertsTab extends StatelessWidget {
  final String childId;
  final AlertProvider alertP;
  const _AlertsTab({required this.childId, required this.alertP});

  @override
  Widget build(BuildContext context) {
    final alerts = alertP.getAlertsForChild(childId);
    if (alerts.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('✅', style: TextStyle(fontSize: 48)),
            SizedBox(height: 12),
            Text('No alerts',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            SizedBox(height: 6),
            Text('All clear',
                style: TextStyle(color: Color(0xFF6B7A99), fontSize: 13)),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: alerts.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final a = alerts[i];
        return GestureDetector(
          onTap: () => alertP.markRead(childId, a.alertId),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF111827),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: a.read
                      ? const Color(0xFF1E2A3A)
                      : const Color(0xFFFF1744).withValues(alpha: 0.35)),
            ),
            child: Row(
              children: [
                Text(a.type == 'panic' ? '🆘' : '💓',
                    style: const TextStyle(fontSize: 24)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(a.message,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 13)),
                      const SizedBox(height: 3),
                      Text(a.time.toString().substring(0, 16),
                          style: const TextStyle(
                              color: Color(0xFF6B7A99), fontSize: 11)),
                    ],
                  ),
                ),
                if (!a.read)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                        color: const Color(0xFFFF1744),
                        borderRadius: BorderRadius.circular(6)),
                    child: const Text('NEW',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w800)),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _WristbandTab extends StatelessWidget {
  final Child child;
  final WristbandData? wristband;
  const _WristbandTab({required this.child, required this.wristband});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: const Color(0xFF111827),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: const Color(0xFF00D4FF).withValues(alpha: 0.2)),
          ),
          child: Column(
            children: [
              const Icon(Icons.watch_rounded,
                  color: Color(0xFF00D4FF), size: 48),
              const SizedBox(height: 12),
              const Text('Smart Wristband',
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                      letterSpacing: -0.3)),
              const SizedBox(height: 4),
              Text(child.wristbandId,
                  style:
                      const TextStyle(color: Color(0xFF6B7A99), fontSize: 12)),
              const SizedBox(height: 14),
              _StatusChip(
                label: wristband?.connected == true
                    ? 'Connected ✓'
                    : 'Disconnected',
                color: wristband?.connected == true
                    ? const Color(0xFF00E676)
                    : const Color(0xFF6B7A99),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 12, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _PulsingHeart extends StatefulWidget {
  final Color color;
  const _PulsingHeart({required this.color});

  @override
  State<_PulsingHeart> createState() => _PulsingHeartState();
}

class _PulsingHeartState extends State<_PulsingHeart>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.85, end: 1.15)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _anim,
      child: Container(
        width: 68,
        height: 68,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color.withValues(alpha: 0.12),
        ),
        child: Icon(Icons.favorite_rounded, color: widget.color, size: 32),
      ),
    );
  }
}
