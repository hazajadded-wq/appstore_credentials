import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:ui' as ui;
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

  // REMOVED: SystemChrome.setPreferredOrientations
  // This was causing touch issues on iPhone 13 mini and iPad Air 5

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

  @override
  void initState() {
    super.initState();
    debugPrint('🚀 SplashScreen initState');

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
                        ),
                        const SizedBox(height: 30),
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

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    debugPrint('الشركة العامة لتعبئة وخدمات الغاز');

    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFC),
      body: Column(
        children: [
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
                debugPrint('✅ Privacy Policy accepted - Navigating to WebView');
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

class WebViewScreen extends StatefulWidget {
  const WebViewScreen({Key? key}) : super(key: key);

  @override
  _WebViewScreenState createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  final String loginUrl = 'http://109.224.38.44:5000/login';
  WebViewController? controller;
  bool isLoading = true;
  double loadingProgress = 0.0;
  bool canGoBack = false;
  bool hasError = false;
  String errorMessage = '';
  String currentUrl = '';
  bool isLoggedIn = false;
  String lastNavigatedUrl = ''; // Track last URL to prevent loops
  int navigationCount = 0; // Count consecutive navigations to same URL
  double zoomLevel = 1.0; // Zoom level for page content

  // GlobalKey for screenshot capture
  final GlobalKey _webViewKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    debugPrint('🌐 WebViewScreen initState');
    debugPrint('🔗 Login URL: $loginUrl');

    // Delay initialization to ensure proper rendering
    Future.delayed(const Duration(milliseconds: 300), () {
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
        ..addJavaScriptChannel(
          'FlutterChannel',
          onMessageReceived: (JavaScriptMessage message) {
            debugPrint('📨 JavaScript message received: ${message.message}');
            // Handle any JavaScript messages from the web page
          },
        );

      // Platform-specific settings for Android
      if (Platform.isAndroid) {
        debugPrint('🤖 Configuring Android WebView settings');

        // Get the Android WebView controller
        final androidController =
            controller!.platform as AndroidWebViewController;

        // Enable critical settings for proper HTML display
        androidController.setMediaPlaybackRequiresUserGesture(false);

        controller!.enableZoom(true);

        debugPrint('✅ Android WebView settings configured');
      }

      controller!.setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            debugPrint('📄 Page started: $url');

            // Reset counter if it's a genuinely different page
            if (!url.contains('download=1')) {
              navigationCount = 0;
              lastNavigatedUrl = '';
            }

            if (mounted) {
              setState(() {
                isLoading = true;
                hasError = false;
                loadingProgress = 0.0;
                currentUrl = url;
                // Check if user is logged in (not on login page)
                isLoggedIn = !url.contains('/login');
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

            // Reset navigation counter on successful load
            navigationCount = 0;

            if (mounted) {
              setState(() {
                isLoading = false;
                loadingProgress = 1.0;
                currentUrl = url;
                isLoggedIn = !url.contains('/login');
              });
            }
            _updateCanGoBack();

            // Hide notifications on login page
            if (url.contains('/login')) {
              debugPrint('🔐 Login page detected - hiding notifications');
              _hideNotificationsOnLoginPage();
            }

            // Auto-fit payslip pages to screen
            if (url.contains('/payslips/view') || url.contains('/salary')) {
              debugPrint('📄 Payslip page detected - auto-fitting to screen');
              // Reset zoom level for new page
              setState(() {
                zoomLevel = 1.0;
              });
              _autoFitPageToScreen();
            }

            // Inject JavaScript to fix HTML download on Android
            if (Platform.isAndroid) {
              _injectAndroidFix();
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
            debugPrint('🔗 Navigation request: ${request.url}');

            // Detect and prevent infinite reload loops
            if (request.url == lastNavigatedUrl) {
              navigationCount++;
              debugPrint(
                  '⚠️ Duplicate navigation detected. Count: $navigationCount');

              // If same URL is being requested more than twice, block it
              if (navigationCount > 2) {
                debugPrint('🛑 Blocking repeated navigation to prevent loop');
                return NavigationDecision.prevent;
              }
            } else {
              // Different URL, reset counter
              lastNavigatedUrl = request.url;
              navigationCount = 1;
            }

            // Allow all navigation for HTML content display
            // This ensures both iOS and Android can view HTML salary slips
            if (request.url.contains('/login') ||
                request.url.contains('/dashboard') ||
                request.url.contains('/salary') ||
                request.url.contains('/payslips') ||
                request.url.contains('109.224.38.44')) {
              return NavigationDecision.navigate;
            }

            return NavigationDecision.navigate;
          },
        ),
      );

      // Load URL
      debugPrint('🚀 Loading URL: $loginUrl');
      controller!.loadRequest(Uri.parse(loginUrl));

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

  Future<void> _updateCanGoBack() async {
    if (controller != null) {
      final canNavigateBack = await controller!.canGoBack();
      setState(() {
        canGoBack = canNavigateBack;
      });
    }
  }

  Future<void> _autoFitPageToScreen() async {
    if (controller == null) return;

    debugPrint('📐 Auto-fitting page to screen...');

    try {
      await controller!.runJavaScript('''
        (function() {
          console.log('Auto-fit page script loading...');
          
          // Remove any existing viewport meta tags
          var existingViewports = document.querySelectorAll('meta[name="viewport"]');
          existingViewports.forEach(function(viewport) {
            viewport.remove();
          });
          
          // Add optimized viewport for mobile display
          var meta = document.createElement('meta');
          meta.name = 'viewport';
          meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=3.0, user-scalable=yes, shrink-to-fit=yes';
          document.getElementsByTagName('head')[0].appendChild(meta);
          
          // Adjust body styling for better fit
          document.body.style.margin = '0';
          document.body.style.padding = '8px';
          document.body.style.boxSizing = 'border-box';
          document.body.style.overflow = 'auto';
          document.body.style.width = '100%';
          
          // Find main content container and adjust
          var containers = document.querySelectorAll('div.container, div.content, main, article');
          containers.forEach(function(container) {
            container.style.maxWidth = '100%';
            container.style.width = '100%';
            container.style.padding = '8px';
            container.style.boxSizing = 'border-box';
          });
          
          // Adjust tables to fit screen
          var tables = document.querySelectorAll('table');
          tables.forEach(function(table) {
            table.style.width = '100%';
            table.style.maxWidth = '100%';
            table.style.fontSize = '14px';
            table.style.display = 'block';
            table.style.overflowX = 'auto';
          });
          
          // Adjust any fixed width elements
          var fixedElements = document.querySelectorAll('[style*="width"]');
          fixedElements.forEach(function(element) {
            var computedWidth = window.getComputedStyle(element).width;
            var widthValue = parseInt(computedWidth);
            
            // If element is wider than screen, make it responsive
            if (widthValue > window.innerWidth) {
              element.style.width = '100%';
              element.style.maxWidth = '100%';
            }
          });
          
          console.log('✅ Page auto-fitted to screen');
        })();
      ''');

      debugPrint('✅ Auto-fit completed');
    } catch (e) {
      debugPrint('⚠️ Error auto-fitting page: $e');
    }
  }

  void _zoomIn() {
    setState(() {
      if (zoomLevel < 3.0) {
        zoomLevel += 0.2;
        _applyZoom();
      }
    });
  }

  void _zoomOut() {
    setState(() {
      if (zoomLevel > 0.5) {
        zoomLevel -= 0.2;
        _applyZoom();
      }
    });
  }

  Future<void> _applyZoom() async {
    if (controller == null) return;

    try {
      if (Platform.isIOS) {
        // iOS: Use simple transform on body
        await controller!.runJavaScript('''
          (function() {
            var body = document.body;
            var html = document.documentElement;
            
            // Apply transform
            body.style.transform = 'scale($zoomLevel)';
            body.style.transformOrigin = 'top center';
            body.style.transition = 'transform 0.2s ease';
            
            // Prevent scroll
            body.style.overflowX = 'hidden';
            html.style.overflowX = 'hidden';
            
            console.log('iOS zoom applied: $zoomLevel');
          })();
        ''');
        debugPrint('🔍 iOS Zoom level: $zoomLevel');
      } else {
        // Android: Use transform scale
        await controller!.runJavaScript('''
          (function() {
            var html = document.documentElement;
            var body = document.body;
            
            html.style.transformOrigin = '0 0';
            body.style.transformOrigin = '0 0';
            html.style.transform = 'scale($zoomLevel)';
            html.style.width = (100 / $zoomLevel) + '%';
            body.style.width = '100%';
            body.style.minHeight = '100vh';
            
            console.log('Android transform zoom applied: $zoomLevel');
          })();
        ''');
        debugPrint('🔍 Android Zoom level: $zoomLevel');
      }
    } catch (e) {
      debugPrint('⚠️ Error applying zoom: $e');
    }
  }

  Future<void> _hideNotificationsOnLoginPage() async {
    if (controller == null) return;

    debugPrint('🔕 Hiding notifications on login page...');

    try {
      await controller!.runJavaScript('''
        (function() {
          console.log('Notification blocker loading...');
          
          // Hide all notification/alert elements
          var notifications = document.querySelectorAll('.alert, .notification, .toast, [role="alert"], .flash-message, .alert-success, .alert-danger, .alert-warning, .alert-info');
          notifications.forEach(function(notif) {
            notif.style.display = 'none';
          });
          
          // Also hide any elements with notification-related classes
          var allElements = document.querySelectorAll('*');
          allElements.forEach(function(el) {
            var classes = el.className || '';
            if (typeof classes === 'string' && (
              classes.includes('notification') || 
              classes.includes('alert') || 
              classes.includes('toast') ||
              classes.includes('تنبيه') ||
              classes.includes('إشعار')
            )) {
              el.style.display = 'none';
            }
          });
          
          console.log('✅ Notifications hidden on login page');
        })();
      ''');

      debugPrint('✅ Notifications hidden');
    } catch (e) {
      debugPrint('⚠️ Error hiding notifications: $e');
    }
  }

  Future<void> _injectAndroidFix() async {
    if (controller == null) return;

    debugPrint('💉 Injecting Android fix for HTML downloads');

    // JavaScript to handle download buttons and prevent reload loops
    const String jsCode = '''
      (function() {
        console.log('Android WebView fix loading...');
        
        // Store original window.open
        var originalOpen = window.open;
        
        // Override window.open to navigate in same window on Android
        window.open = function(url, name, specs) {
          console.log('Intercepted window.open:', url);
          
          // If it's an HTML download or new window, navigate in current window
          if (url) {
            // Remove download parameter to prevent reload loops
            var cleanUrl = url.replace(/[?&]download=1/, '');
            console.log('Cleaned URL:', cleanUrl);
            
            if (cleanUrl !== window.location.href) {
              window.location.href = cleanUrl;
            }
            return window;
          }
          
          // Fallback to original for other cases
          return originalOpen.call(window, url, name, specs);
        };
        
        // Intercept all download buttons
        document.addEventListener('click', function(e) {
          var target = e.target;
          
          // Check if clicked element or parent is a download button
          for (var i = 0; i < 5; i++) {
            if (!target) break;
            
            var href = target.getAttribute('href');
            var onclick = target.getAttribute('onclick');
            
            // If it has download parameter, prevent default and navigate without it
            if (href && href.includes('download=1')) {
              e.preventDefault();
              var cleanUrl = href.replace(/[?&]download=1/, '');
              console.log('Download button clicked, navigating to:', cleanUrl);
              
              // Only navigate if different from current URL
              if (cleanUrl !== window.location.href && cleanUrl !== window.location.pathname + window.location.search) {
                window.location.href = cleanUrl;
              }
              return false;
            }
            
            target = target.parentElement;
          }
        }, true);
        
        console.log('Android WebView fix injected successfully');
      })();
    ''';

    try {
      await controller!.runJavaScript(jsCode);
      debugPrint('✅ Android fix injected successfully');
    } catch (e) {
      debugPrint('❌ Error injecting JavaScript: $e');
    }
  }

  Future<bool> _requestPermissions() async {
    if (Platform.isAndroid) {
      // For Android, gal package handles permissions automatically on Android 13+
      // For Android 12 and below, request storage permission
      try {
        var status = await Permission.photos.status;
        if (!status.isGranted) {
          status = await Permission.photos.request();
        }
        // Even if denied, gal might still work on Android 13+
        return status.isGranted || status.isPermanentlyDenied;
      } catch (e) {
        debugPrint('Permission check error: $e');
        // Continue anyway, gal will handle it
        return true;
      }
    }
    // iOS doesn't need permission for saving to gallery with gal
    return true;
  }

  Future<void> _savePageAsImage() async {
    try {
      debugPrint('📸 Starting screenshot capture...');

      // Request permissions
      bool hasPermission = await _requestPermissions();
      if (!hasPermission) {
        _showMessage('الرجاء منح صلاحية الوصول للتخزين');
        return;
      }

      // Show loading
      if (mounted) {
        setState(() {
          isLoading = true;
        });
      }

      // Wait a bit to ensure everything is rendered
      await Future.delayed(const Duration(milliseconds: 500));

      Uint8List? screenshot;

      if (Platform.isIOS) {
        // iOS: Use html-to-image library (more reliable than html2canvas)
        debugPrint('📱 Using iOS JavaScript-based screenshot');

        try {
          // First, inject html-to-image library
          await controller!.runJavaScript('''
            (function() {
              if (typeof htmlToImage !== 'undefined') {
                console.log('html-to-image already loaded');
                return Promise.resolve('ready');
              }
              
              return new Promise((resolve, reject) => {
                var script = document.createElement('script');
                script.src = 'https://cdn.jsdelivr.net/npm/html-to-image@1.11.11/dist/html-to-image.js';
                script.onload = function() {
                  console.log('html-to-image loaded successfully');
                  resolve('loaded');
                };
                script.onerror = function() {
                  console.error('Failed to load html-to-image');
                  reject('Failed to load library');
                };
                document.head.appendChild(script);
              });
            })();
          ''');

          // Wait for library to initialize
          await Future.delayed(const Duration(milliseconds: 1500));

          debugPrint('📸 Capturing screenshot with html-to-image...');

          // Capture screenshot
          final result = await controller!.runJavaScriptReturningResult('''
            (async function() {
              try {
                if (typeof htmlToImage === 'undefined') {
                  throw new Error('html-to-image not loaded');
                }
                
                console.log('Starting capture...');
                
                // Capture as PNG
                const dataUrl = await htmlToImage.toPng(document.body, {
                  quality: 1.0,
                  pixelRatio: 2,
                  backgroundColor: '#ffffff'
                });
                
                console.log('Capture complete, converting to base64...');
                return dataUrl.split(',')[1];
              } catch (error) {
                console.error('Capture error:', error.toString());
                throw error;
              }
            })();
          ''');

          if (result.toString().isNotEmpty) {
            screenshot = base64Decode(result.toString());
            debugPrint('✅ iOS screenshot captured: ${screenshot.length} bytes');
          } else {
            throw Exception('Empty result from html-to-image');
          }
        } catch (e) {
          debugPrint('❌ Error capturing iOS screenshot: $e');
          _showMessage('فشل التقاط الصورة - الرجاء المحاولة مرة أخرى');
          if (mounted) {
            setState(() {
              isLoading = false;
            });
          }
          return;
        }
      } else {
        // Android: Use RepaintBoundary (works fine on Android)
        debugPrint('🤖 Using Android RepaintBoundary screenshot');
        RenderRepaintBoundary? boundary = _webViewKey.currentContext
            ?.findRenderObject() as RenderRepaintBoundary?;

        if (boundary == null) {
          _showMessage('فشل التقاط الصورة - الرجاء المحاولة مرة أخرى');
          if (mounted) {
            setState(() {
              isLoading = false;
            });
          }
          return;
        }

        // Capture the image
        ui.Image image = await boundary.toImage(pixelRatio: 3.0);
        ByteData? byteData =
            await image.toByteData(format: ui.ImageByteFormat.png);

        if (byteData == null) {
          _showMessage('فشل التقاط الصورة');
          if (mounted) {
            setState(() {
              isLoading = false;
            });
          }
          return;
        }

        screenshot = byteData.buffer.asUint8List();
      }

      debugPrint('✅ Screenshot captured: ${screenshot.length} bytes');

      // Save to temporary file first
      final tempDir = await getTemporaryDirectory();
      final fileName =
          'salary_slip_${DateTime.now().millisecondsSinceEpoch}.png';
      final tempFile = File('${tempDir.path}/$fileName');
      await tempFile.writeAsBytes(screenshot);

      // Save to gallery using gal package
      try {
        await Gal.putImage(tempFile.path, album: 'قسائم الرواتب');
        debugPrint('💾 Image saved to gallery successfully');

        if (mounted) {
          setState(() {
            isLoading = false;
          });
        }

        _showMessage('تم حفظ قسيمة الراتب في المعرض');

        // Clean up temp file
        await tempFile.delete();
      } catch (e) {
        debugPrint('❌ Error saving to gallery: $e');

        if (mounted) {
          setState(() {
            isLoading = false;
          });
        }
        _showMessage('فشل حفظ الصورة في المعرض');
      }
    } catch (e) {
      debugPrint('❌ Error saving screenshot: $e');

      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
      _showMessage('حدث خطأ أثناء حفظ الصورة: ${e.toString()}');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.cairo(fontSize: 16),
          textAlign: TextAlign.center,
        ),
        backgroundColor: const Color(0xFF00BFA5),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<bool> _onWillPop() async {
    if (canGoBack && controller != null) {
      debugPrint('⬅️ Going back in WebView history');
      controller!.goBack();
      return false;
    }

    // Show exit dialog
    return await _showExitDialog() ?? false;
  }

  Future<bool?> _showExitDialog() {
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
          title: Text(
            'الشركة العامة لتعبئة وخدمات الغاز',
            style: GoogleFonts.cairo(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        body: Stack(
          children: [
            // WebView wrapped with RepaintBoundary for screenshot
            if (controller != null && !hasError)
              RepaintBoundary(
                key: _webViewKey,
                child: WebViewWidget(controller: controller!),
              ),

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
          ],
        ),
        // Show zoom controls and save button when viewing payslip
        floatingActionButton: currentUrl.contains('/payslips/view') && !hasError
            ? Row(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Zoom Out button
                  FloatingActionButton(
                    heroTag: 'zoom_out',
                    mini: true,
                    onPressed: _zoomOut,
                    backgroundColor: Colors.white,
                    elevation: 4,
                    child: const Icon(Icons.zoom_out,
                        color: Color(0xFF00BFA5), size: 20),
                  ),
                  const SizedBox(width: 10),

                  // Zoom In button
                  FloatingActionButton(
                    heroTag: 'zoom_in',
                    mini: true,
                    onPressed: _zoomIn,
                    backgroundColor: Colors.white,
                    elevation: 4,
                    child: const Icon(Icons.zoom_in,
                        color: Color(0xFF00BFA5), size: 20),
                  ),
                  const SizedBox(width: 16),

                  // Save button
                  FloatingActionButton.extended(
                    heroTag: 'save_image',
                    onPressed: _savePageAsImage,
                    backgroundColor: const Color(0xFF00BFA5),
                    icon: const Icon(Icons.save_alt, color: Colors.white),
                    label: Text(
                      'حفظ كصورة',
                      style: GoogleFonts.cairo(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    elevation: 6,
                  ),
                ],
              )
            : null,
      ),
    );
  }
}
