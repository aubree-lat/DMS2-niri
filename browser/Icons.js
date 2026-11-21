.pragma library

// File → freedesktop icon names (first match that the icon theme has wins).

const special = {
    "": ["user-home"],
    "Desktop": ["user-desktop", "folder-desktop"],
    "Documents": ["folder-documents"],
    "Downloads": ["folder-download", "folder-downloads"],
    "Pictures": ["folder-pictures", "folder-images"],
    "Music": ["folder-music", "folder-sound"],
    "Videos": ["folder-videos", "folder-video"],
    "Public": ["folder-publicshare"],
    "Templates": ["folder-templates"],
    "Projects": ["folder-development", "folder-projects"],
    "projects": ["folder-development", "folder-projects"],
    ".git": ["folder-git"],
    ".config": ["folder-system", "folder-configure"]
};

const bySuffix = {
    png: "image", jpg: "image", jpeg: "image", gif: "image", webp: "image", bmp: "image", svg: "image-svg", avif: "image", jxl: "image", heic: "image", ico: "image", tiff: "image",
    mp4: "video", mkv: "video", webm: "video", mov: "video", avi: "video", m4v: "video",
    mp3: "audio", flac: "audio", ogg: "audio", oga: "audio", opus: "audio", wav: "audio", m4a: "audio", aac: "audio",
    zip: "archive", tar: "archive", gz: "archive", xz: "archive", zst: "archive", bz2: "archive", "7z": "archive", rar: "archive", tgz: "archive",
    iso: "disc", img: "disc",
    pdf: "pdf",
    txt: "text", md: "markdown", log: "text", conf: "config", ini: "config", toml: "config", yaml: "config", yml: "config", json: "json", jsonc: "json", kdl: "config",
    sh: "script", bash: "script", zsh: "script", fish: "script", py: "python", rs: "rust", js: "javascript", ts: "javascript", qml: "code", c: "csrc", h: "chdr", cpp: "cppsrc", go: "code", java: "java", html: "html", css: "css",
    doc: "doc", docx: "doc", odt: "doc", xls: "sheet", xlsx: "sheet", ods: "sheet", ppt: "slides", pptx: "slides", odp: "slides",
    deb: "package", rpm: "package", pkg: "package", appimage: "exec", exe: "exe", msi: "exe", jar: "java",
    ttf: "font", otf: "font", woff: "font", woff2: "font",
    torrent: "torrent", desktop: "desktop"
};

const names = {
    image: ["image-x-generic"], "image-svg": ["image-svg+xml", "image-x-generic"],
    video: ["video-x-generic"], audio: ["audio-x-generic"],
    archive: ["package-x-generic", "application-x-archive"], disc: ["application-x-cd-image", "media-optical"],
    pdf: ["application-pdf"], text: ["text-x-generic"], markdown: ["text-markdown", "text-x-generic"],
    config: ["text-x-generic-template", "text-x-generic"], json: ["application-json", "text-x-generic"],
    script: ["application-x-shellscript", "text-x-script"], python: ["text-x-python"], rust: ["text-rust", "text-x-rust", "text-x-script"],
    javascript: ["application-javascript", "text-x-javascript"], code: ["text-x-script"], csrc: ["text-x-csrc"], chdr: ["text-x-chdr"], cppsrc: ["text-x-c++src"],
    java: ["application-x-java", "text-x-java"], html: ["text-html"], css: ["text-css"],
    doc: ["x-office-document"], sheet: ["x-office-spreadsheet"], slides: ["x-office-presentation"],
    package: ["application-x-rpm", "package-x-generic"], exec: ["application-x-executable"], exe: ["application-x-ms-dos-executable", "application-x-executable"],
    font: ["font-x-generic"], torrent: ["application-x-bittorrent"], desktop: ["application-x-desktop"],
    unknown: ["application-octet-stream", "text-x-generic", "unknown"]
};

const labels = {
    image: "image", "image-svg": "vector image", video: "video", audio: "audio", archive: "archive", disc: "disc image",
    pdf: "pdf document", text: "text", markdown: "markdown", config: "configuration", json: "json", script: "shell script",
    python: "python", rust: "rust source", javascript: "script", code: "source code", csrc: "c source", chdr: "c header", cppsrc: "c++ source",
    java: "java", html: "web page", css: "stylesheet", doc: "document", sheet: "spreadsheet", slides: "presentation",
    package: "package", exec: "appimage", exe: "windows program", font: "font", torrent: "torrent", desktop: "app shortcut", unknown: "file"
};

function kindOf(suffix) {
    return bySuffix[(suffix || "").toLowerCase()] || "unknown";
}

function isImage(suffix) {
    const k = kindOf(suffix);
    return k === "image" || k === "image-svg";
}

function candidates(isDir, fileName, suffix, relToHome) {
    if (isDir) {
        const s = special[relToHome !== undefined ? relToHome : ""];
        if (relToHome !== undefined && s)
            return s.concat(["folder"]);
        if (special[fileName] && fileName.startsWith("."))
            return special[fileName].concat(["folder"]);
        return ["folder"];
    }
    return names[kindOf(suffix)] || names.unknown;
}

function label(isDir, suffix) {
    return isDir ? "folder" : (labels[kindOf(suffix)] || "file");
}

function humanSize(bytes) {
    if (bytes < 1024)
        return bytes + " b";
    const units = ["kib", "mib", "gib", "tib"];
    let v = bytes / 1024;
    let i = 0;
    while (v >= 1024 && i < units.length - 1) {
        v /= 1024;
        i++;
    }
    return (v >= 100 ? v.toFixed(0) : v.toFixed(1)) + " " + units[i];
}
