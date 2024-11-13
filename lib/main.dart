import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/streaming_control_screen.dart';
import 'screens/introduction_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final bool introShown = prefs.getBool('intro_shown') ?? false;

  runApp(MainApp(showIntroFirst: !introShown));
}

class MainApp extends StatelessWidget {
  final bool showIntroFirst;

  const MainApp({super.key, this.showIntroFirst = false});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WiFi Audio Stream',
      debugShowCheckedModeBanner: false,
      home: showIntroFirst
          ? IntroductionScreen() // Show intro directly
          : const StreamingControl(), // Show main screen directly
    );
  }
}
