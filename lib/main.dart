import 'dart:async';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'music_library.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.example.musicplayer.playback',
      androidNotificationChannelName: 'Riproduzione musica',
      androidNotificationOngoing: true,
      androidNotificationIcon: 'mipmap/ic_launcher',
    );
  } catch (e) {
    debugPrint('JustAudioBackground init: $e');
  }

  runApp(const MusicPlayerApp());
}

class MusicPlayerApp extends StatelessWidget {
  const MusicPlayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lollo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFF121212),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF1DB954),
          surface: Color(0xFF1E1E1E),
          onSurface: Colors.white,
          secondary: Color(0xFF00E676),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF121212),
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
      home: const PlayerHomePage(),
    );
  }
}

enum _Page {
  playlists,
  playlistDetail,
  search,
}

class PlayerHomePage extends StatefulWidget {
  const PlayerHomePage({super.key});

  @override
  State<PlayerHomePage> createState() => _PlayerHomePageState();
}

class _PlayerHomePageState extends State<PlayerHomePage> {
  final MusicLibrary _library = MusicLibrary();
  final AudioPlayer _player = AudioPlayer();
  YoutubeExplode _yt = YoutubeExplode();

  void _resetYt() {
    try {
      _yt.close();
    } catch (_) {}
    _yt = YoutubeExplode();
  }

  _Page _currentPage = _Page.playlists;
  MusicPlaylist? _selectedPlaylist;

  final TextEditingController _searchController = TextEditingController();
  List<MusicTrack> _searchResults = [];
  bool _isSearching = false;
  bool _isLoadingLibrary = true;

  MusicTrack? _currentTrack;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;
  bool _isShuffle = false;

  @override
  void initState() {
    super.initState();
    _initPlayerListeners();
    _loadLibrary();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _player.dispose();
    _yt.close();
    super.dispose();
  }

