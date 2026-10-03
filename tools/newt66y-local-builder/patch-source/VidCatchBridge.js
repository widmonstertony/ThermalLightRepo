(function () {
  "use strict";

  if (window.__newtVidCatchInstalled) return;
  window.__newtVidCatchInstalled = true;

  var candidates = [];
  var seen = new Set();
  var activeVideo = null;
  var scanTimer = null;
  var button = null;
  var toast = null;
  var originalFetch = window.fetch;
  var originalXHROpen = XMLHttpRequest.prototype.open;
  var mediaExtensions = /\.(?:mp4|m4v|webm|mov|mkv|avi|mp3|m4a|aac|ogg|oga|opus|wav|flac)(?:$|[?#])/i;
  var hlsURL = /(?:\.m3u8(?:$|[?#])|\/hls(?:$|[?#])|playlist\/master)/i;
  var dashURL = /\.mpd(?:$|[?#])/i;
  var fragmentURL = /\.(?:ts|m4s|cmfv|cmfa|key)(?:$|[?#])/i;
  var twitterFragment = /video\.twimg\.com\/amplify_video\/\d+\/(?:aud|vid)\//i;

  function absoluteURL(raw) {
    if (!raw || typeof raw !== "string") return null;
    try {
      var value = new URL(raw, location.href);
      return /^https?:$/i.test(value.protocol) ? value.href : null;
    } catch (_) {
      return null;
    }
  }

  function mediaKind(url) {
    if (!url || fragmentURL.test(url) || twitterFragment.test(url)) return null;
    if (hlsURL.test(url)) return "hls";
    if (dashURL.test(url)) return "dash";
    if (mediaExtensions.test(url)) return "direct";
    return null;
  }

  function remember(raw, source, force) {
    var url = absoluteURL(raw);
    var kind = mediaKind(url);
    if (!url || !kind) return;
    if (!force && seen.has(url)) return;
    seen.add(url);
    candidates.push({
      url: url,
      kind: kind,
      source: source || "page",
      seenAt: Date.now()
    });
    if (candidates.length > 80) candidates.splice(0, candidates.length - 80);
  }

  function rememberVideo(video, force) {
    if (!video) return;
    [video.currentSrc, video.src, video.getAttribute("src"), video.getAttribute("data-src"),
      video.getAttribute("data-source"), video.getAttribute("data-url"),
      video.getAttribute("data-video"), video.getAttribute("data-video-src"),
      video.getAttribute("data-hls"), video.getAttribute("data-m3u8")]
      .forEach(function (value) { remember(value, "video", force); });
    video.querySelectorAll("source").forEach(function (source) {
      remember(source.currentSrc || source.src || source.getAttribute("src"), "source", force);
    });
  }

  function bindVideo(video) {
    if (!video || video.__newtVidCatchBound) return;
    video.__newtVidCatchBound = true;
    ["loadstart", "loadedmetadata", "loadeddata", "canplay", "play", "playing", "durationchange"]
      .forEach(function (eventName) {
        video.addEventListener(eventName, function () {
          activeVideo = video;
          rememberVideo(video, true);
        }, true);
      });
    if (!video.paused || video.currentTime > 0) activeVideo = video;
    rememberVideo(video, false);
  }

  function scanDOM(root) {
    if (!root) return;
    if (root.tagName === "VIDEO" || root.tagName === "AUDIO") bindVideo(root);
    if (root.querySelectorAll) root.querySelectorAll("video, audio").forEach(bindVideo);
  }

  function scanPerformance() {
    try {
      performance.getEntriesByType("resource").forEach(function (entry) {
        remember(entry.name, "performance", false);
      });
    } catch (_) {}
  }

  function bestCandidate() {
    if (activeVideo && document.contains(activeVideo)) rememberVideo(activeVideo, true);
    scanDOM(document);
    scanPerformance();

    var direct = activeVideo && absoluteURL(activeVideo.currentSrc || activeVideo.src);
    if (direct && mediaKind(direct)) {
      return { url: direct, kind: mediaKind(direct), source: "active-video" };
    }

    var weighted = candidates.map(function (item, index) {
      var score = item.kind === "hls" ? 300 : item.kind === "dash" ? 240 : 160;
      if (/master|manifest|index/i.test(item.url)) score += 35;
      if (item.source === "video" || item.source === "source") score += 25;
      score += index / Math.max(candidates.length, 1);
      return { item: item, score: score };
    });
    weighted.sort(function (a, b) { return b.score - a.score; });
    return weighted.length ? weighted[0].item : null;
  }

  function currentTitle() {
    var title = (document.title || "").replace(/\s+/g, " ").trim();
    if (activeVideo) {
      var container = activeVideo.closest && activeVideo.closest("article, .post, .entry, .link, [data-tid]");
      var heading = container && container.querySelector && container.querySelector("h1, h2, h3, .title");
      var headingText = heading && heading.textContent && heading.textContent.replace(/\s+/g, " ").trim();
      if (headingText) title = headingText;
    }
    return title || "小草视频";
  }

  function showToast(message, isError) {
    if (!toast) return;
    toast.textContent = message;
    toast.style.background = isError ? "rgba(163, 32, 45, .94)" : "rgba(22, 25, 31, .94)";
    toast.style.opacity = "1";
    clearTimeout(toast.__hideTimer);
    toast.__hideTimer = setTimeout(function () { toast.style.opacity = "0"; }, isError ? 6500 : 3500);
  }

  function setButtonState(label, busy, title) {
    if (!button) return;
    button.textContent = label || "⇩";
    button.disabled = !!busy;
    button.title = title || "用 VidCatch 下载当前视频";
    button.style.opacity = busy ? ".78" : "1";
  }

  function refreshAvailability() {
    if (!button || button.disabled) return;
    var available = !!bestCandidate();
    button.style.filter = available ? "none" : "grayscale(1)";
    button.title = available ? "用 VidCatch 下载当前视频" : "暂未检测到可下载的视频";
  }

  function downloadCurrentVideo(event) {
    if (event) {
      event.preventDefault();
      event.stopPropagation();
    }
    if (button && button.disabled) return;
    var candidate = bestCandidate();
    if (!candidate) {
      showToast("暂未检测到视频地址，请先开始播放再点下载", true);
      return;
    }
    setButtonState("…", true, "正在提交下载任务");
    showToast("正在交给 VidCatch 分析…", false);
    try {
      window.webkit.messageHandlers.newtTouchBarMedia.postMessage({
        type: "download",
        url: candidate.url,
        kind: candidate.kind,
        source: candidate.source || "page",
        title: currentTitle(),
        pageUrl: location.href,
        userAgent: navigator.userAgent || "",
        poster: activeVideo ? (activeVideo.poster || "") : ""
      });
    } catch (_) {
      setButtonState("⇩", false);
      showToast("下载桥接没有加载，请重新打开当前页面", true);
    }
  }

  window.__newtVidCatchStatus = function (payload) {
    payload = payload || {};
    var status = String(payload.status || "");
    var message = String(payload.message || "");
    var progress = Number(payload.progress || 0);
    if (status === "probing" || status === "queued") {
      setButtonState("…", true, message || "正在分析");
    } else if (status === "downloading") {
      setButtonState(progress > 0 ? Math.min(99, Math.round(progress)) + "%" : "↓", true, message || "正在下载");
    } else if (status === "complete") {
      setButtonState("✓", false, "下载完成");
      showToast(message || "视频已保存到下载文件夹", false);
      setTimeout(function () { setButtonState("⇩", false); refreshAvailability(); }, 2600);
    } else if (status === "error") {
      setButtonState("!", false, "下载失败");
      showToast(message || "下载失败", true);
      setTimeout(function () { setButtonState("⇩", false); refreshAvailability(); }, 3200);
    } else {
      if (message) showToast(message, false);
      setButtonState("⇩", false);
      refreshAvailability();
    }
  };

  function installUI() {
    if (!document.documentElement || document.getElementById("__newtVidCatchButton")) return;
    var host = document.body || document.documentElement;
    button = document.createElement("button");
    button.id = "__newtVidCatchButton";
    button.type = "button";
    button.textContent = "⇩";
    button.setAttribute("aria-label", "下载当前视频");
    button.style.cssText = [
      "all:initial", "box-sizing:border-box", "position:fixed", "z-index:2147483647",
      "right:max(16px,env(safe-area-inset-right))",
      "bottom:calc(78px + env(safe-area-inset-bottom))",
      "width:54px", "height:54px", "border-radius:27px", "border:1px solid rgba(255,255,255,.30)",
      "background:linear-gradient(145deg,rgba(52,130,255,.98),rgba(34,92,220,.98))",
      "color:white", "font:700 18px -apple-system,BlinkMacSystemFont,sans-serif",
      "display:flex", "align-items:center", "justify-content:center", "text-align:center",
      "box-shadow:0 7px 22px rgba(0,0,0,.35)", "cursor:pointer", "user-select:none",
      "-webkit-user-select:none", "-webkit-tap-highlight-color:transparent"
    ].join(";");
    button.addEventListener("click", downloadCurrentVideo, true);
    button.addEventListener("touchend", function (event) {
      event.preventDefault();
      downloadCurrentVideo(event);
    }, { capture: true, passive: false });

    toast = document.createElement("div");
    toast.id = "__newtVidCatchToast";
    toast.style.cssText = [
      "all:initial", "box-sizing:border-box", "position:fixed", "z-index:2147483647",
      "right:max(16px,env(safe-area-inset-right))",
      "bottom:calc(142px + env(safe-area-inset-bottom))", "max-width:min(360px,calc(100vw - 32px))",
      "padding:10px 13px", "border-radius:10px", "background:rgba(22,25,31,.94)",
      "color:white", "font:500 13px/1.35 -apple-system,BlinkMacSystemFont,sans-serif",
      "box-shadow:0 5px 18px rgba(0,0,0,.32)", "opacity:0", "pointer-events:none",
      "transition:opacity .18s ease"
    ].join(";");
    host.appendChild(toast);
    host.appendChild(button);
    refreshAvailability();
  }

  window.fetch = function () {
    try {
      var request = arguments[0];
      remember(typeof request === "string" ? request : request && request.url, "fetch", false);
    } catch (_) {}
    return originalFetch.apply(this, arguments);
  };

  XMLHttpRequest.prototype.open = function (method, url) {
    try { remember(String(url || ""), "xhr", false); } catch (_) {}
    return originalXHROpen.apply(this, arguments);
  };

  try {
    var observer = new PerformanceObserver(function (list) {
      list.getEntries().forEach(function (entry) { remember(entry.name, "performance", false); });
    });
    observer.observe({ type: "resource", buffered: true });
  } catch (_) {}

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", function () {
      installUI();
      scanDOM(document);
      scanPerformance();
    }, { once: true });
  } else {
    installUI();
    scanDOM(document);
    scanPerformance();
  }

  new MutationObserver(function (mutations) {
    mutations.forEach(function (mutation) {
      mutation.addedNodes.forEach(scanDOM);
    });
    installUI();
  }).observe(document.documentElement || document, { childList: true, subtree: true });

  scanTimer = setInterval(function () {
    scanDOM(document);
    scanPerformance();
    refreshAvailability();
  }, 1800);
  window.addEventListener("pagehide", function () { clearInterval(scanTimer); }, { once: true });
})();
