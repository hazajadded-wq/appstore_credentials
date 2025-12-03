import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
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

class ModernCard extends StatelessWidget {
  final Widget child;
  final double? width;
  final double? height;
  final double borderRadius;
  final Color? backgroundColor;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final List<BoxShadow>? boxShadow;

  const ModernCard({
    Key? key,
    required this.child,
    this.width,
    this.height,
    this.borderRadius = 20,
    this.backgroundColor,
    this.padding = const EdgeInsets.all(20),
    this.margin = EdgeInsets.zero,
    this.boxShadow,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor ?? Colors.white,
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: boxShadow ??
            [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 15,
                offset: const Offset(0, 5),
              ),
            ],
      ),
      child: child,
    );
  }
}

class ModernButton extends StatelessWidget {
  final VoidCallback onPressed;
  final Widget child;
  final Color? color;
  final double height;
  final double borderRadius;
  final EdgeInsetsGeometry padding;
  final bool isGradient;

  const ModernButton({
    Key? key,
    required this.onPressed,
    required this.child,
    this.color,
    this.height = 56,
    this.borderRadius = 15,
    this.padding = EdgeInsets.zero,
    this.isGradient = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(borderRadius),
        child: Ink(
          height: height,
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(borderRadius),
            gradient: isGradient
                ? LinearGradient(
                    colors: [
                      color ?? const Color(0xFF00BFA5),
                      color != null
                          ? color!.withOpacity(0.8)
                          : const Color(0xFF00A896),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: isGradient ? null : (color ?? const Color(0xFF00BFA5)),
            boxShadow: [
              BoxShadow(
                color: (color ?? const Color(0xFF00BFA5)).withOpacity(0.3),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Center(child: child),
        ),
      ),
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
  late Animation<double> _slideAnimation;
  late Animation<double> _scaleAnimation;
  String _version = '';

  @override
  void initState() {
    super.initState();
    debugPrint('🚀 SplashScreen initState');
    _loadVersion();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.6, curve: Curves.easeIn),
    );

    _slideAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.2, 0.8, curve: Curves.easeOutCubic),
    );

    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.3, 0.9, curve: Curves.easeOutBack),
    );

    _controller.forward();

