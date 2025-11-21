import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'signaling.dart';

class MobileASendScreen extends StatefulWidget {
  final String url;
  const MobileASendScreen({Key? key, required this.url}) : super(key: key);

  @override
  State<MobileASendScreen> createState() => _MobileASendScreenState();
}

class _MobileASendScreenState extends State<MobileASendScreen> {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  late Signaling signaling;

  MediaStream? _localStream;
  bool isStreaming = false;

  /// Each viewer has its own PeerConnection
  Map<String, RTCPeerConnection> pcs = {};

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await Permission.camera.request();
    await Permission.microphone.request();
    await _localRenderer.initialize();

    signaling = Signaling(widget.url, "room1");

    signaling.messages.listen((message) async {
      String msg = _decode(message);
      final data = jsonDecode(msg);

      switch (data['type']) {
        case 'viewer-joined':
          _createPCForViewer(data['viewerId']);
          break;

        case 'answer':
          final viewerId = data['from'];
          final pc = pcs[viewerId];
          if (pc != null) {
            await pc.setRemoteDescription(
              RTCSessionDescription(data['sdp'], "answer"),
            );
          }
          break;

        case 'candidate':
          final viewerId = data['from'];
          final pc = pcs[viewerId];
          if (pc != null) {
            await pc.addCandidate(
              RTCIceCandidate(
                data['candidate'],
                data['sdpMid'],
                data['sdpMLineIndex'],
              ),
            );
          }
          break;
      }
    });
  }

  String _decode(dynamic message) {
    if (message is String) return message;
    if (message is Uint8List) return utf8.decode(message);
    return "";
  }

  Future<void> _startLocalStream() async {
    final constraints = {
      "audio": true,
      "video": {
        "mandatory": {"minWidth": 640, "minHeight": 480, "minFrameRate": 15},
        "facingMode": "user"
      }
    };

    _localStream = await navigator.mediaDevices.getUserMedia(constraints);
    _localRenderer.srcObject = _localStream;
  }

  Future<void> _createPCForViewer(String viewerId) async {
    final pc = await createPeerConnection({
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'}
      ]
    });

    // Add local tracks
    _localStream?.getTracks().forEach((track) {
      pc.addTrack(track, _localStream!);
    });

    // ICE candidates
    pc.onIceCandidate = (c) {
      if (c.candidate != null) {
        signaling.sendCandidate(c, viewerId);
      }
    };

    final offer = await pc.createOffer();
    await pc.setLocalDescription(offer);

    signaling.sendOffer(offer, viewerId);

    pcs[viewerId] = pc;
  }

  Future<void> _startStreaming() async {
    await _startLocalStream();
    setState(() => isStreaming = true);
  }

  @override
  void dispose() {
    pcs.values.forEach((pc) => pc.close());
    _localStream?.dispose();
    _localRenderer.dispose();
    signaling.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Sender - Live Stream")),
      body: Column(
        children: [
          Expanded(
            child: Container(
              color: Colors.black,
              child: RTCVideoView(_localRenderer, mirror: true),
            ),
          ),
          if (!isStreaming)
            ElevatedButton(
              onPressed: _startStreaming,
              child: Text("Start Streaming"),
            ),
          if (isStreaming)
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: Text("Stop"),
            )
        ],
      ),
    );
  }
}