  void _initPlayerListeners() {
    _player.playerStateStream.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state.playing;
        });
      }
    });

    _player.positionStream.listen((pos) {
      if (mounted) {
        setState(() {
          _position = pos;
        });
      }
    });

    _player.durationStream.listen((dur) {
      if (mounted && dur != null) {
        setState(() {
          _duration = dur;
        });
      }
    });

    _player.shuffleModeEnabledStream.listen((enabled) {
      if (mounted) {
        setState(() {
          _isShuffle = enabled;
        });
      }
    });

    _player.sequenceStateStream.listen((sequenceState) {
      if (sequenceState == null) return;
      final currentSource = sequenceState.currentSource;
      final tag = currentSource?.tag;
      if (tag is MediaItem) {
        if (mounted) {
          setState(() {
            _currentTrack = MusicTrack(
              id: tag.id,
              title: tag.title,
              artist: tag.artist ?? '',
              durationSeconds: tag.duration?.inSeconds ?? 0,
              thumbnailUrl: tag.artUri?.toString() ?? '',
            );
          });
        }
      }
    });

    _player.playbackEventStream.listen(
      (_) {},
      onError: (Object e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Errore del player: $e')),
          );
        }
      },
    );
  }

  Future<void> _loadLibrary() async {
    try {
      await _library.load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Non riesco a caricare le playlist: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingLibrary = false;
        });
      }
    }
  }

  Future<void> _persistPlaylists() async {
    await _library.save();
    if (mounted) setState(() {});
  }

  void _showPlaylists() {
    setState(() {
      _currentPage = _Page.playlists;
    });
  }

  void _openSearch() {
    setState(() {
      _currentPage = _Page.search;
    });
  }

  MusicTrack _toTrack(Video video) {
    return MusicTrack.fromVideo(video);
  }

  /// Risolve lo stream audio rigorosamente in formato MP4 / AAC per Apple AVPlayer su iOS.
  /// AVPlayer NON supporta WebM/Opus, quindi se audioOnly ha solo WebM, ricorre al flusso MP4 muxed.
  Future<String?> _resolveAudioStreamUrl(String videoId) async {
    final cleanId = videoId.replaceFirst('yt_', '').trim();
    if (cleanId.isEmpty) return null;

    // Helper per estrarre lo stream MP4/AAC con il bitrate più alto
    String? pickMp4Stream(StreamManifest manifest) {
      // 1. Cerca prima in audioOnly stream con codec AAC/MP4
      final mp4Audio = manifest.audioOnly.where((s) {
        final container = s.container.name.toLowerCase();
        final mime = s.codec.mimeType.toLowerCase();
        return container.contains('mp4') ||
            mime.contains('mp4') ||
            mime.contains('aac') ||
            mime.contains('m4a');
      }).toList();

      if (mp4Audio.isNotEmpty) {
        return mp4Audio.withHighestBitrate().url.toString();
      }

      // 2. Se in audioOnly ci sono solo stream WebM/Opus (incompatibili con iOS AVPlayer),
      // usiamo il flusso MP4 muxed (video+audio AAC), da cui AVPlayer suona l'audio nativamente!
      final mp4Muxed = manifest.muxed.where((s) {
        final container = s.container.name.toLowerCase();
        return container.contains('mp4');
      }).toList();

      if (mp4Muxed.isNotEmpty) {
        return mp4Muxed.withHighestBitrate().url.toString();
      }

      return null;
    }

    // Tentativo 1: con ytClients iOS e AndroidVR
    try {
      final manifest = await _yt.videos.streamsClient.getManifest(
        cleanId,
        ytClients: [
          YoutubeApiClient.ios,
          YoutubeApiClient.androidVr,
        ],
      ).timeout(const Duration(seconds: 10));

      final url = pickMp4Stream(manifest);
      if (url != null) return url;
    } catch (e) {
      debugPrint('Tentativo primario ytClients fallito ($e), provo standard...');
    }

    // Tentativo 2: getManifest standard
    try {
      final manifest = await _yt.videos.streamsClient
          .getManifest(cleanId)
          .timeout(const Duration(seconds: 8));

      final url = pickMp4Stream(manifest);
      if (url != null) return url;
    } catch (e) {
      debugPrint('Tentativo secondario standard fallito ($e), reset client...');
      _resetYt();
    }

    // Tentativo 3: client fresco
    try {
      _resetYt();
      final manifest = await _yt.videos.streamsClient.getManifest(cleanId);
      final url = pickMp4Stream(manifest);
      if (url != null) return url;
    } catch (e) {
      debugPrint('Tentativo terziario finale fallito: $e');
    }

    return null;
  }

  /// Crea una sorgente audio adatta a iOS: usa la cache locale se presente o l'URL diretto senza headers
  Future<AudioSource> _createAudioSource(
    String videoId,
    String streamUrl,
    MediaItem mediaItem,
  ) async {
    final cleanId = videoId.replaceFirst('yt_', '').trim();
    final cacheFile = File('${Directory.systemTemp.path}/$cleanId.m4a');
    if (await cacheFile.exists() && await cacheFile.length() > 50000) {
      return AudioSource.file(cacheFile.path, tag: mediaItem);
    }
    // Niente headers per evitare che just_audio crei un server proxy localhost su iOS
    return AudioSource.uri(Uri.parse(streamUrl), tag: mediaItem);
  }

  Future<void> _playSingleTrack(MusicTrack track) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text('Preparo ${track.title}...'),
        duration: const Duration(seconds: 2),
      ),
    );

    final streamUrl = await _resolveAudioStreamUrl(track.id);
    if (streamUrl == null) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('${track.title}: nessuno stream audio disponibile'),
          ),
        );
      }
      return;
    }

    final mediaItem = MediaItem(
      id: track.id,
      album: 'Lollo',
      title: track.title,
      artist: track.artist,
      artUri: track.thumbnailUrl.isNotEmpty
          ? Uri.tryParse(track.thumbnailUrl)
          : null,
      duration: track.duration > Duration.zero ? track.duration : null,
    );

    try {
      final source = await _createAudioSource(track.id, streamUrl, mediaItem);
      await _player.setAudioSource(source);
      await _player.play();
    } catch (e) {
      debugPrint('Errore streaming diretto ($e), provo download e cache locale per iOS...');
      try {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Caricamento rapido ${track.title}...'),
            duration: const Duration(seconds: 3),
          ),
        );

        final cleanId = track.id.replaceFirst('yt_', '').trim();
        final cacheFile = File('${Directory.systemTemp.path}/$cleanId.m4a');
        final client = http.Client();
        try {
          final req = http.Request('GET', Uri.parse(streamUrl));
          req.headers['User-Agent'] =
              'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15';
          final resp = await client.send(req);
          final sink = cacheFile.openWrite();
          await resp.stream.pipe(sink);
          await sink.flush();
          await sink.close();
        } finally {
          client.close();
        }

        if (await cacheFile.exists() && await cacheFile.length() > 50000) {
          final fileSource = AudioSource.file(cacheFile.path, tag: mediaItem);
          await _player.setAudioSource(fileSource);
          await _player.play();
        } else {
          throw Exception('File audio non riproducibile');
        }
      } catch (inner) {
        if (mounted) {
          messenger.showSnackBar(
            SnackBar(content: Text('Errore del player: $inner')),
          );
        }
        return;
      }
    }

    if (mounted) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Avviata la riproduzione: ${track.title}'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _playPlaylist(
    MusicPlaylist playlist, {
    bool shuffle = false,
    int initialIndex = 0,
  }) async {
    if (playlist.tracks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Questa playlist non contiene brani.')),
      );
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    final total = playlist.tracks.length;
    final List<AudioSource> audioSources = [];

    int readyCount = 0;
    int targetIndex = 0;

    for (int i = 0; i < total; i++) {
      final t = playlist.tracks[i];
      messenger.removeCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text('Preparo i brani ($readyCount/$total)...'),
          duration: const Duration(seconds: 1),
        ),
      );

      final streamUrl = await _resolveAudioStreamUrl(t.id);
      if (streamUrl != null) {
        if (i == initialIndex) {
          targetIndex = audioSources.length;
        }
        final mediaItem = MediaItem(
          id: t.id,
          album: playlist.name,
          title: t.title,
          artist: t.artist,
          artUri: t.thumbnailUrl.isNotEmpty
              ? Uri.tryParse(t.thumbnailUrl)
              : null,
          duration: t.duration > Duration.zero ? t.duration : null,
        );

        final source = await _createAudioSource(t.id, streamUrl, mediaItem);
        audioSources.add(source);
        readyCount++;
      } else {
        debugPrint('${t.title}: nessuno stream audio disponibile');
      }
    }

    if (audioSources.isEmpty) {
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Nessun brano riproducibile.')),
        );
      }
      return;
    }

    try {
      final playlistSource = ConcatenatingAudioSource(children: audioSources);
      await _player.setAudioSource(
        playlistSource,
        initialIndex: shuffle ? 0 : targetIndex,
      );
      if (shuffle) {
        await _player.setShuffleModeEnabled(true);
        await _player.shuffle();
      } else {
        await _player.setShuffleModeEnabled(false);
      }
      await _player.play();

      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Avviata la riproduzione: ${playlist.name}'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Errore del player: $e')),
        );
      }
    }
  }

  void _toggleShuffle() async {
    final nextMode = !_isShuffle;
    await _player.setShuffleModeEnabled(nextMode);
    if (nextMode) {
      await _player.shuffle();
    }
  }

  Future<void> _search(String query) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return;

    setState(() {
      _isSearching = true;
      _searchResults = [];
    });

    try {
      final results = await _yt.search.search(cleanQuery);
      final tracks = <MusicTrack>[];
      for (final item in results) {
        tracks.add(_toTrack(item));
      }
      if (mounted) {
        setState(() {
          _searchResults = tracks;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ricerca non riuscita: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSearching = false;
        });
      }
    }
  }

  void _createPlaylist() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF242424),
        title: const Text('Nuova playlist'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Nome playlist',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annulla'),
          ),
          ElevatedButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                final p = _library.createPlaylist(name);
                _persistPlaylists();
                Navigator.pop(ctx);
                setState(() {
                  _selectedPlaylist = p;
                  _currentPage = _Page.playlistDetail;
                });
              }
            },
            child: const Text('Crea'),
          ),
        ],
      ),
    );
  }

  void _deleteSelectedPlaylist() {
    if (_selectedPlaylist == null) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF242424),
        title: const Text('Elimina playlist'),
        content: const Text('Eliminare la playlist?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annulla'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              final id = _selectedPlaylist!.id;
              _library.deletePlaylist(id);
              _persistPlaylists();
              Navigator.pop(ctx);
              setState(() {
                _selectedPlaylist = null;
                _currentPage = _Page.playlists;
              });
            },
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
  }

  void _addToPlaylist(MusicTrack track) {
    if (_library.playlists.isEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF242424),
          title: const Text('Aggiungi a playlist'),
          content: const Text('Crea una playlist per iniziare.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annulla'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                _createPlaylist();
              },
              child: const Text('Crea playlist'),
            ),
          ],
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'Scegli dove salvare questo brano',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _library.playlists.length,
                itemBuilder: (ctx, i) {
                  final p = _library.playlists[i];
                  return ListTile(
                    leading: _PlaylistArtwork(playlist: p, size: 44),
                    title: Text(p.name),
                    subtitle: Text('${p.tracks.length} brani'),
                    onTap: () {
                      _insertTrack(p, track);
                      Navigator.pop(ctx);
                    },
                  );
                },
              ),
            ),
            ListTile(
              leading: const Icon(Icons.add, color: Color(0xFF1DB954)),
              title: const Text('Nuova playlist'),
              onTap: () {
                Navigator.pop(ctx);
                _createPlaylist();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _insertTrack(MusicPlaylist playlist, MusicTrack track) {
    _library.addTrack(playlist.id, track);
    _persistPlaylists();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Aggiunto a ${playlist.name}'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _removeTrack(MusicPlaylist playlist, int index) {
    _library.removeTrack(playlist.id, index);
    _persistPlaylists();
  }

  String _format(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: _buildCurrentPage()),
            if (_currentTrack != null) _NowPlayingPanel(state: this),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF181818),
        border: Border(top: BorderSide(color: Color(0xFF282828), width: 0.5)),
      ),
      child: BottomNavigationBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        selectedItemColor: const Color(0xFF1DB954),
        unselectedItemColor: Colors.grey,
        currentIndex: _currentPage == _Page.search ? 1 : 0,
        onTap: (index) {
          if (index == 0) {
            _showPlaylists();
          } else {
            _openSearch();
          }
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.queue_music),
            label: 'Le tue playlist',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.search),
            label: 'Cerca',
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentPage() {
    if (_isLoadingLibrary) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF1DB954)),
      );
    }

    switch (_currentPage) {
      case _Page.playlists:
        return _buildPlaylistList();
      case _Page.playlistDetail:
        return _buildPlaylistDetail();
      case _Page.search:
        return _buildSearchPage();
    }
  }

  Widget _buildPlaylistList() {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Le tue playlist'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Cerca musica',
            onPressed: _openSearch,
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Crea playlist',
            onPressed: _createPlaylist,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF1DB954),
        foregroundColor: Colors.white,
        tooltip: 'Crea playlist',
        onPressed: _createPlaylist,
        child: const Icon(Icons.add),
      ),
      body: _library.playlists.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.library_music, size: 72, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text(
                    'Crea una playlist per iniziare.',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1DB954),
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _createPlaylist,
                    icon: const Icon(Icons.add),
                    label: const Text('Crea playlist'),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 80, top: 8),
              itemCount: _library.playlists.length,
              itemBuilder: (context, index) {
                final p = _library.playlists[index];
                return ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  leading: _PlaylistArtwork(playlist: p, size: 54),
                  title: Text(
                    p.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  subtitle: Text(
                    '${p.tracks.length} brani',
                    style: const TextStyle(color: Colors.grey),
                  ),
                  trailing: const Icon(
                    CupertinoIcons.chevron_right,
                    color: Colors.grey,
                    size: 18,
                  ),
                  onTap: () {
                    setState(() {
                      _selectedPlaylist = p;
                      _currentPage = _Page.playlistDetail;
                    });
                  },
                );
              },
            ),
    );
  }

  Widget _buildPlaylistDetail() {
    final playlist = _selectedPlaylist;
    if (playlist == null) {
      return Center(
        child: ElevatedButton(
          onPressed: _showPlaylists,
          child: const Text('Tutte le playlist'),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(CupertinoIcons.back),
          onPressed: _showPlaylists,
        ),
        title: Text(playlist.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            tooltip: 'Elimina playlist',
            onPressed: _deleteSelectedPlaylist,
          ),
        ],
      ),
      body: Column(
        children: [
          // Header info
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                _PlaylistArtwork(playlist: playlist, size: 100),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        playlist.name,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${playlist.tracks.length} brani',
                        style: const TextStyle(color: Colors.grey, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Action Buttons
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1DB954),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () => _playPlaylist(playlist),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Riproduci playlist'),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF282828),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        vertical: 12, horizontal: 16),
                  ),
                  onPressed: () => _playPlaylist(playlist, shuffle: true),
                  child: const Icon(Icons.shuffle),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Divider(color: Color(0xFF282828)),
          // Track list
          Expanded(
            child: playlist.tracks.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.music_off, size: 64, color: Colors.grey),
                        const SizedBox(height: 12),
                        const Text(
                          'Questa playlist non contiene brani.',
                          style: TextStyle(color: Colors.grey, fontSize: 16),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Cerca un brano e aggiungilo a una playlist.',
                          style: TextStyle(color: Colors.grey, fontSize: 13),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1DB954),
                            foregroundColor: Colors.white,
                          ),
                          onPressed: _openSearch,
                          icon: const Icon(Icons.search),
                          label: const Text('Cerca brani'),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 80),
                    itemCount: playlist.tracks.length,
                    itemBuilder: (context, index) {
                      final track = playlist.tracks[index];
                      return ListTile(
                        leading: _TrackArtwork(track: track, size: 48),
                        title: Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          '${track.artist} • ${_format(track.duration)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.grey),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline,
                              color: Colors.grey, size: 20),
                          tooltip: 'Rimuovi dalla playlist',
                          onPressed: () => _removeTrack(playlist, index),
                        ),
                        onTap: () {
                          _playPlaylist(playlist, initialIndex: index);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchPage() {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          autofocus: false,
          textInputAction: TextInputAction.search,
          onSubmitted: _search,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Cerca brani su YouTube',
            hintStyle: const TextStyle(color: Colors.grey),
            prefixIcon: const Icon(Icons.search, color: Colors.grey),
            suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, color: Colors.grey),
                    onPressed: () {
                      _searchController.clear();
                      setState(() {
                        _searchResults = [];
                      });
                    },
                  )
                : null,
            filled: true,
            fillColor: const Color(0xFF282828),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(24),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ),
      body: _isSearching
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF1DB954)),
            )
          : _searchResults.isEmpty
              ? Center(
                  child: Text(
                    _searchController.text.trim().isEmpty
                        ? 'Cerca musica'
                        : 'Nessun risultato.',
                    style: const TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 80),
                  itemCount: _searchResults.length,
                  itemBuilder: (context, index) {
                    final track = _searchResults[index];
                    return ListTile(
                      leading: _TrackArtwork(track: track, size: 50),
                      title: Text(
                        track.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        '${track.artist} • ${_format(track.duration)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.play_circle_outline,
                                color: Color(0xFF1DB954), size: 28),
                            tooltip: 'Riproduci',
                            onPressed: () => _playSingleTrack(track),
                          ),
                          IconButton(
                            icon: const Icon(Icons.playlist_add,
                                color: Colors.white, size: 26),
                            tooltip: 'Aggiungi a playlist',
                            onPressed: () => _addToPlaylist(track),
                          ),
                        ],
                      ),
                      onTap: () => _playSingleTrack(track),
                    );
                  },
                ),
    );
  }
}

