// -----------------------------------------------------------------------------
// zancrew_offer_detail.dart
//
// PREMIUM UI REFINEMENT (frontend only)
// ✅ Backend untouched
// ✅ Same features preserved: hydrate job, live distance refresh, maps, accept/reject
// ✅ Same API calls: /jobs/{id}, getOfferDetail, acceptOffer, rejectOffer
//
// File: lib/features/zancrew/screens/zancrew_offer_detail.dart
// -----------------------------------------------------------------------------

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/api_service.dart';
import '../../../core/widgets/payment_chip.dart';
import '../onboarding/uk_bank_details_screen.dart';

class CrewOfferDetail extends StatefulWidget {
  final Map<String, dynamic> offer;

  const CrewOfferDetail({super.key, required this.offer});

  @override
  State<CrewOfferDetail> createState() => _CrewOfferDetailState();
}

class _CrewOfferDetailState extends State<CrewOfferDetail> {
  bool _loading = true;
  bool _posting = false;
  bool _hasActiveJob = false;

  Map<String, dynamic>? _job; // Full hydrated job object
  double? _distanceKm; // Live distance from backend

  Map<String, dynamic> get _offer => widget.offer;

  // --- Core IDs ---
  String get _jobId => (_offer['job_id'] ?? '').toString();
  String get _offerId => (_offer['offer_id'] ?? _offer['id'] ?? '').toString();

  // --- Short title ---
  String get _shortTitle {
    final s = (_offer['short_title'] ?? '').toString();
    if (s.isNotEmpty) return s;

    final t = (_offer['task_title'] ?? '').toString();
    if (t.isNotEmpty) return t;

    return 'Job offer';
  }

  // --- Basic metadata ---
  String get _bucket => (_offer['bucket'] ?? '').toString();

  String get _whenLabel {
    final w = (_offer['when_label'] ?? '').toString();
    if (w.isNotEmpty) return w;

    final raw = (_offer['scheduled_at'] ?? '').toString();
    return raw;
  }

  // --- Distance display ---
  String get _distanceLabel {
    final d = _distanceKm ?? _offer['distance_km'];
    if (d == null) return '';

    try {
      final dd = (d is num) ? d.toDouble() : double.parse(d.toString());
      if (dd < 1.0) {
        final meters = (dd * 1000).round();
        return '$meters m';
      }
      return '${dd.toStringAsFixed(1)} km';
    } catch (_) {
      return '';
    }
  }

  // --- Price formatting ---
  String get _priceLabel {
    final currency = (_job?['currency'] ?? _offer['currency'] ?? '')
        .toString()
        .toUpperCase();

    // Prefer paise → rupees
    final paise =
        _job?['estimated_amount_paise'] ?? _offer['estimated_amount_paise'];

    if (paise != null) {
      try {
        final p = (paise is num)
            ? paise.toDouble()
            : double.parse(paise.toString());
        final rupees = p / 100.0;
        final symbol = (currency == 'INR')
            ? '₹'
            : (currency == 'GBP')
            ? '£'
            : '£';
        final isWhole = rupees.truncateToDouble() == rupees;
        return '$symbol${rupees.toStringAsFixed(isWhole ? 0 : 2)} est.';
      } catch (_) {}
    }

    // Fallback price
    final raw = _offer['price_estimate'];
    if (raw == null) return '';
    try {
      final v = (raw is num) ? raw.toDouble() : double.parse(raw.toString());
      final symbol = (currency == 'INR')
          ? '₹'
          : (currency == 'GBP')
          ? '£'
          : '£';
      if (raw is String && RegExp(r'[₹£]').hasMatch(raw)) return raw;
      return '$symbol${v.toStringAsFixed(2)} est.';
    } catch (_) {
      return raw.toString();
    }
  }

  // --- Description & address ---
  String get _address =>
      (_job?['location_address'] ?? _offer['location_address'] ?? '')
          .toString();

