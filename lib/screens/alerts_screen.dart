// lib/screens/alerts_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/alert_provider.dart';
import '../providers/child_provider.dart';
import '../models/models.dart';

const _bg     = Color(0xFFFFF8F0);
const _blue   = Color(0xFF4A90D9);
const _red    = Color(0xFFE53935);
const _grey   = Color(0xFF888888);
const _dark   = Color(0xFF1A1A2E);
const _card   = Colors.white;

class AlertsScreen extends StatelessWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer2<AlertProvider, ChildProvider>(
      builder: (context, alertP, childP, _) {
        final all    = alertP.allAlerts;
        final unread = all.where((a) => !a.read).toList();
        final read   = all.where((a) =>  a.read).toList();

        return Scaffold(
          backgroundColor: _bg,
          appBar: AppBar(
            backgroundColor: _bg,
            automaticallyImplyLeading: false,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Text('Alerts',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: _dark)),
                  if (unread.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                      decoration: BoxDecoration(color: _red, borderRadius: BorderRadius.circular(20)),
                      child: Text('${unread.length} new',
                          style: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white)),
                    ),
                  ],
                ]),
                Text(
                  childP.children.isEmpty ? 'No child yet — add one first' : 'Alerts & events',
                  style: const TextStyle(fontSize: 12, color: _grey, fontWeight: FontWeight.w500),
                ),
              ],
            ),
            toolbarHeight: 68,
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Icon(Icons.notifications_rounded,
                    color: _blue.withValues(alpha: 0.65), size: 26),
              ),
            ],
          ),
          body: all.isEmpty
              ? const _NoAlerts()
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (unread.isNotEmpty) ...[
                      _SectionLabel('UNREAD (${unread.length})'),
                      const SizedBox(height: 10),
                      ...unread.map((a) => _AlertCard(
                          alert: a, onTap: () => alertP.markRead(a.childId, a.alertId))),
                      const SizedBox(height: 20),
                    ],
                    if (read.isNotEmpty) ...[
                      const _SectionLabel('EARLIER'),
                      const SizedBox(height: 10),
                      ...read.map((a) => _AlertCard(alert: a)),
                    ],
                    const SizedBox(height: 24),
                  ],
                ),
        );
      },
    );
  }
}

class _NoAlerts extends StatelessWidget {
  const _NoAlerts();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('🎉', style: TextStyle(fontSize: 60)),
          SizedBox(height: 16),
          Text('All clear!',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: _dark)),
          SizedBox(height: 8),
          Text('Your children are all safe\nNo alerts to show 😊',
              textAlign: TextAlign.center,
              style: TextStyle(color: _grey, fontSize: 13, height: 1.6)),
        ]),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Text(label,
        style: const TextStyle(
            fontSize: 10, color: _grey, letterSpacing: 1.5, fontWeight: FontWeight.w800));
  }
}

class _AlertCard extends StatelessWidget {
  final Alert alert;
  final VoidCallback? onTap;
  const _AlertCard({required this.alert, this.onTap});

  @override
  Widget build(BuildContext context) {
    final isPanic = alert.type == 'panic';
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(16),
          border: alert.read
              ? null
              : Border.all(color: _red.withValues(alpha: 0.3), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: alert.read ? 0.03 : 0.06),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Opacity(
          opacity: alert.read ? 0.55 : 1.0,
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Text(isPanic ? '🆘' : '💓', style: const TextStyle(fontSize: 28)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(alert.message,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13, color: _dark)),
                const SizedBox(height: 3),
                Text('${alert.childId} · ${alert.time.toString().substring(0, 16)}',
                    style: const TextStyle(color: _grey, fontSize: 11)),
              ]),
            ),
            if (!alert.read)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: _red, borderRadius: BorderRadius.circular(8)),
                child: const Text('NEW',
                    style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)),
              ),
          ]),
        ),
      ),
    );
  }
}
