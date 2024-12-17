import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: PermissionScreen(),
    );
  }
}

class PermissionScreen extends StatefulWidget {
  @override
  _PermissionScreenState createState() => _PermissionScreenState();
}

class _PermissionScreenState extends State<PermissionScreen> {
  bool _isPermissionGranted = false;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    PermissionStatus cameraStatus = await Permission.camera.request();
    PermissionStatus micStatus = await Permission.microphone.request();

    if (cameraStatus.isGranted && micStatus.isGranted) {
      setState(() {
        _isPermissionGranted = true;
      });
    } else {
      setState(() {
        _isPermissionGranted = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _isPermissionGranted
          ? CameraScreen()
          : Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.warning, color: Colors.red, size: 50),
            SizedBox(height: 20),
            Text(
              "Permissões de Câmera e Microfone são necessárias.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18),
            ),
          ],
        ),
      ),
    );
  }
}

class CameraScreen extends StatefulWidget {
  @override
  _CameraScreenState createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  late CameraController _cameraController;
  late Future<void> _initializeControllerFuture;
  bool _isCameraInitialized = false;
  Timer? _timer;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {

    if (await _requestPermissions()) {
      final cameras = await availableCameras();
      final firstCamera = cameras.first;

      _cameraController = CameraController(firstCamera, ResolutionPreset.medium);
      _initializeControllerFuture = _cameraController.initialize();
      await _initializeControllerFuture;

      await _cameraController.setFlashMode(FlashMode.off);
      _startPeriodicImageSend();
      setState(() {
        _isCameraInitialized = true;
      });
    } else {
      print("Permissões não concedidas.");
    }
  }

  void _startPeriodicImageSend() {

    _timer = Timer.periodic(Duration(milliseconds: 35), (timer) {
      if (!_isSending) {
        _captureAndSendBytes();
      }
    });
  }

  Future<void> _captureAndSendBytes() async {
    try {
      await _initializeControllerFuture;

      final image = await _cameraController.takePicture();

      Uint8List imageBytes = await image.readAsBytes();

      //final originalImage = img.decodeImage(imageBytes);
      //final compressedImage = img.encodeJpg(originalImage!, quality: 70);


      await _sendImageBytesToServer(imageBytes);

      print("imagem enviada com sucesso!");
    } catch (e) {
      print(e);
    }
  }

  Future<void> _sendImageBytesToServer(Uint8List imageBytes) async {

    final url = Uri.parse('http://192.168.1.106:5000/upload_video'); // Substitua pela URL

    var request = http.MultipartRequest('POST', url);
    request.files.add(http.MultipartFile.fromBytes('frame', imageBytes, filename: 'frame.jpg'));

    var response = await request.send();

    if (response.statusCode == 200) {
      print('Imagem enviada com sucesso!');
    } else {
      print('Erro ao enviar a imagem. Código: ${response.statusCode}');
    }
  }

  Future<bool> _requestPermissions() async {
    PermissionStatus cameraStatus = await Permission.camera.request();
    PermissionStatus micStatus = await Permission.microphone.request();

    return cameraStatus.isGranted && micStatus.isGranted;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _cameraController.dispose();
    super.dispose();
  }


  String selectedLanguage = 'Libras → Português';

  void _showLanguageSelector() {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return Container(
          color: Colors.yellow,
          padding: EdgeInsets.all(16),
          height: 200,
          child: Column(
            children: [
              Text("Selecione o idioma", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ListTile(
                title: Text("Libras → Português"),
                leading: Radio<String>(
                  value: 'Libras → Português',
                  groupValue: selectedLanguage,
                  onChanged: (value) {
                    setState(() {
                      selectedLanguage = value!;
                    });
                    Navigator.pop(context);
                  },
                ),
              ),
              ListTile(
                title: Text("Português → Libras"),
                leading: Radio<String>(
                  value: 'Português → Libras',
                  groupValue: selectedLanguage,
                  onChanged: (value) {
                    setState(() {
                      selectedLanguage = value!;
                    });
                    Navigator.pop(context);
                  },
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
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.yellow,
      title: Row(
        mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            _languageSelectorButton(),
            Center(child: const Text('InSignIA')),
            ],
      ),
      ),
      body: _initializeControllerFuture == null
          ? Center(child: CircularProgressIndicator())
          : SafeArea(
        child: Stack(
        children: [
          Positioned.fill(
            child: _isCameraInitialized
                ? CameraPreview(_cameraController)
                : Center(child: CircularProgressIndicator(color: Colors.white)),
          ),
          DraggableScrollableSheet(
            initialChildSize: 0.2,
            minChildSize: 0.1,
            maxChildSize: 0.5,
            builder: (BuildContext context, ScrollController scrollController) {
              return Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.yellow.withOpacity(0.9),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: SingleChildScrollView(
                  controller: scrollController,
                  child: Column(
                    children: [
                      Container(
                        width: 50,
                        height: 5,
                        margin: EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: Colors.white60,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Text(
                        "Texto traduzido de LIBRAS para português",
                        style: TextStyle(color: Colors.black, fontSize: 16),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
      ),
    );
  }

  Positioned _languageSelectorButton() {
    return Positioned(
          top: 5,
          left: 5,
          child:
          IconButton(
            icon: Icon(Icons.sign_language_outlined, color: Colors.black, size: 30),
            onPressed: _showLanguageSelector,
          ),
        );
  }
}
