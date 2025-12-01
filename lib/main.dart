import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]).then((_) {
    runApp(const SalaryInfoApp());
  });
}

class SalaryInfoApp extends StatelessWidget {
  const SalaryInfoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SalaryInfo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF2196F3),
          foregroundColor: Colors.white,
          centerTitle: true,
        ),
      ),
      home: const SalaryInfoWebView(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class SalaryInfoWebView extends StatefulWidget {
  const SalaryInfoWebView({super.key});

  @override
  State<SalaryInfoWebView> createState() => _SalaryInfoWebViewState();
}

class _SalaryInfoWebViewState extends State<SalaryInfoWebView> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _hasError = false;
  double _progress = 0;
  final String _appUrl = 'http://109.224.38.44:5000/login';

  @override
  void initState() {
    super.initState();
    _initializeWebViewController();
  }

  void _initializeWebViewController() {
    final WebViewController controller = WebViewController();

    controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            setState(() {
              _progress = progress / 100.0;
              if (progress == 100) {
                _isLoading = false;
              }
            });
          },
          onPageStarted: (String url) {
            setState(() {
              _isLoading = true;
              _hasError = false;
              _progress = 0;
            });
          },
          onPageFinished: (String url) {
            setState(() {
              _isLoading = false;
              _progress = 1.0;
            });
          },
          onWebResourceError: (WebResourceError error) {
            setState(() {
              _isLoading = false;
              _hasError = true;
            });
          },
        ),
      )
      ..loadRequest(Uri.parse(_appUrl));

    _controller = controller;
  }

  Future<void> _reloadWebView() async {
    await _controller.reload();
    setState(() {
      _hasError = false;
    });
  }

  Future<void> _goBack() async {
    if (await _controller.canGoBack()) {
      await _controller.goBack();
    }
  }

  Future<void> _goForward() async {
    if (await _controller.canGoForward()) {
      await _controller.goForward();
    }
  }

  Future<void> _goHome() async {
    await _controller.loadRequest(Uri.parse(_appUrl));
  }

  Future<void> _shareUrl() async {
    final url = await _controller.currentUrl();
    if (url != null) {
      await Share.share(
        'Check out SalaryInfo: $url',
        subject: 'SalaryInfo App',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SalaryInfo'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _reloadWebView,
            tooltip: 'Refresh',
          ),
          IconButton(
            icon: const Icon(Icons.home),
            onPressed: _goHome,
            tooltip: 'Home',
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(
                value: _progress,
                backgroundColor: Colors.grey[200],
                valueColor: AlwaysStoppedAnimation<Color>(
                  Theme.of(context).primaryColor,
                ),
              ),
            ),
          if (_hasError)
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  const Text(
                    'Unable to load SalaryInfo',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text('Please check your internet connection'),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _reloadWebView,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
        ],
      ),
      bottomNavigationBar: BottomAppBar(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _goBack,
                tooltip: 'Back',
              ),
              IconButton(
                icon: const Icon(Icons.arrow_forward),
                onPressed: _goForward,
                tooltip: 'Forward',
              ),
              IconButton(
                icon: const Icon(Icons.share),
                onPressed: _shareUrl,
                tooltip: 'Share',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
