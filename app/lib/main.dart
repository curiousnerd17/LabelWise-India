import 'package:flutter/material.dart';

/// Launches the LabelWise India application.
void main() {
  runApp(const LabelWiseApp());
}

/// Root widget for the LabelWise India application.
class LabelWiseApp extends StatelessWidget {
  /// Creates the root application widget.
  const LabelWiseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'LabelWise India',
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Text('LabelWise India MVP'),
        ),
      ),
    );
  }
}