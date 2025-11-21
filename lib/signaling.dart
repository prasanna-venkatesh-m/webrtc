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

  void sendOffer(RTCSessionDescription offer, String viewerId) {
    _send({
      'type': 'offer',
      'to': viewerId,
      'sdp': offer.sdp,
    });
  }

  void sendAnswer(RTCSessionDescription answer, String to) {
    _send({
      'type': 'answer',
      'to': to,
      'sdp': answer.sdp,
    });
  }

  void sendCandidate(RTCIceCandidate candidate, String to) {
    _send({
      'type': 'candidate',
      'to': to,
      'candidate': candidate.candidate,
      'sdpMid': candidate.sdpMid,
      'sdpMLineIndex': candidate.sdpMLineIndex,
    });
  }

  void _send(Map data) {
    _channel.sink.add(jsonEncode(data));
  }

  void close() => _channel.sink.close();
}
