import 'dart:convert';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class Signaling {
  late WebSocketChannel _channel;
  late Stream _broadcastStream;

  Signaling(String url, String roomId) {
    _channel = WebSocketChannel.connect(Uri.parse(url));
    _channel.sink.add(jsonEncode({
      'type': 'join',
      'room': roomId,
    }));

    // Make stream broadcast
    _broadcastStream = _channel.stream.asBroadcastStream();

    // Send join message immediately
    _channel.sink.add(jsonEncode({
      'type': 'join',
      'room': roomId,
    }));

    // Optional logging
    _broadcastStream.listen(
      (msg) => print("📩 Signaling message: $msg"),
      onError: (e) => print("❌ Signaling error: $e"),
      onDone: () => print("🔒 Signaling closed"),
    );
  }

  void sendOffer(RTCSessionDescription offer) {
    _channel.sink.add(jsonEncode({'type': 'offer', 'sdp': offer.sdp}));
  }

  void sendAnswer(RTCSessionDescription answer) {
    _channel.sink.add(jsonEncode({'type': 'answer', 'sdp': answer.sdp}));
  }

  void sendIceCandidate(RTCIceCandidate candidate) {
    _channel.sink.add(jsonEncode({
      'type': 'candidate',
      'candidate': candidate.candidate,
      'sdpMid': candidate.sdpMid,
      'sdpMLineIndex': candidate.sdpMLineIndex,
    }));
  }

  Stream get messages => _broadcastStream;

  void close() {
    _channel.sink.close();
  }
}