    // Navigate to Privacy Policy after 3 seconds
    Timer(const Duration(seconds: 3), () {
      debugPrint('⏰ Timer completed - Navigating to Privacy Policy');
      if (mounted) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const PrivacyPolicyScreen(),
            transitionsBuilder: (_, animation, __, child) {
              return FadeTransition(opacity: animation, child: child);
            },
            transitionDuration: const Duration(milliseconds: 500),
          ),
        );
      }
    });
  }

  Future<void> _loadVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      setState(() {
        _version = 'v${packageInfo.version} (${packageInfo.buildNumber})';
      });
      debugPrint('📱 App Version: $_version');
    } catch (e) {
      debugPrint('❌ Error loading version: $e');
      setState(() {
        _version = 'v1.0.8 (11)';
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFF00BFA5).withOpacity(0.05),
              Colors.white,
              const Color(0xFF00BFA5).withOpacity(0.05),
            ],
          ),
        ),
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: ScaleTransition(
                      scale: _scaleAnimation,
                      child: Container(
                        width: 140,
                        height: 140,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(30),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF00BFA5).withOpacity(0.2),
                              blurRadius: 30,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Image.asset(
                          'assets/images/logo.png',
                          width: 100,
                          height: 100,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                  SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.3),
                      end: Offset.zero,
                    ).animate(_slideAnimation),
                    child: FadeTransition(
                      opacity: _fadeAnimation,
                      child: Column(
                        children: [
                          Text(
                            'بوابة الموظف الرقمية',
                            style: GoogleFonts.cairo(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF2D3748),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'الشركة العامة لتعبئة وخدمات الغاز',
                            style: GoogleFonts.cairo(
                              fontSize: 16,
                              color: const Color(0xFF4A5568),
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 50),
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: SizedBox(
                      width: 50,
                      height: 50,
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(
                          const Color(0xFF00BFA5),
                        ),
                        strokeWidth: 3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Version number at bottom
            Positioned(
              bottom: 30,
              left: 0,
              right: 0,
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00BFA5).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: const Color(0xFF00BFA5).withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      _version.isEmpty ? 'جاري التحميل...' : _version,
                      style: GoogleFonts.cairo(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF00BFA5),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    debugPrint('📄 Building PrivacyPolicyScreen');
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                const Color(0xFF00BFA5).withOpacity(0.03),
                Colors.white,
              ],
            ),
          ),
          child: Column(
            children: [
              // Header with Logo
              Container(
                padding: const EdgeInsets.all(30),
                child: Column(
                  children: [
                    Container(
                      width: 100,
                      height: 100,
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF00BFA5).withOpacity(0.15),
                            blurRadius: 20,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: Image.asset('assets/images/logo.png'),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'سياسة الخصوصية',
                      style: GoogleFonts.cairo(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF2D3748),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'بوابة الموظف الرقمية',
                      style: GoogleFonts.cairo(
                        fontSize: 16,
                        color: const Color(0xFF4A5568),
                      ),
                    ),
                  ],
                ),
              ),

              // Privacy Policy Content
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: ModernCard(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildPolicySection(
                          icon: Icons.security,
                          title: 'حماية بياناتك',
                          content:
                              'نحن نحترم خصوصيتك ونلتزم بحماية معلوماتك الشخصية. هذا التطبيق مصمم لعرض معلومات الرواتب للموظفين فقط.',
                        ),
                        const SizedBox(height: 24),
                        _buildPolicySection(
                          icon: Icons.data_usage,
                          title: 'البيانات المستخدمة',
                          content:
                              'يستخدم التطبيق المعلومات التالية:\n• اتصال الإنترنت للوصول إلى البوابة\n• لا يتم جمع أو تخزين معلومات شخصية في التطبيق',
                        ),
                        const SizedBox(height: 24),
                        _buildPolicySection(
                          icon: Icons.lock,
                          title: 'الأمان',
                          content:
                              'جميع الاتصالات مع الخادم آمنة. لا يقوم التطبيق بتخزين أي بيانات حساسة على الجهاز.',
                        ),
                        const SizedBox(height: 24),
                        _buildPolicySection(
                          icon: Icons.phone_android,
                          title: 'الأذونات المطلوبة',
                          content:
                              'التطبيق يحتاج إلى:\n• الإنترنت: للاتصال بالخادم',
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Accept Button
              Container(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: ModernButton(
                        onPressed: () {
                          debugPrint('✅ Privacy policy accepted');
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute(
                                builder: (_) => const WebViewScreen()),
                          );
                        },
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.check_circle, color: Colors.white),
                            const SizedBox(width: 10),
                            Text(
                              'موافق والمتابعة',
                              style: GoogleFonts.cairo(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'بالضغط على موافق، فإنك توافق على سياسة الخصوصية',
                      style: GoogleFonts.cairo(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPolicySection({
    required IconData icon,
    required String title,
    required String content,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF00BFA5).withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            color: const Color(0xFF00BFA5),
            size: 24,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.cairo(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF2D3748),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                content,
                style: GoogleFonts.cairo(
                  fontSize: 14,
                  color: const Color(0xFF4A5568),
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class WebViewScreen extends StatefulWidget {
  const WebViewScreen({Key? key}) : super(key: key);

  @override
  _WebViewScreenState createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  WebViewController? controller;
  bool isLoading = true;
  bool hasError = false;
  bool canGoBack = false;
  bool isLoggedIn = false;
  double loadingProgress = 0.0;
  String errorMessage = '';
  String _version = '';

  @override
  void initState() {
    super.initState();
    debugPrint('🌐 WebViewScreen initState');
    _loadVersion();
    _initializeWebView();
  }

  Future<void> _loadVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      setState(() {
        _version = 'v${packageInfo.version} (${packageInfo.buildNumber})';
      });
      debugPrint('📱 App Version: $_version');
    } catch (e) {
      debugPrint('❌ Error loading version: $e');
      setState(() {
        _version = 'v1.0.8 (11)';
      });
    }
  }

  void _initializeWebView() {
    debugPrint('🔧 Initializing WebView');
    setState(() {
      isLoading = true;
      hasError = false;
      canGoBack = false;
      loadingProgress = 0.0;
    });

    try {
      controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Colors.white)
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageStarted: (String url) {
              debugPrint('📍 Page started: $url');
              setState(() {
                isLoading = true;
                loadingProgress = 0.0;
              });
            },
            onProgress: (int progress) {
              debugPrint('📊 Loading progress: $progress%');
              setState(() {
                loadingProgress = progress / 100.0;
              });
            },
            onPageFinished: (String url) async {
              debugPrint('✅ Page finished: $url');

              // Check if we can go back
              final canGoBackNow = await controller?.canGoBack() ?? false;

              setState(() {
                isLoading = false;
                canGoBack = canGoBackNow;
                isLoggedIn = !url.contains('/login') && !url.contains('=login');
              });

              debugPrint('🔙 Can go back: $canGoBack');
              debugPrint('👤 Is logged in: $isLoggedIn');
            },
            onWebResourceError: (WebResourceError error) {
              debugPrint('❌ WebView Error: ${error.description}');
              setState(() {
                isLoading = false;
                hasError = true;
                errorMessage = error.description;
              });
            },
            onNavigationRequest: (NavigationRequest request) {
              debugPrint('🔗 Navigation request: ${request.url}');
              return NavigationDecision.navigate;
            },
          ),
        )
        ..loadRequest(Uri.parse('http://salary.scgfs.iq'));
      debugPrint('🚀 WebView initialized and loading URL');
    } catch (e) {
      debugPrint('❌ Error initializing WebView: $e');
      setState(() {
        isLoading = false;
        hasError = true;
        errorMessage = e.toString();
      });
    }
  }

  Future<bool> _onWillPop() async {
    if (canGoBack && controller != null) {
      debugPrint('⬅️ Hardware back pressed - Going back in WebView');
      controller!.goBack();
      return false;
    } else {
      debugPrint('🚪 Hardware back pressed - Showing exit dialog');
      final shouldExit = await _showExitDialog();
      return shouldExit ?? false;
    }
  }

  Future<bool?> _showExitDialog() {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                Icon(
                  Icons.exit_to_app,
                  color: const Color(0xFF00BFA5),
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'الخروج من التطبيق',
                    style: GoogleFonts.cairo(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF2D3748),
                    ),
                  ),
                ),
              ],
            ),
            content: Text(
              'هل تريد الخروج من التطبيق؟',
              style: GoogleFonts.cairo(
                fontSize: 16,
                color: const Color(0xFF4A5568),
                height: 1.5,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                child: Text(
                  'لا',
                  style: GoogleFonts.cairo(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[600],
                  ),
                ),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop(true); // close dialog first

                  // Close app depending on platform
                  if (Platform.isAndroid) {
                    SystemNavigator.pop();
                  } else if (Platform.isIOS) {
                    exit(0); // iOS actual app exit
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00BFA5),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(
                  'نعم',
                  style: GoogleFonts.cairo(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    debugPrint(
        '🎨 Building WebViewScreen - isLoading: $isLoading, hasError: $hasError, isLoggedIn: $isLoggedIn');

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              if (canGoBack && controller != null) {
                debugPrint('⬅️ Back button pressed - Going back in WebView');
                controller!.goBack();
              } else {
                debugPrint('🚪 Back button pressed - Showing exit dialog');
                final shouldExit = await _showExitDialog();
                if (shouldExit == true) {
                  SystemNavigator.pop();
                }
              }
            },
          ),
          title: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'الشركة العامة لتعبئة وخدمات الغاز',
                style: GoogleFonts.cairo(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (_version.isNotEmpty)
                Text(
                  _version,
                  style: GoogleFonts.cairo(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
            ],
          ),
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
                      Text(
                        'يرجى الاتصال بالانترنيت',
                        style: GoogleFonts.cairo(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF2D3748),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 15),
                      Text(
                        errorMessage,
                        style: GoogleFonts.cairo(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 40),
                      ModernButton(
                        onPressed: () {
                          setState(() {
                            hasError = false;
                          });
                          _initializeWebView();
                        },
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.refresh,
                              color: Colors.white,
                              size: 22,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'إعادة المحاولة',
                              style: GoogleFonts.cairo(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Loading overlay
            if (isLoading && !hasError)
              Container(
                color: Colors.white.withOpacity(0.9),
                child: Center(
                  child: ModernCard(
                    width: 220,
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: LinearProgressIndicator(
                            value: loadingProgress > 0 ? loadingProgress : null,
                            minHeight: 8,
                            backgroundColor: Colors.grey.withOpacity(0.1),
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              Color(0xFF00BFA5),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          loadingProgress > 0
                              ? 'جاري التحميل... ${(loadingProgress * 100).toInt()}%'
                              : 'جاري التحميل...',
                          style: GoogleFonts.cairo(
                            color: const Color(0xFF2D3748),
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // Version Badge - Always visible at bottom right
            if (_version.isNotEmpty && !hasError)
              Positioned(
                bottom: 16,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00BFA5),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00BFA5).withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    _version,
                    style: GoogleFonts.cairo(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
