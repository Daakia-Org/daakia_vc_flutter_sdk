import 'package:daakia_vc_flutter_sdk/daakia_vc_flutter_sdk.dart';
import 'package:daakia_vc_flutter_sdk/model/daakia_meeting_configuration.dart';
import 'package:daakia_vc_flutter_sdk/utils/utils.dart';
import 'package:example/screen/configuration_screen.dart';
import 'package:example/utils/animate_logo.dart';
import 'package:example/utils/theme_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Daakia VC Demo',
      home: const DataEntryScreen(), // << this is enough
      // 👇 ONLY for edge-to-edge
      builder: (context, child) {
        return SafeArea(
          top: false, // 👈 allow drawing behind status bar
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}

class DataEntryScreen extends StatefulWidget {
  const DataEntryScreen({super.key});

  @override
  State<StatefulWidget> createState() => _DataEntryState();
}

class _DataEntryState extends State<DataEntryScreen> {
  var licenseKey = "";
  var meetingUID = "";
  var isHost = false;
  DaakiaMeetingConfiguration? customConfig;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData().copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: ThemeColor.primaryThemeColor,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF121212),
        inputDecorationTheme: const InputDecorationTheme(
          labelStyle: TextStyle(color: Colors.white70),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.white30),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: ThemeColor.primaryThemeColor),
          ),
        ),
        textTheme: const TextTheme(
          bodyMedium: TextStyle(color: Colors.white),
        ),
      ),
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(top: 40, bottom: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const AnimatedLogo(),
                        const SizedBox(height: 25),
                        const Text(
                          'Daakia VC Flutter SDK',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: ThemeColor.primaryThemeColor,
                          ),
                        ),
                        const SizedBox(height: 40),
                        TextFormField(
                          decoration:
                              const InputDecoration(labelText: 'License Key*'),
                          onChanged: (value) =>
                              setState(() => licenseKey = value),
                        ),
                        const SizedBox(height: 20),
                        TextFormField(
                          decoration:
                              const InputDecoration(labelText: 'Meeting UID*'),
                          onChanged: (value) =>
                              setState(() => meetingUID = value),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            const Text("Join as Host",
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white70)),
                            const Spacer(),
                            Switch(
                              value: isHost,
                              activeColor: ThemeColor.primaryThemeColor,
                              onChanged: (val) => setState(() => isHost = val),
                            ),
                          ],
                        ),
                        const SizedBox(height: 30),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              final result = await Navigator.push<
                                  DaakiaMeetingConfiguration>(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ConfigurationScreen(initialConfig: customConfig),
                                ),
                              );
                              if (result != null) {
                                setState(() {
                                  customConfig = result;
                                });
                              }
                            },
                            icon: const Icon(Icons.tune),
                            label: const Text("Custom Configuration"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: ThemeColor.primaryThemeColor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              textStyle: const TextStyle(fontSize: 16),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        bottomNavigationBar: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          child: ElevatedButton.icon(
            onPressed: () async {
              if (licenseKey.isEmpty || meetingUID.isEmpty) {
                Utils.showSnackBar(context,
                    message: "License Key and Meeting UID are required!");
                return;
              }

              await Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => DaakiaVideoConferenceWidget(
                    meetingId: meetingUID,
                    secretKey: licenseKey,
                    isHost: isHost,
                    configuration: customConfig,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.play_circle_fill),
            label: const Text("Start Video Conference"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.greenAccent[400],
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 16),
              textStyle: const TextStyle(fontSize: 18),
            ),
          ),
        ),
      ),
    );
  }
}
