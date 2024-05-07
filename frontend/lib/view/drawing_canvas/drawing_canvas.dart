import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart' hide Image;
import 'package:flutter_drawing_board/view/drawing_canvas/models/drawing_mode.dart';
import 'package:flutter_drawing_board/view/drawing_canvas/models/sketch.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:http/http.dart' as http;

class DrawingCanvas extends HookWidget {
  final double height;
  final double width;
  final ValueNotifier<Color> selectedColor;
  final ValueNotifier<double> strokeSize;
  final ValueNotifier<Image?> backgroundImage;
  final ValueNotifier<double> eraserSize;
  final ValueNotifier<DrawingMode> drawingMode;
  final AnimationController sideBarController;
  final ValueNotifier<Sketch?> currentSketch;
  final ValueNotifier<List<Sketch>> allSketches;
  final GlobalKey canvasGlobalKey;
  final ValueNotifier<int> polygonSides;
  final ValueNotifier<bool> filled;
  late Timer _timer;

  DrawingCanvas({
    Key? key,
    required this.height,
    required this.width,
    required this.selectedColor,
    required this.strokeSize,
    required this.eraserSize,
    required this.drawingMode,
    required this.sideBarController,
    required this.currentSketch,
    required this.allSketches,
    required this.canvasGlobalKey,
    required this.filled,
    required this.polygonSides,
    required this.backgroundImage,
  }) : super(key: key);

  // IO.Socket socket = IO.io('ws://localhost:3010',
  // IO.OptionBuilder().setTransports(['websocket']).disableAutoConnect().build(),)..connect();
  // final currentSketchStream = StreamController<String>();
  // final allSketchStream = StreamController<String>();
  final Uri url = Uri.parse('http://localhost:6003/transact');
  final Uri _transactionsUri = Uri.parse('http://localhost:6003/transaction');

  // @override
  // void dispose() {
  //   _timer.cancel(); // Cancel the periodic timer
  //   super.dispose();
  // }

  @override
  Widget build(BuildContext context) {
    final _timer = useEffect(() {
      final timer = Timer.periodic(
        const Duration(seconds: 1),
        (timer) => _fetchTransactions(),
      );
      return () => timer.cancel(); // Clean up the timer when the widget is disposed
    }, const [],);
    // socket.onConnect((_) {
    //   print('connect');}
    // );
    // socket.on('currentSketch',(data){
    //   Map<String, dynamic> sketchMap = jsonDecode(data);
    //   Sketch receivedSketch = Sketch.fromJson(sketchMap);
    //   allSketches.value = [...allSketches.value, receivedSketch];
    // });
    // socket.on('allSketches',(data) => allSketchStream.sink.add(data));
    // // socket.onError((data) {
    // //   print(data);
    // // });
    return MouseRegion(
      cursor: SystemMouseCursors.precise,
      child: Stack(
        children: [
          buildAllSketches(context),
          buildCurrentPath(context),
        ],
      ),
    );
  }


  void onPointerDown(PointerDownEvent details, BuildContext context) {
    final box = context.findRenderObject() as RenderBox;
    final offset = box.globalToLocal(details.position);
    currentSketch.value = Sketch.fromDrawingMode(
      Sketch(
        points: [offset],
        size: drawingMode.value == DrawingMode.eraser
            ? eraserSize.value
            : strokeSize.value,
        color: drawingMode.value == DrawingMode.eraser
            ? Colors.white
            : selectedColor.value,
        sides: polygonSides.value,
      ),
      drawingMode.value,
      filled.value,
    );
  }

