(() => {
  const stage = document.querySelector("[data-film-stage]");
  const status = document.querySelector("[data-film-status]");
  if (!stage) return;

  const src = "assets/demo.mp4";
  const captions = "assets/demo.en.vtt";

  const probe = (url) =>
    fetch(url, { method: "HEAD" }).then((res) => res.ok).catch(() => false);

  Promise.all([probe(src), probe(captions)]).then(([hasFilm, hasCaptions]) => {
    if (!hasFilm) return;

    const video = document.createElement("video");
    video.controls = true;
    video.playsInline = true;
    video.preload = "metadata";
    video.setAttribute("controlslist", "nodownload");
    const source = document.createElement("source");
    source.src = src;
    source.type = "video/mp4";
    video.appendChild(source);
    if (hasCaptions) {
      const track = document.createElement("track");
      track.kind = "captions";
      track.srclang = "en";
      track.label = "English";
      track.src = captions;
      track.default = true;
      video.appendChild(track);
    }
    const fallback = document.createElement("p");
    fallback.textContent = "Your browser cannot play this walkthrough film. Download the DMG instead.";
    video.appendChild(fallback);

    stage.replaceChildren(video);
    if (status) {
      status.textContent = hasCaptions
        ? "Walkthrough film for alpha 1.0.0-alpha.10, with captions."
        : "Walkthrough film for alpha 1.0.0-alpha.10. Add demo.en.vtt for captions.";
    }
  });
})();
