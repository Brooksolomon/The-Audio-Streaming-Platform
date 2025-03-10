import 'dart:async';
import 'dart:ui';
import 'package:audiobinge/downloadUtils.dart';
import 'package:audiobinge/downloadsPage.dart';
import 'package:audiobinge/thumbnailUtils.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:youtube_scrape_api/models/thumbnail.dart';
import 'package:youtube_scrape_api/models/video_data.dart';
import 'package:youtube_scrape_api/youtube_scrape_api.dart';

import 'fetchYoutubeStreamUrl.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as ytex;
import 'youtubePage.dart';
import 'favoritePage.dart';
import 'bottomPlayer.dart';
import 'package:just_audio/just_audio.dart';
import 'youtubeAudioStream.dart';
import 'connectivityProvider.dart';
import 'MyVideo.dart';
import 'colors.dart';
import 'videoComponent.dart';
import 'favoriteUtils.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.ryanheise.bg_demo.channel.audio',
    androidNotificationChannelName: 'Audio playback',
    androidNotificationOngoing: true,
  );
  runApp(MultiProvider(providers: [
    ChangeNotifierProvider(create: (_) => LikeNotifier()),
    ChangeNotifierProvider(create: (_) => Playing()),
    ChangeNotifierProvider(create: (_) => NetworkProvider()),
    Provider<DownloadService>(create: (context) => DownloadService()),
  ], child: const MyApp()));
}

class Playing with ChangeNotifier {
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  MyVideo _video = MyVideo();
  List<MyVideo> _queue = [];
  ConcatenatingAudioSource _playlist =
      ConcatenatingAudioSource(children: []); // Initialize playlist
  List<ytex.ClosedCaption> captions = [];
  String currentCaption = "no caption fo this media";

  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  int _isLooping = 0;
  bool _isShuffling = false;
  bool _isloading = false;
  bool _isPlayerVisible = true;

  bool get isloading => _isloading;

  bool get isShuffling => _isShuffling;

  bool get isPlayerVisible => _isPlayerVisible;

  ConcatenatingAudioSource get playlist => _playlist;

  Duration get duration => _duration;

  Duration get position => _position;

  MyVideo get video => _video;

  AudioPlayer get audioPlayer => _audioPlayer;

  bool get isPlaying => _isPlaying;

  List<MyVideo> get queue => _queue;

  int get isLooping => _isLooping;

  Playing() {
    _initAudioPlayer();
  }
  void hidePlayer() {
    _isPlayerVisible = false;
    notifyListeners();
  }

  void showPlayer() {
    _isPlayerVisible = true;
    notifyListeners();
  }

  void setIsPlaying(bool isit) {
    if (isit) {
      play();
    } else {
      pause();
    }
    _isPlaying = isit;
    notifyListeners();
  }

  void _initAudioPlayer() {
    _audioPlayer.durationStream.listen((duration) {
      if (duration != null) {
        _duration = duration;
        notifyListeners();
      }
    });

    _audioPlayer.positionStream.listen((position) {
      _position = position;

      if (captions.isNotEmpty) {
        currentCaption = getCaptionAtTime(captions, position);
      } else {
        currentCaption = "No caption for this media";
      }
      notifyListeners();
    });

    _audioPlayer.playerStateStream.listen((playerState) {
      _isPlaying = playerState.playing;
      notifyListeners();

      if (playerState.processingState == ProcessingState.completed) {
        if (_isLooping == 1) {
          seekAudio(Duration.zero);
          play();
        } else if (_isLooping == 2 && _queue.isNotEmpty) {
          _audioPlayer.seek(Duration.zero, index: 0);
        } else if (_queue.isNotEmpty) {
          next();
        } else {
          _isPlaying = false;
          notifyListeners();
        }
      }
    });

    _audioPlayer.currentIndexStream.listen((index) async {
      if (index != null && index >= 0 && index < _queue.length) {
        _video = _queue[index];
        captions = (await fetchYoutubeClosedCaptions(
            _video.videoId!)); // Sync _video with the current track
        notifyListeners();
      }
    });
  }

