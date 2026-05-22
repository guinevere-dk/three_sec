import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:http/http.dart' as http;

class CloudUsageService {
  CloudUsageService({
    FirebaseAuth? auth,
    FirebaseApp? firebaseApp,
    http.Client? client,
    String? region,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _firebaseApp = firebaseApp ?? Firebase.app(),
       _client = client ?? http.Client(),
       _region = region ?? _defaultRegion;

  static const String _defaultRegion = 'asia-northeast3';
  static const String _functionsOriginOverride = String.fromEnvironment(
    'MOA_FUNCTIONS_ORIGIN',
  );
  static const Duration _timeout = Duration(seconds: 30);

  final FirebaseAuth _auth;
  final FirebaseApp _firebaseApp;
  final http.Client _client;
  final String _region;

  Future<CloudUploadReservation> prepareCloudUpload({
    required String requestId,
    required String fileName,
    required int fileSize,
    required String contentType,
    required String albumName,
    required String source,
    String? videoId,
    bool isFavorite = false,
    Map<String, Object?> metadata = const {},
  }) async {
    final result = await _callFunction('prepareCloudUpload', {
      'requestId': requestId,
      if (videoId != null && videoId.trim().isNotEmpty)
        'videoId': videoId.trim(),
      'fileName': fileName,
      'fileSize': fileSize,
      'contentType': contentType,
      'albumName': albumName,
      'source': source,
      'isFavorite': isFavorite,
      'metadata': metadata,
    });

    return CloudUploadReservation.fromMap(result);
  }

  Future<CloudUploadCommitResult> commitCloudUpload({
    required String videoId,
    required String requestId,
    required String thumbnailStoragePath,
    String? downloadUrl,
    int? thumbnailWidth,
    int? thumbnailHeight,
    int? durationMs,
    Map<String, Object?> metadata = const {},
  }) async {
    final result = await _callFunction('commitCloudUpload', {
      'videoId': videoId,
      'requestId': requestId,
      'thumbnailStoragePath': thumbnailStoragePath,
      if (downloadUrl != null && downloadUrl.trim().isNotEmpty)
        'downloadUrl': downloadUrl.trim(),
      if (thumbnailWidth != null) 'thumbnailWidth': thumbnailWidth,
      if (thumbnailHeight != null) 'thumbnailHeight': thumbnailHeight,
      if (durationMs != null) 'durationMs': durationMs,
      'metadata': metadata,
    });

    return CloudUploadCommitResult.fromMap(result);
  }

  Future<CloudUploadCancelResult> cancelCloudUpload({
    required String videoId,
    required String requestId,
    required String reason,
  }) async {
    final result = await _callFunction('cancelCloudUpload', {
      'videoId': videoId,
      'requestId': requestId,
      'reason': reason,
    });

    return CloudUploadCancelResult.fromMap(result);
  }

  Future<CloudDownloadRecordResult> recordCloudDownload({
    required String videoId,
    required String source,
    required int bytes,
    bool cacheHit = false,
    String? cacheMissId,
    bool enforceHardLimit = false,
  }) async {
    final result = await _callFunction('recordCloudDownload', {
      'videoId': videoId,
      'source': source,
      'bytes': bytes,
      'cacheHit': cacheHit,
      'enforceHardLimit': enforceHardLimit,
      if (cacheMissId != null && cacheMissId.trim().isNotEmpty)
        'cacheMissId': cacheMissId.trim(),
    });

    return CloudDownloadRecordResult.fromMap(result);
  }

  Future<Map<String, dynamic>> _callFunction(
    String functionName,
    Map<String, Object?> data,
  ) async {
    final user = _auth.currentUser;
    final token = await user?.getIdToken();
    if (user == null || token == null || token.isEmpty) {
      throw const CloudUsageServiceException(
        code: 'unauthenticated',
        message: 'Firebase authentication is required.',
      );
    }

    final response = await _client
        .post(
          _functionUri(functionName),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'data': data}),
        )
        .timeout(_timeout);

    final decoded = _decodeResponse(response.body);
    final error = decoded['error'];
    if (error is Map) {
      final normalized = Map<String, dynamic>.from(error);
      throw CloudUsageServiceException(
        code: _normalizeCallableStatus(
          _readString(normalized['status'], fallback: 'unknown'),
        ),
        message: _readString(
          normalized['message'],
          fallback: 'Cloud function failed.',
        ),
        details: normalized['details'],
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CloudUsageServiceException(
        code: 'http_${response.statusCode}',
        message: 'Cloud function HTTP request failed.',
      );
    }

    final result = decoded['result'];
    if (result is Map) {
      return Map<String, dynamic>.from(result);
    }

    throw const CloudUsageServiceException(
      code: 'invalid_response',
      message: 'Cloud function returned an invalid response.',
    );
  }

  Uri _functionUri(String functionName) {
    if (_functionsOriginOverride.trim().isNotEmpty) {
      final origin = _functionsOriginOverride.replaceAll(RegExp(r'/+$'), '');
      return Uri.parse('$origin/$functionName');
    }

    final projectId = _firebaseApp.options.projectId;
    if (projectId.trim().isEmpty) {
      throw const CloudUsageServiceException(
        code: 'project_id_missing',
        message: 'Firebase project id is missing.',
      );
    }

    return Uri.https(
      '$_region-$projectId.cloudfunctions.net',
      '/$functionName',
    );
  }

  Map<String, dynamic> _decodeResponse(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      // Handled by invalid_response below.
    }

    throw const CloudUsageServiceException(
      code: 'invalid_response',
      message: 'Cloud function response was not valid JSON.',
    );
  }

