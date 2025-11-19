import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class UploadManager {
  final http.Client _client = http.Client();

  UploadManager();

  Uri _buildBlobUri(String containerSasUrl, String blobName) {
    final base = containerSasUrl.split('?').first;
    final sas =
        containerSasUrl.contains('?') ? containerSasUrl.split('?').last : '';
    final encodedName = Uri.encodeComponent(blobName);
    final uriString = '$base/$encodedName?$sas';
    return Uri.parse(uriString);
  }

  Uri _buildBlockUri(
      String containerSasUrl, String blobName, String blockIdBase64) {
    final base = containerSasUrl.split('?').first;
    final sas =
        containerSasUrl.contains('?') ? containerSasUrl.split('?').last : '';
    final encodedName = Uri.encodeComponent(blobName);
    final uriString =
        '$base/$encodedName?comp=block&blockid=${Uri.encodeQueryComponent(blockIdBase64)}&$sas';
    return Uri.parse(uriString);
  }

  /// Upload a full file as a single BlockBlob via PUT.
  Future<http.StreamedResponse> uploadSegmentAsBlob({
    required File file,
    required String containerSasUrl,
    required String blobName,
    String contentType = 'video/mp4',
    void Function(int sentBytes, int totalBytes)? onProgress,
    int maxRetries = 3,
  }) async {
    final uri = _buildBlobUri(containerSasUrl, blobName);
    final length = await file.length();

    int attempt = 0;
    while (true) {
      attempt++;
      try {
        final request = http.StreamedRequest('PUT', uri);
        request.headers['x-ms-blob-type'] = 'BlockBlob';
        request.headers['Content-Type'] = contentType;
        request.contentLength = length;

        final fileStream = file.openRead();
        int bytesSent = 0;
        fileStream.listen((chunk) {
          bytesSent += chunk.length;
          request.sink.add(chunk);
          if (onProgress != null) onProgress(bytesSent, length);
        }, onDone: () {
          request.sink.close();
        }, onError: (e) {
          request.sink.close();
        }, cancelOnError: true);

        final response = await _client.send(request);
        return response;
      } catch (e) {
        if (attempt >= maxRetries) rethrow;
        await Future.delayed(
            Duration(milliseconds: 500 * (1 << (attempt - 1))));
      }
    }
  }

  /// Upload a block using Put Block. Returns the base64 block id string.
  Future<String> uploadSegmentAsBlock({
    required File file,
    required String containerSasUrl,
    required String blobName,
    required int blockIndex,
    void Function(int sent, int total)? onProgress,
    int maxRetries = 3,
  }) async {
    final blockId =
        base64Encode(utf8.encode(blockIndex.toString().padLeft(6, '0')));
    final uri = _buildBlockUri(containerSasUrl, blobName, blockId);
    final length = await file.length();

    int attempt = 0;
    while (true) {
      attempt++;
      try {
        final request = http.StreamedRequest('PUT', uri);
        request.headers['Content-Type'] = 'application/octet-stream';
        request.contentLength = length;
        int bytesSent = 0;
        file.openRead().listen((chunk) {
          bytesSent += chunk.length;
          request.sink.add(chunk);
          if (onProgress != null) onProgress(bytesSent, length);
        }, onDone: () {
          request.sink.close();
        }, onError: (e) {
          request.sink.close();
        }, cancelOnError: true);

        final response = await _client.send(request);
        if (response.statusCode == 201 || response.statusCode == 202) {
          return blockId;
        } else {
          final body = await response.stream.bytesToString();
          throw Exception('Put Block failed ${response.statusCode} $body');
        }
      } catch (e) {
        if (attempt >= maxRetries) rethrow;
        await Future.delayed(
            Duration(milliseconds: 500 * (1 << (attempt - 1))));
      }
    }
  }

  /// Commit the ordered list of base64 block ids into a final blob.
  Future<void> commitBlockList({
    required String containerSasUrl,
    required String blobName,
    required List<String> base64BlockIds,
    String contentType = 'video/mp4',
  }) async {
    final base = containerSasUrl.split('?').first;
    final sas =
        containerSasUrl.contains('?') ? containerSasUrl.split('?').last : '';
    final encodedName = Uri.encodeComponent(blobName);
    final uri = Uri.parse('$base/$encodedName?comp=blocklist&$sas');

    final xmlBuffer = StringBuffer();
    xmlBuffer.write('<?xml version="1.0" encoding="utf-8"?><BlockList>');
    for (final id in base64BlockIds) {
      xmlBuffer.write('<Latest>$id</Latest>');
    }
    xmlBuffer.write('</BlockList>');
    final bodyBytes = utf8.encode(xmlBuffer.toString());

    final resp = await _client.put(uri,
        headers: {
          'x-ms-blob-content-type': contentType,
          'Content-Type': 'application/xml',
        },
        body: bodyBytes);

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('Put Block List failed: ${resp.statusCode} ${resp.body}');
    }
  }

  void dispose() {
    _client.close();
  }
}
