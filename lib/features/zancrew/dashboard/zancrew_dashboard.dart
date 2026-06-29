// ZanCrew Dashboard
// - Shows ZanCrew earner status, radius, and selected buckets (config only)
// - Lets user go Online/Offline (linked to backend + location updates)
// - Tabbed list for: Inbox (offered jobs) + My Jobs (accepted jobs)
// - Periodically sends GPS updates to backend while online
// - NEW: Earnings card (Today) + Earnings Details screen
//
// PREMIUM UI REFINEMENT (frontend only)
// ✅ Backend untouched
// ✅ Same API calls + same behavior
//
// lib/features/zancrew/dashboard/zancrew_dashboard.dart

import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart'; // ⭐ Supabase for realtime
import 'package:zanzo_frontend/core/services/zancrew_earnings_service.dart';

import '../../../core/services/api_service.dart';
import '../../../core/services/crew_offers_ws_service.dart';
import '../../../core/services/uk_provider_api.dart';
import '../../../core/services/zancrew_api.dart';
import '../onboarding/uk_bank_details_screen.dart';
import '../screens/zancrew_JobDetails.dart';
import '../screens/zancrew_earnings_details.dart';
import '../screens/zancrew_offer_detail.dart';

class ZanCrewDashboard extends StatefulWidget {
  const ZanCrewDashboard({super.key});

  @override
  State<ZanCrewDashboard> createState() => _ZanCrewDashboardState();
}

