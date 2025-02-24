import 'dart:async';
import 'dart:typed_data';

import 'dart:isolate';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image/image.dart' as imgLib;

String processedText = "";

void main(){
  runApp(MyApp());
}

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
  bool _isCameraInitialized = false;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    final cameras = await availableCameras();
    final firstCamera = cameras.first;

    _cameraController = CameraController(
      firstCamera,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    await _cameraController.initialize();

    if (!mounted) return;
    setState(() {
      _isCameraInitialized = true;
    });

    _cameraController.startImageStream((CameraImage image) {
      if (!_isSending) {
        _isSending = true;
        Future.microtask(() => _processAndSendFrame(image).then((_){
          _isSending = false;
        }));
        Future.microtask(() => getDataFromServer());
      }
    });
  }

  Future<void> getDataFromServer() async {
    String url = 'http://192.168.1.106:5000/get-result';
    try {
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        var data = json.decode(response.body);
        print('Dados recebidos: $data');
        if (data["should_read"] == true)
          {
            setState(() {
              processedText += data["last_read"] + " ";
            });
          }
      } else {
        print('Erro: ${response.statusCode}');
      }
    } catch (e) {
      print('Erro ao buscar dados: $e');
    }
  }

  Future<void> _sendImageBytesToServer(Uint8List imageBytes) async {
    try {
      final url = Uri.parse('http://192.168.1.106:5000/upload_video');

      var request = http.MultipartRequest('POST', url);
      request.files.add(
        http.MultipartFile.fromBytes(
          'frame',
          imageBytes,
          filename: 'frame.jpg',
          contentType: MediaType('image', 'jpeg'), // Define o tipo MIME correto
        ),
      );

      var response = await request.send();

      if (response.statusCode == 200) {
        print('Frame enviado com sucesso!');
      } else {
        print('Erro ao enviar frame: ${response.statusCode}');
      }
    } catch (e) {
      print("Erro na requisição: $e");
    }
  }

  //algoritmo tirado do stack overflow: https://stackoverflow.com/questions/76760769/convert-cameraimage-to-jpeg-and-display-flutter-on-android-and-ios
  imgLib.Image _convertYUV420toImageColor(CameraImage image) {
    const shift = (0xFF << 24);

    final int width = image.width;
    final int height = image.height;
    final int uvRowStride = image.planes[1].bytesPerRow;
    final int uvPixelStride = image.planes[1].bytesPerPixel!;

    final img = imgLib.Image(width: height, height: width);

    // Fill image buffer with plane[0] from YUV420_888
    for (int x = 0; x < width; x++) {
      for (int y = 0; y < height; y++) {
        final int uvIndex =
            uvPixelStride * (x / 2).floor() + uvRowStride * (y / 2).floor();
        final int index = y * width + x;

        final yp = image.planes[0].bytes[index];
        final up = image.planes[1].bytes[uvIndex];
        final vp = image.planes[2].bytes[uvIndex];
        // Calculate pixel color
        int r = (yp + vp * 1436 / 1024 - 179).round().clamp(0, 255);
        int g = (yp - up * 46549 / 131072 + 44 - vp * 93604 / 131072 + 91)
            .round()
            .clamp(0, 255);
        int b = (yp + up * 1814 / 1024 - 227).round().clamp(0, 255);
        // color: 0x FF  FF  FF  FFj
        //           A   B   G   R

        if (img.isBoundsSafe(height - y, x)) {
          img.setPixelRgba(height - y, x, r, g, b, shift);
        }
      }
    }
    return img;
  }

  Future<Uint8List> _convertToJpeg(CameraImage image) async {
    final rbgImage = _convertYUV420toImageColor(image);
    return Uint8List.fromList(imgLib.encodeJpg(rbgImage, quality: 70));
  }

  Future<void> _processAndSendFrame(CameraImage image) async {
    try {
      Uint8List jpegBytes = await _convertToJpeg(image);
      await _sendImageBytesToServer(jpegBytes);
    } catch (e) {
      print("Erro ao processar frame: $e");
    }
  }

  Future<bool> _requestPermissions() async {
    PermissionStatus cameraStatus = await Permission.camera.request();
    PermissionStatus micStatus = await Permission.microphone.request();

    return cameraStatus.isGranted && micStatus.isGranted;
  }

  @override
  void dispose() {
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
              Text("Selecione o idioma", style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold)),
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

  Positioned _languageSelectorButton() {
    return Positioned(
      top: 5,
      left: 5,
      child:
      IconButton(
        icon: Icon(
            Icons.sign_language_outlined, color: Colors.black, size: 30),
        onPressed: _showLanguageSelector,
      ),
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
      body: _isCameraInitialized
          ? SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: _isCameraInitialized
                  ? CameraPreview(_cameraController)
                  : Center(
                  child: CircularProgressIndicator(color: Colors.white)),
            ),
            DraggableScrollableSheet(
              initialChildSize: 0.2,
              minChildSize: 0.1,
              maxChildSize: 0.5,
              builder: (BuildContext context,
                  ScrollController scrollController) {
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
                          processedText,
                          style: TextStyle(color: Colors.black, fontSize: 16),
                          textAlign: TextAlign.center,
                        ),
                        IconButton(onPressed: (){
                          setState(() {
                            processedText = "";
                          });
                        }, icon: const Icon(Icons.delete)
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      )
          : Center(child: CircularProgressIndicator()),
    );
  }
}
