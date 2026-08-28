import '../core/supabase_client.dart';
import '../core/error_mapper.dart';

class ReportService {
  final _client = SupabaseConfig.client;

  Future<void> reportUser({
    required String reportedUserId,
    required String reasonCategory,
    String? details,
    String? bookingId,
  }) async {
    try {
      await _client.rpc('report_user', params: {
        'p_reported_user_id': reportedUserId,
        'p_reason_category': reasonCategory,
        if (details != null && details.trim().isNotEmpty)
          'p_details': details.trim(),
        if (bookingId != null) 'p_booking_id': bookingId,
      });
    } catch (e) {
      throw Exception(AppErrorMapper.toMessage(e));
    }
  }

  Future<void> blockUser(String targetUserId) async {
    try {
      await _client.rpc('block_user', params: {
        'p_blocked_user_id': targetUserId,
      });
    } catch (e) {
      throw Exception(AppErrorMapper.toMessage(e));
    }
  }

  Future<void> unblockUser(String targetUserId) async {
    await _client.rpc('unblock_user', params: {
      'p_blocked_user_id': targetUserId,
    });
  }

  Future<bool> isBlocked(String targetUserId) async {
    final result = await _client.rpc('is_user_blocked', params: {
      'p_target_user_id': targetUserId,
    });
    return (result is bool) ? result : false;
  }

  Future<Set<String>> getBlockedUserIds() async {
    final result = await _client.rpc('get_blocked_user_ids');
    if (result is List) {
      return result
          .map((row) => row['blocked_user_id'] as String)
          .toSet();
    }
    return {};
  }
}
