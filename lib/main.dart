import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Clear cache
  try {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    debugPrint('✅ Cache cleared successfully');
  } catch (e) {
    debugPrint('❌ Error clearing cache: $e');
  }

  // Set orientation
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(const MyApp());
}

final ThemeData appTheme = ThemeData(
  primarySwatch: Colors.teal,
  visualDensity: VisualDensity.adaptivePlatformDensity,
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFF00BFA5),
    brightness: Brightness.light,
  ),
  textTheme: TextTheme(
    displayLarge: GoogleFonts.cairo(fontWeight: FontWeight.w700),
    displayMedium: GoogleFonts.cairo(fontWeight: FontWeight.w700),
    displaySmall: GoogleFonts.cairo(fontWeight: FontWeight.w700),
    headlineLarge: GoogleFonts.cairo(fontWeight: FontWeight.w700),
    headlineMedium: GoogleFonts.cairo(fontWeight: FontWeight.w600),
    headlineSmall: GoogleFonts.cairo(fontWeight: FontWeight.w600),
    titleLarge: GoogleFonts.cairo(fontWeight: FontWeight.w600),
    titleMedium: GoogleFonts.cairo(fontWeight: FontWeight.w500),
    titleSmall: GoogleFonts.cairo(fontWeight: FontWeight.w500),
    bodyLarge: GoogleFonts.cairo(),
    bodyMedium: GoogleFonts.cairo(),
    bodySmall: GoogleFonts.cairo(),
    labelLarge: GoogleFonts.cairo(fontWeight: FontWeight.w500),
    labelMedium: GoogleFonts.cairo(),
    labelSmall: GoogleFonts.cairo(),
  ),
  appBarTheme: AppBarTheme(
    centerTitle: true,
    backgroundColor: const Color(0xFF00BFA5),
    foregroundColor: Colors.white,
    elevation: 0,
    titleTextStyle: GoogleFonts.cairo(
      fontSize: 20,
      fontWeight: FontWeight.bold,
      color: Colors.white,
    ),
  ),
);

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'الشركة العامة لتعبئة وخدمات الغاز',
      theme: appTheme,
      locale: const Locale('ar', 'IQ'),
      builder: (context, child) {
        return Directionality(textDirection: TextDirection.rtl, child: child!);
      },
      home: const SplashScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    debugPrint('🚀 SplashScreen initState');

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeIn,
    );

    _controller.forward();

    // Navigate to WebView after 3 seconds
    Timer(const Duration(seconds: 3), () {
      debugPrint('⏰ Timer completed - Navigating to WebView');
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => const WebViewScreen(),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE8F5F3),
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo
              Container(
                width: 150,
                height: 150,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF00BFA5),
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00BFA5).withOpacity(0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Image.asset(
                  'assets/images/logo.png',
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    debugPrint('❌ Error loading logo: $error');
                    return Icon(
                      Icons.business,
                      size: 80,
                      color: Colors.white,
                    );
                  },
                ),
              ),
              const SizedBox(height: 30),

              // Company name
              Text(
                'الشركة العامة لتعبئة وخدمات الغاز',
                style: GoogleFonts.cairo(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF2D3748),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),

              // Subtitle
              Text(
                'بوابة الموظف الرقمية',
                style: GoogleFonts.cairo(
                  fontSize: 16,
                  color: const Color(0xFF00BFA5),
                ),
              ),
              const SizedBox(height: 40),

              // Loading indicator
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(
                  const Color(0xFF00BFA5),
                ),
                strokeWidth: 3,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class WebViewScreen extends StatefulWidget {
  const WebViewScreen({Key? key}) : super(key: key);

  @override
  _WebViewScreenState createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  final String url = 'http://109.224.38.44:5000/login';
  WebViewController? controller;
  bool isLoading = true;
  double loadingProgress = 0.0;
  bool hasError = false;
  String errorMessage = '';

  @override
  void initState() {
    super.initState();
    debugPrint('🌐 WebViewScreen initState');
    debugPrint('🔗 URL to load: $url');

    // Delay initialization to ensure proper rendering
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        _initializeWebView();
      }
    });
  }

  void _initializeWebView() {
    debugPrint('⚙️ Initializing WebView...');

    try {
      controller = WebViewController()
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
                  loadingProgress = 0.0;
                });
              }
            },
            onProgress: (int progress) {
              debugPrint('⏳ Progress: $progress%');
              if (mounted) {
                setState(() {
                  loadingProgress = progress / 100;
                });
              }
            },
            onPageFinished: (String url) {
              debugPrint('✅ Page finished: $url');
              if (mounted) {
                setState(() {
                  isLoading = false;
                  loadingProgress = 1.0;
                });
              }
            },
            onWebResourceError: (WebResourceError error) {
              debugPrint('❌ WebView Error:');
              debugPrint('   Description: ${error.description}');
              debugPrint('   Error code: ${error.errorCode}');
              debugPrint('   Error type: ${error.errorType}');

              if (mounted) {
                setState(() {
                  isLoading = false;
                  hasError = true;
                  errorMessage = error.description;
                });
              }
            },
            onNavigationRequest: (NavigationRequest request) {
              debugPrint('🔗 Navigation: ${request.url}');
              return NavigationDecision.navigate;
            },
          ),
        );

      // Load URL
      debugPrint('🚀 Loading URL: $url');
      controller!.loadRequest(Uri.parse(url));

      if (mounted) {
        setState(() {});
      }

      debugPrint('✅ WebView initialized successfully');
    } catch (e) {
      debugPrint('❌ Error initializing WebView: $e');
      if (mounted) {
        setState(() {
          hasError = true;
          errorMessage = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    debugPrint(
        '🎨 Building WebViewScreen - hasError: $hasError, isLoading: $isLoading');

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(
          'بوابة الموظف',
          style: GoogleFonts.cairo(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              debugPrint('🔄 Refresh pressed');
              if (controller != null) {
                controller!.reload();
              } else {
                _initializeWebView();
              }
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          // WebView
          if (controller != null && !hasError)
            WebViewWidget(controller: controller!),

          // Error screen
          if (hasError)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 80,
                      color: Colors.red.shade400,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'حدث خطأ في التحميل',
                      style: GoogleFonts.cairo(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF2D3748),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      errorMessage,
                      style: GoogleFonts.cairo(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 30),
                    ElevatedButton.icon(
                      onPressed: () {
                        setState(() {
                          hasError = false;
                        });
                        _initializeWebView();
                      },
                      icon: const Icon(Icons.refresh),
                      label: Text(
                        'إعادة المحاولة',
                        style: GoogleFonts.cairo(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00BFA5),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 30,
                          vertical: 15,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Loading overlay
          if (isLoading && !hasError)
            Container(
              color: Colors.white,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: loadingProgress > 0 ? loadingProgress : null,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Color(0xFF00BFA5),
                      ),
                      strokeWidth: 4,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      loadingProgress > 0
                          ? 'جاري التحميل... ${(loadingProgress * 100).toInt()}%'
                          : 'جاري التحميل...',
                      style: GoogleFonts.cairo(
                        fontSize: 16,
                        color: const Color(0xFF4A5568),
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