  String get _description {
    final d1 = (_job?['polished_task'] ?? '').toString();
    if (d1.isNotEmpty) return d1;
    return (_offer['polished_task'] ?? '').toString();
  }

  // --- Duration & people ---
  int? get _durationHours {
    final v = _job?['duration_hours'] ?? _offer['duration_hours'];
    if (v == null) return null;
    try {
      return (v is num) ? v.toInt() : int.parse(v.toString());
    } catch (_) {
      return null;
    }
  }

  int? get _peopleRequired {
    final v = _job?['people_required'] ?? _offer['people_required'];
    if (v == null) return null;
    try {
      return (v is num) ? v.toInt() : int.parse(v.toString());
    } catch (_) {
      return null;
    }
  }

  // --- Action list ---
  List<String> get _actions {
    final raw = _job?['actions'] ?? _offer['actions'];
    if (raw is List) {
      return raw
          .map((e) => e.toString())
          .where((s) => s.trim().isNotEmpty)
          .toList();
    }
    return const [];
  }

  // --- Tags ---
  List<String> get _tags {
    final raw = _job?['tags'] ?? _offer['tags'];
    if (raw is List) {
      return raw
          .map((e) => e.toString())
          .where((s) => s.trim().isNotEmpty)
          .toList();
    }
    return const [];
  }

  String? get _paymentStatus =>
      (_job?['payment_status'] ?? _offer['payment_status'])
          ?.toString()
          .toLowerCase();

  String get _importantNotes =>
      (_job?['important_notes'] ?? _offer['important_notes'] ?? '').toString();

  // -----------------------------------------------------------------------------
  // Lifecycle, API calls, distance refresh, Google Maps, Accept / Reject logic
  // -----------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();

    _distanceKm = (_offer['distance_km'] is num)
        ? (_offer['distance_km'] as num).toDouble()
        : double.tryParse((_offer['distance_km'] ?? '').toString());

