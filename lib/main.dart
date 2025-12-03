import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:async';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Clear app cache on startup
  await clearAppCache();

  // Set preferred orientations
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(const MyApp());
}

// Function to clear application cache
Future<void> clearAppCache() async {
  SharedPreferences prefs = await SharedPreferences.getInstance();
  await prefs.clear();
}

// Custom theme with Cairo font
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

// Modern UI Components
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

// Splash Screen مع الشعار الحقيقي
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

  @override
  void initState() {
    super.initState();

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

    Timer(const Duration(seconds: 3), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const PrivacyPolicyScreen(),
            transitionsBuilder: (_, animation, __, child) {
              return FadeTransition(opacity: animation, child: child);
            },
            transitionDuration: const Duration(milliseconds: 600),
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
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFFE8F5F3),
              const Color(0xFFD4EDE9),
              const Color(0xFFC0E5DF),
            ],
          ),
        ),
        child: Stack(
          children: [
            // Decorative circles - Top Right
            Positioned(
              top: -100,
              right: -100,
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: Container(
                  width: 300,
                  height: 300,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF00BFA5).withOpacity(0.15),
                  ),
                ),
              ),
            ),

            // Decorative circles - Bottom Left
            Positioned(
              bottom: -150,
              left: -100,
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: Container(
                  width: 400,
                  height: 400,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF00BFA5).withOpacity(0.15),
                  ),
                ),
              ),
            ),

            // Main content card
            Center(
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.3),
                  end: Offset.zero,
                ).animate(_slideAnimation),
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: ModernCard(
                    width: MediaQuery.of(context).size.width * 0.85,
                    padding: const EdgeInsets.all(40),
                    margin: const EdgeInsets.symmetric(horizontal: 20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 30,
                        offset: const Offset(0, 15),
                      ),
                    ],
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Logo with scale animation
                        ScaleTransition(
                          scale: _scaleAnimation,
                          child: Container(
                            width: 140,
                            height: 140,
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: const Color(0xFF00BFA5),
                              borderRadius: BorderRadius.circular(30),
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      const Color(0xFF00BFA5).withOpacity(0.3),
                                  blurRadius: 20,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: Image.asset(
                              'assets/images/logo.png',
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                        const SizedBox(height: 30),

                        // Company name
                        Text(
                          'الشركة العامة لتعبئة',
                          style: GoogleFonts.cairo(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF2D3748),
                          ),
                          textAlign: TextAlign.center,
                        ),
                        Text(
                          'وخدمات الغاز',
                          style: GoogleFonts.cairo(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF2D3748),
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 15),

                        // Subtitle
                        Text(
                          'بوابة الموظف الرقمية',
                          style: GoogleFonts.cairo(
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFF00BFA5),
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 40),

                        // Loading indicator
                        SizedBox(
                          width: 40,
                          height: 40,
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(
                              const Color(0xFF00BFA5),
                            ),
                            strokeWidth: 3,
                          ),
                        ),
                      ],
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

