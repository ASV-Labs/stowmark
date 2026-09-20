const NATIVE_ID = "com.charlesbonetti.cardfile.extension";

// Safari and Firefox expose `browser`; Chrome, Arc, Brave, and Edge expose `chrome`.
// A distinct name is used so this never shadows a namespace the browser already defines.
const ext = globalThis.browser ?? globalThis.chrome;
// Only Safari and Firefox let the app push a message into the extension.
const SUPPORTS_NATIVE_PUSH = globalThis.browser !== undefined;

async function native(payload) {
  if (SUPPORTS_NATIVE_PUSH) {
    return await ext.runtime.sendNativeMessage(NATIVE_ID, payload);
  }
  // Chrome's callback form is the one guaranteed across Chromium versions.
  return await new Promise((resolve, reject) => {
    ext.runtime.sendNativeMessage(NATIVE_ID, payload, (response) => {
      const failure = ext.runtime.lastError;
      if (failure) {
        reject(new Error(failure.message ?? "The native host did not answer."));
      } else {
        resolve(response);
      }
    });
  });
}

function ensureMenus() {
  const create = () => {
    ext.contextMenus.create({ id: "save-page", title: "Save page to Cardfile", contexts: ["page"] });
    ext.contextMenus.create({ id: "save-selection", title: "Save selection to Cardfile", contexts: ["selection"] });
    ext.contextMenus.create({ id: "save-link", title: "Save link to Cardfile", contexts: ["link"] });
    ext.contextMenus.create({ id: "save-image", title: "Save image to Cardfile", contexts: ["image"] });
    ext.contextMenus.create({ id: "save-image-link", title: "Save image link to Cardfile", contexts: ["image"] });
  };
  if (ext.contextMenus.removeAll) {
    ext.contextMenus.removeAll().then(create).catch(create);
  } else {
    create();
  }
}
ext.runtime.onInstalled.addListener(() => {
  ensureMenus();
  refreshToolbarMode();
});
ensureMenus();
refreshToolbarMode();

async function savePageTab(tab) {
  if (!tab?.url) return;
  const response = await native({
    action: "savePage",
    requestId: crypto.randomUUID(),
    pageURL: tab.url,
    title: tab.title ?? "",
  });
  await paintBadge(tab.id, response);
}

ext.commands?.onCommand.addListener(async (command) => {
  if (command !== "save-page") return;
  const [tab] = await ext.tabs.query({ active: true, currentWindow: true });
  await savePageTab(tab);
});

function applyToolbarMode(enabled) {
  if (!ext.action?.setPopup) return;
  const popup = enabled ? "" : "popup.html";
  ext.action.setPopup({ popup }).catch(() => {});
}

async function refreshToolbarMode() {
  try {
    const response = await native({ action: "getSettings" });
    if (typeof response?.safariToolbarClickSaves === "boolean") {
      applyToolbarMode(response.safariToolbarClickSaves);
    }
  } catch {
    // Leave the popup in place. A missing flag stays off.
  }
}

if (ext.runtime.onStartup) {
  ext.runtime.onStartup.addListener(refreshToolbarMode);
}

// Chrome has no equivalent of SFSafariApplication.dispatchMessage, and an idle port would keep a
// host process alive for nothing. Chrome picks the flag up through getSettings instead.
if (SUPPORTS_NATIVE_PUSH) {
  try {
    const port = ext.runtime.connectNative(NATIVE_ID);
    port.onMessage.addListener((message) => {
      const info = message?.userInfo ?? message ?? {};
      if (typeof info.safariToolbarClickSaves === "boolean") {
        applyToolbarMode(info.safariToolbarClickSaves);
      } else if (message?.name === "capture-settings") {
        refreshToolbarMode();
      }
    });
  } catch {
    // The JSON flag is still read on the next getSettings.
  }
}

if (ext.action?.onClicked) {
  ext.action.onClicked.addListener((tab) => {
    savePageTab(tab);
  });
}

async function paintBadge(tabId, response) {
  if (!ext.action?.setBadgeText || tabId == null) return;
  const status = response?.status;
  const text = status === "saved" || status === "already_saved" ? "✓" : status === "pending" ? "…" : "!";
  await ext.action.setBadgeText({ text, tabId });
  if (ext.action.setBadgeBackgroundColor) {
    await ext.action.setBadgeBackgroundColor({ color: status === "failed" ? "#8C2F22" : "#1B5E3B", tabId });
  }
  setTimeout(() => {
    ext.action.setBadgeText({ text: "", tabId });
  }, 3000);
}

function bytesToBase64(buffer) {
  const bytes = new Uint8Array(buffer);
  let binary = "";
  const chunk = 0x8000;
  for (let index = 0; index < bytes.length; index += chunk) {
    binary += String.fromCharCode(...bytes.subarray(index, index + chunk));
  }
  return btoa(binary);
}

ext.contextMenus.onClicked.addListener(async (info, tab) => {
  const requestId = crypto.randomUUID();
  const pageURL = tab?.url ?? info.pageUrl ?? "";
  const title = tab?.title ?? "";
  if (info.menuItemId === "save-selection") {
    await native({
      action: "saveSelection",
      requestId,
      pageURL,
      title,
      selection: info.selectionText ?? "",
    });
    return;
  }
  if (info.menuItemId === "save-link") {
    await native({
      action: "savePage",
      requestId,
      pageURL: info.linkUrl ?? pageURL,
      title: info.linkText || title,
    });
    return;
  }
  if (info.menuItemId === "save-image-link") {
    await native({
      action: "savePage",
      requestId,
      pageURL: info.srcUrl || pageURL,
      title: title || "Image",
    });
    return;
  }
  if (info.menuItemId === "save-image") {
    const src = info.srcUrl || "";
    let bytes = "";
    let filename = "image";
    try {
      const response = await fetch(src);
      const buffer = await response.arrayBuffer();
      if (buffer.byteLength > 8 * 1024 * 1024) throw new Error("too large for the extension message");
      bytes = bytesToBase64(buffer);
      filename = decodeURIComponent(src.split("/").pop()?.split("?")[0] || "image");
    } catch {
      await native({
        action: "savePage",
        requestId,
        pageURL: src || pageURL,
        title: title || "Image",
      });
      return;
    }
    await native({
      action: "saveImage",
      requestId,
      pageURL,
      title: title || filename,
      filename,
      bytes,
    });
    return;
  }
  await native({
    action: "savePage",
    requestId,
    pageURL,
    title,
  });
});
