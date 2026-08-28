import '../core/supabase_client.dart';
import '../core/error_mapper.dart';
import '../models/user_review.dart';

class ReviewService {
  final _client = SupabaseConfig.client;

  Future<void> submitReview({
    required String bookingId,
    required int stars,
    String? comment,
  }) async {
    try {
      await _client.rpc('submit_booking_review', params: {
        'p_booking_id': bookingId,
        'p_stars': stars,
        'p_comment': comment,
      });
    } catch (e) {
      throw Exception(AppErrorMapper.toMessage(e));
    }
  }

  Future<List<UserReview>> getPublicUserReviews(
    String userId, {
    int limit = 5,
  }) async {
    try {
      final rows = await _client.rpc('get_public_user_reviews', params: {
        'p_user_id': userId,
        'p_limit': limit,
      });
      if (rows is! List) return const [];
      return rows
          .map((e) => UserReview.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      throw Exception(AppErrorMapper.toMessage(e));
    }
  }

  Future<bool> hasReviewForBooking(String bookingId) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return false;

    final row = await _client
        .from('booking_reviews')
        .select('id')
        .eq('booking_id', bookingId)
        .eq('reviewer_id', uid)
        .maybeSingle();
    return row != null;
  }
}