// Privacy Policy Screen
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFC),
      body: Column(
        children: [
          // Header
          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.only(top: 60, bottom: 30, left: 20, right: 20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF00BFA5),
                  const Color(0xFF00A896),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00BFA5).withOpacity(0.3),
                  blurRadius: 15,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              children: [
                Icon(
                  Icons.privacy_tip_outlined,
                  size: 50,
                  color: Colors.white,
                ),
                const SizedBox(height: 15),
                Text(
                  'سياسة الخصوصية',
                  style: GoogleFonts.cairo(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'يرجى قراءة سياسة الخصوصية بعناية',
                  style: GoogleFonts.cairo(
                    fontSize: 15,
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
              ],
            ),
          ),

          // Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ModernCard(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildPrivacySection(
                      '1. المقدمة',
                      'تحترم الشركة العامة لتعبئة وخدمات الغاز خصوصية موظفيها وتلتزم بحماية بياناتهم الشخصية. توضح هذه السياسة كيفية جمع واستخدام وحماية المعلومات الخاصة بالموظفين.',
                    ),
                    _buildPrivacySection(
                      '2. البيانات المجمعة',
                      'يتم جمع البيانات الأساسية للموظف مثل الاسم، الرقم الوظيفي، القسم، الراتب، والمعلومات الوظيفية الأخرى اللازمة لإدارة الموارد البشرية والرواتب.',
                    ),
                    _buildPrivacySection(
                      '3. استخدام البيانات',
                      'تُستخدم البيانات لأغراض إدارية فقط، مثل حساب الرواتب، إدارة الحضور والانصراف، والتواصل مع الموظفين بخصوص الأمور الوظيفية.',
                    ),
                    _buildPrivacySection(
                      '4. حماية البيانات',
                      'تتخذ الشركة العامة لتعبئة وخدمات الغاز جميع التدابير الأمنية اللازمة لحماية بيانات الموظفين من الوصول غير المصرح به أو الكشف عنها.',
                    ),
                    _buildPrivacySection(
                      '5. مشاركة البيانات',
                      'لن يتم مشاركة بيانات الموظفين مع أي جهة خارجية إلا في حالات ضرورية مثل الامتثال للقوانين أو بموافقة الموظف.',
                    ),
                    _buildPrivacySection(
                      '6. الاحتفاظ بالبيانات',
                      'سيتم الاحتفاظ ببيانات الموظفين طوال فترة عملهم في الشركة، وبعد انتهاء الخدمة، سيتم حفظها وفقًا للمتطلبات القانونية.',
                    ),
                    _buildPrivacySection(
                      '7. حقوق الموظف',
                      'يحق للموظف الاطلاع على بياناته، وطلب تصحيح أي خطأ، أو حذف بياناته بعد انتهاء العلاقة الوظيفية، ما لم يكن الاحتفاظ بها مطلوبًا قانونيًا.',
                    ),
                    _buildPrivacySection(
                      '8. التعديلات على السياسة',
                      'قد تقوم الشركة العامة لتعبئة وخدمات الغاز بتحديث هذه السياسة من وقت لآخر، وسيتم إخطار الموظفين بأي تعديل من خلال التطبيق.',
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Agreement button
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: ModernButton(
              onPressed: () {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (context) => const WebViewScreen(),
                  ),
                );
              },
              child: Text(
                'موافق',
                style: GoogleFonts.cairo(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrivacySection(String title, String content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F5E9),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              title,
              style: GoogleFonts.cairo(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF00BFA5),
              ),
            ),
          ),
          Text(
            content,
            style: GoogleFonts.cairo(
              fontSize: 15,
              height: 1.6,
              color: const Color(0xFF4A5568),
            ),
            textAlign: TextAlign.right,
          ),
        ],
      ),
    );
  }
}

// WebView Screen with Internet Connection Check
class WebViewScreen extends StatefulWidget {
  const WebViewScreen({Key? key}) : super(key: key);

  @override
  _WebViewScreenState createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  final String url = 'http://109.224.38.44:5000/login';
  late final WebViewController controller;
  bool isLoading = true;
  double loadingProgress = 0.0;
  bool canGoBack = false;
  bool hasInternetConnection = true;
  late StreamSubscription<List<ConnectivityResult>> connectivitySubscription;

  @override
  void initState() {
    super.initState();
    _checkInternetConnection();
    _initializeWebView();
    _listenToConnectivityChanges();
  }

  @override
  void dispose() {
    connectivitySubscription.cancel();
    super.dispose();
  }

  // Check internet connection - FIXED
  Future<void> _checkInternetConnection() async {
    final List<ConnectivityResult> connectivityResult =
        (await Connectivity().checkConnectivity()) as List<ConnectivityResult>;
    setState(() {
      // Check if there's any connection (not none)
      hasInternetConnection = connectivityResult.any((result) =>
          result == ConnectivityResult.mobile ||
          result == ConnectivityResult.wifi ||
          result == ConnectivityResult.ethernet ||
          result == ConnectivityResult.vpn ||
          result == ConnectivityResult.bluetooth ||
          result == ConnectivityResult.other);
    });
  }

