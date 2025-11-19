import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'signaling.dart';

class MobileBReceiveScreen extends StatefulWidget {
  final String url;
  const MobileBReceiveScreen({Key? key, required this.url}) : super(key: key);

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

    signaling = Signaling(widget.url, 'room1');

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

    _peerConnection!.onIceCandidate = (candidate) {
      if (candidate.candidate != null) {
        signaling.sendIceCandidate(candidate);
      }
    };

    _peerConnection!.onIceConnectionState =
        (state) => print("🔥 ICE state = $state");
  }

  void _listenSignaling() {
    signaling.messages.listen((msg) async {
      String messageStr;
      if (msg is String) {
        messageStr = msg;
      } else if (msg is Uint8List) {
        messageStr = String.fromCharCodes(msg);
      } else {
        print('❌ Unknown message type: ${msg.runtimeType}');
        return;
      }

      final data = jsonDecode(messageStr);
      switch (data['type']) {
        case 'offer':
          print('📩 OFFER received');
          await _peerConnection!.setRemoteDescription(
              RTCSessionDescription(data['sdp'], 'offer'));
          final answer = await _peerConnection!.createAnswer();
          await _peerConnection!.setLocalDescription(answer);
          signaling.sendAnswer(answer);
          print('📤 ANSWER sent');
          break;

        case 'answer':
          print('📩 ANSWER received');
          await _peerConnection!.setRemoteDescription(
              RTCSessionDescription(data['sdp'], 'answer'));
          break;

        case 'candidate':
          print('💡 ICE candidate received');
          await _peerConnection!.addCandidate(RTCIceCandidate(
              data['candidate'], data['sdpMid'], data['sdpMLineIndex']));
          break;

        default:
          print('⚠️ Unknown signaling type: ${data['type']}');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Watch Live")),
      body: Center(
        child: _remoteRenderer.srcObject != null
            ? RTCVideoView(_remoteRenderer)
            : const Text("Waiting for live..."),
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
