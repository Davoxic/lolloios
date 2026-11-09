import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// Rappresenta un singolo brano musicale salvato o in riproduzione.
class MusicTrack {
  final String id;
  final String title;
  final String artist;
  final int durationSeconds;
  final String thumbnailUrl;

  const MusicTrack({
    required this.id,
    required this.title,
    required this.artist,
    required this.durationSeconds,
    required this.thumbnailUrl,
  });

  Duration get duration => Duration(seconds: durationSeconds);

  factory MusicTrack.fromJson(Map<String, dynamic> json) {
    return MusicTrack(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      artist: json['artist'] as String? ?? '',
      durationSeconds: (json['durationSeconds'] as num?)?.toInt() ?? 0,
      thumbnailUrl: json['thumbnailUrl'] as String? ?? '',
    );
  }

  factory MusicTrack.fromVideo(Video video) {
    return MusicTrack(
      id: video.id.value,
      title: video.title,
      artist: video.author,
      durationSeconds: video.duration?.inSeconds ?? 0,
      thumbnailUrl: video.thumbnails.highResUrl,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'artist': artist,
      'durationSeconds': durationSeconds,
      'thumbnailUrl': thumbnailUrl,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MusicTrack && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// Rappresenta una playlist creata dall'utente contenente una lista di brani.
class MusicPlaylist {
  final String id;
  String name;
  final List<MusicTrack> tracks;

  MusicPlaylist({
    required this.id,
    required this.name,
    List<MusicTrack>? tracks,
  }) : tracks = tracks ?? [];

  factory MusicPlaylist.fromJson(Map<String, dynamic> json) {
    final rawTracks = json['tracks'] as List<dynamic>? ?? [];
    return MusicPlaylist(
      id: json['id'] as String? ?? const Uuid().v4(),
      name: json['name'] as String? ?? 'Playlist',
      tracks: rawTracks
          .map((t) => MusicTrack.fromJson(t as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'tracks': tracks.map((t) => t.toJson()).toList(),
    };
  }
}

/// Gestore della libreria musicale e persistenza tramite SharedPreferences.
class MusicLibrary {
  static const String storageKey = 'music_library_playlists_v1';
  final List<MusicPlaylist> playlists = [];

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(storageKey);
      playlists.clear();
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as List<dynamic>;
        for (final item in decoded) {
          playlists.add(MusicPlaylist.fromJson(item as Map<String, dynamic>));
        }
      }
    } catch (e) {
      // Continua con lista vuota o preesistente
    }
  }

  Future<void> save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(playlists.map((p) => p.toJson()).toList());
      await prefs.setString(storageKey, encoded);
    } catch (_) {}
  }

  MusicPlaylist createPlaylist(String name) {
    final cleanName = name.trim().isEmpty ? 'Nuova playlist' : name.trim();
    final p = MusicPlaylist(
      id: const Uuid().v4(),
      name: cleanName,
    );
    playlists.add(p);
    return p;
  }

  void deletePlaylist(String playlistId) {
    playlists.removeWhere((p) => p.id == playlistId);
  }

  void addTrack(String playlistId, MusicTrack track) {
    final index = playlists.indexWhere((p) => p.id == playlistId);
    if (index != -1) {
      playlists[index].tracks.add(track);
    }
  }

  void removeTrack(String playlistId, int trackIndex) {
    final index = playlists.indexWhere((p) => p.id == playlistId);
    if (index != -1 &&
        trackIndex >= 0 &&
        trackIndex < playlists[index].tracks.length) {
      playlists[index].tracks.removeAt(trackIndex);
    }
  }
}
