import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'signaling.dart';

class MobileBReceiveScreen extends StatefulWidget {
  const MobileBReceiveScreen({Key? key}) : super(key: key);

  @override
  State<MobileBReceiveScreen> createState() => _MobileBReceiveScreenState();
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
    _remoteRenderer = RTCVideoRenderer();
    await _remoteRenderer.initialize();

    signaling = Signaling('ws://192.168.1.155:8888', 'room1');

    await _createPeerConnection();
    _listenSignaling();
  }

  Future<void> _createPeerConnection() async {
    _peerConnection = await createPeerConnection({
      'iceServers': [
        {
          'urls': ['stun:stun.l.google.com:19302']
        }
      ]
    });

    _peerConnection!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        setState(() => _remoteRenderer.srcObject = event.streams[0]);
      }
    };

    // _peerConnection!.onIceCandidate = (candidate) {
    //   if (candidate != null) signaling.sendIceCandidate(candidate);
    // };

    _peerConnection!.onIceConnectionState = (state) {
      print("🔥 ICE state = $state");
    };
  }

  void _listenSignaling() {
    signaling.messages.listen((msg) async {
      final data = jsonDecode(msg);
      switch (data['type']) {
        case 'offer':
          await _peerConnection!.setRemoteDescription(
              RTCSessionDescription(data['sdp'], 'offer'));
          final answer = await _peerConnection!.createAnswer();
          await _peerConnection!.setLocalDescription(answer);
          signaling.sendAnswer(answer);
          break;

        case 'candidate':
          await _peerConnection!.addCandidate(RTCIceCandidate(
              data['candidate'], data['sdpMid'], data['sdpMLineIndex']));
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Mobile B — Receive Stream")),
      body: Center(
        child: _remoteRenderer.srcObject != null
            ? RTCVideoView(_remoteRenderer)
            : const Text("Waiting for stream..."),
      ),
    );
  }

  @override
  void dispose() {
    _peerConnection?.close();
    _remoteRenderer.dispose();
    signaling.close();
    super.dispose();
  }
}