  void onPointerMove(PointerMoveEvent details, BuildContext context) {
    final box = context.findRenderObject() as RenderBox;
    final offset = box.globalToLocal(details.position);

    // Check if the new point is within the canvas bounds
    if (offset.dx >= 0 &&
        offset.dx <= width &&
        offset.dy >= 0 &&
        offset.dy <= height) {
      final points = List<Offset>.from(currentSketch.value?.points ?? [])
        ..add(offset);

      currentSketch.value = Sketch.fromDrawingMode(
        Sketch(
          points: points,
          size: drawingMode.value == DrawingMode.eraser
              ? eraserSize.value
              : strokeSize.value,
          color: drawingMode.value == DrawingMode.eraser
              ? Colors.white
              : selectedColor.value,
          sides: polygonSides.value,
        ),
        drawingMode.value,
        filled.value,
      );
    }
    // socket.emit('currentSketch', jsonEncode(currentSketch.value?.toJson()));
  }

  Future<void> onPointerUp(PointerUpEvent details) async {
    allSketches.value = List<Sketch>.from(allSketches.value)
      ..add(currentSketch.value!);
    // socket.emit('currentSketch', jsonEncode(currentSketch.value?.toJson()));
    Map data = {'data': {"current" : currentSketch.value}};
    var body1 = jsonEncode(data);
    // print('Response body: ${body1}');
    var response = await http.post(url,headers: {'Content-Type': 'application/json'}, body: body1);
    // print('Response body: ${response.body}');
    currentSketch.value = Sketch.fromDrawingMode(
      Sketch(
        points: [],
        size: drawingMode.value == DrawingMode.eraser
            ? eraserSize.value
            : strokeSize.value,
        color: drawingMode.value == DrawingMode.eraser
            ? Colors.white
            : selectedColor.value,
        sides: polygonSides.value,
      ),
      drawingMode.value,
      filled.value,
    );
  }

int _lastFetchedTransactionsCount = 0;

Future<void> _fetchTransactions() async {
  try {
    final response = await http.get(_transactionsUri);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as List<dynamic>;
      print('Decoded data: $data');

      final remoteSketches = <Sketch>[];
      final currentTransactionsCount = data.length;

      // Fetch only the new transactions
      for (int i = _lastFetchedTransactionsCount; i < currentTransactionsCount; i++) {
        final transaction = data[i];
        print("transaction ${transaction}");
        if (transaction is Map<String, dynamic>) {
          final inputData = transaction;
          if (inputData is Map<String, dynamic>) {
            final currentData = inputData['data'];
            if (currentData is Map<String, dynamic>) {
              final sketchData = currentData['current'];
              if (sketchData is Map<String, dynamic>) {
                print("sketch data ${sketchData}");
                final sketch = Sketch.fromJson(sketchData);
                print("sketch ${sketch}");
                remoteSketches.add(sketch);
                print(remoteSketches);
              } else if (sketchData == null) {
                print('Skipping transaction with no current data');
              } else {
                print('Unexpected data type for sketch data: ${sketchData.runtimeType}');
              }
            } else {
              print('Unexpected data type for current data: ${currentData.runtimeType}');
            }
          } else {
            print('Unexpected data type for input data: ${inputData.runtimeType}');
          }
        } else {
          print('Unexpected data type for transaction: ${transaction.runtimeType}');
        }
      }

      print('Remote sketches: $remoteSketches');
      allSketches.value = [...allSketches.value, ...remoteSketches];
      _lastFetchedTransactionsCount = currentTransactionsCount;
    } else {
      print('Failed to fetch transactions: ${response.body}');
    }
  } catch (e) {
    print('Error fetching transactions: $e');
  }
}

