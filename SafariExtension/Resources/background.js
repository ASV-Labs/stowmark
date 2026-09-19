const NATIVE_ID = "com.charlesbonetti.mymind.extension";

async function native(payload) {
  return await browser.runtime.sendNativeMessage(NATIVE_ID, payload);
}

function ensureMenus() {
  const create = () => {
    browser.contextMenus.create({ id: "save-page", title: "Save page to My Mind", contexts: ["page"] });
    browser.contextMenus.create({ id: "save-selection", title: "Save selection to My Mind", contexts: ["selection"] });
    browser.contextMenus.create({ id: "save-link", title: "Save link to My Mind", contexts: ["link"] });
    browser.contextMenus.create({ id: "save-image", title: "Save image link to My Mind", contexts: ["image"] });
  };
  if (browser.contextMenus.removeAll) {
    browser.contextMenus.removeAll().then(create).catch(create);
  } else {
    create();
  }
}
browser.runtime.onInstalled.addListener(ensureMenus);
ensureMenus();

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
  if (info.menuItemId === "save-image") {
    await native({
      action: "savePage",
      requestId,
      pageURL: info.srcUrl || pageURL,
      title: title || "Image",
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
