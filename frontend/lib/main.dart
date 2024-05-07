import 'package:flutter/material.dart';
import 'package:flutter_drawing_board/view/drawing_page.dart';

void main() {
  runApp(const MyApp());
}

const Color kCanvasColor = Color.fromARGB(104, 226, 225, 225);

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Let\'s Draw',
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: false),
      debugShowCheckedModeBanner: false,
      home: const DrawingPage(),
    );
  }
}
