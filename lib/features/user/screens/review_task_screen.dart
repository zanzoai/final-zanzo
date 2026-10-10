// lib/features/user/screens/review_task_screen.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:geocoding/geocoding.dart' as geocoding;
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Core services
import 'package:zanzo_frontend/core/services/api_service.dart';
import 'package:zanzo_frontend/core/services/auth.dart';
// Widgets
import 'package:zanzo_frontend/core/widgets/location_selector.dart';
// Screens
import 'package:zanzo_frontend/features/user/screens/track_job_screen.dart';
import 'package:zanzo_frontend/core/services/token_store.dart';
import 'package:zanzo_frontend/core/utils/log.dart';
import 'package:zanzo_frontend/core/utils/currency.dart';

enum PaymentMethod { standard }

/// Strict word limit for job title
class WordLimitFormatter extends TextInputFormatter {
  final int maxWords;
  WordLimitFormatter(this.maxWords);

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final words = newValue.text.trim().split(RegExp(r"\s+"));
    if (words.length > maxWords) {
      final limited = words.take(maxWords).join(" ");
      return TextEditingValue(
        text: limited,
        selection: TextSelection.collapsed(offset: limited.length),
      );
    }
    return newValue;
  }
}

class ReviewTaskScreen extends StatefulWidget {
  final String taskType;
  final Map<String, dynamic> taskDetail;
  final double? initialLat;
  final double? initialLng;

  const ReviewTaskScreen({
    super.key,
    required this.taskType,
    required this.taskDetail,
    this.initialLat,
    this.initialLng,
  });

  @override
  State<ReviewTaskScreen> createState() => _ReviewTaskScreenState();
}

class _ReviewTaskScreenState extends State<ReviewTaskScreen> {
  // ========================= UI STATE =========================
  bool _expanded = false;
  bool _isNow = true;
  int _peopleCount = 1;
  double _durationHours = 0.5;
  DateTime? _scheduledAt;
  bool _isProcessing = false;
  bool _postPayment = false; // true after Stripe sheet closes, until navigation

  // Pickup
  bool _hasPickup = false;
  final TextEditingController _pickupController = TextEditingController();
  double? _pickupLat;
  double? _pickupLng;

  // ========================= DATA =========================
  late TextEditingController _taskController;
  late TextEditingController _locationController;
  late TextEditingController _titleController;

  final TextEditingController _chipEditController = TextEditingController();
  List<String> _importantNotes = [];

  double _estimatedCost = 0.0;
  // Until the server's first quote arrives this is a guess from the user's
  // saved country (India → INR, otherwise GBP); after that it is always the
  // currency the server quoted / charged.
  String _currencyCode = 'GBP';
  // Price of one 30-minute block for one person, from the server's quote, so
  // later changes to people/duration can update the price instantly.
  double? _pricePerBlock;
  // Default per-block prices — only used if the server can't be reached.
  static const _fallbackPerBlock = {'GBP': 7.80, 'INR': 150.0};

  // A task created for a payment that was cancelled or failed. Retrying reuses
  // it (instead of creating another task + PaymentIntent each time) as long as
  // the details haven't changed; it is deleted if the user leaves unpaid.
  String? _pendingJobId;
  String? _pendingJobKey;
  bool _paid = false;
  int _costRequest = 0;

  double? _selectedLat;
  double? _selectedLng;

  // ========================= THEME (WARM / MATCHES HOME SCREEN) =========================
  static const Color _accent = Color(
    0xFFD97706,
  ); // saffron — matches home screen
  static const Color _bg = Color(
    0xFFFCFAF6,
  ); // warm off-white — matches home screen
  static const Color _surface = Color(
    0xFFF5F2EE,
  ); // warm surface for inputs / pills
  static const Color _card = Colors.white;
  static const Color _ink = Color(
    0xFF26211C,
  ); // warm charcoal — matches home screen
  static const Color _muted = Color(
    0xFF8C8378,
  ); // warm muted — matches home screen
  static const Color _line = Color(0xFFE8E2D9); // warm divider

