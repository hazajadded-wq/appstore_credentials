import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

// ✅ EMERGENCY FIX: MINIMAL MAIN - NO FIREBASE, NO COMPLEXITY
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint('🚀 MINIMAL APP - EMERGENCY BLACK SCREEN FIX');
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SalaryInfo',
      theme: ThemeData(
        primarySwatch: Colors.teal,
        useMaterial3: true,
      ),
      home: const WebViewScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class WebViewScreen extends StatefulWidget {
  const WebViewScreen({Key? key}) : super(key: key);

  @override
  _WebViewScreenState createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  final String loginUrl = 'http://109.224.38.44:5000/login';
  WebViewController? controller;
  bool isLoading = true;
  bool hasError = false;
  String errorMessage = '';

  @override
  void initState() {
    super.initState();
    debugPrint('🌐 WebViewScreen initState');
    debugPrint('🔗 URL: $loginUrl');

    // ✅ Initialize IMMEDIATELY
    _initializeWebView();
  }

  void _initializeWebView() {
    debugPrint('⚙️ Initializing WebView...');

    try {
      // ✅ Create controller with proper iOS configuration
      late final PlatformWebViewControllerCreationParams params;
      if (Platform.isIOS) {
        params = WebKitWebViewControllerCreationParams(
          allowsInlineMediaPlayback: true,
          mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
        );
      } else {
        params = const PlatformWebViewControllerCreationParams();
      }

      controller = WebViewController.fromPlatformCreationParams(params)
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Colors.white)
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageStarted: (String url) {
              debugPrint('📄 Page started: $url');
              if (mounted) {
                setState(() {
                  isLoading = true;
                  hasError = false;
                });
              }
            },
            onProgress: (int progress) {
              debugPrint('⏳ Progress: $progress%');
            },
            onPageFinished: (String url) {
              debugPrint('✅ Page finished: $url');
              if (mounted) {
                setState(() {
                  isLoading = false;
                });
              }
            },
            onWebResourceError: (WebResourceError error) {
              debugPrint('❌ WebView error: ${error.description}');
              if (mounted) {
                setState(() {
                  isLoading = false;
                  hasError = true;
                  errorMessage = error.description;
                });
              }
            },
          ),
        );

      // ✅ iOS-specific configuration
      if (Platform.isIOS) {
        final wkController = controller!.platform as WebKitWebViewController;
        wkController.setAllowsBackForwardNavigationGestures(true);
        debugPrint('✅ iOS WebView configured');
      }

      // ✅ Load URL
      debugPrint('🚀 Loading URL: $loginUrl');
      controller!.loadRequest(Uri.parse(loginUrl));

      if (mounted) {
        setState(() {});
      }

      debugPrint('✅ WebView initialized successfully');
    } catch (e, stackTrace) {
      debugPrint('❌ Error initializing WebView: $e');
      debugPrint('Stack: $stackTrace');
      if (mounted) {
        setState(() {
          hasError = true;
          errorMessage = e.toString();
          isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    debugPrint(
        '🎨 Building WebViewScreen - isLoading: $isLoading, hasError: $hasError');

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('بوابة الموظف الرقمية'),
        backgroundColor: const Color(0xFF00BFA5),
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          // ✅ ALWAYS show white background
          Container(
            color: Colors.white,
            width: double.infinity,
            height: double.infinity,
          ),

          // ✅ Show loading BEFORE controller is ready
          if (controller == null || isLoading)
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 60,
                    height: 60,
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Color(0xFF00BFA5),
                      ),
                      strokeWidth: 4,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'جاري تحميل التطبيق...',
                    style: TextStyle(
                      fontSize: 18,
                      color: Color(0xFF2D3748),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    loginUrl,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),

          // ✅ Show WebView when ready
          if (controller != null && !hasError && !isLoading)
            WebViewWidget(controller: controller!),

          // ✅ Show error if needed
          if (hasError)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.error_outline,
                        size: 60,
                        color: Colors.red.shade400,
                      ),
                    ),
                    const SizedBox(height: 30),
                    const Text(
                      'يرجى الاتصال بالانترنيت',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2D3748),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 15),
                    Text(
                      errorMessage,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 40),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          hasError = false;
                          isLoading = true;
                        });
                        _initializeWebView();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00BFA5),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 40,
                          vertical: 15,
                        ),
                      ),
                      child: const Text(
                        'إعادة المحاولة',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
