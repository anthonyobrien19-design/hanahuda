// In-game voice chat (audio only). Voice goes directly between players using WebRTC;
// the game's Firebase database is only used to introduce the players to each other.
import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'online.dart';

class VoiceChat {
  final String code;
  final int mySeat;
  final VoidCallback onChanged;
  VoiceChat({required this.code, required this.mySeat, required this.onChanged});

  MediaStream? _local;
  final Map<int, RTCPeerConnection> _peers = {};
  final Map<int, RTCVideoRenderer> _renderers = {};
  final Map<int, List<Map<String, dynamic>>> _myCands = {};
  final Map<int, int> _sentCands = {}, _gotCands = {}, _sid = {};
  final Map<int, bool> _remoteSet = {}, _ready = {};
  final Set<int> _failed = {};

  final Set<int> speaking = {};
  Set<int> members = {};
  bool muted = false, active = false;
  String status = 'Not connected';
  Timer? _timer;
  bool _busy = false;

  String _key(int a, int b) => a < b ? '${a}_$b' : '${b}_$a';
  String get _base => 'rooms/$code/voice';

  Map<String, dynamic> get _config => {
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
          if (kTurnUrl.isNotEmpty) {'urls': kTurnUrl, 'username': kTurnUser, 'credential': kTurnPass},
        ],
        'sdpSemantics': 'unified-plan',
      };

  Future<bool> start() async {
    try {
      _local = await navigator.mediaDevices.getUserMedia({'audio': true, 'video': false});
    } catch (e) {
      status = 'Microphone is blocked. Allow it in your browser or phone settings.';
      onChanged();
      return false;
    }
    try {
      // Remove leftovers from an earlier session that involve my seat.
      final sig = keyed(await Rtdb.get('$_base/sig'));
      for (final k in sig.keys) {
        if (k.split('_').contains('$mySeat')) await Rtdb.delete('$_base/sig/$k');
      }
      await Rtdb.put('$_base/members/$mySeat', DateTime.now().millisecondsSinceEpoch);
    } catch (_) {
      status = 'Could not reach the game server.';
      onChanged();
      return false;
    }
    active = true;
    status = 'Voice on. Waiting for others to join voice...';
    onChanged();
    _timer = Timer.periodic(const Duration(milliseconds: 1200), (_) => _tick());
    _tick();
    return true;
  }

  void setMuted(bool m) {
    muted = m;
    for (final t in _local?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = !m;
    }
    onChanged();
  }

  Future<void> stop() async {
    active = false;
    _timer?.cancel();
    for (final s in _peers.keys.toList()) {
      await _closePeer(s);
    }
    for (final t in _local?.getTracks() ?? <MediaStreamTrack>[]) {
      await t.stop();
    }
    await _local?.dispose();
    _local = null;
    try {
      await Rtdb.delete('$_base/members/$mySeat');
    } catch (_) {}
  }

  Future<void> _tick() async {
    if (!active || _busy) return;
    _busy = true;
    try {
      await Rtdb.put('$_base/members/$mySeat', DateTime.now().millisecondsSinceEpoch);
      final mem = keyed(await Rtdb.get('$_base/members'));
      final now = DateTime.now().millisecondsSinceEpoch;
      final live = <int>{};
      mem.forEach((k, v) {
        final s = int.tryParse(k);
        final t = (v as num?)?.toInt() ?? 0;
        if (s != null && s != mySeat && now - t < 30000) live.add(s);
      });
      members = live;
      for (final s in _peers.keys.toList()) {
        if (!live.contains(s) || _failed.contains(s)) {
          await _closePeer(s);
          if (live.contains(s)) await Rtdb.delete('$_base/sig/${_key(mySeat, s)}');
        }
      }
      final sig = keyed(await Rtdb.get('$_base/sig'));
      for (final s in live) {
        await _connect(s, sig[_key(mySeat, s)]);
        await _flushCands(s);
      }
      await _levels();
      status = live.isEmpty ? 'Voice on. Waiting for others to join voice...' : (_peers.isEmpty ? 'Connecting...' : 'Voice on');
      onChanged();
    } catch (_) {
    } finally {
      _busy = false;
    }
  }

  Future<RTCPeerConnection> _newPeer(int s) async {
    final pc = await createPeerConnection(_config);
    _peers[s] = pc;
    _myCands[s] = [];
    _sentCands[s] = 0;
    _gotCands[s] = 0;
    _remoteSet[s] = false;
    _ready[s] = false;
    _failed.remove(s);
    for (final t in _local!.getTracks()) {
      await pc.addTrack(t, _local!);
    }
    pc.onIceCandidate = (RTCIceCandidate c) {
      if (c.candidate != null) {
        _myCands[s]?.add({'candidate': c.candidate, 'sdpMid': c.sdpMid, 'sdpMLineIndex': c.sdpMLineIndex});
      }
    };
    pc.onTrack = (RTCTrackEvent e) async {
      if (e.streams.isEmpty) return;
      var r = _renderers[s];
      if (r == null) {
        r = RTCVideoRenderer();
        await r.initialize();
        _renderers[s] = r;
      }
      r.srcObject = e.streams.first;
      onChanged();
    };
    pc.onConnectionState = (RTCPeerConnectionState st) {
      if (st == RTCPeerConnectionState.RTCPeerConnectionStateFailed) _failed.add(s);
    };
    return pc;
  }

  Future<void> _closePeer(int s) async {
    try {
      await _peers[s]?.close();
    } catch (_) {}
    _peers.remove(s);
    final r = _renderers.remove(s);
    if (r != null) {
      r.srcObject = null;
      await r.dispose();
    }
    speaking.remove(s);
    _myCands.remove(s);
    _sentCands.remove(s);
    _gotCands.remove(s);
    _remoteSet.remove(s);
    _ready.remove(s);
    _sid.remove(s);
    _failed.remove(s);
  }

  Future<void> _connect(int s, dynamic node) async {
    final key = _key(mySeat, s);
    final n = node is Map ? Map<String, dynamic>.from(node) : <String, dynamic>{};
    var pc = _peers[s];
    if (mySeat < s) {
      // The lower seat always makes the offer.
      if (pc == null) {
        pc = await _newPeer(s);
        final sid = DateTime.now().millisecondsSinceEpoch;
        _sid[s] = sid;
        final offer = await pc.createOffer({'offerToReceiveAudio': true});
        await pc.setLocalDescription(offer);
        await Rtdb.put('$_base/sig/$key', {
          'offer': {'sdp': offer.sdp, 'type': offer.type},
          'sid': sid,
        });
        _ready[s] = true;
      } else if (_remoteSet[s] != true && n['answer'] is Map && n['sid'] == _sid[s]) {
        final a = Map<String, dynamic>.from(n['answer'] as Map);
        await pc.setRemoteDescription(RTCSessionDescription(a['sdp'] as String?, a['type'] as String?));
        _remoteSet[s] = true;
      }
    } else if (n['offer'] is Map) {
      final sid = (n['sid'] as num?)?.toInt();
      if (pc != null && _sid[s] != sid) {
        await _closePeer(s); // a newer offer arrived: start over
        pc = null;
      }
      if (pc == null) {
        pc = await _newPeer(s);
        _sid[s] = sid ?? 0;
        final o = Map<String, dynamic>.from(n['offer'] as Map);
        await pc.setRemoteDescription(RTCSessionDescription(o['sdp'] as String?, o['type'] as String?));
        _remoteSet[s] = true;
        final ans = await pc.createAnswer({'offerToReceiveAudio': true});
        await pc.setLocalDescription(ans);
        await Rtdb.patch('$_base/sig/$key', {
          'answer': {'sdp': ans.sdp, 'type': ans.type},
        });
        _ready[s] = true;
      }
    }
    pc = _peers[s];
    if (pc != null && _remoteSet[s] == true) {
      final list = asList(n['c$s']);
      var applied = _gotCands[s] ?? 0;
      while (applied < list.length) {
        final c = list[applied];
        if (c is Map) {
          await pc.addCandidate(RTCIceCandidate(c['candidate'] as String?, c['sdpMid'] as String?, (c['sdpMLineIndex'] as num?)?.toInt()));
        }
        applied++;
      }
      _gotCands[s] = applied;
    }
  }

  Future<void> _flushCands(int s) async {
    final mine = _myCands[s];
    if (mine == null || _ready[s] != true) return;
    if (mine.length != (_sentCands[s] ?? 0)) {
      await Rtdb.patch('$_base/sig/${_key(mySeat, s)}', {'c$mySeat': mine});
      _sentCands[s] = mine.length;
    }
  }

  Future<void> _levels() async {
    final sp = <int>{};
    for (final e in _peers.entries) {
      try {
        final stats = await e.value.getStats();
        for (final r in stats) {
          if (r.type == 'inbound-rtp') {
            final v = r.values['audioLevel'];
            if (v is num && v > 0.02) sp.add(e.key);
          }
        }
      } catch (_) {}
    }
    if (sp.length != speaking.length || !sp.containsAll(speaking)) {
      speaking
        ..clear()
        ..addAll(sp);
    }
  }

  /// Tiny hidden players that make the other players' voices audible (needed on the web).
  List<Widget> audioViews() => [
        for (final r in _renderers.values) Positioned(left: 0, top: 0, width: 1, height: 1, child: RTCVideoView(r)),
      ];
}