class _TrackArtwork extends StatelessWidget {
  final MusicTrack track;
  final double size;

  const _TrackArtwork({
    required this.track,
    this.size = 50,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: size,
        height: size,
        color: const Color(0xFF282828),
        child: track.thumbnailUrl.isNotEmpty
            ? Image.network(
                track.thumbnailUrl,
                fit: BoxFit.cover,
                errorBuilder: (ctx, err, stack) =>
                    Icon(Icons.music_note, color: Colors.grey, size: size * 0.5),
              )
            : Icon(Icons.music_note, color: Colors.grey, size: size * 0.5),
      ),
    );
  }
}

class _PlaylistArtwork extends StatelessWidget {
  final MusicPlaylist playlist;
  final double size;

  const _PlaylistArtwork({
    required this.playlist,
    this.size = 54,
  });

  @override
  Widget build(BuildContext context) {
    if (playlist.tracks.isNotEmpty &&
        playlist.tracks.first.thumbnailUrl.isNotEmpty) {
      return _TrackArtwork(track: playlist.tracks.first, size: size);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: size,
        height: size,
        color: const Color(0xFF282828),
        child: Icon(Icons.queue_music, color: Colors.grey, size: size * 0.5),
      ),
    );
  }
}

class _NowPlayingPanel extends StatelessWidget {
  final _PlayerHomePageState state;