  Future<void> toggleShuffle() async {
    _isShuffling = !_isShuffling;
    await _audioPlayer
        .setShuffleModeEnabled(_isShuffling); // Use just_audio's shuffle
    notifyListeners();
  }

  Future<void> toggleLooping() async {
    _isLooping = (_isLooping + 1) % 3;
    if (_isLooping == 0) {
      await _audioPlayer.setLoopMode(LoopMode.off);
    } else if (_isLooping == 1) {
      await _audioPlayer.setLoopMode(LoopMode.one);
    } else if (_isLooping == 2) {
      await _audioPlayer.setLoopMode(LoopMode.all);
    }
    notifyListeners();
  }

  Future<void> assign(MyVideo v, bool clear) async {
    _isloading = true;
    _isPlayerVisible = true;
    await pause();
    notifyListeners();

    if (clear) {
      // Clear and replace the queue if `clear` is true
      _queue.clear();
      AudioSource audioSource = await createAudioSource(v);
      _queue.add(v);
      _playlist = ConcatenatingAudioSource(children: [audioSource]);
      await _audioPlayer.setAudioSource(_playlist);
    } else {
      // Play from existing playlist
      int index = _queue.indexWhere((video) => video.videoId == v.videoId);
      if (index != -1) {
        await _audioPlayer.seek(Duration.zero, index: index);
      } else {
        print("Video not found in the playlist.");
        return;
      }
    }

    _video = v;
    resetPosition();

    _isloading = false;
    notifyListeners();
    await play();
  }

  Future<void> addToQueue(MyVideo v) async {
    if (_queue.isEmpty) {
      print("empty");
      await assign(v, true);
      notifyListeners();
      return;
    }

    _queue.add(v); // Add video to the queue

    AudioSource audioSource = await createAudioSource(v);
    await _playlist.add(audioSource); // Add audio source to the playlist
    notifyListeners();
  }

  Future<void> removeFromQueue(MyVideo video) async {
    final index = _queue.indexOf(video);
    if (index != -1) {
      _queue.removeAt(index); // Remove video from the queue
      await _playlist.removeAt(index); // Remove audio source from the playlist

      // If the removed video was the current video, update _video
      if (_video.videoId == video.videoId) {
        if (_queue.isNotEmpty) {
          _video = _queue[_audioPlayer.currentIndex ?? 0];
        } else {
          _video = MyVideo(); // Reset _video if the queue is empty
        }
      }

      notifyListeners();
    }
  }

  Future<void> clearQueue() async {
    _queue.clear(); // Clear the queue
    _playlist = ConcatenatingAudioSource(children: []); // Clear the playlist
    await _audioPlayer.setAudioSource(_playlist);

    _video = MyVideo(); // Reset _video
    notifyListeners();
  }

  Future<void> setQueue(List<MyVideo> videos) async {
    _isloading = true;
    notifyListeners(); // Notify listeners that loading has started

    await clearQueue(); // Clear the existing queue

    if (videos.isNotEmpty) {
      List<AudioSource> sources = [];

      for (var video in videos) {
        print(video.title ?? "none");
        AudioSource audioSource = await createAudioSource(video);
        _queue.add(video);
        sources.add(audioSource);
      }

      // Assign all sources at once
      _playlist = ConcatenatingAudioSource(children: sources);
      _video = videos.first;
      await _audioPlayer.setAudioSource(_playlist);

      print(_queue);
      print(_playlist);

      await play();
    }

    _isloading = false;
    notifyListeners();
  }

  Future<void> next() async {
    if (_queue.isNotEmpty) {
      _isloading = true;
      notifyListeners();
      await _audioPlayer.seekToNext();
      _isloading = false;
      notifyListeners();
    }
  }

