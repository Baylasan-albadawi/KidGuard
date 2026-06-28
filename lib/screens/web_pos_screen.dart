import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/firebase_service.dart';

const _posBg = Color(0xFFFFFCF6);
const _posBlue = Color(0xFF5C8DFF);
const _posGreen = Color(0xFF43A047);
const _posRed = Color(0xFFE53935);
const _posOrange = Color(0xFFFFB86C);
const _posDark = Color(0xFF1A1A2E);
const _posGrey = Color(0xFF777777);

class WebPosScreen extends StatefulWidget {
  const WebPosScreen({super.key});

  @override
  State<WebPosScreen> createState() => _WebPosScreenState();
}

class _WebPosScreenState extends State<WebPosScreen> {
  final FirebaseService _firebaseService = FirebaseService();
  final TextEditingController _wristbandCtrl = TextEditingController();
  final String _terminalId = 'canteen-1';

  String? _selectedProductId;
  PurchaseDecision? _lastDecision;
  bool _processing = false;
  bool _autoFilledFromScan = false;

  @override
  void dispose() {
    _wristbandCtrl.dispose();
    super.dispose();
  }

  Future<void> _processPurchase() async {
    if (_wristbandCtrl.text.trim().isEmpty || _selectedProductId == null) {
      setState(() {
        _lastDecision = const PurchaseDecision(
          approved: false,
          message: 'Scan/enter a wristband and select a product first.',
        );
      });
      return;
    }

    setState(() => _processing = true);
    try {
      final decision = await _firebaseService.processPurchase(
        wristbandId: _wristbandCtrl.text.trim(),
        productId: _selectedProductId!,
      );
      if (!mounted) return;
      setState(() {
        _processing = false;
        _lastDecision = decision;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _processing = false;
        _lastDecision = PurchaseDecision(
          approved: false,
          message: 'Firebase error: $e',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _posBg,
      appBar: AppBar(
        backgroundColor: _posBg,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'KidGuard POS',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: _posDark),
            ),
            Text(
              'Simple canteen checkout',
              style: TextStyle(fontSize: 12, color: _posGrey, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
      body: StreamBuilder<PosScan?>(
        stream: _firebaseService.getPosScanStream(_terminalId),
        builder: (context, scanSnapshot) {
          final scan = scanSnapshot.data;
          if (scan != null && !_autoFilledFromScan) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              setState(() {
                _wristbandCtrl.text = scan.wristbandId;
                if (scan.productId != null && scan.productId!.isNotEmpty) {
                  _selectedProductId = scan.productId;
                }
                _autoFilledFromScan = true;
              });
            });
          }

          if (scan == null && _autoFilledFromScan) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              setState(() => _autoFilledFromScan = false);
            });
          }

          return Row(
            children: [
              Expanded(
                flex: 3,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Panel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Wristband',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _posDark),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: _wristbandCtrl,
                              decoration: const InputDecoration(
                                hintText: 'Scan RFID or type wristband ID',
                                prefixIcon: Icon(Icons.watch_outlined),
                              ),
                            ),
                            const SizedBox(height: 10),
                            if (scan != null)
                              Text(
                                'Live RFID scan received at ${scan.timestamp.hour.toString().padLeft(2, '0')}:${scan.timestamp.minute.toString().padLeft(2, '0')}',
                                style: const TextStyle(color: _posBlue, fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: _Panel(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Products',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _posDark),
                              ),
                              const SizedBox(height: 12),
                              Expanded(
                                child: StreamBuilder<List<Product>>(
                                  stream: _firebaseService.getProductsStream(),
                                  builder: (context, snapshot) {
                                    if (!snapshot.hasData) {
                                      return const Center(child: CircularProgressIndicator());
                                    }

                                    final products = snapshot.data!;
                                    if (products.isEmpty) {
                                      return const Center(
                                        child: Text(
                                          'No products in Firebase yet.\nAdd products under /products.',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(color: _posGrey),
                                        ),
                                      );
                                    }

                                    return ListView.separated(
                                      itemCount: products.length,
                                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                                      itemBuilder: (context, index) {
                                        final product = products[index];
                                        final selected = product.productId == _selectedProductId;
                                        return InkWell(
                                          onTap: () => setState(() => _selectedProductId = product.productId),
                                          borderRadius: BorderRadius.circular(16),
                                          child: Container(
                                            padding: const EdgeInsets.all(14),
                                            decoration: BoxDecoration(
                                              color: selected
                                                  ? _posBlue.withValues(alpha: 0.12)
                                                  : Colors.white,
                                              borderRadius: BorderRadius.circular(16),
                                              border: Border.all(
                                                color: selected
                                                    ? _posBlue
                                                    : const Color(0xFFEAEAEA),
                                              ),
                                            ),
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        '${product.emoji.isEmpty ? '🍽️' : product.emoji} ${product.cat.isNotEmpty && product.cat != 'General' ? '[${product.cat}] ' : ''}${product.name}',
                                                        style: const TextStyle(
                                                          fontWeight: FontWeight.w700,
                                                          color: _posDark,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 4),
                                                      Text(
                                                        product.allergens.isEmpty
                                                            ? 'No allergens listed'
                                                            : 'Allergens: ${product.allergens.join(', ')}',
                                                        style: const TextStyle(
                                                          fontSize: 12,
                                                          color: _posGrey,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                Text(
                                                  '${product.price.toStringAsFixed(2)} NIS',
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w800,
                                                    color: _posDark,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 20, 20, 20),
                  child: Column(
                    children: [
                      _Panel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Checkout',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _posDark),
                            ),
                            const SizedBox(height: 14),
                            ElevatedButton.icon(
                              onPressed: _processing ? null : _processPurchase,
                              icon: _processing
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Icon(Icons.shopping_cart_checkout_rounded),
                              label: Text(_processing ? 'Processing...' : 'Validate & Purchase'),
                            ),
                            const SizedBox(height: 10),
                            OutlinedButton.icon(
                              onPressed: () async {
                                await _firebaseService.clearPosScan(_terminalId);
                                if (!mounted) return;
                                setState(() {
                                  _wristbandCtrl.clear();
                                  _selectedProductId = null;
                                  _lastDecision = null;
                                });
                              },
                              icon: const Icon(Icons.refresh_rounded),
                              label: const Text('Clear'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: _Panel(
                          child: _lastDecision == null
                              ? const Center(
                                  child: Text(
                                    'Waiting for checkout...',
                                    style: TextStyle(color: _posGrey, fontSize: 16),
                                  ),
                                )
                              : _DecisionCard(decision: _lastDecision!),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  final Widget child;
  const _Panel({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _DecisionCard extends StatelessWidget {
  final PurchaseDecision decision;
  const _DecisionCard({required this.decision});

  @override
  Widget build(BuildContext context) {
    final color = decision.approved ? _posGreen : _posRed;
    final accent = decision.approved ? 'Approved' : 'Blocked';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                accent,
                style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                decision.message,
                style: const TextStyle(color: _posDark, height: 1.5),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (decision.child != null) ...[
          Text('Child: ${decision.child!.name}', style: const TextStyle(color: _posDark, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
            'Balance: ${decision.child!.balance.toStringAsFixed(2)} NIS',
            style: const TextStyle(color: _posGrey),
          ),
          const SizedBox(height: 12),
        ],
        if (decision.product != null) ...[
          Text('Item: ${decision.product!.name}', style: const TextStyle(color: _posDark, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
            'Price: ${decision.product!.price.toStringAsFixed(2)} NIS',
            style: const TextStyle(color: _posGrey),
          ),
          if (decision.product!.allergens.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Allergens: ${decision.product!.allergens.join(', ')}',
              style: const TextStyle(color: _posOrange, fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ],
    );
  }
}