  // Listen to connectivity changes - FIXED
  void _listenToConnectivityChanges() {
    connectivitySubscription = Connectivity()
            .onConnectivityChanged
            .listen((List<ConnectivityResult> results) {
              setState(() {
                // Check if there's any connection (not none)
                hasInternetConnection = results.any((result) =>
                    result == ConnectivityResult.mobile ||
                    result == ConnectivityResult.wifi ||
                    result == ConnectivityResult.ethernet ||
                    result == ConnectivityResult.vpn ||
                    result == ConnectivityResult.bluetooth ||
                    result == ConnectivityResult.other);
              });

              // Reload page if connection restored
              if (hasInternetConnection && !isLoading) {
                controller.reload();
              }
            } as void Function(ConnectivityResult event)?)
        as StreamSubscription<List<ConnectivityResult>>;
  }

  void _initializeWebView() {
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            setState(() {
              isLoading = true;
              loadingProgress = 0.0;
            });
            _updateCanGoBack();
          },
          onProgress: (int progress) {
            setState(() {
              loadingProgress = progress / 100;
            });
          },
          onPageFinished: (String url) {
            setState(() {
              isLoading = false;
              loadingProgress = 1.0;
            });
            _updateCanGoBack();
          },
          onWebResourceError: (WebResourceError error) {
            setState(() {
              isLoading = false;
            });
          },
        ),
      )
      ..loadRequest(Uri.parse(url));
  }

  Future<void> _updateCanGoBack() async {
    final canNavigateBack = await controller.canGoBack();
    setState(() {
      canGoBack = canNavigateBack;
    });
  }

  Future<bool> _onWillPop() async {
    if (canGoBack) {
      return await _showBackDialog() ?? false;
    }
    return await _showBackDialog() ?? false;
  }

  Future<bool?> _showBackDialog() {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                Icon(
                  Icons.arrow_forward,
                  color: const Color(0xFF00BFA5),
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'العودة',
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
              'هل تريد العودة الى واجهة تسجيل الدخول؟',
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
                onPressed: () => Navigator.of(context).pop(true),
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
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              if (canGoBack) {
                controller.goBack();
              } else {
                final shouldGoBack = await _showBackDialog();
                if (shouldGoBack == true) {
                  SystemNavigator.pop();
                }
              }
            },
          ),
          title: Text(
            'الشركة العامة لتعبئة وخدمات الغاز',
            style: GoogleFonts.cairo(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () {
                _checkInternetConnection();
                controller.reload();
              },
            ),
          ],
        ),
        body: Stack(
          children: [
            // WebView
            if (hasInternetConnection) WebViewWidget(controller: controller),

            // No Internet Connection Screen
            if (!hasInternetConnection)
              Container(
                width: double.infinity,
                height: double.infinity,
                color: Colors.white,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(40),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // No internet icon
                        Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.wifi_off_rounded,
                            size: 60,
                            color: Colors.red.shade400,
                          ),
                        ),
                        const SizedBox(height: 30),

                        // Title
                        Text(
                          'لا يوجد اتصال بالإنترنت',
                          style: GoogleFonts.cairo(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF2D3748),
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 15),

                        // Message
                        Text(
                          'يرجى التحقق من اتصالك بالإنترنت والمحاولة مرة أخرى',
                          style: GoogleFonts.cairo(
                            fontSize: 16,
                            color: const Color(0xFF4A5568),
                            height: 1.6,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 40),

                        // Retry button
                        ModernButton(
                          onPressed: () async {
                            await _checkInternetConnection();
                            if (hasInternetConnection) {
                              controller.reload();
                            }
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
              ),

            // Loading indicator
            if (isLoading && hasInternetConnection)
              Container(
                width: double.infinity,
                height: double.infinity,
                color: Colors.white.withOpacity(0.8),
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
                            value: loadingProgress,
                            minHeight: 8,
                            backgroundColor: Colors.grey.withOpacity(0.1),
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              Color(0xFF00BFA5),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'جاري التحميل... ${(loadingProgress * 100).toInt()}%',
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
          ],
        ),
      ),
    );
  }
}
