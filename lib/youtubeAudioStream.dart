import 'fetchYoutubeStreamUrl.dart';
import 'package:flutter/material.dart';
import 'main.dart';
import 'package:provider/provider.dart';
import 'dart:ui';
import 'favoriteUtils.dart';
import 'package:youtube_scrape_api/models/video.dart';

// LikeNotifier provider
class LikeNotifier extends ChangeNotifier {
  bool _isLiked = false;
  Video? _currentVideo;

  bool get isLiked => _isLiked;

  void setVideo(Video video) async {
    _currentVideo = video;
    _isLiked = await isFavorites(video);
    notifyListeners();
  }

  void toggleLike() {
    _isLiked = !_isLiked;
    if (_isLiked) {
      saveToFavorites(_currentVideo!);
    } else {
      removeFavorites(_currentVideo!);
    }
    notifyListeners();
  }
}

class YoutubeAudioPlayer extends StatefulWidget {
  final String videoId;
  YoutubeAudioPlayer({required this.videoId});

  @override
  _YoutubeAudioPlayerState createState() => _YoutubeAudioPlayerState();
}

class _YoutubeAudioPlayerState extends State<YoutubeAudioPlayer> {
  bool _isInPlaylist = false; // Track playlist state
  bool _showLyrics = false; // Track lyrics visibility

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final playing = context.read<Playing>();
      context.read<LikeNotifier>().setVideo(playing.video);
    });
  }

  @override
  Widget build(BuildContext context) {
    final playing = context.watch<Playing>();
    final likeNotifier = context.watch<LikeNotifier>(); // Watch the LikeNotifier

    // Set the current video in LikeNotifier
    likeNotifier.setVideo(playing.video);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white),
          onPressed: () {
            Navigator.pop(context); // Close the player
          },
        ),
        title: const Text('Now Playing'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.queue_music, color: Colors.white),
            onPressed: () {
              _showQueue(context, playing);
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          // Blurred Background
          Positioned.fill(
            child: Image.network(
              playing.video.thumbnails![0].url!,
              fit: BoxFit.cover,
            ),
          ),
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                color: Colors.black.withOpacity(0.5),
              ),
            ),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Album Art
              Container(
                height: 280,
                width: 280,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 10,
                      spreadRadius: 2,
                      offset: Offset(0, 4),
                    )
                  ],
                  image: DecorationImage(
                    image: NetworkImage(playing.video.thumbnails![0].url!),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              SizedBox(height: 30),
              // Song Title & Channel
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      playing.video.title!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 24.0,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 1.2),
                    ),
                    SizedBox(height: 6),
                    Text(
                      playing.video.channelName!,
                      style: TextStyle(
                          fontSize: 16.0,
                          color: Colors.white70),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 20),
              // Like, Add to Playlist, and Lyrics Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Consumer<LikeNotifier>(
                      builder: (context, likeNotifier, child) {
                        return _animatedButton(
                          likeNotifier.isLiked ? Icons.favorite : Icons.favorite_border,
                              () {
                            likeNotifier.toggleLike();
                          },
                          28,
                          color: likeNotifier.isLiked ? Colors.red : Colors.white,
                        );
                      }) ,
                  SizedBox(width: 20),
                  _animatedButton(
                    _isInPlaylist ? Icons.playlist_add_check : Icons.playlist_add,
                        () {
                      setState(() {
                        _isInPlaylist = !_isInPlaylist;
                      });
                    },
                    28,
                    color: _isInPlaylist ? Colors.green : Colors.white,
                  ),
                  SizedBox(width: 20),
                  _animatedButton(
                    Icons.lyrics,
                        () {
                      setState(() {
                        _showLyrics = !_showLyrics;
                        fetchYoutubeClosedCaptions(playing.video.videoId!);
                      });
                    },
                    28,
                    color: _showLyrics ? Colors.blue : Colors.white,
                  ),
                ],
              ),
              SizedBox(height: 20),
              // Lyrics Section (Conditional)
              if (_showLyrics)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    playing.currentCaption,
                    style: TextStyle(
                        fontSize: 16,
                        color: Colors.white70),
                  ),
                ),
              SizedBox(height: 20),
              // Progress Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: Colors.white,
                        inactiveTrackColor: Colors.white38,
                        thumbColor: Colors.white,
                        thumbShape: RoundSliderThumbShape(enabledThumbRadius: 8),
                        overlayShape: RoundSliderOverlayShape(overlayRadius: 16),
                      ),
                      child: Slider(
                        min: 0,
                        max: playing.duration.inSeconds.toDouble(),
                        value: playing.position.inSeconds.toDouble(),
                        onChanged: (double value) {
                          playing.seekAudio(Duration(seconds: value.toInt()));
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${playing.position.inMinutes}:${(playing.position.inSeconds % 60).toString().padLeft(2, '0')}',
                            style: TextStyle(color: Colors.white70),
                          ),
                          Text(
                            '${playing.duration.inMinutes}:${(playing.duration.inSeconds % 60).toString().padLeft(2, '0')}',
                            style: TextStyle(color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 30),
              // Playback Controls
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _animatedButton(Icons.shuffle, playing.toggleShuffle, 24, color: playing.isShuffling ? Colors.blue : Colors.white),
                  SizedBox(width: 16),
                  _animatedButton(Icons.skip_previous, playing.previous, 32),
                  SizedBox(width: 16),
                  GestureDetector(
                    onTap: () {
                      playing.isPlaying ? playing.pause() : playing.play();
                    },
                    child: AnimatedContainer(
                      duration: Duration(milliseconds: 200),
                      curve: Curves.easeInOut,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 10,
                            spreadRadius: 2,
                            offset: Offset(0, 4),
                          )
                        ],
                      ),
                      child: Icon(
                        playing.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                        size: 72,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  SizedBox(width: 16),
                  _animatedButton(Icons.skip_next, () {playing.next();}, 32),
                  SizedBox(width: 16),
                  _animatedButton(playing.isLooping==0? Icons.repeat_rounded: playing.isLooping==1? Icons.repeat_one: Icons.repeat_rounded , () {
                    playing.toggleLooping();
                  }, 24,color:playing.isLooping==0? Colors.white: playing.isLooping==1? Colors.white: Colors.blue),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Helper function to create animated buttons
  Widget _animatedButton(IconData icon, VoidCallback onPressed, double size, {Color color = Colors.white}) {
    bool _isButtonPressed = false;

    return GestureDetector(
      onTapDown: (_) => setState(() => _isButtonPressed = true),
      onTapUp: (_) => setState(() => _isButtonPressed = false),
      onTapCancel: () => setState(() => _isButtonPressed = false),
      onTap: onPressed,
      child: AnimatedContainer(
        duration: Duration(milliseconds: 150),
        curve: Curves.easeInOut,
        padding: EdgeInsets.all(10),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withOpacity(0.1),
        ),
        child: ScaleTransition(
          scale: Tween(begin: 1.0, end: 0.9).animate(
            AlwaysStoppedAnimation(_isButtonPressed ? 0.9 : 1.0),
          ),
          child: Icon(
            icon,
            size: size,
            color: color,
          ),
        ),
      ),
    );
  }

  // Show Queue Dialog with Currently Playing Highlighted
  void _showQueue(BuildContext context, Playing playing) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.8),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Queue',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white),
              ),
              SizedBox(height: 16),
              Expanded(
                child: ListView.builder(
                  itemCount: playing.queue.length,
                  itemBuilder: (context, index) {
                    final video = playing.queue[index];
                    final isCurrent = video.videoId == playing.video.videoId;
                    return ListTile(
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          video.thumbnails![0].url!,
                          width: 50,
                          height: 50,
                          fit: BoxFit.cover,
                        ),
                      ),
                      title: Text(
                        video.title!,
                        style: TextStyle(
                            color: isCurrent ? Colors.blue : Colors.white,
                            fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal),
                      ),
                      subtitle: Text(
                        video.channelName!,
                        style: TextStyle(
                            color: isCurrent ? Colors.blue.shade200 : Colors.white70),
                      ),
                      onTap: () {
                        playing.assign(video,false);
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}