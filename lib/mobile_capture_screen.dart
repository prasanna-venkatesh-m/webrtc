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
  final RTCVideoRenderer _renderer = RTCVideoRenderer();
  late Signaling signaling;
  RTCPeerConnection? pc;
  String? senderId;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _renderer.initialize();
    signaling = Signaling(widget.url, 'room1');
    await _createPC();
    _listen();
  }

  Future<void> _createPC() async {
    pc = await createPeerConnection({
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'}
      ]
    });

    // Receive-only
    await pc!.addTransceiver(
      kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
      init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
    );
    await pc!.addTransceiver(
      kind: RTCRtpMediaType.RTCRtpMediaTypeAudio,
      init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
    );

    pc!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        setState(() => _renderer.srcObject = event.streams[0]);
      }
    };
  }

  void _listen() {
    signaling.messages.listen((m) async {
      String msg = _decode(m);
      final data = jsonDecode(msg);

      switch (data['type']) {
        case 'offer':
          senderId = data['from'];

          await pc!.setRemoteDescription(
            RTCSessionDescription(data['sdp'], 'offer'),
          );

          final answer = await pc!.createAnswer();
          await pc!.setLocalDescription(answer);

          signaling.sendAnswer(answer, senderId!);
          break;

        case 'candidate':
          await pc!.addCandidate(
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

  String _decode(dynamic m) {
    if (m is String) return m;
    if (m is Uint8List) return utf8.decode(m);
    return "";
  }

  @override
  void dispose() {
    pc?.close();
    _renderer.dispose();
    signaling.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Viewer")),
      body: Center(
        child: _renderer.srcObject != null
            ? RTCVideoView(_renderer)
            : Text("Waiting for stream..."),
      ),
    );
  }
}
