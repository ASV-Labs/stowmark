const status = document.getElementById("status");
const undo = document.getElementById("undo");
const NATIVE_ID = "com.charlesbonetti.mymind.extension";
let lastRequestId = null;

async function activeTab() {
  const [tab] = await browser.tabs.query({ active: true, currentWindow: true });
  return tab;
}

async function selectionFromTab(tab) {
  try {
    const response = await browser.tabs.sendMessage(tab.id, { action: "getSelection" });
    return response?.text ?? "";
  } catch {
    return "";
  }
}

async function send(action, extras = {}) {
  const tab = await activeTab();
  const requestId = crypto.randomUUID();
  lastRequestId = requestId;
  const tags = document.getElementById("tags").value
    .split(",")
    .map((value) => value.trim())
    .filter(Boolean);
  const payload = {
    action,
    requestId,
    pageURL: tab?.url ?? "",
    title: tab?.title ?? "",
    note: document.getElementById("note").value,
    shelf: document.getElementById("shelf").value,
    tags,
    ...extras,
  };
  status.textContent = "Saving…";
  undo.hidden = true;
  try {
    let response = await browser.runtime.sendNativeMessage(NATIVE_ID, payload);
    if (response?.requestId) lastRequestId = response.requestId;
    if (response?.status === "pending") {
      status.textContent = response.message || "Waiting for My Mind to finish saving.";
      response = await waitForReceipt(lastRequestId);
    }
    status.textContent = response?.message ?? "Not saved.";
    undo.hidden = response?.status !== "saved";
    return response;
  } catch (error) {
    status.textContent = "Not saved. Open My Mind once, then try again.";
    return { status: "failed" };
  }
}

async function waitForReceipt(requestId) {
  for (let attempt = 0; attempt < 40; attempt += 1) {
    await new Promise((resolve) => setTimeout(resolve, 500));
    try {
      const response = await browser.runtime.sendNativeMessage(NATIVE_ID, {
        action: "receipt",
        requestId,
      });
      if (response?.status === "saved" || response?.status === "already_saved" || response?.status === "failed") {
        return response;
      }
      status.textContent = response?.message || "Waiting for My Mind to finish saving.";
    } catch {
      status.textContent = "Waiting for My Mind to finish saving.";
    }
  }
  return {
    status: "pending",
    message: "My Mind is still saving. Open the library to confirm — this window did not get a receipt.",
  };
}

document.getElementById("save").addEventListener("click", () => send("savePage"));
document.getElementById("excerpt").addEventListener("click", async () => {
  const tab = await activeTab();
  const text = await selectionFromTab(tab);
  if (!text) {
    status.textContent = "Not saved. Select some text first.";
    return;
  }
  await send("saveSelection", { selection: text });
});
document.getElementById("undo").addEventListener("click", async () => {
  if (!lastRequestId) return;
  status.textContent = "Saving…";
  try {
    const response = await browser.runtime.sendNativeMessage(NATIVE_ID, {
      action: "undo",
      requestId: lastRequestId,
    });
    status.textContent = response?.message ?? "Nothing to undo.";
  } catch {
    status.textContent = "Nothing to undo.";
  }
  undo.hidden = true;
});
document.getElementById("open").addEventListener("click", () => {
  browser.runtime.sendNativeMessage(NATIVE_ID, { action: "openApp" });
});
