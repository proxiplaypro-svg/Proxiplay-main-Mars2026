import '/auth/firebase_auth/account_routing.dart';
import '/auth/firebase_auth/auth_util.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/index.dart';
import '/utils/referral_link_logic.dart';
import '/utils/share_links.dart';
import 'package:flutter/material.dart';

/// Player referral invitation link https://play.proxiplay.fr/i?ref=CODE
/// (Android App Link, iOS Universal Link), at cold start or with the app
/// already open: a visitor lands on the signup page with the code filled in,
/// a signed-in account on its usual home. Without the app the same address
/// shows hosting/i/index.html (code to copy, store links).
class ReferralLinkPageWidget extends StatefulWidget {
  const ReferralLinkPageWidget({super.key, this.referralCode});

  final String? referralCode;

  static String routeName = 'ReferralLinkPage';
  static String routePath = referralLinkRoutePath;

  @override
  State<ReferralLinkPageWidget> createState() => _ReferralLinkPageWidgetState();
}

class _ReferralLinkPageWidgetState extends State<ReferralLinkPageWidget> {
  final _auth = AppStateNotifier.instance;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _auth.addListener(_route);
    WidgetsBinding.instance.addPostFrameCallback((_) => _route());
  }

  @override
  void dispose() {
    _auth.removeListener(_route);
    super.dispose();
  }

  Future<void> _route() async {
    if (!mounted || _done) {
      return;
    }
    final target = resolveReferralLinkTarget(
      authResolved: _auth.hasResolvedAuthState,
      authenticated: _auth.loggedIn && currentUserUid.isNotEmpty && !isGuestOrAnonymous,
    );
    if (target == ReferralLinkTarget.wait) {
      return;
    }
    _done = true;
    if (target == ReferralLinkTarget.home) {
      final resolution = await resolveAuthenticatedHome(source: 'referral_link');
      if (mounted) {
        context.goNamedAuth(resolution.routeName, mounted, ignoreRedirect: true);
      }
      return;
    }
    final code = extractReferralCodeFromUri(
      Uri(queryParameters: {'ref': widget.referralCode ?? ''}),
    );
    if (code != null && FFAppState().pendingReferralCode != code) {
      FFAppState().update(() {
        FFAppState().pendingReferralCode = code;
      });
    }
    context.goNamed(InscriptionPageWidget.routeName);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FlutterFlowTheme.of(context).secondaryBackground,
      body: const Center(child: CircularProgressIndicator()),
    );
  }
}
