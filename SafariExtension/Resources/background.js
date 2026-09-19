const NATIVE_ID = "com.charlesbonetti.mymind.extension";

async function native(payload) {
  return await browser.runtime.sendNativeMessage(NATIVE_ID, payload);
}

function ensureMenus() {
  const create = () => {
    browser.contextMenus.create({ id: "save-page", title: "Save page to My Mind", contexts: ["page"] });
    browser.contextMenus.create({ id: "save-selection", title: "Save selection to My Mind", contexts: ["selection"] });
    browser.contextMenus.create({ id: "save-link", title: "Save link to My Mind", contexts: ["link"] });
    browser.contextMenus.create({ id: "save-image", title: "Save image to My Mind", contexts: ["image"] });
    browser.contextMenus.create({ id: "save-image-link", title: "Save image link to My Mind", contexts: ["image"] });
  };
  if (browser.contextMenus.removeAll) {
    browser.contextMenus.removeAll().then(create).catch(create);
  } else {
    create();
  }
}
browser.runtime.onInstalled.addListener(() => {
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

browser.commands?.onCommand.addListener(async (command) => {
  if (command !== "save-page") return;
  const [tab] = await browser.tabs.query({ active: true, currentWindow: true });
  await savePageTab(tab);
});

function applyToolbarMode(enabled) {
  if (!browser.action?.setPopup) return;
  const popup = enabled ? "" : "popup.html";
  browser.action.setPopup({ popup }).catch(() => {});
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

if (browser.runtime.onStartup) {
  browser.runtime.onStartup.addListener(refreshToolbarMode);
}

try {
  const port = browser.runtime.connectNative(NATIVE_ID);
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

if (browser.action?.onClicked) {
  browser.action.onClicked.addListener((tab) => {
    savePageTab(tab);
  });
}

async function paintBadge(tabId, response) {
  if (!browser.action?.setBadgeText || tabId == null) return;
  const status = response?.status;
  const text = status === "saved" || status === "already_saved" ? "✓" : status === "pending" ? "…" : "!";
  await browser.action.setBadgeText({ text, tabId });
  if (browser.action.setBadgeBackgroundColor) {
    await browser.action.setBadgeBackgroundColor({ color: status === "failed" ? "#8C2F22" : "#1B5E3B", tabId });
  }
  setTimeout(() => {
    browser.action.setBadgeText({ text: "", tabId });
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

browser.contextMenus.onClicked.addListener(async (info, tab) => {
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