Widget buildAllSketches(BuildContext context) {
    return SizedBox(
      height: height,
      width: width,
      child: ValueListenableBuilder<List<Sketch>>(
        valueListenable: allSketches,
        builder: (context, sketches, _) {
          return RepaintBoundary(
            child: Container(
              height: height,
              width: width,
              color: Colors.white,
              child: CustomPaint(
                size: Size(width, height),
                painter: SketchPainter(
                  sketches: sketches,
                  backgroundImage: backgroundImage.value,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
// Widget buildAllSketches(BuildContext context) {
//   return SizedBox(
//     height: height,
//     width: width,
//     child: Stack(
//       children: [
//         // Local sketches
//         ValueListenableBuilder<List<Sketch>>(
//           valueListenable: allSketches,
//           builder: (context, localSketches, _) {
//             return RepaintBoundary(
//               child: Container(
//                 height: height,
//                 width: width,
//                 color: Colors.white,
//                 child: CustomPaint(
//                   size: Size(width, height),
//                   painter: SketchPainter(
//                     sketches: localSketches,
//                     backgroundImage: backgroundImage.value,
//                   ),
//                 ),
//               ),
//             );
//           },
//         ),
//         // Remote sketches
//         StreamBuilder<String>(
//           stream: allSketchStream.stream,
//           builder: (context, snapshot) {
//             List<Sketch> remoteSketches = [];
//             if (snapshot.hasData) {
//               List<dynamic> sketchesMap = jsonDecode(snapshot.data!);
//               remoteSketches = sketchesMap
//                   .cast<Map<String, dynamic>>()
//                   .map((json) => Sketch.fromJson(json))
//                   .toList();
//             }
//             return RepaintBoundary(
//               child: Container(
//                 height: height,
//                 width: width,
//                 color: Colors.transparent,
//                 child: CustomPaint(
//                   size: Size(width, height),
//                   painter: SketchPainter(
//                     sketches: remoteSketches,
//                   ),
//                 ),
//               ),
//             );
//           },
//         ),
//       ],
//     ),
//   );
// }
// Widget buildAllSketches(BuildContext context) {
//   return SizedBox(
//     height: height,
//     width: width,
//     child: ValueListenableBuilder<List<Sketch>>(
//       valueListenable: allSketches,
//       builder: (context, localSketches, _) {
//         return StreamBuilder<String>(
//           stream: allSketchStream.stream,
//           builder: (context, snapshot) {
//             List<Sketch> sketches = [...localSketches];

//             if (snapshot.hasData) {
//               List<dynamic> sketchesMap = jsonDecode(snapshot.data!);
//               List<Sketch> receivedSketches =
//                   sketchesMap.cast<Map<String, dynamic>>().map((json) => Sketch.fromJson(json)).toList();
//               sketches = [...sketches, ...receivedSketches];
//             }

//             return RepaintBoundary(
//               key: canvasGlobalKey,
//               child: Container(
//                 height: height,
//                 width: width,
//                 color: Colors.white,
//                 child: CustomPaint(
//                   size: const Size(1000, 700),
//                   painter: SketchPainter(
//                     sketches: sketches,
//                     backgroundImage: backgroundImage.value,
//                   ),
//                 ),
//               ),
//             );
//           },
//         );
//       },
//     ),
//   );
// }
  // return StreamBuilder(
  //   stream: allSketchStream.stream,
  //   builder: (context, snapshot){
  // List<Sketch> sketches = List.empty(growable: true);
  // List<Sketch> sketchesMap = List.empty(growable: true);
  // if (snapshot.hasData) {
  //   sketchesMap = jsonDecode(snapshot.data!);
  //   sketches = sketchesMap.map((json) => Sketch.fromJson(json as Map<String,dynamic>)).toList();

  // }
  //     return RepaintBoundary(
  //       child: SizedBox(
  //         height: height,
  //         width: width,
  //         child: CustomPaint(
  //           painter: SketchPainter(sketches: sketches),
  //         )
  //         ),
  //     );
  //   });
  // }

  Widget buildCurrentPath(BuildContext context) {
    // return StreamBuilder(
    //   stream: currentSketchStream.stream,
    //   builder: (context, snapshot) {
    //     Sketch? sketch;
    //     Map<String, dynamic>? sketchMap;
    //     if (snapshot.hasData) {
    //       sketchMap = jsonDecode(snapshot.data!);

    //     }
    //     if (sketchMap!= null) {
    //       sketch = Sketch.fromJson(sketchMap);
    //     }
    return Listener(
      onPointerDown: (details) => onPointerDown(details, context),
      onPointerMove: (details) => onPointerMove(details, context),
      onPointerUp: onPointerUp,
      child: ValueListenableBuilder(
        valueListenable: currentSketch,
        builder: (context, sketch, child) {
          return RepaintBoundary(
            child: SizedBox(
              height: height,
              width: width,
              child: CustomPaint(
                painter: SketchPainter(
                  sketches: sketch == null ? [] : [sketch],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class SketchPainter extends CustomPainter {
  final List<Sketch> sketches;
  final Image? backgroundImage;

  const SketchPainter({
    Key? key,
    this.backgroundImage,
    required this.sketches,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (backgroundImage != null) {
      canvas.drawImageRect(
        backgroundImage!,
        Rect.fromLTWH(
          0,
          0,
          backgroundImage!.width.toDouble(),
          backgroundImage!.height.toDouble(),
        ),
        Rect.fromLTWH(0, 0, size.width, size.height),
        Paint(),
      );
    }
    for (Sketch sketch in sketches) {
      final points = sketch.points;
      if (points.isEmpty) return;

      final path = Path();

      path.moveTo(points[0].dx, points[0].dy);
      if (points.length < 2) {
        // If the path only has one line, draw a dot.
        path.addOval(
          Rect.fromCircle(
            center: Offset(points[0].dx, points[0].dy),
            radius: 1,
          ),
        );
      }

      for (int i = 1; i < points.length - 1; ++i) {
        final p0 = points[i];
        final p1 = points[i + 1];
        path.quadraticBezierTo(
          p0.dx,
          p0.dy,
          (p0.dx + p1.dx) / 2,
          (p0.dy + p1.dy) / 2,
        );
      }

      Paint paint = Paint()
        ..color = sketch.color
        ..strokeCap = StrokeCap.round;

      if (!sketch.filled) {
        paint.style = PaintingStyle.stroke;
        paint.strokeWidth = sketch.size;
      }

      // define first and last points for convenience
      Offset firstPoint = sketch.points.first;
      Offset lastPoint = sketch.points.last;

      // create rect to use rectangle and circle
      Rect rect = Rect.fromPoints(firstPoint, lastPoint);

      // Calculate center point from the first and last points
      Offset centerPoint = (firstPoint / 2) + (lastPoint / 2);

      // Calculate path's radius from the first and last points
      double radius = (firstPoint - lastPoint).distance / 2;
      canvas.clipRect(Rect.fromLTWH(0, 0, size.width, size.height));
      if (sketch.type == SketchType.scribble) {
        canvas.drawPath(path, paint);
      } else if (sketch.type == SketchType.square) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(5)),
          paint,
        );
      } else if (sketch.type == SketchType.line) {
        canvas.drawLine(firstPoint, lastPoint, paint);
      } else if (sketch.type == SketchType.circle) {
        canvas.drawOval(rect, paint);
        // Uncomment this line if you need a PERFECT CIRCLE
        // canvas.drawCircle(centerPoint, radius , paint);
      } else if (sketch.type == SketchType.polygon) {
        Path polygonPath = Path();
        int sides = sketch.sides;
        var angle = (math.pi * 2) / sides;

        double radian = 0.0;

        Offset startPoint =
            Offset(radius * math.cos(radian), radius * math.sin(radian));

        polygonPath.moveTo(
          startPoint.dx + centerPoint.dx,
          startPoint.dy + centerPoint.dy,
        );
        for (int i = 1; i <= sides; i++) {
          double x = radius * math.cos(radian + angle * i) + centerPoint.dx;
          double y = radius * math.sin(radian + angle * i) + centerPoint.dy;
          polygonPath.lineTo(x, y);
        }
        polygonPath.close();
        canvas.drawPath(polygonPath, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant SketchPainter oldDelegate) {
    return oldDelegate.sketches != sketches;
  }
}
