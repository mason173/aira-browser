export const MEDIA_VIDEO_FRAME_PROBE_PROTOCOL: string = 'aira.media_frame_probe.v1';
export const MEDIA_VIDEO_FRAME_PROBE_SOURCE: string = 'aira_frame_probe_v1';
export const MEDIA_VIDEO_FRAME_PROBE_CHANNEL_KIND: string = 'aira_media_frame_probe_v1';
export const MEDIA_VIDEO_FRAME_COMMAND_PROTOCOL: string = 'aira.media_frame_command.v1';
export const MEDIA_VIDEO_FRAME_COMMAND_KIND_PREFIX: string = 'aira_media_frame_command_v1:';

const MEDIA_VIDEO_FRAME_PROBE_SCRIPT: string = `
(function airaMediaVideoFrameProbeBootstrap() {
  if (window.__airaMediaVideoFrameProbeInstalled === true) {
    return;
  }
  window.__airaMediaVideoFrameProbeInstalled = true;
  var protocol = 'aira.media_frame_probe.v1';
  var sourceName = 'aira_frame_probe_v1';
  var channelKind = 'aira_media_frame_probe_v1';
  var commandProtocol = 'aira.media_frame_command.v1';
  var commandKindPrefix = 'aira_media_frame_command_v1:';
  var frameHostProtocol = 'aira.media_frame_host.v1';
  var frameHostBridgeProperty = '__airaMediaVideoFrameHostBridgeV1';
  var maxFrameHostRelayDepth = 32;
  var mainFrame = isMainFrame();
  installFrameHostBridge();
  if (mainFrame) {
    window.addEventListener('message', function (event) {
      var payload = event && event.data;
      if (!payload || payload.protocol !== protocol || !event.source) {
        return;
      }
      if (payload.kind === 'signal_relay') {
        try {
          var signalBridge = window.__airaPageBehaviorNativeBridge;
          if (signalBridge && typeof signalBridge.onSignal === 'function' &&
            typeof payload.payloadJson === 'string') {
            signalBridge.onSignal(payload.payloadJson);
          }
        } catch (_signalRelayError) {
        }
        return;
      }
      if (payload.kind !== 'channel_request') {
        return;
      }
      try {
        var bridge = window.__airaWebVideoControllerBridge;
        var raw = bridge && typeof bridge.readSystemControl === 'function' ?
          bridge.readSystemControl(channelKind) : '{}';
        var snapshot = JSON.parse(String(raw || '{}'));
        event.source.postMessage({
          protocol: protocol,
          kind: 'channel_response',
          frameRuntimeId: String(payload.frameRuntimeId || ''),
          channelId: typeof snapshot.channelId === 'string' ? snapshot.channelId : ''
        }, '*');
      } catch (_channelResponseError) {
      }
    }, false);
    return;
  }
  var runtimeIdProperty = '__airaPageBehaviorVideoRuntimeId';
  var frameRuntimeId = createRuntimeId('frame');
  var frameControlKey = createControlKey();
  var currentChannelId = '';
  var channelRequestPending = false;
  var bootstrapReported = false;
  var nextVideoSequence = 1;
  var commandPollTimer = 0;
  var commandInFlight = false;
  var commandCapabilityActive = false;
  var commandFastPollUntil = 0;
  var lastPlaybackHeartbeatAt = 0;
  var geometryRevalidationTimer = 0;
  var geometryRevalidationGeneration = 0;

  function createRuntimeId(prefix) {
    var randomPart = '';
    try {
      var values = new Uint32Array(2);
      window.crypto.getRandomValues(values);
      randomPart = values[0].toString(36) + values[1].toString(36);
    } catch (_randomError) {
      randomPart = Math.random().toString(36).slice(2);
    }
    return prefix + ':' + Date.now().toString(36) + ':' + randomPart;
  }

  function createControlKey() {
    var value = createRuntimeId('control');
    return value.replace(/[^a-zA-Z0-9_-]/g, '');
  }

  function installFrameHostBridge() {
    var existingBridge = window[frameHostBridgeProperty];
    if (existingBridge && existingBridge.protocol === frameHostProtocol &&
      typeof existingBridge.execute === 'function') {
      return;
    }
    var maxRegisteredFrames = 64;
    var maxScannedFrames = 128;
    var maxAncestorDepth = 32;
    var records = [];

    function hostResult(ok, reason, detail) {
      return JSON.stringify({
        ok: ok === true,
        reason: String(reason || ''),
        detail: String(detail || '').slice(0, 512)
      });
    }

    function normalizeFrameRuntimeId(value) {
      var normalized = String(value || '').trim();
      return normalized.length > 0 && normalized.length <= 256 ? normalized : '';
    }

    function restoreElementStyle(snapshot) {
      if (!snapshot || !snapshot.element) {
        return;
      }
      try {
        if (snapshot.hadStyleAttribute === true) {
          snapshot.element.setAttribute('style', snapshot.styleAttribute);
        } else {
          snapshot.element.removeAttribute('style');
        }
      } catch (_restoreStyleError) {
      }
    }

    function unbindPresentation(state) {
      var bindings = state && state.bindings ? state.bindings : [];
      for (var index = bindings.length - 1; index >= 0; index -= 1) {
        var binding = bindings[index];
        try {
          binding.target.removeEventListener(binding.eventName, binding.listener, false);
        } catch (_unbindError) {
        }
      }
      if (state) {
        state.bindings = [];
      }
    }

    function restorePresentation(record) {
      var state = record && record.presentationState;
      if (!state || state.active !== true) {
        return true;
      }
      state.active = false;
      unbindPresentation(state);
      try {
        if (state.backdrop && typeof state.backdrop.remove === 'function') {
          state.backdrop.remove();
        } else if (state.backdrop && state.backdrop.parentElement) {
          state.backdrop.parentElement.removeChild(state.backdrop);
        }
      } catch (_removeBackdropError) {
      }
      var snapshots = state.snapshots || [];
      for (var index = snapshots.length - 1; index >= 0; index -= 1) {
        restoreElementStyle(snapshots[index]);
      }
      record.presentationState = null;
      return true;
    }

    function pruneRecords() {
      var retained = [];
      for (var index = 0; index < records.length; index += 1) {
        var record = records[index];
        var frame = record && record.frameElement;
        var stillMapped = false;
        try {
          stillMapped = !!frame && frame.isConnected !== false && frame.contentWindow === record.sourceWindow;
        } catch (_mappingError) {
        }
        if (stillMapped) {
          retained.push(record);
        } else {
          restorePresentation(record);
        }
      }
      records = retained;
    }

    function findDirectFrame(sourceWindow) {
      var frames = [];
      try {
        frames = document.querySelectorAll('iframe,frame');
      } catch (_queryError) {
        return null;
      }
      var match = null;
      var matchCount = 0;
      var limit = Math.min(frames.length, maxScannedFrames);
      for (var index = 0; index < limit; index += 1) {
        try {
          if (frames[index] && frames[index].contentWindow === sourceWindow) {
            match = frames[index];
            matchCount += 1;
          }
        } catch (_frameAccessError) {
        }
      }
      return matchCount === 1 ? match : null;
    }

    function findUniqueRecord(frameRuntimeId) {
      pruneRecords();
      var match = null;
      var matchCount = 0;
      for (var index = 0; index < records.length; index += 1) {
        if (records[index].frameRuntimeId === frameRuntimeId) {
          match = records[index];
          matchCount += 1;
        }
      }
      return matchCount === 1 ? match : null;
    }

    function rememberStyle(element) {
      return {
        element: element,
        hadStyleAttribute: element.hasAttribute('style'),
        styleAttribute: String(element.getAttribute('style') || '')
      };
    }

    function collectPresentationElements(frameElement) {
      var elements = [frameElement];
      var current = frameElement.parentElement;
      var depth = 0;
      while (current && depth < maxAncestorDepth) {
        elements.push(current);
        if (current === document.documentElement) {
          break;
        }
        current = current.parentElement;
        depth += 1;
      }
      if (document.body && elements.indexOf(document.body) < 0) {
        elements.push(document.body);
      }
      if (document.documentElement && elements.indexOf(document.documentElement) < 0) {
        elements.push(document.documentElement);
      }
      return elements;
    }

    function applyImportantStyle(element, name, value) {
      try {
        element.style.setProperty(name, value, 'important');
      } catch (_styleError) {
      }
    }

    function resolvePresentationViewportGeometry() {
      var visualViewport = window.visualViewport || null;
      var documentElement = document.documentElement || null;
      var layoutWidth = Math.max(
        0,
        Number(window.innerWidth || 0),
        Number(documentElement && documentElement.clientWidth || 0)
      );
      var layoutHeight = Math.max(
        0,
        Number(window.innerHeight || 0),
        Number(documentElement && documentElement.clientHeight || 0)
      );
      var visualWidth = visualViewport && Number(visualViewport.width) > 0 ?
        Number(visualViewport.width) : layoutWidth;
      var visualHeight = visualViewport && Number(visualViewport.height) > 0 ?
        Number(visualViewport.height) : layoutHeight;
      var visualLeft = visualViewport ? Number(visualViewport.offsetLeft || 0) : 0;
      var visualTop = visualViewport ? Number(visualViewport.offsetTop || 0) : 0;
      if (!Number.isFinite(visualLeft)) {
        visualLeft = 0;
      }
      if (!Number.isFinite(visualTop)) {
        visualTop = 0;
      }
      var left = Math.min(0, visualLeft);
      var top = Math.min(0, visualTop);
      var right = Math.max(layoutWidth, visualLeft + Math.max(0, visualWidth));
      var bottom = Math.max(layoutHeight, visualTop + Math.max(0, visualHeight));
      return {
        left: left,
        top: top,
        width: Math.max(0, right - left),
        height: Math.max(0, bottom - top)
      };
    }

    function describeHostState(record) {
      var viewport = resolvePresentationViewportGeometry();
      var frame = record && record.frameElement;
      var connected = false;
      var rectWidth = 0;
      var rectHeight = 0;
      try {
        connected = !!frame && frame.isConnected !== false;
        if (frame && typeof frame.getBoundingClientRect === 'function') {
          var rect = frame.getBoundingClientRect();
          rectWidth = Number(rect && rect.width || 0);
          rectHeight = Number(rect && rect.height || 0);
        }
      } catch (_frameStateError) {
      }
      return 'viewport=' + String(Math.round(viewport.width)) + 'x' + String(Math.round(viewport.height)) +
        ',frameRect=' + String(Math.round(rectWidth)) + 'x' + String(Math.round(rectHeight)) +
        ',connected=' + (connected ? 'yes' : 'no') + ',records=' + String(records.length);
    }

    function refreshPresentationGeometry(state) {
      if (!state || state.active !== true || !state.frameElement) {
        return false;
      }
      var frameElement = state.frameElement;
      try {
        if (frameElement.isConnected === false) {
          return false;
        }
      } catch (_connectedError) {
      }
      var viewportGeometry = resolvePresentationViewportGeometry();
      var viewportWidth = viewportGeometry.width;
      var viewportHeight = viewportGeometry.height;
      var viewportLeft = viewportGeometry.left;
      var viewportTop = viewportGeometry.top;
      var ancestors = state.ancestors || [];
      for (var index = 0; index < ancestors.length; index += 1) {
        var ancestor = ancestors[index];
        applyImportantStyle(ancestor, 'position', 'relative');
        applyImportantStyle(ancestor, 'z-index', '2147483646');
        applyImportantStyle(ancestor, 'visibility', 'visible');
        applyImportantStyle(ancestor, 'opacity', '1');
        applyImportantStyle(ancestor, 'transform', 'none');
        applyImportantStyle(ancestor, 'filter', 'none');
        applyImportantStyle(ancestor, 'perspective', 'none');
        applyImportantStyle(ancestor, 'clip', 'auto');
        applyImportantStyle(ancestor, 'clip-path', 'none');
        applyImportantStyle(ancestor, 'contain', 'none');
        applyImportantStyle(ancestor, 'isolation', 'auto');
        applyImportantStyle(ancestor, 'overflow', 'visible');
        applyImportantStyle(ancestor, 'overflow-x', 'visible');
        applyImportantStyle(ancestor, 'overflow-y', 'visible');
      }
      if (document.documentElement) {
        applyImportantStyle(document.documentElement, 'overflow', 'hidden');
      }
      if (document.body) {
        applyImportantStyle(document.body, 'overflow', 'hidden');
      }
      applyImportantStyle(frameElement, 'position', 'fixed');
      applyImportantStyle(frameElement, 'top', String(viewportTop) + 'px');
      applyImportantStyle(frameElement, 'left', String(viewportLeft) + 'px');
      applyImportantStyle(frameElement, 'right', 'auto');
      applyImportantStyle(frameElement, 'bottom', 'auto');
      applyImportantStyle(frameElement, 'width', String(viewportWidth) + 'px');
      applyImportantStyle(frameElement, 'height', String(viewportHeight) + 'px');
      applyImportantStyle(frameElement, 'min-width', String(viewportWidth) + 'px');
      applyImportantStyle(frameElement, 'min-height', String(viewportHeight) + 'px');
      applyImportantStyle(frameElement, 'max-width', 'none');
      applyImportantStyle(frameElement, 'max-height', 'none');
      applyImportantStyle(frameElement, 'margin', '0');
      applyImportantStyle(frameElement, 'padding', '0');
      applyImportantStyle(frameElement, 'border', '0');
      applyImportantStyle(frameElement, 'z-index', '2147483647');
      applyImportantStyle(frameElement, 'display', 'block');
      applyImportantStyle(frameElement, 'visibility', 'visible');
      applyImportantStyle(frameElement, 'opacity', '1');
      applyImportantStyle(frameElement, 'transform', 'none');
      applyImportantStyle(frameElement, 'clip', 'auto');
      applyImportantStyle(frameElement, 'clip-path', 'none');
      applyImportantStyle(frameElement, 'contain', 'none');
      applyImportantStyle(frameElement, 'overflow', 'hidden');
      applyImportantStyle(frameElement, 'pointer-events', 'auto');
      applyImportantStyle(frameElement, 'box-sizing', 'border-box');
      applyImportantStyle(frameElement, 'background-color', 'black');
      if (state.backdrop) {
        applyImportantStyle(state.backdrop, 'position', 'fixed');
        applyImportantStyle(state.backdrop, 'top', String(viewportTop) + 'px');
        applyImportantStyle(state.backdrop, 'left', String(viewportLeft) + 'px');
        applyImportantStyle(state.backdrop, 'width', String(viewportWidth) + 'px');
        applyImportantStyle(state.backdrop, 'height', String(viewportHeight) + 'px');
        applyImportantStyle(state.backdrop, 'margin', '0');
        applyImportantStyle(state.backdrop, 'padding', '0');
        applyImportantStyle(state.backdrop, 'border', '0');
        applyImportantStyle(state.backdrop, 'z-index', '2147483645');
        applyImportantStyle(state.backdrop, 'display', 'block');
        applyImportantStyle(state.backdrop, 'background-color', 'black');
        applyImportantStyle(state.backdrop, 'pointer-events', 'none');
      }
      return viewportWidth > 0 && viewportHeight > 0;
    }

    function bindPresentation(state) {
      var refresh = function () {
        refreshPresentationGeometry(state);
      };
      var bindings = [];
      function bind(target, eventName) {
        if (!target || typeof target.addEventListener !== 'function') {
          return;
        }
        try {
          target.addEventListener(eventName, refresh, false);
          bindings.push({ target: target, eventName: eventName, listener: refresh });
        } catch (_bindError) {
        }
      }
      bind(window, 'resize');
      bind(window, 'scroll');
      bind(window, 'orientationchange');
      bind(window.visualViewport, 'resize');
      bind(window.visualViewport, 'scroll');
      state.bindings = bindings;
    }

    function enterPresentation(record) {
      if (record.presentationState && record.presentationState.active === true) {
        return refreshPresentationGeometry(record.presentationState);
      }
      var frameElement = record.frameElement;
      var elements = collectPresentationElements(frameElement);
      var snapshots = [];
      for (var index = 0; index < elements.length; index += 1) {
        snapshots.push(rememberStyle(elements[index]));
      }
      var backdrop = null;
      try {
        backdrop = document.createElement('div');
        backdrop.setAttribute('data-aira-media-frame-host-backdrop', 'true');
        (document.documentElement || document.body).appendChild(backdrop);
      } catch (_backdropError) {
        backdrop = null;
      }
      var state = {
        active: true,
        frameElement: frameElement,
        ancestors: elements.slice(1),
        snapshots: snapshots,
        backdrop: backdrop,
        bindings: []
      };
      record.presentationState = state;
      bindPresentation(state);
      if (refreshPresentationGeometry(state)) {
        return true;
      }
      restorePresentation(record);
      return false;
    }

    function acceptRegistration(event) {
      var payload = event && event.data;
      if (!payload || payload.protocol !== frameHostProtocol || payload.kind !== 'register_frame_host') {
        return;
      }
      var frameRuntimeId = normalizeFrameRuntimeId(payload.frameRuntimeId);
      if (frameRuntimeId.length <= 0 || !event.source) {
        return;
      }
      var frameElement = findDirectFrame(event.source);
      if (!frameElement) {
        return;
      }
      var relayDepth = Number(payload.relayDepth || 0);
      if (!Number.isFinite(relayDepth) || relayDepth < 0 || relayDepth >= maxFrameHostRelayDepth) {
        return;
      }
      pruneRecords();
      var existingRecord = null;
      for (var index = records.length - 1; index >= 0; index -= 1) {
        var record = records[index];
        if (record.frameRuntimeId === frameRuntimeId) {
          existingRecord = record;
          break;
        }
      }
      if (existingRecord) {
        if (existingRecord.sourceWindow !== event.source || existingRecord.frameElement !== frameElement) {
          restorePresentation(existingRecord);
          existingRecord.sourceWindow = event.source;
          existingRecord.frameElement = frameElement;
        }
        existingRecord.registeredAt = Date.now();
      } else {
        if (records.length >= maxRegisteredFrames) {
          records.sort(function (left, right) {
            return Number(left.registeredAt || 0) - Number(right.registeredAt || 0);
          });
          while (records.length >= maxRegisteredFrames) {
            restorePresentation(records[0]);
            records.shift();
          }
        }
        records.push({
          frameRuntimeId: frameRuntimeId,
          frameElement: frameElement,
          sourceWindow: event.source,
          registeredAt: Date.now(),
          presentationState: null
        });
      }
      forwardFrameHostRegistration(payload, relayDepth);
    }

    function forwardFrameHostRegistration(payload, relayDepth) {
      try {
        if (mainFrame || !window.parent || window.parent === window ||
          typeof window.parent.postMessage !== 'function') {
          return;
        }
        window.parent.postMessage({
          protocol: frameHostProtocol,
          kind: 'register_frame_host',
          frameRuntimeId: String(payload.frameRuntimeId || ''),
          channelId: String(payload.channelId || ''),
          relayDepth: relayDepth + 1
        }, '*');
      } catch (_relayError) {
      }
    }

    function forwardFrameHostCommand(record, payload) {
      try {
        if (!record || !record.sourceWindow || typeof record.sourceWindow.postMessage !== 'function') {
          return;
        }
        record.sourceWindow.postMessage({
          protocol: frameHostProtocol,
          kind: 'execute_frame_host',
          action: String(payload.action || ''),
          frameRuntimeId: String(payload.frameRuntimeId || '')
        }, '*');
      } catch (_relayError) {
      }
    }

    function executeHostCommand(payloadJson) {
      var payload = null;
      try {
        payload = typeof payloadJson === 'string' ? JSON.parse(payloadJson) : payloadJson;
      } catch (_parseError) {
        return hostResult(false, 'invalid_frame_host_command');
      }
      if (!payload || payload.protocol !== frameHostProtocol || typeof payload.action !== 'string') {
        return hostResult(false, 'invalid_frame_host_command');
      }
      var frameRuntimeId = normalizeFrameRuntimeId(payload.frameRuntimeId);
      if (frameRuntimeId.length <= 0) {
        return hostResult(false, 'invalid_frame_host_command');
      }
      var record = findUniqueRecord(frameRuntimeId);
      if (!record) {
        return hostResult(false, 'frame_host_unreachable', 'records=' + String(records.length));
      }
      if (payload.action === 'probe_frame_host') {
        return hostResult(true, 'frame_host_reachable');
      }
      if (payload.action === 'enter_frame_host_presentation') {
        if (!enterPresentation(record)) {
          return hostResult(false, 'frame_host_presentation_failed', describeHostState(record));
        }
        forwardFrameHostCommand(record, payload);
        return hostResult(true, 'frame_host_presentation_entered', describeHostState(record));
      }
      if (payload.action === 'restore_frame_host_presentation') {
        restorePresentation(record);
        forwardFrameHostCommand(record, payload);
        return hostResult(true, 'frame_host_presentation_restored');
      }
      return hostResult(false, 'unsupported_frame_host_command');
    }

    function acceptHostCommand(event) {
      var payload = event && event.data;
      if (!payload || payload.protocol !== frameHostProtocol || payload.kind !== 'execute_frame_host' ||
        !event.source || event.source !== window.parent) {
        return;
      }
      executeHostCommand(payload);
    }

    window.addEventListener('message', acceptRegistration, false);
    window.addEventListener('message', acceptHostCommand, false);
    window[frameHostBridgeProperty] = {
      protocol: frameHostProtocol,
      execute: executeHostCommand
    };
  }

  function reportFrameHostRegistration() {
    try {
      if (!window.parent || window.parent === window || typeof window.parent.postMessage !== 'function') {
        return false;
      }
      window.parent.postMessage({
        protocol: frameHostProtocol,
        kind: 'register_frame_host',
        frameRuntimeId: frameRuntimeId,
        channelId: currentChannelId,
        relayDepth: 0
      }, '*');
      return true;
    } catch (_registrationError) {
      return false;
    }
  }

  function readCurrentChannel() {
    try {
      var bridge = window.__airaWebVideoControllerBridge;
      var userBridge = window.__airaUserScriptNativeBridge;
      var readSystemControl = bridge && typeof bridge.readSystemControl === 'function'
        ? function (kind) { return bridge.readSystemControl(kind); }
        : userBridge && typeof userBridge.webVideoReadSystemControl === 'function'
          ? function (kind) { return userBridge.webVideoReadSystemControl(kind); }
          : null;
      if (!readSystemControl) {
        requestChannelFromParent();
        return false;
      }
      var raw = readSystemControl(channelKind);
      var snapshot = JSON.parse(String(raw || '{}'));
      if (snapshot.protocol !== protocol || typeof snapshot.channelId !== 'string' ||
        snapshot.channelId.length <= 0) {
        requestChannelFromParent();
        return false;
      }
      currentChannelId = snapshot.channelId;
      return true;
    } catch (_bridgeError) {
      requestChannelFromParent();
      return false;
    }
  }

  function requestChannelFromParent() {
    if (channelRequestPending || !window.parent || window.parent === window ||
      typeof window.parent.postMessage !== 'function') {
      return;
    }
    channelRequestPending = true;
    try {
      window.parent.postMessage({
        protocol: protocol,
        kind: 'channel_request',
        frameRuntimeId: frameRuntimeId
      }, '*');
      setTimeout(function () {
        channelRequestPending = false;
      }, 250);
    } catch (_channelRequestError) {
      channelRequestPending = false;
    }
  }

  window.addEventListener('message', function (event) {
    var payload = event && event.data;
    if (!payload || payload.protocol !== protocol) {
      return;
    }
    if (payload.kind === 'channel_request' || payload.kind === 'signal_relay') {
      if (window.parent && window.parent !== window && typeof window.parent.postMessage === 'function') {
        try {
          window.parent.postMessage(payload, '*');
        } catch (_frameRelayError) {
        }
      }
      return;
    }
    if (payload.kind !== 'channel_response' || String(payload.frameRuntimeId || '') !== frameRuntimeId) {
      return;
    }
    var channelId = String(payload.channelId || '');
    channelRequestPending = false;
    if (channelId.length <= 0) {
      return;
    }
    currentChannelId = channelId;
    reportFrameHostRegistration();
    emit('ready', 'channel_response', null);
    reportVisiblePlayingVideos('channel_response');
  }, false);

  function resolveFrameUrl() {
    try {
      return String(window.location && window.location.href || '');
    } catch (_locationError) {
      return '';
    }
  }

  function isMainFrame() {
    try {
      return window.top === window;
    } catch (_frameError) {
      return false;
    }
  }

  function reportBootstrapBoundary(reason) {
    if (bootstrapReported) {
      return true;
    }
    try {
      var bridge = window.__airaPageBehaviorNativeBridge;
      if (!bridge || typeof bridge.onSignal !== 'function') {
        return false;
      }
      bridge.onSignal(JSON.stringify({
        source: sourceName,
        protocol: protocol,
        kind: 'bootstrap',
        reason: String(reason || ''),
        timestamp: Date.now(),
        frameRuntimeId: frameRuntimeId,
        isMainFrame: isMainFrame()
      }));
      bootstrapReported = true;
      return true;
    } catch (_bootstrapError) {
      return false;
    }
  }

  function resolveVideoRuntimeId(video) {
    try {
      var existing = String(video[runtimeIdProperty] || '');
      if (existing.length > 0) {
        return existing;
      }
      var runtimeId = frameRuntimeId + ':video:' + String(nextVideoSequence++);
      video[runtimeIdProperty] = runtimeId;
      return runtimeId;
    } catch (_runtimeError) {
      return frameRuntimeId + ':video:fallback:' + String(nextVideoSequence++);
    }
  }

  function resolveVideoSource(video) {
    try {
      return String(video.currentSrc || video.src || '');
    } catch (_sourceError) {
      return '';
    }
  }

  function isVideoVisible(video, rect) {
    try {
      if (!rect || rect.width < 2 || rect.height < 2) {
        return false;
      }
      var viewportWidth = Math.max(1, Number(window.innerWidth || document.documentElement.clientWidth || 1));
      var viewportHeight = Math.max(1, Number(window.innerHeight || document.documentElement.clientHeight || 1));
      if (rect.right <= 0 || rect.bottom <= 0 || rect.left >= viewportWidth || rect.top >= viewportHeight) {
        return false;
      }
      var style = typeof window.getComputedStyle === 'function' ? window.getComputedStyle(video) : null;
      return !style || (style.display !== 'none' && style.visibility !== 'hidden' &&
        Number.parseFloat(style.opacity || '1') > 0.02);
    } catch (_visibilityError) {
      return false;
    }
  }

  function buildVideoEvent(video, eventName) {
    var rect = null;
    try {
      rect = video.getBoundingClientRect();
    } catch (_rectError) {
    }
    return {
      eventName: String(eventName || 'snapshot'),
      runtimeId: resolveVideoRuntimeId(video),
      elementId: String(video.id || ''),
      source: resolveVideoSource(video),
      muted: video.muted === true,
      paused: video.paused === true,
      ended: video.ended === true,
      seeking: video.seeking === true,
      readyState: Number.isFinite(Number(video.readyState)) ? Math.max(0, Number(video.readyState)) : 0,
      networkState: Number.isFinite(Number(video.networkState)) ? Math.max(0, Number(video.networkState)) : 0,
      visible: isVideoVisible(video, rect),
      rect: {
        x: rect ? Number(rect.x || 0) : 0,
        y: rect ? Number(rect.y || 0) : 0,
        width: rect ? Math.max(0, Number(rect.width || 0)) : 0,
        height: rect ? Math.max(0, Number(rect.height || 0)) : 0
      },
      viewportWidth: Math.max(0, Number(window.innerWidth || 0)),
      viewportHeight: Math.max(0, Number(window.innerHeight || 0)),
      videoWidth: Math.max(0, Number(video.videoWidth || 0)),
      videoHeight: Math.max(0, Number(video.videoHeight || 0)),
      currentTime: Math.max(0, Number(video.currentTime || 0)),
      duration: Number.isFinite(Number(video.duration)) ? Math.max(0, Number(video.duration)) : 0
    };
  }

  function emit(kind, reason, videoEvent) {
    if (currentChannelId.length <= 0) {
      return false;
    }
    try {
      var bridge = window.__airaPageBehaviorNativeBridge;
      var payload = {
        source: sourceName,
        protocol: protocol,
        kind: kind,
        reason: String(reason || ''),
        timestamp: Date.now(),
        channelId: currentChannelId,
        frameRuntimeId: frameRuntimeId,
        frameControlKey: frameControlKey,
        frameUrl: resolveFrameUrl(),
        isMainFrame: isMainFrame()
      };
      if (videoEvent) {
        payload.videoEvent = videoEvent;
      }
      var payloadJson = JSON.stringify(payload);
      if (bridge && typeof bridge.onSignal === 'function') {
        bridge.onSignal(payloadJson);
      } else if (window.parent && window.parent !== window &&
        typeof window.parent.postMessage === 'function') {
        window.parent.postMessage({
          protocol: protocol,
          kind: 'signal_relay',
          payloadJson: payloadJson
        }, '*');
      } else {
        return false;
      }
      return true;
    } catch (_signalError) {
      return false;
    }
  }

  function reportFrameCommandResult(setSystemControl, command, rawResult) {
    try {
      setSystemControl(JSON.stringify({
        protocol: commandProtocol,
        channelId: currentChannelId,
        requestId: String(command.requestId || ''),
        frameRuntimeId: frameRuntimeId,
        frameControlKey: frameControlKey,
        action: String(command.action || ''),
        result: String(rawResult == null ? '' : rawResult)
      }));
    } catch (_resultError) {
    }
  }

  function pollFrameCommand() {
    if (commandInFlight || currentChannelId.length <= 0 || !shouldPollFrameCommands()) {
      return;
    }
    var bridge = window.__airaWebVideoControllerBridge;
    var userBridge = window.__airaUserScriptNativeBridge;
    var readSystemControl = bridge && typeof bridge.readSystemControl === 'function'
      ? function (kind) { return bridge.readSystemControl(kind); }
      : userBridge && typeof userBridge.webVideoReadSystemControl === 'function'
        ? function (kind) { return userBridge.webVideoReadSystemControl(kind); }
        : null;
    var setSystemControl = bridge && typeof bridge.setSystemControl === 'function'
      ? function (payloadJson) { return bridge.setSystemControl(payloadJson); }
      : userBridge && typeof userBridge.webVideoSetSystemControl === 'function'
        ? function (payloadJson) { return userBridge.webVideoSetSystemControl(payloadJson); }
        : null;
    if (!readSystemControl || !setSystemControl) {
      return;
    }
    commandInFlight = true;
    try {
      var rawCommand = readSystemControl(commandKindPrefix + frameControlKey);
      var command = JSON.parse(String(rawCommand || '{}'));
      if (command.protocol !== commandProtocol || command.channelId !== currentChannelId ||
        command.frameRuntimeId !== frameRuntimeId || command.frameControlKey !== frameControlKey ||
        typeof command.requestId !== 'string' || command.requestId.length <= 0 ||
        typeof command.action !== 'string' || command.action.length <= 0 || command.action.length > 64 ||
        typeof command.script !== 'string' || command.script.length <= 0 || command.script.length > 131072) {
        return;
      }
      commandCapabilityActive = true;
      commandFastPollUntil = Date.now() + 15000;
      var rawResult = '';
      try {
        rawResult = (0, eval)(command.script);
      } catch (commandError) {
        rawResult = JSON.stringify({
          ok: false,
          reason: String(commandError && commandError.message || commandError || 'frame_command_failed'),
          userVisibleMessage: '网页视频控制失败。',
          currentTime: 0,
          duration: 0,
          paused: true,
          ended: false,
          playbackRate: 1,
          fullscreenActive: false
        });
      }
      reportFrameCommandResult(setSystemControl, command, rawResult);
    } catch (_commandError) {
    } finally {
      commandInFlight = false;
      if (Date.now() - lastPlaybackHeartbeatAt >= 8000) {
        lastPlaybackHeartbeatAt = Date.now();
        reportVisiblePlayingVideos('frame_control_heartbeat');
      }
      if (shouldPollFrameCommands()) {
        scheduleCommandPoll(resolveCommandPollDelay());
      }
    }
  }

  function isDocumentVisible() {
    try {
      return document.visibilityState !== 'hidden';
    } catch (_visibilityError) {
      return true;
    }
  }

  function hasPlayingVideo() {
    try {
      var videos = document.querySelectorAll('video');
      var limit = Math.min(videos.length, 24);
      for (var index = 0; index < limit; index += 1) {
        if (videos[index] && videos[index].paused === false && videos[index].ended !== true) {
          return true;
        }
      }
    } catch (_queryError) {
    }
    return false;
  }

  function shouldPollFrameCommands() {
    return isDocumentVisible() && (commandCapabilityActive || hasPlayingVideo());
  }

  function resolveCommandPollDelay() {
    if (Date.now() < commandFastPollUntil) {
      return 120;
    }
    return hasPlayingVideo() ? 500 : 2000;
  }

  function stopCommandPolling() {
    if (commandPollTimer !== 0) {
      clearTimeout(commandPollTimer);
      commandPollTimer = 0;
    }
  }

  function scheduleCommandPoll(delay) {
    if (commandPollTimer !== 0) {
      clearTimeout(commandPollTimer);
    }
    commandPollTimer = setTimeout(function () {
      commandPollTimer = 0;
      pollFrameCommand();
    }, Math.max(0, Number(delay || 0)));
  }

  function ensureCommandPolling() {
    if (commandPollTimer !== 0 || !shouldPollFrameCommands()) {
      return;
    }
    scheduleCommandPoll(0);
  }

  function reportVisiblePlayingVideos(reason) {
    var videos = [];
    try {
      videos = document.querySelectorAll('video');
    } catch (_queryError) {
      return;
    }
    var limit = Math.min(videos.length, 24);
    for (var index = 0; index < limit; index += 1) {
      var video = videos[index];
      if (video && video.paused === false && video.ended !== true) {
        ensureCommandPolling();
        emit('video_event', reason, buildVideoEvent(video, 'playing'));
      }
    }
  }

  function cancelGeometryRevalidation() {
    geometryRevalidationGeneration += 1;
    if (geometryRevalidationTimer !== 0) {
      clearTimeout(geometryRevalidationTimer);
      geometryRevalidationTimer = 0;
    }
  }

  function scheduleGeometryRevalidation(reason) {
    cancelGeometryRevalidation();
    var generation = geometryRevalidationGeneration;
    var eventName = String(reason || 'geometry_layout');
    geometryRevalidationTimer = setTimeout(function () {
      if (generation !== geometryRevalidationGeneration) {
        return;
      }
      geometryRevalidationTimer = 0;
      reportVisiblePlayingVideos(eventName);
      geometryRevalidationTimer = setTimeout(function () {
        if (generation !== geometryRevalidationGeneration) {
          return;
        }
        geometryRevalidationTimer = 0;
        reportVisiblePlayingVideos(eventName + '_settled');
      }, 200);
    }, 80);
  }

  function installGeometryRevalidationListeners() {
    try {
      document.addEventListener('scroll', function () {
        scheduleGeometryRevalidation('geometry_scroll');
      }, true);
      window.addEventListener('resize', function () {
        scheduleGeometryRevalidation('geometry_resize');
      }, true);
      window.addEventListener('orientationchange', function () {
        scheduleGeometryRevalidation('geometry_orientation');
      }, true);
      if (window.visualViewport) {
        window.visualViewport.addEventListener('resize', function () {
          scheduleGeometryRevalidation('geometry_visual_resize');
        }, true);
        window.visualViewport.addEventListener('scroll', function () {
          scheduleGeometryRevalidation('geometry_visual_scroll');
        }, true);
      }
    } catch (_geometryListenerError) {
    }
  }

  function refreshChannelAndReport(reason) {
    if (!readCurrentChannel()) {
      return;
    }
    reportFrameHostRegistration();
    emit('ready', reason, null);
    reportVisiblePlayingVideos(reason);
  }

  ['loadstart', 'loadedmetadata', 'canplay', 'canplaythrough', 'play', 'playing', 'waiting', 'stalled',
    'seeking', 'seeked', 'pause', 'ended', 'emptied', 'abort', 'error', 'resize'].forEach(
    function (eventName) {
      document.addEventListener(eventName, function (event) {
        var video = event && event.target;
        if (!video || String(video.tagName || '').toLowerCase() !== 'video') {
          return;
        }
        emit('video_event', eventName, buildVideoEvent(video, eventName));
        if (eventName === 'play' || eventName === 'playing') {
          ensureCommandPolling();
          return;
        }
        if ((eventName === 'ended' || eventName === 'emptied' || eventName === 'abort') &&
          !hasPlayingVideo()) {
          commandCapabilityActive = false;
          commandFastPollUntil = 0;
          stopCommandPolling();
          return;
        }
        if (commandCapabilityActive) {
          ensureCommandPolling();
        }
      }, true);
    }
  );

  installGeometryRevalidationListeners();

  [0, 50, 250, 1000, 2500].forEach(function (delay) {
    setTimeout(function () {
      reportBootstrapBoundary('document_start_' + String(delay));
      refreshChannelAndReport('document_start_' + String(delay));
    }, delay);
  });
  window.addEventListener('pageshow', function () {
    reportBootstrapBoundary('pageshow');
    refreshChannelAndReport('pageshow');
  }, true);
  window.addEventListener('pagehide', function (event) {
    cancelGeometryRevalidation();
    stopCommandPolling();
    commandCapabilityActive = false;
    commandFastPollUntil = 0;
    if (!event || event.persisted !== true) {
      emit('frame_ended', 'pagehide', null);
    }
  }, true);
  document.addEventListener('visibilitychange', function () {
    if (document.visibilityState === 'visible') {
      reportBootstrapBoundary('visible');
      refreshChannelAndReport('visible');
      if (commandCapabilityActive) {
        ensureCommandPolling();
      }
      return;
    }
    stopCommandPolling();
  }, true);
})();
`;

export class MediaVideoFrameProbeScript {
  buildDocumentStartScriptItem(): ScriptItem {
    return {
      script: MEDIA_VIDEO_FRAME_PROBE_SCRIPT,
      scriptRules: ['*']
    };
  }
}