  Future<void> previous() async {
    if (_queue.isNotEmpty) {
      _isloading = true;
      int currentPosition = _position.inSeconds;
      if (currentPosition > 3) {
        await seekAudio(Duration.zero);
      } else {
        await _audioPlayer.seekToPrevious();
      }
      _isloading = false;
      notifyListeners();
    }
  }

  void updateDuration(Duration d) {
    _duration = d;
    notifyListeners();
  }

  void updatePosition(Duration p) {
    _position = p;
    notifyListeners();
  }

  void resetPosition() {
    _position = Duration.zero;
    notifyListeners();
  }

  void resetDuration() {
    _duration = Duration.zero;
    notifyListeners();
  }

  void resetAllDurationAndPosition() {
    _position = Duration.zero;
    notifyListeners();
    _duration = Duration.zero;
    notifyListeners();
  }

  Future<void> streamAudio(String url) async {
    try {
      await _audioPlayer.setAudioSource(AudioSource.uri(Uri.parse(url)));
      await play();
    } catch (e) {
      print('Error streaming audio: $e');
      _isPlaying = false;
      notifyListeners();
    }
  }

  Future<void> pause() async {
    await _audioPlayer.pause();
    _isPlaying = false;
    notifyListeners();
  }

  Future<void> play() async {
    await _audioPlayer.play();
    _isPlaying = true;
    notifyListeners();
  }

  Future<void> stop() async {
    await _audioPlayer.stop();
    _isPlaying = false;
    notifyListeners();
  }

  Future<void> seekAudio(Duration position) async {
    await _audioPlayer.seek(position);
  }

  Future<AudioSource> createAudioSource(MyVideo v) async {
    var local = await isDownloaded(v);
    if (local) {
      return AudioSource.uri(
        Uri.file(v.localaudio!),
        tag: MediaItem(
          id: v.videoId!,
          album: v.channelName,
          title: v.title!,
          artUri: v.thumbnails != null && v.thumbnails!.isNotEmpty
              ? Uri.file(v.localimage!)
              : null,
        ),
      );
    } else {
      var url = "hello";
      if (await isFavorites(v)) {
        url = v.localaudio!;
      } else {
        url = await fetchYoutubeStreamUrl(v.videoId!);
      }
      print('------------------------');
      print(v.videoId);
      print(v.channelName);
      print(v.title);
      print(v.thumbnails);

      return AudioSource.uri(
        Uri.parse(url),
        tag: MediaItem(
          id: v.videoId!,
          album: v.channelName,
          title: v.title!,
          artUri: v.thumbnails != null && v.thumbnails!.isNotEmpty
              ? Uri.parse(v.thumbnails![0].url!)
              : null,
        ),
      );
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }
}

class Thumbnail2 {
  String? url;
  int? width, height;
  Thumbnail2({this.url, this.width, this.height});
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late StreamSubscription _intentSub;
  final _sharedFiles = <SharedMediaFile>[];

  @override
  void initState() {
    super.initState();

    _intentSub = ReceiveSharingIntent.instance.getMediaStream().listen((value) {
      setState(() {
        _sharedFiles.clear();
        _sharedFiles.addAll(value);

        if (_sharedFiles.isNotEmpty) {
          final videoId =
              _sharedFiles.first.path.split('watch?v=').last.split('&').first;
          addSharedVideo(videoId);
        }

        print(_sharedFiles.map((f) => f.toMap()));
      });
    });

    ReceiveSharingIntent.instance.getInitialMedia().then((value) {
      setState(() {
        _sharedFiles.clear();
        _sharedFiles.addAll(value);
        print(_sharedFiles.map((f) => f.toMap()));

        // Tell the library that we are done processing the intent.
        ReceiveSharingIntent.instance.reset();
      });
    });
  }

