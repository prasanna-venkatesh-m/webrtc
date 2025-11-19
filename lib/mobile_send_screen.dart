import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'signaling.dart';

class MobileASendScreen extends StatefulWidget {
  final String url;
  const MobileASendScreen({Key? key, required this.url}) : super(key: key);

  @override
  State<MobileASendScreen> createState() => _MobileASendScreenState();
}

class _MobileASendScreenState extends State<MobileASendScreen> {
  final _localRenderer = RTCVideoRenderer();
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  late Signaling signaling;
  final _logs = <String>[];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _localRenderer.initialize();

    signaling = Signaling(widget.url, 'room1');

    // Listen for ANSWER and remote ICE
    signaling.messages.listen((message) async {
      String messageStr;
      if (message is String) {
        messageStr = message;
      } else if (message is Uint8List) {
        messageStr = String.fromCharCodes(message);
      } else {
        print('❌ Unknown message type: ${message.runtimeType}');
        return;
      }

      final data = jsonDecode(messageStr);
      switch (data['type']) {
        case 'answer':
          _log('📥 Received ANSWER');
          final answer = RTCSessionDescription(data['sdp'], 'answer');
          await _peerConnection?.setRemoteDescription(answer);
          break;

        case 'candidate':
          _log('📥 Received remote ICE candidate');
          await _peerConnection?.addCandidate(RTCIceCandidate(
            data['candidate'],
            data['sdpMid'],
            data['sdpMLineIndex'],
          ));
          break;

        default:
          print('⚠️ Unknown signaling type: ${data['type']}');
      }
    });
  }

  void _log(String msg) {
    setState(() => _logs.insert(0, msg));
    print(msg);
  }

  Future<void> _start() async {
    await _startLocalStream();
    await _createPeerAndSendOffer();
  }

  Future<void> _startLocalStream() async {
    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': {'facingMode': 'user'}
    });
    _localRenderer.srcObject = _localStream;
    _log("🎥 Local camera started");
  }

  Future<void> _createPeerAndSendOffer() async {
    _peerConnection = await createPeerConnection({
      'iceServers': [
        {
          'urls': ['stun:stun.l.google.com:19302']
        }
      ]
    });

    // Add local tracks
    _localStream?.getTracks().forEach((track) {
      _peerConnection!.addTrack(track, _localStream!);
    });

    // Handle ICE candidates
    _peerConnection!.onIceCandidate = (candidate) {
      if (candidate.candidate != null) {
        signaling.sendIceCandidate(candidate);
      }
    };

    _peerConnection!.onIceConnectionState =
        (state) => _log("🔥 ICE State: $state");

    final offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);
    signaling.sendOffer(offer);
    _log("📤 OFFER sent");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Mobile A — Send Stream")),
      body: Column(
        children: [
          Expanded(
            child: Container(
              color: Colors.black,
              child: RTCVideoView(_localRenderer, mirror: true),
            ),
          ),
          ElevatedButton(onPressed: _start, child: const Text("Start")),
          const SizedBox(height: 12),
          const Text("Logs:"),
          Expanded(
            child: ListView.builder(
              reverse: true,
              itemCount: _logs.length,
              itemBuilder: (_, i) => Text(_logs[i]),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _peerConnection?.close();
    _localRenderer.dispose();
    _localStream?.dispose();
    signaling.close();
    super.dispose();
  }
}