  static String _normalizeCallableStatus(String status) {
    return status.trim().toLowerCase().replaceAll('_', '-');
  }
}

class CloudUploadReservation {
  final String videoId;
  final String storagePath;
  final String thumbnailStoragePath;
  final String reservationId;
  final int? reservationExpiresAt;
  final String uploadStatus;
  final bool reused;

  const CloudUploadReservation({
    required this.videoId,
    required this.storagePath,
    required this.thumbnailStoragePath,
    required this.reservationId,
    required this.reservationExpiresAt,
    required this.uploadStatus,
    required this.reused,
  });

  factory CloudUploadReservation.fromMap(Map<String, dynamic> data) {
    return CloudUploadReservation(
      videoId: _readString(data['videoId']),
      storagePath: _readString(data['storagePath']),
      thumbnailStoragePath: _readString(data['thumbnailStoragePath']),
      reservationId: _readString(data['reservationId']),
      reservationExpiresAt: _readInt(data['reservationExpiresAt']),
      uploadStatus: _readString(data['uploadStatus'], fallback: 'reserved'),
      reused: data['reused'] == true,
    );
  }
}

class CloudUploadCommitResult {
  final String videoId;
  final String status;
  final bool alreadyCommitted;
  final bool storageUsageCommitted;

  const CloudUploadCommitResult({
    required this.videoId,
    required this.status,
    required this.alreadyCommitted,
    required this.storageUsageCommitted,
  });

  factory CloudUploadCommitResult.fromMap(Map<String, dynamic> data) {
    return CloudUploadCommitResult(
      videoId: _readString(data['videoId']),
      status: _readString(data['status'], fallback: 'completed'),
      alreadyCommitted: data['alreadyCommitted'] == true,
      storageUsageCommitted: data['storageUsageCommitted'] == true,
    );
  }
}

class CloudUploadCancelResult {
  final String videoId;
  final String status;
  final int releasedBytes;

  const CloudUploadCancelResult({
    required this.videoId,
    required this.status,
    required this.releasedBytes,
  });

  factory CloudUploadCancelResult.fromMap(Map<String, dynamic> data) {
    return CloudUploadCancelResult(
      videoId: _readString(data['videoId']),
      status: _readString(data['status'], fallback: 'cancelled'),
      releasedBytes: _readInt(data['releasedBytes']) ?? 0,
    );
  }
}

class CloudDownloadRecordResult {
  final String videoId;
  final String eventId;
  final bool recorded;
  final bool duplicate;
  final bool cacheHit;
  final int bytesRecorded;
  final int monthlyDownloadBytes;
  final bool softLimitExceeded;
  final bool hardLimitEnforced;
  final bool hardLimitExceeded;

  const CloudDownloadRecordResult({
    required this.videoId,
    required this.eventId,
    required this.recorded,
    required this.duplicate,
    required this.cacheHit,
    required this.bytesRecorded,
    required this.monthlyDownloadBytes,
    required this.softLimitExceeded,
    required this.hardLimitEnforced,
    required this.hardLimitExceeded,
  });

  factory CloudDownloadRecordResult.fromMap(Map<String, dynamic> data) {
    return CloudDownloadRecordResult(
      videoId: _readString(data['videoId']),
      eventId: _readString(data['eventId']),
      recorded: data['recorded'] == true,
      duplicate: data['duplicate'] == true,
      cacheHit: data['cacheHit'] == true,
      bytesRecorded: _readInt(data['bytesRecorded']) ?? 0,
      monthlyDownloadBytes: _readInt(data['monthlyDownloadBytes']) ?? 0,
      softLimitExceeded: data['softLimitExceeded'] == true,
      hardLimitEnforced: data['hardLimitEnforced'] == true,
      hardLimitExceeded: data['hardLimitExceeded'] == true,
    );
  }
}

class CloudUsageServiceException implements Exception {
  final String code;
  final String message;
  final Object? details;

  const CloudUsageServiceException({
    required this.code,
    required this.message,
    this.details,
  });

  @override
  String toString() => 'CloudUsageServiceException($code): $message';
}

String _readString(Object? value, {String fallback = ''}) {
  if (value == null) return fallback;
  final text = '$value'.trim();
  return text.isEmpty ? fallback : text;
}

int? _readInt(Object? value) {
  if (value is int) return value;
  if (value is num && value.isFinite) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  return null;
}
