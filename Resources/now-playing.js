// Reads system Now Playing through osascript.
// Since macOS 15.4, normal apps are not entitled to read MediaRemote directly.
// /usr/bin/osascript is an Apple-signed process that still can.
function run() {
  function str(value) {
    try {
      if (value === null || value === undefined) return "";
      if (value.isNil && value.isNil()) return "";
      return String(ObjC.unwrap(value));
    } catch (error) {
      return "";
    }
  }

  function num(value) {
    try {
      if (value === null || value === undefined) return 0;
      if (value.isNil && value.isNil()) return 0;
      const number = Number(ObjC.unwrap(value));
      return Number.isFinite(number) ? number : 0;
    } catch (error) {
      return 0;
    }
  }

  try {
    ObjC.import("Foundation");
    const bundle = $.NSBundle.bundleWithPath("/System/Library/PrivateFrameworks/MediaRemote.framework");
    if (!bundle || !bundle.load) return JSON.stringify({ empty: true });

    const request = $.NSClassFromString("MRNowPlayingRequest");
    if (!request) return JSON.stringify({ empty: true });

    const path = request.localNowPlayingPlayerPath;
    if (!path || (path.isNil && path.isNil())) return JSON.stringify({ empty: true });

    const item = request.localNowPlayingItem;
    if (!item || (item.isNil && item.isNil())) return JSON.stringify({ empty: true });

    const info = item.nowPlayingInfo;
    if (!info || (info.isNil && info.isNil())) return JSON.stringify({ empty: true });

    const title = str(info.objectForKey("kMRMediaRemoteNowPlayingInfoTitle"));
    if (!title) return JSON.stringify({ empty: true });

    let timestamp = Date.now() / 1000;
    try {
      const stamp = info.objectForKey("kMRMediaRemoteNowPlayingInfoTimestamp");
      if (stamp && !(stamp.isNil && stamp.isNil())) {
        timestamp = Number(stamp.timeIntervalSince1970);
      }
    } catch (error) {}

    let appName = "";
    let bundleID = "";
    try {
      appName = str(path.client.displayName);
      bundleID = str(path.client.bundleIdentifier);
    } catch (error) {}

    return JSON.stringify({
      empty: false,
      title: title,
      artist: str(info.objectForKey("kMRMediaRemoteNowPlayingInfoArtist")),
      album: str(info.objectForKey("kMRMediaRemoteNowPlayingInfoAlbum")),
      duration: num(info.objectForKey("kMRMediaRemoteNowPlayingInfoDuration")),
      elapsed: num(info.objectForKey("kMRMediaRemoteNowPlayingInfoElapsedTime")),
      rate: num(info.objectForKey("kMRMediaRemoteNowPlayingInfoPlaybackRate")),
      timestamp: timestamp,
      appName: appName,
      bundleID: bundleID
    });
  } catch (error) {
    return JSON.stringify({ empty: true, error: String(error) });
  }
}