  // ========================= INIT =========================
  @override
  void initState() {
    super.initState();

    _taskController = TextEditingController(
      text: (widget.taskDetail['polished_task'] ?? '').toString(),
    );

    _locationController = TextEditingController(
      text:
          (widget.taskDetail['location_address'] ??
                  widget.taskDetail['delivery_address'] ??
                  '')
              .toString(),
    );

    final t0 = _locationController.text.trim().toLowerCase();
    if (t0.isEmpty || t0 == 'unknown address' || t0 == 'unknown location') {
      _locationController.text = '';
    }

    _titleController = TextEditingController(
      text:
          (widget.taskDetail['task_title'] ??
                  widget.taskDetail['job_title'] ??
                  widget.taskType)
              .toString(),
    );

    // AUTO-DETERMINE PICKUP NEED
    _autoDetectPickupFromTask();

    // Prefill notes
    final rawNotes = widget.taskDetail['important_notes'];
    if (rawNotes is List) {
      _importantNotes = rawNotes
          .map((e) => e.toString())
          .where((e) => e.trim().isNotEmpty)
          .toList();
    } else if (rawNotes is String && rawNotes.trim().isNotEmpty) {
      _importantNotes = rawNotes
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    } else {
      _importantNotes = _extractKeywords(_taskController.text);
    }

    _durationHours = 0.5;

    // Seed coordinates passed from HomeScreen (GPS position captured before processTask call).
    // These are the authoritative coordinates for this task; LocationSelector.onSelected
    // will overwrite them if the user explicitly changes the address.
    _selectedLat = widget.initialLat;
    _selectedLng = widget.initialLng;

    _currencyCode = CurrencyFormatter.userCurrency();
    _fetchEstimatedCost();

    // ========================= AUTO LOCATION PREFILL (GPS) =========================
    // Only activate when both the address field AND the seeded coordinates are absent.
    if (_locationController.text.trim().isEmpty && _selectedLat == null) {
      Future.microtask(() {
        Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.best)
            .then((pos) async {
              final prefs = await SharedPreferences.getInstance();
              _selectedLat = pos.latitude;
              _selectedLng = pos.longitude;
              if (mounted) _fetchEstimatedCost();

              String address;

              try {
                final placemarks = await geocoding.placemarkFromCoordinates(
                  pos.latitude,
                  pos.longitude,
                );

                final p = placemarks.isNotEmpty ? placemarks.first : null;
                final parts = <String>[
                  if ((p?.subThoroughfare ?? '').trim().isNotEmpty)
                    p!.subThoroughfare!,
                  if ((p?.thoroughfare ?? '').trim().isNotEmpty)
                    p!.thoroughfare!,
                  if ((p?.subLocality ?? '').trim().isNotEmpty) p!.subLocality!,
                  if ((p?.locality ?? '').trim().isNotEmpty) p!.locality!,
                  if ((p?.postalCode ?? '').trim().isNotEmpty) p!.postalCode!,
                ];

                address = parts.where((s) => s.trim().isNotEmpty).join(', ');
                if (address.isEmpty) address = "Current location";
              } catch (_) {
                address = "Current location";
              }

              _locationController.text = address;

              await prefs.setString('review_address', address);
              await prefs.setString('review_place_id', 'auto');
              await prefs.setDouble('review_lat', pos.latitude);
              await prefs.setDouble('review_lng', pos.longitude);

              if (mounted) setState(() {});
            })
            .catchError((_) {});
      });
    }
  }

  @override
  void dispose() {
    final abandoned = _pendingJobId;
    if (abandoned != null && !_paid) {
      ApiService.deleteUnpaidTask(abandoned); // fire and forget
    }
    _taskController.dispose();
    _locationController.dispose();
    _pickupController.dispose();
    _titleController.dispose();
    _chipEditController.dispose();
    super.dispose();
  }

  // ========================= HELPERS =========================
  List<String> _extractKeywords(String text) {
    if (text.isEmpty) return [];
    final lower = text.toLowerCase();

    final numberish = RegExp(
      r'(?:(?:no\.?|flat|apt|apartment|house|door|gate|room|block|floor)\s*)?#?\b\d+[a-z]?\b',
    );

    final nouns = <String>[
      'wardrobe',
      'cupboard',
      'locker',
      'kitchen',
      'bathroom',
      'toilet',
      'bedroom',
      'balcony',
      'garden',
      'bin',
      'box',
      'parcel',
      'package',
      'sofa',
      'fridge',
      'oven',
      'microwave',
      'tv',
      'router',
      'ac',
      'lift',
      'stairs',
      'landmark',
      'security',
      'reception',
    ];

    final set = <String>{};

    for (final m in numberish.allMatches(lower)) {
      final s = m.group(0)?.trim();
      if (s != null && s.isNotEmpty) set.add(s);
    }

    for (final n in nouns) {
      if (lower.contains(RegExp('\\b$n\\b'))) set.add(n);
    }

    final originals = <String>[];
    for (final k in set) {
      final idx = text.toLowerCase().indexOf(k);
      originals.add(idx >= 0 ? text.substring(idx, idx + k.length) : k);
    }

    return originals;
  }

  Future<String?> _addNoteDialog() async {
    _chipEditController.clear();

    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Add note"),
        content: TextField(
          controller: _chipEditController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: "Flat number, landmark, gate code…",
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(ctx, _chipEditController.text.trim()),
            child: const Text("Add"),
          ),
        ],
      ),
    );
  }

  // =====================================================
  // AUTO-DETECT PICKUP BASED ON PROMPT / STRUCTURED FIELDS
  // =====================================================
  void _autoDetectPickupFromTask() {
    final text = _taskController.text.toLowerCase();

    // 1) Use structured tags from backend if present
    final tags = widget.taskDetail['tags'];
    if (tags is List) {
      for (final t in tags) {
        final tag = t.toString().toLowerCase();
        if (tag.contains("pickup") ||
            tag.contains("drop") ||
            tag.contains("delivery") ||
            tag.contains("collect") ||
            tag.contains("collection")) {
          setState(() => _hasPickup = true);
          return;
        }
      }
    }

    // 2) Use primary_category from backend if present
    final cat = (widget.taskDetail['primary_category'] ?? "")
        .toString()
        .toLowerCase();
    if (cat.contains("delivery") || cat.contains("pickup")) {
      setState(() => _hasPickup = true);
      return;
    }

    // 3) Keyword scan in polished prompt
    final pickupKeywords = [
      "pickup",
      "pick up",
      "collect",
      "collect from",
      "drop",
      "drop off",
      "bring from",
      "from another location",
      "take from",
      "deliver from",
    ];

    for (final k in pickupKeywords) {
      if (text.contains(k)) {
        setState(() => _hasPickup = true);
        return;
      }
    }
  }

  void _suggestNotesFromText() {
    final suggestions = _extractKeywords(_taskController.text);
    final existingLC = _importantNotes.map((e) => e.toLowerCase()).toSet();
    final merged = List<String>.from(_importantNotes);

    for (final s in suggestions) {
      if (!existingLC.contains(s.toLowerCase())) merged.add(s);
    }

    setState(() => _importantNotes = merged);
  }

  String _tidyTitleForSubmit(String s) {
    var t = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    t = t.replaceAll(RegExp(r'\.+$'), '');
    return t;
  }

  String get _conciseTitle {
    final t = _titleController.text.trim();
    if (t.isNotEmpty) return _tidyTitleForSubmit(t);

    final polished = _taskController.text.trim();
    if (polished.isNotEmpty) {
      final first = polished
          .split('\n')
          .firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
      return _tidyTitleForSubmit(
        first.length > 48 ? first.substring(0, 48) : first,
      );
    }

    return _tidyTitleForSubmit(widget.taskType);
  }

  List<String> get _actions {
    final raw = widget.taskDetail['actions'];
    if (raw is List) {
      return raw
          .map((e) => e.toString())
          .where((e) => e.trim().isNotEmpty)
          .toList();
    }
    return const [];
  }

  List<String> get _tags {
    final raw = widget.taskDetail['tags'];
    if (raw is List) {
      return raw
          .map((e) => e.toString())
          .where((e) => e.trim().isNotEmpty)
          .toList();
    }
    return const [];
  }

  String _formatAmount(num amt) => CurrencyFormatter.format(amt, _currencyCode);

  String get _scheduleLabel {
    if (_scheduledAt == null) return "Schedule";
    return DateFormat("dd MMM, hh:mm a").format(_scheduledAt!);
  }

  // ========================= COST CALC =========================
  Future<void> _fetchEstimatedCost() async {
    final request = ++_costRequest;
    try {
      final safeDuration = double.parse(_durationHours.toStringAsFixed(1));
      final blocks = ((safeDuration * 60).round() / 30).ceil();

      // Instant estimate from the server's own per-block price (or, before the
      // first quote, the default price for the user's market)…
      final perBlock =
          _pricePerBlock ?? _fallbackPerBlock[_currencyCode] ?? 7.80;
      if (!mounted) return;
      setState(() => _estimatedCost = blocks * perBlock * _peopleCount);

      // …then the server's quote. The server decides the country — from the
      // task location when we have one, else the user's profile, else the UK —
      // so the amount and currency match what the task will be charged.
      if ((await TokenStore.accessToken()) == null) return;
      final quote = await ApiService.calculateCost(
        safeDuration,
        people: _peopleCount,
        lat: _selectedLat,
        lng: _selectedLng,
      );
      final amount = (quote?['estimated_cost'] as num?)?.toDouble();
      final currency = quote?['currency_code']?.toString();
      final serverPerBlock = (quote?['price_per_block'] as num?)?.toDouble();
      // Ignore a late answer to an older request (user kept changing values).
      if (!mounted || request != _costRequest || amount == null) return;
      setState(() {
        _estimatedCost = amount;
        if (currency != null && currency.isNotEmpty) {
          _currencyCode = currency.toUpperCase();
        }
        if (serverPerBlock != null) _pricePerBlock = serverPerBlock;
      });
    } catch (e) {
      dlog('cost estimate failed: $e');
    }
  }

  // ========================= SCHEDULING =========================
  Future<void> _pickSchedule() async {
    final now = DateTime.now();

    final pickedDate = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 7)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: _accent,
              onPrimary: Colors.white,
              surface: _card,
              onSurface: _ink,
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(foregroundColor: _accent),
            ),
          ),
          child: child!,
        );
      },
    );
    if (pickedDate == null) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      initialEntryMode: TimePickerEntryMode.input,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: _accent,
              onPrimary: Colors.white,
              surface: _card,
              onSurface: _ink,
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(foregroundColor: _accent),
            ),
          ),
          child: child!,
        );
      },
    );
    if (pickedTime == null) return;
    // Working hours (07:00–22:00) are checked by the server in the task's own
    // country time zone (London / Kolkata) and its message is shown if the
    // time is outside them. A check here would use the phone's time zone.

    setState(() {
      _isNow = false;
      _scheduledAt = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
      );
    });

    _fetchEstimatedCost();
  }

  /// Message safe to show a customer: our own exceptions carry a readable
  /// sentence; anything else (network, parsing) gets a generic one.
  String _friendlyError(Object e) {
    final text = e.toString().replaceFirst('Exception: ', '');
    if (e is Exception && text.length < 140 && !text.contains('{')) return text;
    return 'Payment could not be completed. Please try again.';
  }

  int _toMinorUnits(double amount, String currency) => (amount * 100).round();

  // ========================= PAYMENT =========================
  Map<String, dynamic> _jobPayload() {
    final utcWhen = (_isNow ? DateTime.now() : (_scheduledAt ?? DateTime.now()))
        .toUtc();
    final notesText = _importantNotes.isEmpty
        ? null
        : _importantNotes.join(", ");
    return {
      "title": _conciseTitle,
      "polished_task": _taskController.text,

      // DELIVERY / RETURN ADDRESS
      "location_address": _locationController.text,
      "latitude": _selectedLat,
      "longitude": _selectedLng,

      // PICKUP FIELDS
      "pickup_address": _hasPickup ? _pickupController.text : null,
      "pickup_latitude": _hasPickup ? _pickupLat : null,
      "pickup_longitude": _hasPickup ? _pickupLng : null,

      // OTHER FIELDS (price and currency are set by the server)
      "scheduled_at": utcWhen.toIso8601String(),
      "duration_hours": _durationHours,
      "people_required": _peopleCount,
      "notes": notesText,
      "actions": _actions,
      "tags": _tags,
    };
  }

  /// Identifies "the same task" across payment retries. An ASAP task's
  /// timestamp changes every attempt, so it is left out of the key.
  String _jobKey(Map<String, dynamic> payload) {
    final keyed = Map<String, dynamic>.from(payload);
    if (_isNow) keyed.remove("scheduled_at");
    return jsonEncode(keyed);
  }

  Future<String> _createJob(Map<String, String> authHeaders) async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id');

    if (userId == null || userId.isEmpty) {
      throw Exception("User not verified");
    }

    final payload = _jobPayload();
    final key = _jobKey(payload);
    if (_pendingJobId != null && _pendingJobKey == key) {
      dlog('🔷 reusing unpaid task $_pendingJobId');
      return _pendingJobId!;
    }
    // Details changed since the last attempt: drop the stale unpaid task.
    if (_pendingJobId != null) {
      ApiService.deleteUnpaidTask(_pendingJobId!);
      _pendingJobId = null;
    }

    final jobRes = await ApiService.callWithRefresh(
      (h) => http.post(
        Uri.parse("${ApiService.baseUrl}/tasks/"),
        headers: h,
        body: jsonEncode(payload),
      ),
    );

    if (jobRes.statusCode < 200 || jobRes.statusCode >= 300) {
      // Show the server's reason (e.g. outside 07:00–22:00 local hours)
      // when it sent a short, readable one.
      String? detail;
      try {
        final d = jsonDecode(jobRes.body)['detail'];
        if (d is String && d.isNotEmpty && d.length < 140) detail = d;
      } catch (_) {}
      throw Exception(
        detail ?? "Couldn't create the task (${jobRes.statusCode}). Please try again.",
      );
    }

    final jobData = jsonDecode(jobRes.body) as Map<String, dynamic>;
    final jobId = jobData['id']?.toString();
    if (jobId == null) throw Exception("Couldn't create the task. Please try again.");

    _pendingJobId = jobId;
    _pendingJobKey = key;
    // Show the price the server set for this task.
    final serverAmount = (jobData['estimated_amount'] as num?)?.toDouble();
    final serverCurrency = jobData['currency']?.toString();
    if (mounted && serverAmount != null) {
      setState(() {
        _estimatedCost = serverAmount;
        if (serverCurrency != null && serverCurrency.isNotEmpty) {
          _currencyCode = serverCurrency.toUpperCase();
        }
      });
    }
    return jobId;
  }

  Future<void> _startStripeFlow() async {
    setState(() => _isProcessing = true);

    String? jobId;

    try {
      dlog('🔷 [Stripe] requireSignIn...');
      final signedIn = await Auth.requireSignIn(context);
      if (!signedIn) {
        dlog('🔷 [Stripe] user not signed in — aborting');
        setState(() => _isProcessing = false);
        return;
      }

      final authHeaders = await ApiService.authHeaders();

      dlog('🔷 [Stripe] creating job...');
      jobId = await _createJob(authHeaders);
      dlog('🔷 [Stripe] job created: $jobId');

      final amountPence = _toMinorUnits(_estimatedCost, _currencyCode);
      dlog(
        '🔷 [Stripe] POST create-payment-intent amount=$amountPence currency=${_currencyCode.toLowerCase()} job=$jobId',
      );

      final payRes = await ApiService.callWithRefresh(
        (h) => http.post(
          Uri.parse('${ApiService.baseUrl}/payments/create-intent'),
          headers: h,
          body: json.encode({
            'amount': amountPence,
            'currency': _currencyCode.toLowerCase(),
            'task_id': jobId,
          }),
        ),
      );

      dlog(
        '🔷 [Stripe] payment-intent response: ${payRes.statusCode} ${redactBody(payRes.body)}',
      );

      if (payRes.statusCode < 200 || payRes.statusCode >= 300) {
        throw Exception("Create intent failed: ${payRes.body}");
      }

      final payData = json.decode(payRes.body);
      final clientSecret = payData['client_secret'];
      final customerId = payData['customer_id'] as String?;
      final customerSessionClientSecret =
          payData['customer_session_client_secret'] as String?;

      dlog(
        '🔷 [Stripe] clientSecret present: ${clientSecret != null} prefix: ${clientSecret?.toString().substring(0, 20)}',
      );
      dlog('🔷 [Stripe] customerId: $customerId');

      if (clientSecret == null) {
        throw Exception("No client_secret returned");
      }

      dlog('🔷 [Stripe] calling initPaymentSheet...');
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: clientSecret,
          merchantDisplayName: 'Zanzo AI',
          style: ThemeMode.light,
          returnURL: 'zanzo://stripe-redirect',
          customerId: customerId,
          customerSessionClientSecret: customerSessionClientSecret,
        ),
      );
      dlog(
        '🟡 [Stripe] initPaymentSheet complete — clearing loading state before present',
      );
      // iOS: native sheet presentation fails silently if Flutter is mid-frame rebuild.
      // Clear loading state and yield one event-loop tick so the view hierarchy settles.
      setState(() => _isProcessing = false);
      await Future.delayed(const Duration(milliseconds: 50));

      dlog('🔷 [Stripe] presentPaymentSheet — isProcessing=$_isProcessing');
      await Stripe.instance.presentPaymentSheet();
      dlog('🟢 [Stripe] presentPaymentSheet completed successfully');

      // Show post-payment overlay while stripe-authorized call and navigation settle.
      if (mounted) setState(() => _postPayment = true);

      // Notify backend that Stripe has authorized the card (PI is requires_capture).
      // This sets payments.status='authorized', payments.gateway='stripe',
      // and jobs.payment_status='authorized' before the job lifecycle events fire.
      final authResp = await ApiService.callWithRefresh(
        (h) => http.post(
          Uri.parse("${ApiService.baseUrl}/payments/stripe-authorized"),
          headers: h,
          body: jsonEncode({"task_id": jobId}),
        ),
      );
      dlog(
        '🔷 [Stripe] stripe-authorized response: ${authResp.statusCode} ${redactBody(authResp.body)}',
      );

      // The card is authorised either way (the sheet succeeded), so the task
      // is no longer "abandoned" — don't delete it on leaving the screen.
      _paid = true;
      _pendingJobId = null;
      final confirmed = authResp.statusCode >= 200 && authResp.statusCode < 300;

      if (!mounted) return;

      // Only claim success when the server confirmed the authorisation. If it
      // couldn't yet, Stripe's webhook will move the task on shortly.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            confirmed
                ? '✅ Payment successful • Job #${jobId.substring(0, 8)}'
                : 'Payment received — confirming it now. Your task will start '
                    'searching for help as soon as it is confirmed.',
          ),
        ),
      );

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => TrackJobScreen(
            taskTitle: _conciseTitle,
            userLocation: _locationController.text,
            jobId: jobId,
          ),
        ),
      );
    } on StripeException catch (e) {
      dlog(
        '🔴 [Stripe] StripeException: code=${e.error.code} message=${e.error.localizedMessage} declineCode=${e.error.declineCode}',
      );
      if (!mounted) return;
      // Closing the payment sheet is the user's choice, not an error.
      final cancelled = e.error.code == FailureCode.Canceled;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            cancelled
                ? 'Payment cancelled. You can confirm again whenever you are ready.'
                : '❌ ${e.error.localizedMessage ?? 'Payment failed. Please try again.'}',
          ),
        ),
      );
    } catch (e, st) {
      dlog('🔴 [Stripe] catch: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('❌ ${_friendlyError(e)}')));
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _makePaymentFlow() async {
    if (_locationController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter a location')));
      return;
    }

    if (_selectedLat == null || _selectedLng == null) {
      dlog('🔴 [Stripe] lat/lng missing from state — blocking payment');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please select or confirm your task location before continuing.',
          ),
        ),
      );
      return;
    }

    dlog(
      '🔷 [Stripe] lat/lng OK (lat=$_selectedLat lng=$_selectedLng) — starting Stripe flow',
    );
    await _startStripeFlow();
  }

  // ========================= UI HELPERS (CALM / CLASSIC) =========================
  EdgeInsets get _pagePad => const EdgeInsets.fromLTRB(16, 14, 16, 120);

  Widget _sectionTitle(String t, {String? subtitle}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t,
            style: const TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w800,
              color: _ink,
              letterSpacing: 0.1,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 13, height: 1.25, color: _muted),
            ),
          ],
        ],
      ),
    );
  }

  Widget _cardShell({required Widget child, EdgeInsets? padding}) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _line),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.035),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _pill({
    required IconData icon,
    required String text,
    Color? bg,
    Color? fg,
    VoidCallback? onTap,
  }) {
    final child = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: bg ?? _surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: fg ?? _muted),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              fontSize: 13.2,
              fontWeight: FontWeight.w700,
              color: fg ?? _ink,
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return child;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: child,
    );
  }

  Widget _stepperRow({
    required IconData icon,
    required String label,
    required String value,
    VoidCallback? onMinus,
    VoidCallback? onPlus,
  }) {
    return Row(
      children: [
        Icon(icon, size: 20, color: _ink),
        const SizedBox(width: 10),

        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
              color: _ink,
            ),
          ),
        ),

        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: _line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                onPressed: onMinus,
                icon: const Icon(Icons.remove),
                iconSize: 18,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 32,
                  height: 32,
                ),
                visualDensity: VisualDensity.compact,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  value,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: _ink,
                  ),
                ),
              ),
              IconButton(
                onPressed: onPlus,
                icon: const Icon(Icons.add),
                iconSize: 18,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 32,
                  height: 32,
                ),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _counterPill({
    required int min,
    required int max,
    required int value,
    required VoidCallback onMinus,
    required VoidCallback onPlus,
    required String label,
  }) {
    final canMinus = value > min;
    final canPlus = value < max;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: canMinus ? onMinus : null,
            icon: const Icon(Icons.remove),
            iconSize: 18,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 34, height: 34),
            visualDensity: VisualDensity.compact,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w900,
                color: _ink,
              ),
            ),
          ),
          IconButton(
            onPressed: canPlus ? onPlus : null,
            icon: const Icon(Icons.add),
            iconSize: 18,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 34, height: 34),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  String _durationLabel() {
    if (_durationHours < 1.0) return "${(_durationHours * 60).toInt()} min";
    if (_durationHours % 1 == 0) return "${_durationHours.toInt()} h";
    return "${_durationHours.floor()} h 30 min";
  }

  // ========================= UI =========================
  @override
  Widget build(BuildContext context) {
    final payDisabled = _isProcessing || _postPayment;

    final String primaryCtaText = _isNow
        ? "Confirm & Start • ${_formatAmount(_estimatedCost)}"
        : "Confirm & Schedule • ${_formatAmount(_estimatedCost)}";

    // Calm “approval summary” psychology:
    // - The user should feel like they’re approving something already prepared for them.
    // - Reduce “form feeling” by: summary first, edit second (expand).
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: _bg,
        foregroundColor: _ink,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          "Review",
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),

      // ---------- Bottom confirmation bar ----------
      bottomNavigationBar: SafeArea(
        child: Container(
          decoration: BoxDecoration(
            color: _bg,
            border: Border(top: BorderSide(color: _line)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Price reassurance row
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        const Icon(Icons.lock_rounded, size: 13, color: _muted),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            "Held securely until a ZanCrew accepts.",
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: _muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    _formatAmount(_estimatedCost),
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w900,
                      color: _ink,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 54,
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: payDisabled
                        ? _accent.withOpacity(0.5)
                        : _ink,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: payDisabled ? null : _makePaymentFlow,
                  child: (_isProcessing || _postPayment)
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          primaryCtaText,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.2,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "You can edit any detail before confirming.",
                style: TextStyle(
                  fontSize: 12.5,
                  color: _muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),

      body: _postPayment
          ? Material(
              color: _bg,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 36),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 36,
                        height: 36,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: _accent,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        "Setting up live tracking…",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          color: _ink,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        "Your payment is secure. We're creating your job.",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: _muted,
                          fontWeight: FontWeight.w500,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          : SingleChildScrollView(
              padding: _pagePad,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ========================= APPROVAL SUMMARY (TOP) =========================
                  _cardShell(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Summary",
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w900,
                            color: _ink,
                          ),
                        ),
                        const SizedBox(height: 10),

                        // Title (primary anchor)
                        Text(
                          _titleController.text.trim().isEmpty
                              ? _conciseTitle
                              : _titleController.text.trim(),
                          style: const TextStyle(
                            fontSize: 17.5,
                            fontWeight: FontWeight.w900,
                            height: 1.15,
                            color: _ink,
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Short description (secondary)
                        Text(
                          _taskController.text.trim().isEmpty
                              ? "Your task details will appear here."
                              : _taskController.text.trim(),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13.5,
                            height: 1.35,
                            color: _muted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),

                        const SizedBox(height: 12),

                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            _pill(
                              icon: Icons.flash_on_rounded,
                              text: _isNow ? "ASAP" : _scheduleLabel,
                              bg: _isNow ? const Color(0xFFFFF3E9) : _surface,
                              fg: _ink,
                              onTap: () async {
                                if (_isNow) {
                                  setState(() => _isNow = true);
                                  _fetchEstimatedCost();
                                } else {
                                  await _pickSchedule();
                                }
                              },
                            ),
                            _pill(
                              icon: Icons.people_alt_rounded,
                              text: "People: $_peopleCount",
                            ),
                            _pill(
                              icon: Icons.timer_rounded,
                              text: "Duration: ${_durationLabel()}",
                            ),
                            if (_hasPickup)
                              _pill(
                                icon: Icons.alt_route_rounded,
                                text: "Pickup included",
                              ),
                          ],
                        ),

                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                          decoration: BoxDecoration(
                            color: _surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: _line),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.lock_rounded,
                                size: 16,
                                color: _muted,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  "Payment is held securely until a ZanCrew accepts.",
                                  style: TextStyle(
                                    fontSize: 12.8,
                                    fontWeight: FontWeight.w700,
                                    color: _muted,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),
                  // ========================= DETAILS (EDITABLE / EXPANDABLE) =========================
                  GestureDetector(
                    onTap: () => setState(() => _expanded = !_expanded),
                    child: _cardShell(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Text(
                                "Task details",
                                style: TextStyle(
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w900,
                                  color: _ink,
                                ),
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: _expanded ? _surface : _ink,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _expanded ? "Hide" : "Edit",
                                      style: TextStyle(
                                        fontSize: 12.8,
                                        fontWeight: FontWeight.w900,
                                        color: _expanded ? _ink : Colors.white,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Icon(
                                      _expanded
                                          ? Icons.keyboard_arrow_up_rounded
                                          : Icons.keyboard_arrow_down_rounded,
                                      size: 16,
                                      color: _expanded ? _ink : Colors.white,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),

                          if (!_expanded) ...[
                            if (_actions.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                "Expected actions",
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: _muted,
                                ),
                              ),
                              const SizedBox(height: 8),
                              ..._actions.take(2).map((a) {
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        margin: const EdgeInsets.only(top: 3),
                                        width: 18,
                                        height: 18,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFFF3E9),
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                        child: Icon(
                                          Icons.check_rounded,
                                          size: 14,
                                          color: _accent,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          a,
                                          style: const TextStyle(
                                            fontSize: 13.8,
                                            height: 1.35,
                                            color: _ink,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                              if (_actions.length > 2)
                                Text(
                                  "+ ${_actions.length - 2} more",
                                  style: const TextStyle(
                                    fontSize: 12.8,
                                    color: _muted,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                            ] else ...[
                              Text(
                                "Tap Edit to review full details.",
                                style: TextStyle(
                                  fontSize: 13,
                                  color: _muted,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ],

                          if (_expanded) ...[
                            const SizedBox(height: 12),
                            _sectionTitle(
                              "Job title",
                              subtitle: "Keep it short and clear.",
                            ),
                            TextField(
                              controller: _titleController,
                              maxLines: 1,
                              inputFormatters: [WordLimitFormatter(10)],
                              decoration: InputDecoration(
                                hintText:
                                    "Example: Key handover & utility check",
                                hintStyle: TextStyle(
                                  color: _muted.withValues(alpha: 0.8),
                                ),
                                filled: true,
                                fillColor: _surface,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(color: _line),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(color: _line),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: const BorderSide(
                                    color: _ink,
                                    width: 1.2,
                                  ),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                              ),
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: _ink,
                              ),
                            ),
                            const SizedBox(height: 18),

                            if (_actions.isNotEmpty) ...[
                              _sectionTitle(
                                "Expected actions",
                                subtitle:
                                    "This helps your partner do the job correctly.",
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: _actions.map((a) {
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          margin: const EdgeInsets.only(top: 2),
                                          width: 18,
                                          height: 18,
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFFFF3E9),
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                          ),
                                          child: Icon(
                                            Icons.check_rounded,
                                            size: 14,
                                            color: _accent,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            a,
                                            style: const TextStyle(
                                              fontSize: 13.8,
                                              height: 1.35,
                                              color: _ink,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ),
                              const SizedBox(height: 16),
                            ],

                            _sectionTitle(
                              "Your requirements",
                              subtitle:
                                  "You can tweak anything — ZanCrew will follow this.",
                            ),
                            TextField(
                              controller: _taskController,
                              maxLines: null,
                              textAlign: TextAlign.start,
                              decoration: InputDecoration(
                                hintText: "Describe exactly what you need…",
                                hintStyle: TextStyle(
                                  color: _muted.withValues(alpha: 0.8),
                                ),
                                filled: true,
                                fillColor: _surface,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(color: _line),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(color: _line),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: const BorderSide(
                                    color: _ink,
                                    width: 1.2,
                                  ),
                                ),
                                contentPadding: const EdgeInsets.fromLTRB(
                                  14,
                                  14,
                                  14,
                                  14,
                                ),
                              ),
                              style: const TextStyle(
                                fontSize: 14.2,
                                height: 1.45,
                                letterSpacing: 0.1,
                                color: _ink,
                                fontWeight: FontWeight.w600,
                              ),
                              cursorColor: _ink,
                            ),
                            const SizedBox(height: 16),

                            Row(
                              children: [
                                Expanded(
                                  child: _sectionTitle(
                                    "Important notes",
                                    subtitle:
                                        "Gate code, flat number, landmark…",
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: _suggestNotesFromText,
                                  icon: const Icon(
                                    Icons.auto_awesome_rounded,
                                    size: 18,
                                  ),
                                  label: const Text("Auto"),
                                  style: TextButton.styleFrom(
                                    foregroundColor: _ink,
                                  ),
                                ),
                              ],
                            ),

                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                ..._importantNotes.map((note) {
                                  return InputChip(
                                    label: Text(note),
                                    labelStyle: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: _ink,
                                    ),
                                    backgroundColor: const Color(0xFFFFF3E9),
                                    deleteIconColor: _muted,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(999),
                                      side: BorderSide(color: _line),
                                    ),
                                    onDeleted: () => setState(
                                      () => _importantNotes.remove(note),
                                    ),
                                  );
                                }).toList(),

                                ActionChip(
                                  label: const Text("+ Add"),
                                  labelStyle: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    color: _ink,
                                  ),
                                  backgroundColor: _surface,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(999),
                                    side: BorderSide(color: _line),
                                  ),
                                  onPressed: () async {
                                    _chipEditController.clear();
                                    final newNote = await _addNoteDialog();
                                    if (newNote != null &&
                                        newNote.trim().isNotEmpty) {
                                      setState(
                                        () =>
                                            _importantNotes.add(newNote.trim()),
                                      );
                                    }
                                  },
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ========================= LOCATION =========================
                  _cardShell(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionTitle(
                          "Location",
                          subtitle:
                              "Where should the ZanCrew partner arrive or return items?",
                        ),
                        const SizedBox(height: 10),

                        Theme(
                          data: Theme.of(context).copyWith(
                            inputDecorationTheme: Theme.of(context)
                                .inputDecorationTheme
                                .copyWith(
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide(color: _line),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide(
                                      color: _ink,
                                      width: 1.2,
                                    ),
                                  ),
                                ),
                          ),
                          child: LocationSelector(
                            controller: _locationController,
                            icon: Icons.location_on_rounded,
                            iconColor: const Color(0xFF22C55E),
                            onSelected: (address, lat, lng) async {
                              _locationController.text = address;
                              _selectedLat = lat;
                              _selectedLng = lng;
                              // The task's country (and so its currency)
                              // follows its location — re-quote.
                              _fetchEstimatedCost();

                              final prefs =
                                  await SharedPreferences.getInstance();
                              await prefs.setString('review_address', address);
                              await prefs.setDouble('review_lat', lat);
                              await prefs.setDouble('review_lng', lng);
                              await prefs.setString(
                                'review_place_id',
                                "manual",
                              );

                              if (mounted) setState(() {});
                            },
                          ),
                        ),

                        const SizedBox(height: 14),

                        Container(
                          decoration: BoxDecoration(
                            color: _surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: _line),
                          ),
                          child: SwitchListTile(
                            value: _hasPickup,
                            onChanged: (v) => setState(() => _hasPickup = v),
                            title: const Text(
                              "Pickup from another location",
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w800,
                                color: _ink,
                              ),
                            ),
                            subtitle: Text(
                              "Enable if something must be collected first",
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: _muted,
                              ),
                            ),
                            activeThumbColor: _ink,
                          ),
                        ),

                        if (_hasPickup &&
                            _pickupController.text.trim().isEmpty) ...[
                          const SizedBox(height: 8),
                          Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: Text(
                              "Auto-detected: this task may need a pickup location.",
                              style: TextStyle(
                                fontSize: 12,
                                color: _muted,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],

                        if (_hasPickup) ...[
                          const SizedBox(height: 14),
                          _sectionTitle(
                            "Pickup address",
                            subtitle: "Where should the partner collect from?",
                          ),
                          const SizedBox(height: 10),
                          Theme(
                            data: Theme.of(context).copyWith(
                              inputDecorationTheme: Theme.of(context)
                                  .inputDecorationTheme
                                  .copyWith(
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: BorderSide(color: _line),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: BorderSide(
                                        color: _ink,
                                        width: 1.2,
                                      ),
                                    ),
                                  ),
                            ),
                            child: LocationSelector(
                              controller: _pickupController,
                              icon: Icons.location_on_rounded,
                              iconColor: _accent,
                              onSelected: (address, lat, lng) async {
                                _pickupController.text = address;
                                _pickupLat = lat;
                                _pickupLng = lng;

                                final prefs =
                                    await SharedPreferences.getInstance();
                                await prefs.setString(
                                  'pickup_address',
                                  address,
                                );
                                await prefs.setDouble('pickup_lat', lat);
                                await prefs.setDouble('pickup_lng', lng);

                                if (mounted) setState(() {});
                              },
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ========================= WHEN & SETUP (MERGED) =========================
                  _cardShell(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionTitle(
                          "When & setup",
                          subtitle: "Timing, team size, and duration.",
                        ),
                        const SizedBox(height: 12),

                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _isNow ? _ink : _surface,
                                  foregroundColor: _isNow ? Colors.white : _ink,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                onPressed: () {
                                  setState(() => _isNow = true);
                                  _fetchEstimatedCost();
                                },
                                icon: const Icon(Icons.flash_on_rounded),
                                label: const Text(
                                  "ASAP",
                                  style: TextStyle(fontWeight: FontWeight.w800),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: !_isNow ? _ink : _surface,
                                  foregroundColor: !_isNow
                                      ? Colors.white
                                      : _ink,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                onPressed: _pickSchedule,
                                icon: const Icon(Icons.calendar_month_rounded),
                                label: Text(
                                  _scheduleLabel,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),
                        const Divider(color: _line),
                        const SizedBox(height: 14),

                        _stepperRow(
                          icon: Icons.people_alt_rounded,
                          label: "People",
                          value: "$_peopleCount",
                          onMinus: _peopleCount > 1
                              ? () {
                                  setState(() => _peopleCount--);
                                  _fetchEstimatedCost();
                                }
                              : null,
                          onPlus: _peopleCount < 4
                              ? () {
                                  setState(() => _peopleCount++);
                                  _fetchEstimatedCost();
                                }
                              : null,
                        ),

                        const SizedBox(height: 14),
                        const Divider(color: _line),
                        const SizedBox(height: 14),

                        _stepperRow(
                          icon: Icons.timer_rounded,
                          label: "Duration",
                          value: _durationLabel(),
                          onMinus: _durationHours > 0.5
                              ? () {
                                  setState(() {
                                    _durationHours = (_durationHours - 0.5)
                                        .clamp(0.5, 8.0);
                                  });
                                  _fetchEstimatedCost();
                                }
                              : null,
                          onPlus: () {
                            setState(() {
                              _durationHours = (_durationHours + 0.5).clamp(
                                0.5,
                                8.0,
                              );
                            });
                            _fetchEstimatedCost();
                          },
                        ),
                        const SizedBox(height: 6),
                        Padding(
                          padding: const EdgeInsets.only(left: 30),
                          child: Text(
                            "Minimum job time is 30 minutes.",
                            style: TextStyle(
                              fontSize: 11.5,
                              color: _muted,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }
}
