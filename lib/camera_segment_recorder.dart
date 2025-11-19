import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

typedef OnSegmentRecorded = Future<void> Function(File segmentFile);

class CameraSegmentRecorder {
  final Duration segmentDuration;
  final OnSegmentRecorded onSegmentRecorded;
  CameraController? _controller;
  bool _running = false;
  final Uuid _uuid = Uuid();

  CameraSegmentRecorder({
    required this.segmentDuration,
    required this.onSegmentRecorded,
  });

  Future<void> initialize(
      {CameraLensDirection prefDirection = CameraLensDirection.back}) async {
    final cameras = await availableCameras();
    CameraDescription? selected;
    try {
      selected = cameras.firstWhere((c) => c.lensDirection == prefDirection);
    } catch (e) {
      selected = cameras.isNotEmpty ? cameras.first : null;
    }
    if (selected == null) throw Exception('No camera available');
    _controller = CameraController(
      selected,
      ResolutionPreset.medium,
      enableAudio: true,
    );
    await _controller!.initialize();
  }

  Future<void> start() async {
    if (_controller == null) throw Exception('Controller not initialized');
    if (_running) return;
    _running = true;
    _loopSegments();
  }

  Future<void> _loopSegments() async {
    while (_running) {
      try {
        // Start recording
        await _controller!.startVideoRecording();

        // Wait for segment duration or stop
        var completed = Completer<void>();
        Timer(segmentDuration, () => completed.complete());
        await completed.future;

        // Stop recording and retrieve file
        final XFile recorded = await _controller!.stopVideoRecording();

        final tempDir = await getTemporaryDirectory();
        final filename =
            'segment_${DateTime.now().toUtc().toIso8601String()}_${_uuid.v4()}.mp4';
        final filePath = '${tempDir.path}/$filename';

        final File tmp = File(recorded.path);
        final File moved = await tmp.copy(filePath);

        // Fire-and-forget the uploader; the handler should manage errors and deletion
        unawaited(onSegmentRecorded(moved));
      } catch (e) {
        // If something goes wrong, break the loop
        print('Segment loop error: $e');
        _running = false;
      }
    }
  }

  Future<void> stop() async {
    _running = false;
    try {
      if (_controller != null && _controller!.value.isRecordingVideo) {
        await _controller!.stopVideoRecording();
      }
    } catch (_) {}
  }

  Future<void> dispose() async {
    try {
      await _controller?.dispose();
    } catch (_) {}
    _controller = null;
  }
}

// Helper to allow unawaited call without analyzer warning
void unawaited(Future<void> f) {}
