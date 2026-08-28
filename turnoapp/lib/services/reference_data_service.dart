import 'package:flutter/foundation.dart';

import '../core/supabase_client.dart';
import '../core/constants.dart';

class ReferenceDataService {
  final _client = SupabaseConfig.client;

  bool _lastCallUsedFallback = false;
  bool get lastCallUsedFallback => _lastCallUsedFallback;

  Future<List<Map<String, dynamic>>> getUniversities() async {
    _lastCallUsedFallback = false;
    try {
      final rows = await _client
          .from('universities')
          .select('id, code, name')
          .order('name')
          .limit(100);
      final normalized = _normalizeRows(rows);
      if (normalized.isNotEmpty) {
        return normalized;
      }
    } catch (e) {
      debugPrint('[Turno] ReferenceData: getUniversities fallback: $e');
    }

    _lastCallUsedFallback = true;

    return AppConstants.universitiesWithIds
        .map((u) => Map<String, dynamic>.from(u))
        .toList();
  }

  Future<Map<String, dynamic>?> getUniversityById(String universityId) async {
    try {
      final row = await _client
          .from('universities')
          .select('id, code, name')
          .eq('id', universityId)
          .maybeSingle();
      if (row != null) {
        _lastCallUsedFallback = false;
        return Map<String, dynamic>.from(row);
      }
    } catch (e) {
      debugPrint('[Turno] ReferenceData: getUniversities fallback: $e');
    }

    _lastCallUsedFallback = true;
    final local = AppConstants.universitiesWithIds
        .where((u) => u['id'] == universityId)
        .cast<Map<String, String>>()
        .toList();
    if (local.isEmpty) return null;
    return Map<String, dynamic>.from(local.first);
  }

  Future<List<Map<String, dynamic>>> getCampusesByUniversity(
    String universityId,
  ) async {
    _lastCallUsedFallback = false;
    try {
      final rows = await _client
          .from('campuses')
          .select('id, name')
          .eq('university_id', universityId)
          .order('name')
          .limit(200);
      final normalized = _normalizeRows(rows);
      if (normalized.isNotEmpty) {
        return normalized;
      }
    } catch (e) {
      debugPrint('[Turno] ReferenceData: getUniversities fallback: $e');
    }

    _lastCallUsedFallback = true;

    final local = AppConstants.campusesWithIds
        .where((campus) => campus['university_id'] == universityId)
        .toList();
    local.sort((a, b) =>
        (a['name'] ?? '').toString().compareTo((b['name'] ?? '').toString()));

    return local
        .map((campus) => {
              'id': campus['id'],
              'name': campus['name'],
            })
        .cast<Map<String, dynamic>>()
        .toList();
  }

  List<Map<String, dynamic>> _campusFallbackSorted() {
    final list = AppConstants.campusesWithIds
        .map((e) => Map<String, String>.from(e))
        .toList();
    list.sort((a, b) =>
        (a['name'] ?? '').toString().compareTo((b['name'] ?? '').toString()));
    return list.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<List<Map<String, dynamic>>> getCampusesWithUniversity() async {
    _lastCallUsedFallback = false;
    try {
      final rows = await _client
          .from('campuses')
          .select('id, name, universities!university_id(name)')
          .order('name')
          .limit(300);
      final normalized = _normalizeRows(rows);
      if (normalized.isNotEmpty) {
        return normalized;
      }
    } catch (e) {
      debugPrint('[Turno] ReferenceData: getUniversities fallback: $e');
    }

    _lastCallUsedFallback = true;

    return _campusFallbackSorted()
        .map((campus) => {
              'id': campus['id'],
              'name': campus['name'],
              'universities': {
                'name': campus['university_name'],
              },
            })
        .cast<Map<String, dynamic>>()
        .toList();
  }

  List<Map<String, dynamic>> _normalizeRows(dynamic rows) {
    if (rows is List) {
      return rows
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
    }
    return const <Map<String, dynamic>>[];
  }
}