    _refreshDistance();
    _loadJob();
    _checkActiveJob();
  }

  Future<void> _checkActiveJob() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id') ?? '';
      if (userId.isEmpty) return;

      final res = await ApiService.getJson('/zancrew/active_task');
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data is Map && data['active'] == true) {
          setState(() => _hasActiveJob = true);
        }
      }
      // 404 means no active job — leave _hasActiveJob false
    } catch (_) {
      // network error: do not block — backend guard is the safety net
    }
  }

  Future<void> _loadJob() async {
    if (_jobId.isEmpty) {
      setState(() {
        _job = {};
        _loading = false;
      });
      return;
    }

    setState(() => _loading = true);
    try {
      final res = await ApiService.getJson('/tasks/$_jobId');

      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data is Map) {
          setState(() => _job = Map<String, dynamic>.from(data));
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load job: HTTP ${res.statusCode}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load job: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refreshDistance() async {
    if (_offerId.isEmpty) return;

    try {
      final res = await ApiService.getOfferDetail(_offerId);
      if (!mounted) return;

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data is Map && data['distance_km'] != null) {
          final v = (data['distance_km'] is num)
              ? (data['distance_km'] as num).toDouble()
              : double.tryParse(data['distance_km'].toString());
          setState(() => _distanceKm = v);
        }
      }
    } catch (_) {
      // ignore for MVP
    }
  }

  Future<void> _openInGoogleMaps() async {
    final addr = _address;
    if (addr.isEmpty) return;

    final url = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(addr)}',
    );

    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not open Maps')));
    }
  }

  Future<void> _accept() async {
    if (_offerId.isEmpty) return;

    setState(() => _posting = true);
    try {
      await ApiService.acceptOffer(_offerId);
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Accepted')));
      Navigator.of(context).pop('accepted');
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().toLowerCase();
      if (msg.contains('403') ||
          msg.contains('bank') ||
          msg.contains('kyc') ||
          msg.contains('verified')) {
        _showBankMissingSheet();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to accept. Please try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  Future<void> _reject() async {
    if (_offerId.isEmpty) return;

    setState(() => _posting = true);
    try {
      await ApiService.rejectOffer(_offerId);
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Rejected')));
      Navigator.of(context).pop('rejected');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to reject. Please try again.')),
      );
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  // -----------------------------------------------------------------------------
  // Premium UI helpers (no backend changes)
  // -----------------------------------------------------------------------------

  void _showBankMissingSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: _border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Text(
                'Add bank details to accept jobs',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: _ink,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'We need your bank details before you can accept paid work.',
                style: TextStyle(fontSize: 14, color: _muted, height: 1.4),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const UkBankDetailsScreen(),
                      ),
                    );
                  },
                  child: const Text(
                    'Add bank details',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text(
                    'Not now',
                    style: TextStyle(
                      color: _muted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static const Color _accent = Color(0xFFD97706);
  static const Color _bg = Color(0xFFFCFAF6);
  static const Color _surface = Color(0xFFF5F2EE);
  static const Color _card = Colors.white;
  static const Color _ink = Color(0xFF26211C);
  static const Color _muted = Color(0xFF9B8B7E);
  static const Color _border = Color(0xFFE8E2D9);
  static const Color _success = Color(0xFF16A34A);

  Widget _softCard({required Widget child, EdgeInsets? padding}) {
    return Container(
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      padding: padding ?? const EdgeInsets.all(14),
      child: child,
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w800,
        color: _ink,
      ),
    );
  }

  Widget _pill({required IconData icon, required String text}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: _muted),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 12.5,
              color: _ink,
            ),
          ),
        ],
      ),
    );
  }

  Widget _tag(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _border),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w800,
          color: _ink,
        ),
      ),
    );
  }

  // -----------------------------------------------------------------------------
  // Full UI
  // -----------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Widget paymentChip = PaymentChip.fromMap(_job ?? _offer);

    final hasPaidSignal =
        (_paymentStatus == 'paid' || _paymentStatus == 'settled');

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: _ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Job Offer',
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: -0.2),
        ),
        actions: [
          IconButton(
            tooltip: 'Open in Google Maps',
            icon: const Icon(Icons.map_outlined),
            onPressed: _openInGoogleMaps,
          ),
          IconButton(
            tooltip: 'Refresh distance',
            icon: const Icon(Icons.refresh),
            onPressed: _refreshDistance,
          ),
        ],
      ),
      // Bottom bar: intentional decision area
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: _border)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_hasActiveJob)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: const Text(
                    'You already have an active job. Complete it before accepting another offer.',
                    style: TextStyle(
                      color: _accent,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              Row(
                children: [
                  // LEFT → Reject (secondary)
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _ink,
                          side: const BorderSide(color: _border),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: (_posting || _loading) ? null : _reject,
                        child: const Text(
                          'Reject',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 12),

                  // RIGHT → Accept (disabled when crew has an active job)
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          elevation: 0,
                          backgroundColor: _accent,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: _border,
                          disabledForegroundColor: _muted,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: (_posting || _loading || _hasActiveJob)
                            ? null
                            : _accept,
                        child: _posting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                _hasActiveJob
                                    ? 'Complete active job first'
                                    : 'Accept',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                  letterSpacing: -0.2,
                                ),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),

      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async {
                await _loadJob();
                await _refreshDistance();
              },
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
                children: [
                  // HEADER CARD: price + bucket + payment chip + title + key signals
                  _softCard(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              _priceLabel.isEmpty ? '—' : _priceLabel,
                              style: theme.textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.6,
                                color: _ink,
                              ),
                            ),
                            const Spacer(),
                            if (_bucket.isNotEmpty) _tag(_bucket),
                          ],
                        ),
                        const SizedBox(height: 8),

                        Align(
                          alignment: Alignment.centerLeft,
                          child: paymentChip,
                        ),

                        if (hasPaidSignal) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFECFDF5),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: _border),
                            ),
                            child: const Text(
                              'Payment confirmed',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 12.5,
                                color: _success,
                              ),
                            ),
                          ),
                        ],

                        const SizedBox(height: 10),
                        Text(
                          _shortTitle,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            height: 1.15,
                            color: _ink,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 10),

                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (_whenLabel.isNotEmpty)
                              _pill(icon: Icons.schedule, text: _whenLabel),
                            if (_distanceLabel.isNotEmpty)
                              _pill(
                                icon: Icons.place_outlined,
                                text: '$_distanceLabel away',
                              ),
                            if (_durationHours != null)
                              _pill(
                                icon: Icons.timer_outlined,
                                text: '${_durationHours}h',
                              ),
                            if (_peopleRequired != null)
                              _pill(
                                icon: Icons.people_alt_outlined,
                                text: 'People: $_peopleRequired',
                              ),
                          ],
                        ),

                        const SizedBox(height: 12),
                        const Text(
                          'Decide fast, but decide confidently.',
                          style: TextStyle(
                            color: _muted,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // LOCATION CARD (tap to open maps)
                  if (_address.isNotEmpty)
                    _softCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionTitle('Location'),
                          const SizedBox(height: 10),
                          InkWell(
                            onTap: _openInGoogleMaps,
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: _surface,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: _border),
                              ),
                              child: Row(
                                children: const [
                                  Icon(
                                    Icons.navigation_outlined,
                                    color: _muted,
                                  ),
                                  SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'Open directions in Maps',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        color: _ink,
                                      ),
                                    ),
                                  ),
                                  Icon(
                                    Icons.arrow_forward_ios,
                                    size: 14,
                                    color: _muted,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _address,
                            style: const TextStyle(
                              color: _muted,
                              height: 1.35,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),

                  if (_address.isNotEmpty) const SizedBox(height: 12),

                  // DETAILS
                  if (_description.isNotEmpty)
                    _softCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionTitle('Details'),
                          const SizedBox(height: 10),
                          Text(
                            _description,
                            style: const TextStyle(
                              color: _ink,
                              height: 1.5,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),

                  if (_description.isNotEmpty) const SizedBox(height: 12),

                  // EXPECTED ACTIONS (premium checklist)
                  if (_actions.isNotEmpty)
                    _softCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionTitle('Expected actions'),
                          const SizedBox(height: 10),
                          ..._actions.map((a) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    margin: const EdgeInsets.only(top: 3),
                                    width: 18,
                                    height: 18,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFEF3C7),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: _border),
                                    ),
                                    child: const Icon(
                                      Icons.check,
                                      size: 14,
                                      color: _accent,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      a,
                                      style: const TextStyle(
                                        color: _ink,
                                        height: 1.4,
                                        fontSize: 14.2,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                          const Text(
                            'If this matches your skills and time, accept.',
                            style: TextStyle(
                              color: _muted,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),

                  if (_actions.isNotEmpty) const SizedBox(height: 12),

                  // IMPORTANT NOTES
                  if (_importantNotes.trim().isNotEmpty)
                    _softCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionTitle('Important notes'),
                          const SizedBox(height: 10),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFFBEB),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFFFDE68A),
                              ),
                            ),
                            child: Text(
                              _importantNotes,
                              style: const TextStyle(
                                color: _ink,
                                height: 1.4,
                                fontSize: 13.8,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  if (_importantNotes.trim().isNotEmpty)
                    const SizedBox(height: 12),

                  // TAGS
                  if (_tags.isNotEmpty)
                    _softCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionTitle('Tags'),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _tags.map(_tag).toList(),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 12),

                  // Subtle utility row (optional, helpful)
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _ink,
                            side: const BorderSide(color: _border),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            minimumSize: const Size(double.infinity, 48),
                          ),
                          icon: const Icon(Icons.map_outlined),
                          label: const Text(
                            'Maps',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                          onPressed: _openInGoogleMaps,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _ink,
                            side: const BorderSide(color: _border),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            minimumSize: const Size(double.infinity, 48),
                          ),
                          icon: const Icon(Icons.refresh),
                          label: const Text(
                            'Update',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                          onPressed: _refreshDistance,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }
}
