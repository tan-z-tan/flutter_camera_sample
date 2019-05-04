import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:firebase_ml_vision/firebase_ml_vision.dart';
import 'dart:async';


void logError(String code, String message) =>
    print('Error: $code\nError Message: $message');


CameraController controller;

Future<Null> main() async {
  try {
    final cameras = await availableCameras();
    final mainCamera = cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.back, orElse: () => null);
    controller = new CameraController(mainCamera, ResolutionPreset.high);

  } on CameraException catch (e) {
    logError(e.code, e.description);
  }

  runApp(new MyApp());
}


class CameraExampleHome extends StatefulWidget {
  @override
  _CameraExampleHomeState createState() {
    return _CameraExampleHomeState();
  }
}

IconData getCameraLensIcon(CameraLensDirection direction) {
  switch (direction) {
    case CameraLensDirection.back:
      return Icons.camera_rear;
    case CameraLensDirection.front:
      return Icons.camera_front;
    case CameraLensDirection.external:
      return Icons.camera;
  }
  throw ArgumentError("Unknown lens direction");
}

class _CameraExampleHomeState extends State<CameraExampleHome>
  with WidgetsBindingObserver {

//  CameraController controller;
  String _detectedText = null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    onNewCameraSelected(controller.description);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      controller?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      if (controller != null) {
        onNewCameraSelected(controller.description);
      }
    }
  }

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: const Text("Camera sample"),
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: _cameraPreviewWidget()
          ),
          _captureControlRowWidget(),
          Padding(
            padding: const EdgeInsets.all(5.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: <Widget>[
                _thumbnailWidget(),
              ],
            )
          )
        ],
      )
    );
  }

  /// Display the preview from the camera (or a message if the preview is not available).
  Widget _cameraPreviewWidget() {
    if (controller == null || !controller.value.isInitialized) {
      return const Text(
        'Tap a camera',
        style: TextStyle(
          color: Colors.white,
          fontSize: 24.0,
          fontWeight: FontWeight.w900,
        ),
      );
    } else {
      return AspectRatio(
        aspectRatio: controller.value.aspectRatio,
        child: CameraPreview(controller),
      );
    }
  }

  /// Display the thumbnail of the captured image or video.
  Widget _thumbnailWidget() {
    return Expanded(
      child: Align(
        alignment: Alignment.center,
        child: Text(
          _detectedText != null && _detectedText.length > 0
              ? "Detected😃:" + "\n" + _detectedText
              : "Text not found🤪"
          ,
          style: TextStyle(fontStyle: FontStyle.italic,fontSize: 34),
        ),
      ),
    );
  }

  /// Display the control bar with buttons to take pictures and record videos.
  Widget _captureControlRowWidget() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      mainAxisSize: MainAxisSize.max,
      children: <Widget>[
        IconButton(
          icon: const Icon(Icons.camera_alt),
          color: Colors.blue,
          onPressed: controller != null &&
              controller.value.isInitialized &&
              !controller.value.isRecordingVideo
              ? onTakePictureButtonPressed
              : null,
        ),
      ],
    );
  }

  String timestamp() => DateTime.now().millisecondsSinceEpoch.toString();

  void showInSnackBar(String message) {
    _scaffoldKey.currentState.showSnackBar(SnackBar(content: Text(message)));
  }

  void onNewCameraSelected(CameraDescription cameraDescription) async {
    if (controller != null) {
      await controller.dispose();
    }
    controller = CameraController(cameraDescription, ResolutionPreset.high);

    // If the controller is updated then update the UI.
    controller.addListener(() {
      if (mounted) setState(() {});
      if (controller.value.hasError) {
        showInSnackBar('Camera error ${controller.value.errorDescription}');
      }
    });

    try {
      await controller.initialize();
    } on CameraException catch (e) {
      _showCameraException(e);
    }

    if (mounted) {
      setState(() {});
    }
  }

  void onTakePictureButtonPressed() {
    takePicture();
  }

  void takePicture() async {
    if (!controller.value.isInitialized) {
      showInSnackBar('Error: select a camera first.');
      return null;
    }

    if (controller.value.isTakingPicture) {
      // A capture is already pending, do nothing.
      return null;
    }

    try {
      await controller.startImageStream((CameraImage img) {
        controller.stopImageStream();

        scanTextFromImage(img).then((dynamic detected) {
          setState(() {
            _detectedText = detected;
          });
        });
      });
    } on CameraException catch (e) {
      _showCameraException(e);
    }
  }

  Future<String> scanTextFromImage(CameraImage img) async {
    final FirebaseVisionImageMetadata metadata = FirebaseVisionImageMetadata(
        size: Size(img.width.toDouble(), img.height.toDouble()),
        rawFormat: img.format.raw,
        planeData: img.planes.map((plane) => FirebaseVisionImagePlaneMetadata(
          bytesPerRow: plane.bytesPerRow,
          height: plane.height,
          width: plane.width,
          ),
        ).toList(),
        rotation: ImageRotation.rotation90,
    );

    final FirebaseVisionImage visionImage = FirebaseVisionImage.fromBytes(img.planes[0].bytes, metadata);
    final TextRecognizer textRecognizer = FirebaseVision.instance.textRecognizer();
    final VisionText visionText = await textRecognizer.processImage(visionImage);

    if (visionText != null) {
      var detectedWords = <String>[];
      print("--------------------visionText:${visionText.text}");
      for (TextBlock block in visionText.blocks) {
        print("--------------------visionText:${visionText.text}");
        print(block.text);
        print(block.boundingBox);
        print(block.cornerPoints);
        print(block.confidence);

        for (TextLine line in block.lines) {
          print(line.text);
          for (TextElement element in line.elements) {
            print(element.text);
            detectedWords.add("'" + element.text + "'");
          }
        }
      }
      return detectedWords.join(" ");
    }
    return null;
  }

  void _showCameraException(CameraException e) {
    logError(e.code, e.description);
    showInSnackBar('Error: ${e.code}\n${e.description}');
  }
}

class MyApp extends StatelessWidget {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Camera Sample App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: CameraApp(),
    );
  }
}

class CameraApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: CameraExampleHome(),
    );
  }
}