class _ZanCrewDashboardState extends State<ZanCrewDashboard>
    with WidgetsBindingObserver {
  // ---------------------------------------------------------------------------
  // STATE
  // ---------------------------------------------------------------------------
  bool _loading = true;

  bool _zancrewEnabled = false;
  bool _online = false;

  double _radiusKm = 5;
  List<String> _buckets = const [];

  String? _crewUserId;

  bool _offersLoading = false;
  List<Map<String, dynamic>> _offers = const [];

  String _currentTab = 'offered';

  Timer? _locationTimer;

  double _todayEarnings = 0;

  static const List<String> _defaultBucketCatalog = [
    'Delivery',
    'Cleaning',
    'Moving',
    'Errands',
    'Supervision',
    'Assembly',
  ];

  // ⭐ Realtime subscription channel handles (Supabase — kept for earnings)
  RealtimeChannel? _earningsChannel;
  RealtimeChannel? _jobEventsChannel;

  // WS offer fanout
  CrewOffersWsService? _wsOffers;

  // 🔔 FCM token refresh subscription
  StreamSubscription<String>? _fcmRefreshSub;

  // 🔔 FCM notification-opened subscription (background tap)
  StreamSubscription<RemoteMessage>? _fcmOpenedSub;

  // ---------------------------------------------------------------------------
  // PREMIUM UI constants
  // ---------------------------------------------------------------------------
  static const Color _bg = Color(0xFFF6F7F9);
  static const Color _card = Colors.white;
  static const Color _ink = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _border = Color(0xFFE5E7EB);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadPrefs();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initRealtimeListeners();
      _initFcmOpenListeners();
    });
  }

  // ---------------------------------------------------------------------------
  // APP LIFECYCLE — refresh offers on resume (covers notification tap from bg)
  // ---------------------------------------------------------------------------
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _online && _crewUserId != null) {
      debugPrint('[ZanCrew] app resumed — refreshing offers');
      _refreshOffers(status: 'offered');
    }
  }

  // ---------------------------------------------------------------------------
  // FCM OPEN LISTENERS
  // ---------------------------------------------------------------------------
  void _initFcmOpenListeners() {
    // Notification tapped while app was in background
    _fcmOpenedSub = FirebaseMessaging.onMessageOpenedApp.listen((message) {
      debugPrint('[FCM] notification opened app — refreshing offers');
      if (_online && _crewUserId != null) {
        _refreshOffers(status: 'offered');
      }
    }, onError: (e) => debugPrint('[FCM] onMessageOpenedApp error: $e'));

    // Notification tapped when app was fully terminated (cold start)
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null) {
        debugPrint('[FCM] launched from notification tap — refreshing offers');
        if (_online && _crewUserId != null) {
          _refreshOffers(status: 'offered');
        }
      }
    });
  }

  // ---------------------------------------------------------------------------
  // REALTIME SUBSCRIPTIONS
  // ---------------------------------------------------------------------------
  void _initRealtimeListeners() {
    if (_crewUserId == null) {
      // prefs not loaded yet — retry in 300ms
      Future.delayed(const Duration(milliseconds: 300), _initRealtimeListeners);
      return;
    }

    final supabase = Supabase.instance.client;

    // ===================================================================
    // REALTIME SUB #1: crew_earnings INSERT + UPDATE
    // ===================================================================
    _earningsChannel = supabase
        .channel('earnings_updates_${_crewUserId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'crew_earnings',
          filter: PostgresChangeFilter(
            column: 'crew_user_id',
            type: PostgresChangeFilterType.eq,
            value: _crewUserId!,
          ),
          callback: (payload) {
            _recalculateTodayEarningsFromOffers(_currentTab);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'crew_earnings',
          filter: PostgresChangeFilter(
            column: 'crew_user_id',
            type: PostgresChangeFilterType.eq,
            value: _crewUserId!,
          ),
          callback: (payload) async {
            await _recalculateTodayEarningsFromOffers(_currentTab);
            if (mounted) setState(() {});
          },
        )
        .subscribe();

    // ===================================================================
    // REALTIME SUB #2: job_events (for job status changes)
    // ===================================================================
    _jobEventsChannel = supabase
        .channel('job_events_${_crewUserId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'job_events', // backend updates job status here
          callback: (payload) async {
            await _recalculateTodayEarningsFromOffers(_currentTab);
            if (mounted) setState(() {});
          },
        )
        .subscribe();
  }

  // ---------------------------------------------------------------------------
  // FCM — TOKEN REGISTRATION
  // ---------------------------------------------------------------------------

  /// Set up the token-refresh listener once per dashboard session.
  void _initFcmRefreshListener() {
    _fcmRefreshSub?.cancel();
    _fcmRefreshSub = FirebaseMessaging.instance.onTokenRefresh.listen((
      newToken,
    ) async {
      final prefix = newToken.length >= 8 ? newToken.substring(0, 8) : '???';
      debugPrint('[FCM] token refreshed token=$prefix…');
      final platform = Platform.isIOS
          ? 'ios'
          : Platform.isAndroid
          ? 'android'
          : 'unknown';
      await ApiService.registerDeviceToken(token: newToken, platform: platform);
    }, onError: (e) => debugPrint('[FCM] onTokenRefresh error: $e'));
  }

  /// Request notification permission (iOS shows system dialog; Android 13+ also shows dialog).
  /// Then register the current FCM token with the backend.
  Future<void> _requestFcmPermissionAndRegister() async {
    try {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        debugPrint('[FCM] notification permission denied');
        return;
      }
      await _registerCurrentFcmToken();
    } catch (e) {
      debugPrint('[FCM] _requestFcmPermissionAndRegister error: $e');
    }
  }

  /// Get the current FCM token and register it with the backend (silent, no permission dialog).
  /// On iOS, waits for the APNS token before requesting the FCM token.
  Future<void> _registerCurrentFcmToken() async {
    try {
      if (Platform.isIOS) {
        String? apns;
        for (int i = 0; i < 5; i++) {
          apns = await FirebaseMessaging.instance.getAPNSToken();
          if (apns != null) break;
          debugPrint(
            '[FCM] APNS token not ready, attempt ${i + 1}/5 — retrying in 1s…',
          );
          await Future.delayed(const Duration(seconds: 1));
        }
        if (apns == null) {
          debugPrint(
            '[FCM] APNS token still null after 5 attempts — skipping FCM registration',
          );
          return;
        }
        final apnsPrefix = apns.length >= 8 ? apns.substring(0, 8) : '???';
        debugPrint('[FCM] APNS token ready apns=$apnsPrefix…');
      }

      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) {
        debugPrint('[FCM] getToken() returned null');
        return;
      }
      final prefix = token.length >= 8 ? token.substring(0, 8) : '???';
      debugPrint('[FCM] got token=$prefix…');
      final platform = Platform.isIOS
          ? 'ios'
          : Platform.isAndroid
          ? 'android'
          : 'unknown';
      await ApiService.registerDeviceToken(token: token, platform: platform);
    } catch (e) {
      debugPrint('[FCM] _registerCurrentFcmToken error: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // FIRST-TIME ACTIVATION BANNER — disabled for UK MVP
  // ---------------------------------------------------------------------------
  Future<void> _maybeShowActivationBanner() async {
    // Intentionally suppressed: UK MVP does not show this banner.
  }

  // ---------------------------------------------------------------------------
  // LOAD & MIGRATE PREFERENCES
  // ---------------------------------------------------------------------------
  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();

    // Migration (old keys → new keys)
    if (prefs.containsKey('earner_enabled')) {
      await prefs.setBool(
        'zancrew_enabled',
        prefs.getBool('earner_enabled') ?? false,
      );
      await prefs.remove('earner_enabled');
    }

    if (prefs.containsKey('earner_radius_km')) {
      await prefs.setDouble(
        'zancrew_radius_km',
        prefs.getDouble('earner_radius_km') ?? 5,
      );
      await prefs.remove('earner_radius_km');
    }

    if (prefs.containsKey('earner_buckets')) {
      await prefs.setStringList(
        'zancrew_buckets',
        prefs.getStringList('earner_buckets') ?? <String>[],
      );
      await prefs.remove('earner_buckets');
    }

    if (prefs.containsKey('earner_online')) {
      await prefs.setBool(
        'zancrew_online',
        prefs.getBool('earner_online') ?? false,
      );
      await prefs.remove('earner_online');
    }

    // Load state into memory
    setState(() {
      _zancrewEnabled = prefs.getBool('zancrew_enabled') ?? false;
      _radiusKm = prefs.getDouble('zancrew_radius_km') ?? 5;
      _buckets = prefs.getStringList('zancrew_buckets') ?? <String>[];
      _online = prefs.getBool('zancrew_online') ?? false;
      _crewUserId = prefs.getString('user_id');
      _loading = false;
    });

    // If SharedPreferences still says not enabled, live-check UK provider
    // status — the admin may have approved via Supabase without the prefs
    // being updated on this device.
    if (!_zancrewEnabled && _crewUserId != null) {
      try {
        final ukStatus = await UkProviderApi.getStatus(_crewUserId!);
        if (ukStatus != null &&
            ukStatus['provider_status'] == 'approved' &&
            ukStatus['can_receive_offers'] == true) {
          await prefs.setBool('zancrew_enabled', true);
          if (mounted) setState(() => _zancrewEnabled = true);
        }
      } catch (_) {}
    }

    await _maybeShowActivationBanner();

    // 🔔 FCM: start refresh listener once; silently re-register token if already online
    _initFcmRefreshListener();
    if (_online && _crewUserId != null) {
      unawaited(_registerCurrentFcmToken());
    }

    // CRITICAL FIX: re-sync backend
    if (_online && _crewUserId != null) {
      try {
        await ZanCrewApi.setOnline(userId: _crewUserId!, online: true);
      } catch (_) {}

      _startLocationUpdates();
      _refreshOffers(status: _currentTab);
      _connectOffersWs();
    } else {
      // Still refresh earnings even if offline, so earnings card is always current
      _recalculateTodayEarningsFromOffers(_currentTab);
    }
  }

  // ---------------------------------------------------------------------------
  // LOCATION UPDATES WHILE ONLINE
  // ---------------------------------------------------------------------------
  Future<void> _startLocationUpdates() async {
    _locationTimer?.cancel();

    if (!_online || _crewUserId == null) return;

    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
    }

    _locationTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      try {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );

        if (_crewUserId == null) return;

        await ApiService.postCrewLocationUpdate(
          crewUserId: _crewUserId!,
          lat: pos.latitude,
          lng: pos.longitude,
        );
      } catch (_) {
        // ignore for MVP
      }
    });
  }

  // ---------------------------------------------------------------------------
  // ONLINE TOGGLE (LOCAL + BACKEND)
  // ---------------------------------------------------------------------------
  Future<void> _setOnline(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('zancrew_online', v);
    setState(() => _online = v);

    try {
      final uid = _crewUserId ?? prefs.getString('user_id');
      if (uid != null) {
        await ZanCrewApi.setOnline(userId: uid, online: v);
      }
    } catch (e) {
      // Revert local state so UI matches backend
      await prefs.setBool('zancrew_online', !v);
      if (mounted) {
        setState(() => _online = !v);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
  }

  /// Push a best-effort location fix to /crew_location/update before the
  /// backend /set_online call. The backend guards on COALESCE(last_lat,
  /// home_lat) being non-null, so a fresh device with no prior GPS history
  /// will always be rejected without this pre-seed.
  ///
  /// Strategy:
  ///   1. getLastKnownPosition() — instant OS cache, no satellite wait.
  ///   2. If null, getCurrentPosition(medium accuracy, 20 s) — uses cell/Wi-Fi.
  /// Non-fatal: if no fix is obtainable we log and continue; _setOnline will
  /// surface the backend 403 message to the user as a clear snackbar.
  Future<void> _tryPushLocationBeforeOnline() async {
    try {
      Position? pos = await Geolocator.getLastKnownPosition();

      if (pos == null) {
        debugPrint(
          '[ZanCrew] no last known position — trying current (medium)',
        );
        pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
        ).timeout(const Duration(seconds: 20));
      }

      if (pos == null) {
        debugPrint('[ZanCrew] pre-online: no position available');
        return;
      }

      if (pos.latitude == 0.0 && pos.longitude == 0.0) {
        debugPrint('[ZanCrew] pre-online: ignoring (0,0) coordinates');
        return;
      }

      debugPrint(
        '[ZanCrew] pre-online location: ${pos.latitude},${pos.longitude}',
      );
      await ApiService.postCrewLocationUpdate(
        crewUserId: _crewUserId!,
        lat: pos.latitude,
        lng: pos.longitude,
      );
    } catch (e) {
      debugPrint('[ZanCrew] pre-online location push failed (non-fatal): $e');
    }
  }

  Future<void> _toggleOnline(bool v) async {
    // ── Location guard (going online only) ───────────────────────────────────
    if (v) {
      try {
        final serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (!serviceEnabled) {
          debugPrint('[ZanCrew] location service disabled');
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Please turn on Location in your device settings and try again.',
              ),
              duration: Duration(seconds: 4),
            ),
          );
          return;
        }

        LocationPermission perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.denied) {
          perm = await Geolocator.requestPermission();
        }
        if (perm == LocationPermission.denied ||
            perm == LocationPermission.deniedForever) {
          debugPrint('[ZanCrew] location permission denied: $perm');
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Location permission is required to receive nearby job offers. '
                'Please grant it in app settings and try again.',
              ),
              duration: Duration(seconds: 4),
            ),
          );
          return;
        }

        debugPrint('[ZanCrew] location permission ok: $perm');
      } catch (e) {
        debugPrint('[ZanCrew] location check error: $e');
        // Non-fatal: permission check itself failed — allow online and let
        // the location timer handle retries gracefully.
      }
    }

    // Push a location fix to the backend before going online so the backend
    // location guard (COALESCE last_lat, home_lat) has a non-null value.
    if (v && _crewUserId != null) {
      await _tryPushLocationBeforeOnline();
    }

    // 🔔 When going online: request FCM permission + register token (non-blocking)
    if (v && _crewUserId != null) {
      unawaited(_requestFcmPermissionAndRegister());
    }

    await _setOnline(v);

    if (_online) {
      _startLocationUpdates();
      _refreshOffers(status: _currentTab);
      _connectOffersWs();
    } else {
      _locationTimer?.cancel();
      _disconnectOffersWs();
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(v ? 'You are now ONLINE' : 'You are OFFLINE')),
    );
  }

  // ---------------------------------------------------------------------------
  // CREW OFFERS WEBSOCKET
  // ---------------------------------------------------------------------------
  void _connectOffersWs() {
    _wsOffers?.dispose();
    final svc = CrewOffersWsService();
    svc.onOfferReceived = (_) => _refreshOffers(status: 'offered');
    svc.onOfferExpired = (_) => _refreshOffers(status: _currentTab);
    svc.onTaskCancelled = (_) => _refreshOffers(status: _currentTab);
    svc.connect();
    _wsOffers = svc;
  }

  void _disconnectOffersWs() {
    _wsOffers?.dispose();
    _wsOffers = null;
  }

  // ---------------------------------------------------------------------------
  // LOAD OFFERS / JOBS FOR CURRENT TAB
  // ---------------------------------------------------------------------------
  Future<void> _refreshOffers({String? status}) async {
    if (_crewUserId == null) return;

    final effStatus = status ?? _currentTab;
    setState(() => _offersLoading = true);

    try {
      final list = await ApiService.fetchCrewOffers(
        crewUserId: _crewUserId!,
        status: effStatus,
        limit: 20,
      );
      if (!mounted) return;
      setState(() {
        _offers = list;
      });

      _recalculateTodayEarningsFromOffers(effStatus);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load offers: $e')));
    } finally {
      if (mounted) setState(() => _offersLoading = false);
    }
  }

  // ---------------------------------------------------------------------------
  // EARNINGS (BACKEND VERSION)
  // ---------------------------------------------------------------------------
  double _parseAmount(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    if (value is String) {
      final cleaned = value.replaceAll(RegExp(r'[^\d.]'), '');
      if (cleaned.isEmpty) return 0;
      return double.tryParse(cleaned) ?? 0;
    }
    return 0;
  }

  Future<void> _recalculateTodayEarningsFromOffers(String statusLoaded) async {
    if (_crewUserId == null) return;

    try {
      final result = await ZanCrewEarningsService.getEarnings(_crewUserId!);
      final todayPaise = result["today_paise"] ?? 0;

      setState(() {
        _todayEarnings = todayPaise / 100;
      });
    } catch (_) {
      // ignore for MVP
    }
  }

  // ---------------------------------------------------------------------------
  // CLEANUP
  // ---------------------------------------------------------------------------
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _locationTimer?.cancel();
    _earningsChannel?.unsubscribe();
    _jobEventsChannel?.unsubscribe();
    _fcmRefreshSub?.cancel();
    _fcmOpenedSub?.cancel();
    _wsOffers?.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // SMALL FORMAT HELPERS
  // ---------------------------------------------------------------------------
  String _shortTitle(Map<String, dynamic> o) {
    final s = (o['short_title'] ?? '').toString().trim();
    if (s.isNotEmpty) return s;

    final t = (o['task_title'] ?? '').toString().trim();
    if (t.isNotEmpty && t.toLowerCase() != 'assist_location') return t;

    final p = (o['polished_task'] ?? '').toString().trim();
    if (p.isNotEmpty) {
      final words = p.split(RegExp(r'\s+'));
      if (words.length <= 6) return p;
      return '${words.take(6).join(' ')}…';
    }

    return 'Job offer';
  }

  String _whenLabel(Map<String, dynamic> o) {
    final w = (o['when_label'] ?? '').toString().trim();
    if (w.isNotEmpty) return w;

    final raw = (o['scheduled_at'] ?? '').toString();
    return raw;
  }

  String _priceLabel(Map<String, dynamic> o) {
    final p = o['price_estimate'];
    if (p == null) return '';

    if (p is String && p.trim().isNotEmpty) return p;

    try {
      final v = (p is num) ? p.toDouble() : double.parse(p.toString());
      final whole = v.truncateToDouble();
      return '£${v.toStringAsFixed(whole == v ? 0 : 2)}';
    } catch (_) {
      return '';
    }
  }

  String _distanceLabel(Map<String, dynamic> o) {
    final d = o['distance_km'];
    if (d == null) return '';

    try {
      final v = (d is num) ? d.toDouble() : double.parse(d.toString());
      if (v < 1.0) {
        final meters = (v * 1000).round();
        return '$meters m';
      }
      return '${v.toStringAsFixed(1)} km';
    } catch (_) {
      return '';
    }
  }

  // ---------------------------------------------------------------------------
  // EDIT PREFERENCES
  // ---------------------------------------------------------------------------
  Future<void> _openEditPreferences() async {
    if (_crewUserId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please sign in first.')));
      return;
    }

    final currentBuckets = Set<String>.from(_buckets);
    final catalog = {..._defaultBucketCatalog, ...currentBuckets}.toList();

    double tempRadius = _radiusKm;
    final tempBuckets = Set<String>.from(currentBuckets);

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: 16 + MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: StatefulBuilder(
            builder: (ctx, setLocal) {
              return SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.black26,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const Text(
                      'Edit Preferences',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Categories',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: catalog.map((b) {
                        final selected = tempBuckets.contains(b);
                        return FilterChip(
                          label: Text(b),
                          selected: selected,
                          onSelected: (v) {
                            setLocal(() {
                              if (v) {
                                tempBuckets.add(b);
                              } else {
                                tempBuckets.remove(b);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Radius (km)',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Slider(
                            value: tempRadius.clamp(1, 50),
                            min: 1,
                            max: 50,
                            divisions: 49,
                            label: '${tempRadius.toStringAsFixed(0)} km',
                            onChanged: (v) => setLocal(() => tempRadius = v),
                          ),
                        ),
                        SizedBox(
                          width: 48,
                          child: Text(
                            tempRadius.toStringAsFixed(0),
                            textAlign: TextAlign.right,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel'),
                        ),
                        const Spacer(),
                        ElevatedButton(
                          onPressed: tempBuckets.isEmpty
                              ? null
                              : () => Navigator.pop(ctx, true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.black,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('Save'),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );

    if (saved != true) return;

    final newBuckets = tempBuckets.toList()..sort();
    final newRadius = tempRadius.clamp(1, 50).round();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('zancrew_buckets', newBuckets);
    await prefs.setDouble('zancrew_radius_km', newRadius.toDouble());

    try {
      final serverProfile = await ZanCrewApi.getProfile(_crewUserId!);
      final currentStatus = serverProfile?['status'] ?? 'pending';
      final safeStatus = currentStatus == 'active' ? 'active' : 'pending';

      await ZanCrewApi.upsertProfile(
        userId: _crewUserId!,
        buckets: newBuckets,
        radiusKm: newRadius,
        status: safeStatus,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Preferences saved')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved locally, but server failed: $e')),
      );
    }

    if (!mounted) return;
    setState(() {
      _buckets = newBuckets;
      _radiusKm = newRadius.toDouble();
    });
  }

  // ---------------------------------------------------------------------------
  // PREMIUM UI HELPERS
  // ---------------------------------------------------------------------------
  Widget _softCard({required Widget child, EdgeInsets? padding}) {
    return Container(
      decoration: BoxDecoration(
        color: _card,
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
      padding: padding ?? const EdgeInsets.all(14),
      child: child,
    );
  }

  Widget _pill({required IconData icon, required String text}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
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

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final isInbox = _currentTab == 'offered';
    final tabIndex = isInbox ? 0 : 1;

    return DefaultTabController(
      length: 2,
      initialIndex: tabIndex,
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: _ink,
          elevation: 0,
          title: const Text(
            'ZanCrew Dashboard',
            style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: -0.2),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
              Navigator.pop(context);
            },
          ),
          actions: [
            IconButton(
              tooltip: 'Bank Details',
              icon: const Icon(Icons.account_balance_outlined),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const UkBankDetailsScreen(),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Preferences',
              icon: const Icon(Icons.tune),
              onPressed: _openEditPreferences,
            ),
            if (_online && !_offersLoading)
              IconButton(
                tooltip: 'Refresh',
                icon: const Icon(Icons.refresh),
                onPressed: () => _refreshOffers(status: _currentTab),
              ),
          ],
          bottom: TabBar(
            onTap: (i) {
              final next = (i == 0) ? 'offered' : 'accepted';
              if (next != _currentTab) {
                setState(() => _currentTab = next);
                _refreshOffers(status: next);
              }
            },
            labelColor: _ink,
            unselectedLabelColor: _muted,
            indicatorColor: _ink,
            indicatorWeight: 3,
            labelStyle: const TextStyle(fontWeight: FontWeight.w900),
            tabs: const [
              Tab(text: 'Inbox'),
              Tab(text: 'My Jobs'),
            ],
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: !_zancrewEnabled
              ? _buildZanCrewOffBody(context)
              : _buildZanCrewOnBody(context, isInbox),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // SUB-UI — ZanCrew disabled
  // ---------------------------------------------------------------------------
  Widget _buildZanCrewOffBody(BuildContext context) {
    return Center(
      child: _softCard(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 42, color: _muted),
            const SizedBox(height: 12),
            const Text(
              'ZanCrew Mode is OFF',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            const Text(
              'Turn it on from your profile to start receiving jobs.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _muted, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () {
                  ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
                  Navigator.pop(context);
                },
                child: const Text(
                  'Go to Profile',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // SUB-UI — ZanCrew enabled
  // ---------------------------------------------------------------------------
  Widget _buildZanCrewOnBody(BuildContext context, bool isInbox) {
    return Column(
      children: [
        // Earnings (secondary motivation)
        _buildEarningsCard(context),

        const SizedBox(height: 12),

        // Online control (primary action)
        _softCard(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _online ? 'You are online' : 'You are offline',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: _ink,
                  ),
                ),
              ),
              Switch(
                value: _online,
                activeColor: Colors.green,
                onChanged: _toggleOnline,
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        Expanded(
          child: !_online
              ? Center(
                  child: Text(
                    'Turn online to receive nearby jobs.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _muted.withOpacity(0.95),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              : _buildOffersList(isInbox),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // EARNINGS CARD
  // ---------------------------------------------------------------------------
  Widget _buildEarningsCard(BuildContext context) {
    final todayLabel = _todayEarnings <= 0
        ? '£0'
        : '£${_todayEarnings.toStringAsFixed(_todayEarnings.truncateToDouble() == _todayEarnings ? 0 : 2)}';

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () {
        if (_crewUserId == null) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text("User ID missing!")));
          return;
        }

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                ZanCrewEarningsDetailsScreen(crewUserId: _crewUserId!),
          ),
        );
      },
      child: _softCard(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          children: [
            const Icon(Icons.payments_outlined, color: _ink),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Today’s earnings',
                    style: TextStyle(
                      fontSize: 13,
                      color: _muted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    todayLabel,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.4,
                      color: _ink,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: _muted),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // OFFERS/JOBS LIST (PREMIUM CARDS)
  // ---------------------------------------------------------------------------
  Widget _buildOffersList(bool isInbox) {
    if (_offersLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_offers.isEmpty) {
      return Center(
        child: Text(
          isInbox ? 'No job offers right now' : 'No active jobs yet',
          style: const TextStyle(color: _muted, fontWeight: FontWeight.w600),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _refreshOffers(status: _currentTab),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(0, 4, 0, 16),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _offers.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final o = _offers[i];

          final title = _shortTitle(o);
          final bucket = (o['bucket'] ?? '').toString();
          final price = _priceLabel(o);
          final when = _whenLabel(o);
          final dist = _distanceLabel(o);

          final paymentStatus = (o['payment_status'] ?? '')
              .toString()
              .toLowerCase();
          Widget? paymentChip;
          if (paymentStatus == 'paid') {
            paymentChip = Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: _border),
              ),
              child: const Text(
                'Paid',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                  color: Color(0xFF16A34A),
                ),
              ),
            );
          }

          final offerStatus = ((o['status'] ?? o['offer_status']) ?? 'offered')
              .toString()
              .toLowerCase();
          final isAccepted = offerStatus == 'accepted';

          final jobId = (o['task_id'] ?? o['job_id'] ?? '').toString();

          return InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: _currentTab == 'offered'
                ? () async {
                    final result = await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => CrewOfferDetail(offer: o),
                      ),
                    );
                    if (result == 'accepted' || result == 'rejected') {
                      _refreshOffers(status: _currentTab);
                    }
                  }
                : (jobId.isNotEmpty
                      ? () async {
                          final result = await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => CrewJobDetail(jobId: jobId),
                            ),
                          );

                          if (result == true) {
                            await _recalculateTodayEarningsFromOffers(
                              _currentTab,
                            );
                            await _refreshOffers(status: _currentTab);
                          }
                        }
                      : null),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top row: bucket + status + chevron
                  Row(
                    children: [
                      if (bucket.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF3F4F6),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            bucket,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 12.5,
                              color: _ink,
                            ),
                          ),
                        ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: isAccepted
                              ? const Color(0xFFECFDF5)
                              : const Color(0xFFFFFBEB),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: _border),
                        ),
                        child: Text(
                          isAccepted ? 'Accepted' : 'Offered',
                          style: TextStyle(
                            color: isAccepted
                                ? const Color(0xFF16A34A)
                                : const Color(0xFFF59E0B),
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.chevron_right, color: _muted),
                    ],
                  ),

                  const SizedBox(height: 10),

                  // Price + paid
                  Row(
                    children: [
                      if (price.isNotEmpty)
                        Text(
                          price,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.4,
                            color: _ink,
                          ),
                        ),
                      const Spacer(),
                      if (paymentChip != null) paymentChip,
                    ],
                  ),

                  const SizedBox(height: 6),

                  // Title
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: _ink,
                      height: 1.15,
                    ),
                  ),

                  const SizedBox(height: 10),

                  // Meta row
                  Row(
                    children: [
                      if (when.isNotEmpty) ...[
                        const Icon(Icons.schedule, size: 16, color: _muted),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            when,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              color: _ink,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                      if (when.isNotEmpty && dist.isNotEmpty)
                        const SizedBox(width: 12),
                      if (dist.isNotEmpty) ...[
                        const Icon(
                          Icons.place_outlined,
                          size: 16,
                          color: _muted,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '$dist away',
                          style: const TextStyle(
                            fontSize: 13,
                            color: _muted,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
