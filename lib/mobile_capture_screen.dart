import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'signaling.dart';

class MobileBReceiveScreen extends StatefulWidget {
  @override
  _MobileBReceiveScreenState createState() => _MobileBReceiveScreenState();
}

class _MobileBReceiveScreenState extends State<MobileBReceiveScreen> {
  late RTCVideoRenderer _remoteRenderer;
  RTCPeerConnection? _peerConnection;
  late Signaling signaling;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    // Initialize renderer
    _remoteRenderer = RTCVideoRenderer();
    await _remoteRenderer.initialize();

    // Initialize signaling
    signaling = Signaling('ws://192.168.1.155:8888', 'room1');

    // Log WebSocket connection events
    // signaling.onOpen = () => print("📡 Connected to signaling server");
    // signaling.onError = (e) => print("❌ Signaling error: $e");
    // signaling.onClose = () => print("🔒 Signaling closed");

    // Connect signaling
    // signaling.connect();

    // Create peer connection
    await _createPeerConnection();

    // Listen for messages from signaling server
    _listenSignaling();
  }

  Future<void> _createPeerConnection() async {
    print("B: Creating PeerConnection...");

    final config = {
      'iceServers': [
        {
          'urls': [
            'stun:stun.l.google.com:19302',
            'stun:stun1.l.google.com:19302',
          ]
        }
      ],
      'iceCandidatePoolSize': 10,
    };

    _peerConnection = await createPeerConnection(config);

    // Listen for remote tracks
    _peerConnection!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        print("🔥 B: Remote stream received");
        setState(() {
          _remoteRenderer.srcObject = event.streams[0];
        });
      }
    };

    // Send ICE candidates to A
    _peerConnection!.onIceCandidate = (candidate) {
      if (candidate != null) {
        print("📤 B: Sending ICE → A");
        signaling.sendIceCandidate(candidate);
      }
    };

    _peerConnection!.onIceConnectionState = (state) {
      print("🔥 B: ICE state = $state");
    };
  }

  void _listenSignaling() {
    signaling.messages.listen((msg) async {
      final data = jsonDecode(msg);

      switch (data['type']) {
        case 'offer':
          print("📥 B: Received OFFER");

          await _peerConnection!.setRemoteDescription(
            RTCSessionDescription(data['sdp'], 'offer'),
          );

          final answer = await _peerConnection!.createAnswer();
          await _peerConnection!.setLocalDescription(answer);

          signaling.sendAnswer(answer);
          print("📤 B: Sent ANSWER");
          break;

        case 'candidate':
          print("📥 B: Received ICE from A");
          await _peerConnection!.addCandidate(
            RTCIceCandidate(
              data['candidate'],
              data['sdpMid'],
              data['sdpMLineIndex'],
            ),
          );
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Mobile B — Watching Stream")),
      body: Center(
        child: _remoteRenderer.srcObject != null
            ? AspectRatio(
                aspectRatio: 16 / 9,
                child: RTCVideoView(
                  _remoteRenderer,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                ),
              )
            : Container(
                color: Colors.black,
                child: Center(
                  child: Text(
                    "Waiting for stream...",
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
      ),
    );
  }

  @override
  void dispose() {
    _remoteRenderer.dispose();
    _peerConnection?.close();
    signaling.close();
    super.dispose();
  }
}
