import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class Signaling {
  final String url;
  final String room;
  late WebSocketChannel _channel;

  Signaling(this.url, this.room) {
    _channel = WebSocketChannel.connect(Uri.parse(url));
    _channel.sink.add(jsonEncode({'type': 'join', 'room': room}));
  }

  Stream get messages => _channel.stream;

  void sendOffer(RTCSessionDescription offer) {
    _sendMessage({
      'type': 'offer',
      'sdp': offer.sdp,
    });
  }

  void sendAnswer(RTCSessionDescription answer) {
    _sendMessage({
      'type': 'answer',
      'sdp': answer.sdp,
    });
  }

  void sendIceCandidate(RTCIceCandidate candidate) {
    _sendMessage({
      'type': 'candidate',
      'candidate': candidate.candidate,
      'sdpMid': candidate.sdpMid,
      'sdpMLineIndex': candidate.sdpMLineIndex,
    });
  }

  void _sendMessage(Map<String, dynamic> message) {
    _channel.sink.add(jsonEncode(message));
  }

  void close() {
    _channel.sink.close();
  }
}
