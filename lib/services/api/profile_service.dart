import '../api/base_client.dart';
import '../api/api_constants.dart';
import '../../models/profile_data.dart';
import '../../locator.dart';
import 'auth_service.dart';
export '../../models/profile_data.dart';

class ProfileService {
  final BaseClient _client = BaseClient();

  /// Get user profile from API
  Future<Map<String, dynamic>> getProfile() async {
    bool isTransientTransportError(Object error) {
      final msg = error.toString().toLowerCase();
      return msg.contains('connection closed before full header') ||
          msg.contains('clientexception') ||
          msg.contains('socketexception') ||
          msg.contains('transport_error');
    }

    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        return await _client.get(ApiConstants.profileEndpoint);
      } catch (e) {
        lastError = e;
        if (!isTransientTransportError(e) || attempt == 2) {
          break;
        }
        await Future.delayed(Duration(milliseconds: 350 * (attempt + 1)));
      }
    }

    final cachedUser = getIt<AuthService>().getUser();
    if (cachedUser != null) {
      return {
        'status': 200,
        'message': 'cached_profile_fallback',
        'data': cachedUser,
      };
    }

    throw lastError ?? Exception('Failed to load profile');
  }

  /// Get full profile data with all fields
  Future<ProfileData?> getProfileData() async {
    try {
      final response = await getProfile();
      if (response['data'] != null) {
        return ProfileData.fromJson(response['data']);
      }
      return null;
    } catch (e) {
      throw Exception('Failed to load profile: $e');
    }
  }
}