  Future<void> addSharedVideo(String videoId) async {
    YoutubeDataApi youtubeDataApi = YoutubeDataApi();
    VideoData? sharedVideo = await youtubeDataApi.fetchVideoData(videoId);
    // Thumbnail? highestThumbnail = getHighestQualityThumbnail(sharedVideo!.video.channelThumb);
    print('-------------');
    print('video data: ${sharedVideo!.video?.channelThumb}');

    Provider.of<Playing>(context, listen: false).assign(
        MyVideo(
          videoId: videoId,
          channelName: sharedVideo.video?.channelName,
          title: sharedVideo.video?.title,
          thumbnails: [Thumbnail(url: sharedVideo!.video?.channelThumb)]
        ),
        true);
  }

  @override
  void dispose() {
    _intentSub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.black87,
          brightness: Brightness.dark,
        ).copyWith(
          surface: Colors.black87,
          primary: Colors.black87,
        ),
        useMaterial3: true,
      ),
      home: YouTubeTwitchTabs(),
    );
  }
}

class YouTubeTwitchTabs extends StatefulWidget {
  const YouTubeTwitchTabs({super.key});

  @override
  _YouTubeTwitchTabsState createState() => _YouTubeTwitchTabsState();
}

class _YouTubeTwitchTabsState extends State<YouTubeTwitchTabs> {
  int _selectedIndex = 0;
  final List<Widget> _pages = [
    YoutubeScreen(),
    FavoriteScreen(),
    DownloadScreen()
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final playing = context.watch<Playing>();
    return Scaffold(
      extendBody: true,
      appBar: CustomAppBar(),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.deepPurple.shade800, Colors.black],
          ),
        ),
        child: Stack(
          children: [
            // Main content with fade transition
            AnimatedSwitcher(
              duration: Duration(milliseconds: 300),
              child: _pages[_selectedIndex],
              transitionBuilder: (Widget child, Animation<double> animation) {
                return FadeTransition(
                  opacity: animation,
                  child: child,
                );
              },
            ),

            // BottomPlayer positioned above the bottom navigation
            if (playing.video.title != null && playing.isPlayerVisible)
              Positioned(
                left: 0,
                right: 0,
                bottom: kBottomNavigationBarHeight +
                    5, // Position above the bottom nav
                child: Dismissible(
                  key: Key("bottomPlayer"),
                  direction: DismissDirection.startToEnd,
                  onDismissed: (_) {
                    playing.hidePlayer();
                    playing.stop();
                  },
                  child: BottomPlayer(),
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: ClipRRect(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: Container(
            color: Colors.black.withValues(alpha: 0.5),
            child: BottomNavigationBar(
              currentIndex: _selectedIndex,
              onTap: _onItemTapped,
              backgroundColor: Colors.transparent,
              elevation: 0,
              type: BottomNavigationBarType.fixed,
              selectedItemColor: AppColors.primaryColor,
              unselectedItemColor: Colors.grey,
              selectedLabelStyle: TextStyle(fontWeight: FontWeight.bold),
              unselectedLabelStyle: TextStyle(fontWeight: FontWeight.normal),
              items: const <BottomNavigationBarItem>[
                BottomNavigationBarItem(
                  icon: Icon(Icons.video_library),
                  label: 'YouTube',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.favorite_sharp),
                  label: 'Favorites',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.download_for_offline_rounded),
                  label: 'Downloads',
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Extracted Custom AppBar
class CustomAppBar extends StatelessWidget implements PreferredSizeWidget {
  const CustomAppBar({super.key});

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: Row(
        children: [
          // App Logo
          Image.asset(
            'assets/icon.png',
            height: 40, // Adjusted for better proportions
            width: 40,
          ),
          SizedBox(width: 10), // Spacing between logo and title
          // App Title
          Text(
            "The Audio Streaming Platform",
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
      backgroundColor: Colors.transparent,
      elevation: 0,
      flexibleSpace: Container(),
    );
  }

  @override
  Size get preferredSize => Size.fromHeight(kToolbarHeight);
}
