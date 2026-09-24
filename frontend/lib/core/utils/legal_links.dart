import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/in_app_web_view.dart';

/// The app's hosted legal/support pages. The paywall must link Terms and
/// Privacy directly (App Review 3.1.2), and Settings links all three.
const supportUrl = 'https://sila.fitness/support.html';
const privacyUrl = 'https://sila.fitness/privacy.html';
const termsUrl = 'https://sila.fitness/terms.html';

/// Opens one of the hosted pages above in the in-app browser, so the user
/// stays in the app. The WebView's toolbar still offers "open in browser".
void openHostedPage(BuildContext context, String url, String title) {
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => InAppWebViewScreen(title: title, url: url),
  ));
}

/// Where the user cancels a store subscription - the app itself can't, the
/// store owns renewal.
String get storeName => Platform.isIOS ? 'App Store' : 'Google Play';

/// Opens the platform's own subscription-management screen.
Future<void> openManageSubscriptions() => launchUrl(
      Uri.parse(Platform.isIOS
          ? 'https://apps.apple.com/account/subscriptions'
          : 'https://play.google.com/store/account/subscriptions'),
      mode: LaunchMode.externalApplication,
    );