  const _NowPlayingPanel({required this.state});

  @override
  Widget build(BuildContext context) {
    final track = state._currentTrack;
    if (track == null) return const SizedBox.shrink();

    final pos = state._position;
    final dur = state._duration;
    final maxMs = dur.inMilliseconds.toDouble();
    final curMs = pos.inMilliseconds.toDouble().clamp(0.0, maxMs > 0 ? maxMs : 1.0);

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF202020),
        border: Border(top: BorderSide(color: Color(0xFF333333), width: 0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Slider
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2.5,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              activeTrackColor: const Color(0xFF1DB954),
              inactiveTrackColor: Colors.grey.shade800,
              thumbColor: Colors.white,
            ),
            child: Slider(
              value: curMs,
              max: maxMs > 0 ? maxMs : 1.0,
              onChanged: (val) {
                state._player.seek(Duration(milliseconds: val.toInt()));
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                _TrackArtwork(track: track, size: 48),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        track.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(
                    state._isShuffle ? Icons.shuffle_on_outlined : Icons.shuffle,
                    color: state._isShuffle
                        ? const Color(0xFF1DB954)
                        : Colors.grey,
                  ),
                  tooltip: 'Riproduci in shuffle',
                  onPressed: state._toggleShuffle,
                ),
                IconButton(
                  icon: const Icon(Icons.skip_previous, color: Colors.white),
                  tooltip: 'Brano precedente',
                  onPressed: () => state._player.seekToPrevious(),
                ),
                IconButton(
                  icon: Icon(
                    state._isPlaying
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_filled,
                    color: Colors.white,
                    size: 38,
                  ),
                  tooltip: state._isPlaying ? 'Pausa' : 'Riproduci',
                  onPressed: () {
                    if (state._isPlaying) {
                      state._player.pause();
                    } else {
                      state._player.play();
                    }
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.skip_next, color: Colors.white),
                  tooltip: 'Brano successivo',
                  onPressed: () => state._player.seekToNext(),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  state._format(pos),
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
                Text(
                  state._format(dur),
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
