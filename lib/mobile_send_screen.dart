import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'signaling.dart';

class MobileASendScreen extends StatefulWidget {
  const MobileASendScreen({Key? key}) : super(key: key);

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

    // CONNECT SIGNALING
    signaling = Signaling('ws://192.168.1.155:8888', 'room1');

    // LISTEN FOR ANSWER + ICE
    signaling.messages.listen((message) async {
      final data = jsonDecode(message);

      switch (data['type']) {
        case 'answer':
          _log('📥 Received ANSWER');
          final answer = RTCSessionDescription(data['sdp'], 'answer');
          await _peerConnection?.setRemoteDescription(answer);
          break;

        case 'candidate':
          _log('📥 Received remote ICE candidate');
          await _peerConnection?.addCandidate(
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

  void _log(String msg) {
    setState(() {
      _logs.insert(0, msg);
    });
    print(msg);
  }

  Future<void> _startLocalStream() async {
    final mediaConstraints = {
      'audio': true,
      'video': {'facingMode': 'user'}
    };

    _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
    _localRenderer.srcObject = _localStream;

    _log("🎥 Local camera started");
  }

  Future<void> _createPeerAndSendOffer() async {
    final configuration = {
      'iceServers': [
        {
          'urls': [
            'stun:stun.l.google.com:19302',
            'stun:stun1.l.google.com:19302',
            'stun:stun2.l.google.com:19302',
          ]
        }
      ],
    };

    _peerConnection = await createPeerConnection(configuration);

    // ADD LOCAL STREAM
    if (_localStream != null) {
      for (var track in _localStream!.getTracks()) {
        await _peerConnection!.addTrack(track, _localStream!);
      }
    }

    // SEND LOCAL ICE TO MOBILE B
    _peerConnection!.onIceCandidate = (candidate) {
      if (candidate.candidate != null) {
        _log("📤 Sending ICE candidate: ${candidate.candidate}");
        signaling.sendIceCandidate(candidate);
      }
    };

    // ICE CONNECTION STATE
    _peerConnection!.onIceConnectionState = (state) {
      _log("🔥 Mobile A ICE State: $state");
    };

    // CREATE OFFER
    _log("📡 Creating OFFER...");
    final offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);

    // SEND OFFER TO B
    _log("📤 Sending OFFER to B");
    signaling.sendOffer(offer);
  }

  Future<void> _start() async {
    try {
      _log("🚀 Starting...");

      await _startLocalStream();
      await _createPeerAndSendOffer();
    } catch (e) {
      _log("❌ Start error: $e");
    }
  }

  Future<void> _stop() async {
    try {
      await _localStream?.dispose();
      await _peerConnection?.close();
      _localRenderer.srcObject = null;
      signaling.close();
    } catch (e) {
      _log("Stop error: $e");
    }
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mobile A: Send Stream')),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Expanded(
              child: Container(
                color: Colors.black,
                child: RTCVideoView(_localRenderer, mirror: true),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                ElevatedButton(
                  onPressed: _start,
                  child: const Text("Start"),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _stop,
                  child: const Text("Stop"),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text("Logs:"),
            Expanded(
              child: ListView.builder(
                reverse: true,
                itemCount: _logs.length,
                itemBuilder: (_, i) => Text(_logs[i]),
              ),
            )
          ],
        ),
      ),
    );
  }
}
