browser.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message?.action === "getSelection") {
    sendResponse({ text: window.getSelection ? window.getSelection().toString() : "" });
    return;
  }
  if (message?.action === "pageInfo") {
    sendResponse({
      url: location.href,
      title: document.title,
      selection: window.getSelection ? window.getSelection().toString() : "",
    });
  }
});
