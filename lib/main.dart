import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'camera_segment_recorder.dart';
import 'upload_manager.dart';
import 'mobile_send_screen.dart';
import 'mobile_capture_screen.dart';

void main() {
  runApp(MaterialApp(
    home: MainApp(),
  ));
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    String url = 'ws://192.168.1.155:8888';
    // String url = 'ws://05ca9f993aa3.ngrok-free.app';
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Live Streaming Demo')),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => MobileASendScreen(url: url)));
                  },
                  child: const Text('Stream Live'),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => MobileBReceiveScreen(url: url)));
                  },
                  child: const Text('Watch Live'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class LiveStreamDemo extends StatefulWidget {
  const LiveStreamDemo({super.key});

  @override
  State<LiveStreamDemo> createState() => _LiveStreamDemoState();
}

class _LiveStreamDemoState extends State<LiveStreamDemo> {
  final _sasController = TextEditingController();
  final _logs = <String>[];
  late final UploadManager _uploadManager;
  CameraSegmentRecorder? _recorder;
  bool _recording = false;

  @override
  void initState() {
    super.initState();
    _uploadManager = UploadManager();
  }

  void _log(String s) {
    if (kDebugMode) print(s);
    setState(() => _logs.insert(0, '${DateTime.now().toIso8601String()} - $s'));
  }

  Future<void> _start() async {
    final sas = _sasController.text.trim();
    if (sas.isEmpty) {
      _log('Provide container SAS URL first');
      return;
    }

    _recorder = CameraSegmentRecorder(
      segmentDuration: const Duration(seconds: 5),
      onSegmentRecorded: (File file) async {
        final blobName = 'segments/${file.uri.pathSegments.last}';
        _log('Recorded ${file.path}, uploading as $blobName');
        try {
          final resp = await _uploadManager.uploadSegmentAsBlob(
            file: file,
            containerSasUrl: sas,
            blobName: blobName,
            onProgress: (sent, total) =>
                _log('Uploading $blobName $sent/$total'),
          );
          if (resp.statusCode >= 200 && resp.statusCode < 300) {
            _log('Upload succeeded: ${resp.statusCode}');
            try {
              await file.delete();
            } catch (_) {}
          } else {
            final body = await resp.stream.bytesToString();
            _log('Upload failed ${resp.statusCode}: $body');
          }
        } catch (e) {
          _log('Upload exception: $e');
        }
      },
    );

    try {
      _log('Initializing camera...');
      await _recorder!.initialize();
      _log('Camera initialized, starting recording');
      await _recorder!.start();
      setState(() => _recording = true);
    } catch (e) {
      _log('Failed to start recorder: $e');
    }
  }

  Future<void> _stop() async {
    if (_recorder != null) {
      await _recorder!.stop();
      await _recorder!.dispose();
      _recorder = null;
    }
    setState(() => _recording = false);
    _log('Stopped');
  }

  @override
  void dispose() {
    _sasController.dispose();
    _uploadManager.dispose();
    _recorder?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          const Text(
              'Paste your container SAS URL (https://<acct>.blob.core.windows.net/<container>?<sas>)'),
          const SizedBox(height: 8),
          TextField(
            controller: _sasController,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(
                border: OutlineInputBorder(), hintText: 'Container SAS URL'),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              ElevatedButton(
                onPressed: _recording ? null : _start,
                child: const Text('Start Recording'),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: _recording ? _stop : null,
                child: const Text('Stop Recording'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text('Logs'),
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              decoration: BoxDecoration(border: Border.all(color: Colors.grey)),
              child: ListView.builder(
                reverse: true,
                itemCount: _logs.length,
                itemBuilder: (context, index) => Padding(
                  padding: const EdgeInsets.all(6.0),
                  child: Text(_logs[index]),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
