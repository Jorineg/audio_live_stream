import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'streaming_control_screen.dart';
import 'settings_explanation_screen.dart';

class IntroductionScreen extends StatefulWidget {
  const IntroductionScreen({super.key});

  @override
  State<IntroductionScreen> createState() => _IntroductionScreenState();
}

class _IntroductionScreenState extends State<IntroductionScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<Map<String, dynamic>> _pages = [
    {
      'image': Image.asset('assets/introduction/step1.png'),
      'title': 'Get Connected',
      'text':
          'Join a Wi-Fi network or activate your own hotspot to get started.',
    },
    {
      'image': Image.asset('assets/introduction/step2.png'),
      'title': 'Invite Listeners',
      'text':
          'Ask others to join the same Wi-Fi or hotspot to prepare for streaming.',
    },
    {
      'image': Image.asset('assets/introduction/step3.png'),
      'title': 'Share the Link',
      'text':
          'Share the QR code with your listeners so they can open your streaming site.',
    },
    {
      'image': Image.asset('assets/introduction/step4.png'),
      'title': 'Start Streaming',
      'text': 'Tap the microphone icon to go live with your audio stream.',
    },
    {
      'image': Image.asset('assets/introduction/step5.png'),
      'title': 'Optimize Settings',
      'text':
          'Experiencing lag? Try reducing the sample rate or enabling compression.',
      'showExplainButton': true,
    },
    {
      'image': null,
      'title': 'Privacy Policy',
      'text': '''WiFi Audio Stream respects user privacy. This app does not collect, store, or share any personal data or information. We do not use servers, require user accounts, or log any interactions within the app.

The app only requests access to your device's microphone to enable audio streaming, which is the app's main function. This microphone data is not saved, processed, or shared beyond the local streaming session.

By using this app, you agree to this privacy policy. If you have questions, please contact us at jorineggers@gmail.com.''',
    },
  ];

  int _numPages = 0;

  @override
  void initState() {
    _numPages = _pages.length;
    super.initState();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int page) {
    setState(() {
      _currentPage = page;
    });
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (Navigator.canPop(context)) {
          return true; // Allow popping if possible
        } else {
          // Prevent popping the initial route to avoid black screen
          return false;
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: Navigator.canPop(context)
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.of(context).pop(),
                )
              : null,
          title: const Text('How it works'),
        ),
        body: Stack(
          children: [
            PageView(
              controller: _pageController,
              onPageChanged: _onPageChanged,
              children: List.generate(_numPages, (index) {
                return Column(
                  children: [
                    if (_pages[index]['image'] != null)
                      SizedBox(
                        width: MediaQuery.of(context).size.width * 0.85,
                        child: _pages[index]['image']!,
                      ),
                    const SizedBox(height: 16),
                    Text(
                      _pages[index]['title'],
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32.0),
                      child: Text(
                        _pages[index]['text'],
                        textAlign: index == _numPages - 1 ? TextAlign.left : TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ),
                    if (_pages[index]['showExplainButton'] == true) ...[
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.help_outline),
                        label: const Text('Learn More'),
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => const SettingsExplanationScreen(),
                            ),
                          );
                        },
                      ),
                    ],
                  ],
                );
              }),
            ),
            Positioned(
              bottom: 80.0,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(_numPages, (index) {
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _currentPage == index
                              ? Theme.of(context).primaryColor
                              : Colors.grey,
                        ),
                      );
                    }),
                  ),
                ],
              ),
            ),
            if (_currentPage == _numPages - 1)
              Positioned(
                bottom: 20.0,
                left: 0,
                right: 0,
                child: Center(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.check),
                    label: const Text('Start'),
                    onPressed: () async {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setBool('intro_shown', true);
                      if (Navigator.canPop(context)) {
                        Navigator.of(context).pop();
                      } else {
                        if (context.mounted) {
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute(
                              builder: (context) => const StreamingControl(),
                            ),
                          );
                        }
                      }
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
