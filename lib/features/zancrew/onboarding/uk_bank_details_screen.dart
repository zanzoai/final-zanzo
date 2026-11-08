import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/services/uk_provider_api.dart';
import '../../../core/widgets/skeleton.dart';

class UkBankDetailsScreen extends StatefulWidget {
  const UkBankDetailsScreen({super.key});

  @override
  State<UkBankDetailsScreen> createState() => _UkBankDetailsScreenState();
}

class _UkBankDetailsScreenState extends State<UkBankDetailsScreen> {
  static const Color _accent = Color(0xFFD97706);
  static const Color _bg = Color(0xFFFCFAF6);
  static const Color _surface = Color(0xFFF5F2EE);
  static const Color _ink = Color(0xFF26211C);
  static const Color _muted = Color(0xFF9B8B7E);
  static const Color _border = Color(0xFFE8E2D9);
  static const Color _success = Color(0xFF16A34A);

  bool _loading = true;
  bool _saving = false;
  bool _editing = false;

  Map<String, dynamic>? _saved;

  final _nameCtrl = TextEditingController();
  final _sortCtrl = TextEditingController();
  final _accountCtrl = TextEditingController();
  final _bankCtrl = TextEditingController();
  bool _confirmed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _sortCtrl.dispose();
    _accountCtrl.dispose();
    _bankCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await UkProviderApi.getBankDetails();
      setState(() {
        _saved = data;
        _loading = false;
      });
    } catch (_) {
      setState(() {
        _saved = {'has_bank_details': false};
        _loading = false;
      });
    }
  }

  bool get _hasSaved => _saved?['has_bank_details'] == true;

  bool _sortCodeValid(String v) => v.replaceAll(RegExp(r'\D'), '').length == 6;

  bool _accountValid(String v) => v.replaceAll(RegExp(r'\D'), '').length == 8;

  bool get _formValid {
    final name = _nameCtrl.text.trim();
    return name.length >= 2 &&
        name.length <= 150 &&
        _sortCodeValid(_sortCtrl.text) &&
        _accountValid(_accountCtrl.text) &&
        _confirmed;
  }

  void _startEditing() {
    _nameCtrl.text = _saved?['account_holder_name']?.toString() ?? '';
    _sortCtrl.clear();
    _accountCtrl.clear();
    _bankCtrl.text = _saved?['bank_name']?.toString() ?? '';
    _confirmed = false;
    setState(() => _editing = true);
  }

  Future<void> _save() async {
    if (!_formValid || _saving) return;
    setState(() => _saving = true);
    try {
      final result = await UkProviderApi.saveBankDetails(
        accountHolderName: _nameCtrl.text.trim(),
        sortCode: _sortCtrl.text.trim(),
        accountNumber: _accountCtrl.text.trim(),
        bankName: _bankCtrl.text.trim().isEmpty ? null : _bankCtrl.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _saved = result;
        _editing = false;
        _saving = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Bank details saved')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Something went wrong. Please try again.'),
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: _ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Bank Details',
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: -0.2),
        ),
      ),
      body: _loading
          ? const SkeletonDetail()
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: _hasSaved && !_editing
                    ? _buildStatusCard()
                    : _buildForm(),
              ),
            ),
    );
  }

  // ---------------------------------------------------------------------------
  // STATUS CARD
  // ---------------------------------------------------------------------------
  Widget _buildStatusCard() {
    final name = _saved?['account_holder_name']?.toString() ?? '';
    final last4 = _saved?['account_number_last4']?.toString() ?? '';
    final sortDisplay = _saved?['sort_code_display']?.toString() ?? '';
    final bankName = _saved?['bank_name']?.toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _border),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0A000000),
                blurRadius: 16,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: const Color(0xFFECFDF5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.check, size: 18, color: _success),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Bank details saved',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: _ink,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: _border),
              _detailRow('Account holder', name),
              _detailRow('Account', '••••$last4'),
              _detailRow('Sort code', sortDisplay),
              if (bankName != null && bankName.isNotEmpty)
                _detailRow('Bank', bankName),
              const SizedBox(height: 8),
            ],
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          height: 50,
          child: OutlinedButton(
            onPressed: _startEditing,
            style: OutlinedButton.styleFrom(
              foregroundColor: _ink,
              side: const BorderSide(color: _border, width: 1.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text(
              'Update Bank Details',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
          ),
        ),
      ],
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              color: _muted,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              color: _ink,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // FORM
  // ---------------------------------------------------------------------------
  Widget _buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildInfoBanner(),
        const SizedBox(height: 20),
        _field(
          controller: _nameCtrl,
          label: 'Account holder name',
          hint: 'Full name as on your bank account',
          keyboardType: TextInputType.name,
          textCapitalization: TextCapitalization.words,
          maxLength: 150,
        ),
        const SizedBox(height: 14),
        _field(
          controller: _sortCtrl,
          label: 'Sort code',
          hint: '12-34-56',
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[\d\-\s]')),
            LengthLimitingTextInputFormatter(8),
          ],
        ),
        const SizedBox(height: 14),
        _field(
          controller: _accountCtrl,
          label: 'Account number',
          hint: '12345678',
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(8),
          ],
        ),
        const SizedBox(height: 14),
        _field(
          controller: _bankCtrl,
          label: 'Bank name (optional)',
          hint: 'e.g. Barclays, HSBC',
          maxLength: 100,
        ),
        const SizedBox(height: 20),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: _confirmed,
              activeColor: _accent,
              onChanged: (v) => setState(() => _confirmed = v ?? false),
            ),
            const SizedBox(width: 4),
            const Expanded(
              child: Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'I confirm this bank account is in my name.',
                  style: TextStyle(
                    fontSize: 14,
                    color: _ink,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: _formValid && !_saving ? _save : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: Colors.white,
              elevation: 0,
              disabledBackgroundColor: _border,
              disabledForegroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: _saving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.5,
                    ),
                  )
                : Text(
                    _hasSaved ? 'Update Bank Details' : 'Save Bank Details',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15.5,
                    ),
                  ),
          ),
        ),
        if (_hasSaved) ...[
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => setState(() => _editing = false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: _muted, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildInfoBanner() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      padding: const EdgeInsets.all(14),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: _accent),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your bank details are used to process your earnings. '
                  'These are stored securely and only seen by the Zanzo payments team.',
                  style: TextStyle(
                    fontSize: 13.5,
                    color: _ink,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'For secure payouts, your account holder name should match the full legal name used in your ZanCrew application. If it doesn\'t, payouts may be delayed while our team reviews it.',
                  style: TextStyle(fontSize: 13, color: _ink, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required String hint,
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.none,
    int? maxLength,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: _ink,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          textCapitalization: textCapitalization,
          maxLength: maxLength,
          inputFormatters: inputFormatters,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: _muted),
            counterText: '',
            filled: true,
            fillColor: _surface,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 14,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _ink, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}
