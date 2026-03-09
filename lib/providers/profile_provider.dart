import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/profile.dart';
import '../services/profile_service.dart';

// ------------------------------------------------------------------
// Current active profile
// ------------------------------------------------------------------

final activeProfileIdProvider = StateProvider<String?>((ref) => null);

// ------------------------------------------------------------------
// Profiles list
// ------------------------------------------------------------------

final profilesProvider =
    StateNotifierProvider<ProfilesNotifier, AsyncValue<List<Profile>>>(
  (ref) => ProfilesNotifier(),
);

class ProfilesNotifier extends StateNotifier<AsyncValue<List<Profile>>> {
  ProfilesNotifier() : super(const AsyncValue.loading()) {
    load();
  }

  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      final profiles = await ProfileService.loadProfiles();
      state = AsyncValue.data(profiles);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<Profile> add({required String name, required String url}) async {
    final profile = await ProfileService.addProfile(name: name, url: url);
    await load();
    return profile;
  }

  Future<void> update(Profile profile) async {
    await ProfileService.updateProfile(profile);
    await load();
  }

  Future<void> delete(String id) async {
    await ProfileService.deleteProfile(id);
    await load();
  }
}
