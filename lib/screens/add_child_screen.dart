import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../providers/child_provider.dart';

const _bg    = Color(0xFFFFF8F0);
const _blue  = Color(0xFF4A90D9);
const _green = Color(0xFF4CAF50);
const _grey  = Color(0xFF888888);
const _dark  = Color(0xFF1A1A2E);
const _card  = Colors.white;

class AddChildScreen extends StatefulWidget {
  const AddChildScreen({super.key});

  @override
  State<AddChildScreen> createState() => _AddChildScreenState();
}

class _AddChildScreenState extends State<AddChildScreen> {
  final _formKey      = GlobalKey<FormState>();
  final _nameCtrl     = TextEditingController();
  final _wristbandCtrl = TextEditingController();
  final _phoneCtrl    = TextEditingController();
  final _balanceCtrl  = TextEditingController(text: '20');
  DateTime? _birthdate;
  bool _loading = false;
  bool _success = false;
  String? _registeredDeviceId;
  final Set<String> _selectedAllergens = {};

  static const _allergens = [
    'Peanuts',
    'Milk',
    'Eggs',
    'Fish',
    'Wheat',
    'Tree Nuts',
    'Soy',
    'Shellfish',
    'Sesame',
  ];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _wristbandCtrl.dispose();
    _phoneCtrl.dispose();
    _balanceCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickBirthdate() async {
    final now = DateTime.now();
    final initial = _birthdate ?? DateTime(now.year - 8, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 17),
      lastDate: now,
      helpText: 'Select birthdate',
    );
    if (picked != null) {
      setState(() => _birthdate = picked);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_birthdate == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Please select a birthdate'),
        backgroundColor: Color(0xFFE53935),
      ));
      return;
    }
    setState(() => _loading = true);
    try {
      final child = Child(
        childId: '',
        name: _nameCtrl.text.trim(),
        birthdate: _birthdate,
        wristbandId: _wristbandCtrl.text.trim(),
        parentPhone: _phoneCtrl.text.trim(),
        balance: double.tryParse(_balanceCtrl.text.trim()) ?? 0,
        allergens: _selectedAllergens.toList()..sort(),
      );
      final deviceId = await context.read<ChildProvider>().addChild(child);
      setState(() {
        _loading = false;
        _success = true;
        _registeredDeviceId = deviceId;
      });
      await Future.delayed(const Duration(seconds: 3));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Oops: $e'),
          backgroundColor: const Color(0xFFE53935),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_success) {
      return Scaffold(
        backgroundColor: _bg,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 600),
                curve: Curves.elasticOut,
                builder: (_, v, child) => Transform.scale(scale: v, child: child),
                child: Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _green.withValues(alpha: 0.12),
                  ),
                  child: const Center(child: Text('🎉', style: TextStyle(fontSize: 44))),
                ),
              ),
              const SizedBox(height: 20),
              Text('${_nameCtrl.text} added!',
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w800, color: _dark)),
              const SizedBox(height: 6),
              const Text('Registered in Firebase',
                  style: TextStyle(color: _grey, fontSize: 14)),
              if (_registeredDeviceId != null) ...[
                const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _blue.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _blue.withValues(alpha: 0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('WRISTBAND DEVICE ID',
                          style: TextStyle(
                              fontSize: 10,
                              color: _grey,
                              letterSpacing: 1.2,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      SelectableText(
                        _registeredDeviceId!,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w800, color: _dark),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Set #define CHILD_ID to this value in your Arduino sketch so WiFi, Firebase, and SMS can find this child.',
                        style: TextStyle(color: _grey, fontSize: 12, height: 1.5),
                      ),
                    ],
                  ),
                ),
              ],
            ]),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        title: const Text('Add Child',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: _dark)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: _dark),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const SizedBox(height: 4),
            _PlayfulField(
              label: 'Full Name',
              hint: 'e.g. Emma',
              icon: Icons.person_outline_rounded,
              controller: _nameCtrl,
              validator: (v) => (v == null || v.isEmpty) ? 'Name is required' : null,
            ),
            const SizedBox(height: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('BIRTHDATE',
                    style: TextStyle(
                        fontSize: 10,
                        color: _grey,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                InkWell(
                  onTap: _pickBirthdate,
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    decoration: BoxDecoration(
                      color: _card,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _birthdate == null
                            ? const Color(0xFFEEEEEE)
                            : _blue,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.cake_outlined,
                            color: _blue.withValues(alpha: 0.6), size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _birthdate == null
                                ? 'Tap to select birthdate'
                                : '${_birthdate!.year}-${_birthdate!.month.toString().padLeft(2, '0')}-${_birthdate!.day.toString().padLeft(2, '0')}  (age ${_agePreview()} yrs)',
                            style: TextStyle(
                              color: _birthdate == null ? _grey : _dark,
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const Icon(Icons.calendar_today_rounded,
                            color: _grey, size: 18),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _PlayfulField(
              label: 'Wristband ID',
              hint: 'e.g. WB-004',
              icon: Icons.watch_outlined,
              controller: _wristbandCtrl,
              validator: (v) => (v == null || v.isEmpty) ? 'Wristband ID is required' : null,
            ),
            const SizedBox(height: 14),
            _PlayfulField(
              label: 'Parent Phone',
              hint: 'e.g. +972599000000',
              icon: Icons.phone_outlined,
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              validator: (v) => (v == null || v.isEmpty) ? 'Phone number is required' : null,
            ),
            const SizedBox(height: 20),
            _PlayfulField(
              label: 'Starting Balance',
              hint: 'e.g. 20',
              icon: Icons.account_balance_wallet_outlined,
              controller: _balanceCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Balance is required';
                final n = double.tryParse(v);
                if (n == null || n < 0) return 'Enter a valid balance';
                return null;
              },
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFEEEEEE)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'ALLERGENS TO BLOCK',
                    style: TextStyle(
                      fontSize: 10,
                      color: _grey,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _allergens.map((allergen) {
                      final selected = _selectedAllergens.contains(allergen);
                      return FilterChip(
                        selected: selected,
                        label: Text(allergen),
                        onSelected: (value) {
                          setState(() {
                            if (value) {
                              _selectedAllergens.add(allergen);
                            } else {
                              _selectedAllergens.remove(allergen);
                            }
                          });
                        },
                        selectedColor: _green.withValues(alpha: 0.16),
                        checkmarkColor: _green,
                        side: BorderSide(
                          color: selected ? _green : const Color(0xFFDDDDDD),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _blue.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _blue.withValues(alpha: 0.18)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('💡', style: TextStyle(fontSize: 20)),
                  SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Setup Tip',
                            style: TextStyle(
                                color: _blue, fontWeight: FontWeight.w700, fontSize: 13)),
                        SizedBox(height: 4),
                        Text(
                          'After registering, copy the Device ID into your wristband firmware (#define CHILD_ID). The band will then sync vitals to Firebase and load this parent phone for SMS.',
                          style: TextStyle(color: _grey, fontSize: 12, height: 1.6),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            ElevatedButton(
              onPressed: _loading ? null : _submit,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 54),
              ),
              child: _loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                  : const Text('Register Child'),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  int _agePreview() {
    if (_birthdate == null) return 0;
    final now = DateTime.now();
    var years = now.year - _birthdate!.year;
    if (now.month < _birthdate!.month ||
        (now.month == _birthdate!.month && now.day < _birthdate!.day)) {
      years--;
    }
    return years;
  }
}

class _PlayfulField extends StatelessWidget {
  final String label, hint;
  final IconData icon;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  const _PlayfulField({
    required this.label,
    required this.hint,
    required this.icon,
    required this.controller,
    this.keyboardType,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label.toUpperCase(),
          style: const TextStyle(
              fontSize: 10, color: _grey, letterSpacing: 1.2, fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        validator: validator,
        style: const TextStyle(color: _dark, fontSize: 15, fontWeight: FontWeight.w500),
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: Icon(icon, color: _blue.withValues(alpha: 0.6), size: 20),
          filled: true,
          fillColor: _card,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFEEEEEE)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: _blue, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFE53935)),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
    ]);
  }
}
