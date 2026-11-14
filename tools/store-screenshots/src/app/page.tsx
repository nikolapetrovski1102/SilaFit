"use client";

import { toJpeg } from "html-to-image";
import React, { useCallback, useEffect, useLayoutEffect, useRef, useState } from "react";

/* ------------------------------------------------------------------ */
/* Sizes                                                               */
/* ------------------------------------------------------------------ */

type Size = { label: string; w: number; h: number };
type Device = "iphone" | "android" | "feature-graphic" | "ios-header" | "ios-search";

/** Single landscape artwork (no carousel). */
const BANNERS: Device[] = ["feature-graphic", "ios-header", "ios-search"];
const isBanner = (d: Device) => BANNERS.includes(d);

const SIZES: Record<Device, Size[]> = {
  iphone: [
    { label: '6.9"', w: 1320, h: 2868 },
    { label: '6.5"', w: 1284, h: 2778 },
    { label: '6.5" (older)', w: 1242, h: 2688 },
    { label: '6.3"', w: 1206, h: 2622 },
  ],
  // Play rejects anything taller than 2:1, so no iPhone-ratio canvases here.
  android: [
    { label: "Phone 9:16", w: 1080, h: 1920 },
    { label: "Phone 1:2", w: 1080, h: 2160 },
  ],
  "feature-graphic": [{ label: "Feature graphic", w: 1024, h: 500 }],
  // App Store product-page artwork.
  "ios-header": [
    { label: "Header 16:9", w: 5244, h: 2950 },
    { label: "Header wide", w: 3840, h: 1646 },
  ],
  "ios-search": [
    { label: "Search 16:9", w: 5244, h: 2950 },
    { label: "Search 3:2", w: 3840, h: 2560 },
    { label: "Search 3:2 small", w: 1920, h: 1280 },
  ],
};

const LOCALES = ["en", "mk"] as const;
type Locale = (typeof LOCALES)[number];

/* ------------------------------------------------------------------ */
/* Brand (frontend/lib/core/theme/app_colors.dart)                     */
/* ------------------------------------------------------------------ */

const T = {
  fg: "#f3f7f4",
  muted: "rgba(214,224,219,0.78)",
  accent: "#defb92",
};

/* ------------------------------------------------------------------ */
/* Copy. *word* = accent (marker, lime).                               */
/* ------------------------------------------------------------------ */

type SlideCopy = { label: string; headline: string[]; sub: string };
type Copy = { slides: Record<SlideId, SlideCopy>; fgTagline: string };

type SlideId = "today" | "set-logging" | "progress" | "nutrition" | "splits" | "get-started";

const COPY: Record<Locale, Copy> = {
  en: {
    slides: {
      today: { label: "SilaFit", headline: ["Your strongest", "self, one day", "at a *time.*"], sub: "Plan it. Lift it. Repeat." },
      "set-logging": { label: "Set logging", headline: ["Every rep.", "*Nothing*", "missed."], sub: "Log weight and reps without breaking flow." },
      progress: { label: "Progress", headline: ["Strength you", "can *see.*"], sub: "1RM trends and every personal record." },
      nutrition: { label: "Nutrition", headline: ["Eat for the", "way you *train.*"], sub: "Calories and macros matched to your training." },
      splits: { label: "Splits", headline: ["The right", "split. *Yours.*"], sub: "Matched to your goal, level and schedule." },
      "get-started": { label: "All in one", headline: ["Train. Eat.", "*Progress.*"], sub: "Everything a lifter tracks, nothing they don't." },
    },
    fgTagline: "Splits, nutrition and personal records in one app.",
  },
  mk: {
    slides: {
      today: { label: "SilaFit", headline: ["Твојата најсилна", "верзија, ден", "по *ден.*"], sub: "Планирај. Кревај. Повтори." },
      "set-logging": { label: "Запис на серии", headline: ["Секоја серија.", "*Ништо*", "пропуштено."], sub: "Тежина и повторувања без да застанеш." },
      progress: { label: "Напредок", headline: ["Сила што", "ја *гледаш.*"], sub: "1RM трендови и секој личен рекорд." },
      nutrition: { label: "Исхрана", headline: ["Јади како", "што *тренираш.*"], sub: "Калории и макроа според твојот тренинг." },
      splits: { label: "Сплитови", headline: ["Вистинскиот", "сплит. *Твој.*"], sub: "Според твојата цел, ниво и распоред." },
      "get-started": { label: "Сѐ на едно место", headline: ["Тренирај. Јади.", "*Напредувај.*"], sub: "Сѐ што ти треба во теретана, ништо вишок." },
    },
    fgTagline: "Сплитови, исхрана и лични рекорди во една апликација.",
  },
};

/* ------------------------------------------------------------------ */
/* Images: preloaded as data URIs so html-to-image never re-fetches.   */
/* ------------------------------------------------------------------ */

const SHOTS: SlideId[] = ["today", "set-logging", "progress", "nutrition", "splits", "get-started"];
const shotPath = (platform: "iphone" | "android", locale: Locale, id: SlideId) =>
  `/screenshots/${platform}/${locale}/${id}.png`;

const BASE = "/bg/carousel-base.jpg";
const IMAGE_PATHS = [
  "/app-icon.png",
  ...LOCALES.flatMap((l) => SHOTS.flatMap((s) => [shotPath("iphone", l, s), shotPath("android", l, s)])),
];

const imageCache: Record<string, string> = {};

async function preloadAllImages() {
  await Promise.all(
    [...IMAGE_PATHS, BASE].map(async (path) => {
      try {
        const resp = await fetch(path, { cache: "no-store" });
        if (!resp.ok || !resp.headers.get("content-type")?.startsWith("image/")) return;
        const blob = await resp.blob();
        imageCache[path] = await new Promise<string>((resolve) => {
          const reader = new FileReader();
          reader.onloadend = () => resolve(reader.result as string);
          reader.readAsDataURL(blob);
        });
      } catch {
        /* missing capture: placeholder */
      }
    }),
  );
  await buildBackgrounds();
}

/** Android falls back to the iPhone capture of the same screen. */
function shot(platform: "iphone" | "android", locale: Locale, id: SlideId): string | null {
  if (platform === "android") {
    return imageCache[shotPath("android", locale, id)] ?? imageCache[shotPath("iphone", locale, id)] ?? null;
  }
  return imageCache[shotPath("iphone", locale, id)] ?? null;
}

/* ------------------------------------------------------------------ */
/* Carousel background                                                 */
/*                                                                     */
/* The base panorama (public/bg/carousel-base.jpg) runs behind all six */
/* slides as one strip, so the store carousel reads as one scene. Its  */
/* five glowing nodes are evenly spaced; the strip is scaled so each   */
/* node lands exactly on a slide boundary and the props sit in the     */
/* gaps between phones. Where the panorama runs out (sides, and the    */
/* top on tall canvases) it continues as a mirror image - the seams    */
/* fall behind the first and last phones.                              */
/* ------------------------------------------------------------------ */

const NODE0 = 0.1048; // first node, fraction of base width
const NODE_STEP = 0.1998; // node spacing, fraction of base width
const LINE_TOP = 0.25; // highest point of the line's glow, fraction of base height

const bgCache: Record<string, string> = {};
const bgKey = (w: number, h: number, i: number) => `${w}x${h}#${i}`;

function loadImg(src: string) {
  return new Promise<HTMLImageElement>((resolve, reject) => {
    const im = new Image();
    im.onload = () => resolve(im);
    im.onerror = reject;
    im.src = src;
  });
}

/** Draws `img` at (x,y,w,h), optionally mirrored about its own centre. */
function drawTile(ctx: CanvasRenderingContext2D, img: HTMLImageElement, x: number, y: number, w: number, h: number, fx: boolean, fy: boolean) {
  ctx.save();
  ctx.translate(x + (fx ? w : 0), y + (fy ? h : 0));
  ctx.scale(fx ? -1 : 1, fy ? -1 : 1);
  ctx.drawImage(img, 0, 0, w, h);
  ctx.restore();
}

function paintStrip(ctx: CanvasRenderingContext2D, img: HTMLImageElement, cW: number, cH: number) {
  const bw = cW / NODE_STEP;
  const bh = (bw * img.height) / img.width;
  const bx = cW - NODE0 * bw;
  // Floor anchored to the bottom edge, unless that would lift the glowing
  // line (peaks at ~25% of the base height) into the caption: then the
  // scene drops and the floor continues as a mirrored reflection.
  const by = Math.max(cH - bh, captionBottom(cW, cH) + cH * 0.035 - LINE_TOP * bh);
  ctx.imageSmoothingEnabled = true;
  ctx.imageSmoothingQuality = "high";
  for (const dy of [-1, 0, 1]) {
    if (dy === -1 && by <= 0) continue;
    if (dy === 1 && by + bh >= cH) continue;
    for (const dx of [-1, 0, 1]) {
      drawTile(ctx, img, bx + dx * bw, by + dy * bh, bw, bh, dx !== 0, dy !== 0);
    }
  }
}

async function buildBackgrounds() {
  const src = imageCache[BASE];
  if (!src) return;
  const img = await loadImg(src);
  for (const s of [...SIZES.iphone, ...SIZES.android]) {
    for (let i = 0; i < SHOTS.length; i++) {
      const c = document.createElement("canvas");
      c.width = s.w;
      c.height = s.h;
      const ctx = c.getContext("2d")!;
      ctx.translate(-i * s.w, 0);
      paintStrip(ctx, img, s.w, s.h);
      ctx.setTransform(1, 0, 0, 1, 0, 0);
      // Deepen the wall behind the caption so the type sits on calm dark.
      const g = ctx.createLinearGradient(0, 0, 0, s.h * 0.42);
      g.addColorStop(0, "rgba(9,20,22,0.62)");
      g.addColorStop(1, "rgba(9,20,22,0)");
      ctx.fillStyle = g;
      ctx.fillRect(0, 0, s.w, s.h);
      bgCache[bgKey(s.w, s.h, i)] = c.toDataURL("image/jpeg", 0.95);
    }
  }
  // Feature graphic: the centre of the panorama, covering 1024x500.
  const fg = SIZES["feature-graphic"][0];
  const c = document.createElement("canvas");
  c.width = fg.w;
  c.height = fg.h;
  const ctx = c.getContext("2d")!;
  ctx.imageSmoothingQuality = "high";
  const bh = fg.h * 1.04;
  const bw = (bh * img.width) / img.height;
  ctx.drawImage(img, fg.w * 0.5 - bw * 0.47, fg.h - bh, bw, bh);
  const g = ctx.createLinearGradient(0, 0, fg.w * 0.62, 0);
  g.addColorStop(0, "rgba(9,20,22,0.88)");
  g.addColorStop(0.7, "rgba(9,20,22,0.55)");
  g.addColorStop(1, "rgba(9,20,22,0)");
  ctx.fillStyle = g;
  ctx.fillRect(0, 0, fg.w, fg.h);
  bgCache[bgKey(fg.w, fg.h, 0)] = c.toDataURL("image/jpeg", 0.95);

  // App Store artwork: the panorama's centre behind the phones. Up to ~2.4x
  // upscaled on the largest canvas, so a slight blur turns softness into depth.
  for (const s of [...SIZES["ios-header"], ...SIZES["ios-search"]]) {
    const key = bgKey(s.w, s.h, 0);
    if (bgCache[key]) continue;
    const c = document.createElement("canvas");
    c.width = s.w;
    c.height = s.h;
    const ctx = c.getContext("2d")!;
    ctx.imageSmoothingQuality = "high";
    ctx.fillStyle = "#0d1a1c";
    ctx.fillRect(0, 0, s.w, s.h);
    const bh = Math.max(s.h * 1.06, (s.w / img.width) * img.height * 1.0);
    const bw = (bh * img.width) / img.height;
    ctx.filter = `blur(${Math.round(s.h * 0.0025)}px)`;
    ctx.drawImage(img, s.w * 0.62 - bw * 0.5, s.h - bh, bw, bh);
    ctx.filter = "none";
    const g = ctx.createLinearGradient(0, 0, s.w * 0.7, 0);
    g.addColorStop(0, "rgba(9,20,22,0.9)");
    g.addColorStop(0.6, "rgba(9,20,22,0.55)");
    g.addColorStop(1, "rgba(9,20,22,0.1)");
    ctx.fillStyle = g;
    ctx.fillRect(0, 0, s.w, s.h);
    const v = ctx.createLinearGradient(0, s.h * 0.6, 0, s.h);
    v.addColorStop(0, "rgba(9,20,22,0)");
    v.addColorStop(1, "rgba(9,20,22,0.55)");
    ctx.fillStyle = v;
    ctx.fillRect(0, 0, s.w, s.h);
    bgCache[key] = c.toDataURL("image/jpeg", 0.95);
  }
}

function Backdrop({ cW, cH, i }: { cW: number; cH: number; i: number }) {
  const src = bgCache[bgKey(cW, cH, i)];
  // eslint-disable-next-line @next/next/no-img-element
  return src ? <img src={src} alt="" style={{ position: "absolute", inset: 0, width: cW, height: cH }} /> : <div style={{ position: "absolute", inset: 0, background: "#172d30" }} />;
}

/* ------------------------------------------------------------------ */
/* Device frames (CSS only)                                            */
/* ------------------------------------------------------------------ */

type FrameProps = { src: string | null; missing: string; style?: React.CSSProperties };

function ScreenImage({ src, missing }: { src: string | null; missing: string }) {
  if (!src) {
    return (
      <div
        style={{
          width: "100%", height: "100%", background: "repeating-linear-gradient(45deg,#203538 0 18px,#1a2e31 18px 36px)",
          display: "flex", alignItems: "center", justifyContent: "center", textAlign: "center",
          color: "#defb92", fontFamily: "monospace", fontSize: "4cqw", padding: "8%",
        }}
      >
        missing
        <br />
        {missing}
      </div>
    );
  }
  // eslint-disable-next-line @next/next/no-img-element
  return <img src={src} alt="" draggable={false} style={{ display: "block", width: "100%", height: "100%", objectFit: "cover", objectPosition: "top" }} />;
}

/** iPhone 16 Pro Max-ish: titanium rail, black bezel, Dynamic Island. */
const IPHONE_RATIO = 0.4835; // frame width / height
function IPhone({ src, missing, style }: FrameProps) {
  return (
    <div style={{ position: "relative", aspectRatio: `${IPHONE_RATIO}`, containerType: "inline-size", ...style }}>
      {/* side buttons */}
      {[
        { left: "-0.9%", top: "18%", h: "4%" },
        { left: "-0.9%", top: "25%", h: "7%" },
        { left: "-0.9%", top: "33.5%", h: "7%" },
        { right: "-0.9%", top: "27%", h: "11%" },
      ].map((b, i) => (
        <div key={i} style={{ position: "absolute", width: "1.6%", height: b.h, top: b.top, left: b.left, right: b.right, borderRadius: 4, background: "linear-gradient(90deg,#5b5f60,#2c2f30)" }} />
      ))}
      <div
        style={{
          position: "absolute", inset: 0, borderRadius: "15.5% / 7.2%",
          background: "linear-gradient(145deg,#6a6e6f 0%,#2b2e2f 30%,#4a4e4f 60%,#1f2223 100%)",
          padding: "1.1%",
          boxShadow: "0 3cqw 9cqw rgba(0,0,0,0.55), 0 1cqw 2cqw rgba(0,0,0,0.35)",
        }}
      >
        <div style={{ width: "100%", height: "100%", borderRadius: "14.8% / 6.9%", background: "#050505", padding: "3.2%" }}>
          <div style={{ position: "relative", width: "100%", height: "100%", borderRadius: "12.4% / 5.75%", overflow: "hidden", background: "#000" }}>
            <ScreenImage src={src} missing={missing} />
            <div style={{ position: "absolute", top: "1.15%", left: "50%", transform: "translateX(-50%)", width: "30%", aspectRatio: "126/37", borderRadius: 999, background: "#000" }} />
          </div>
        </div>
      </div>
    </div>
  );
}

/** Generic Android phone: flat rail, thin bezel, punch-hole camera. */
const ANDROID_RATIO = 0.468;
function AndroidPhone({ src, missing, style }: FrameProps) {
  return (
    <div style={{ position: "relative", aspectRatio: `${ANDROID_RATIO}`, containerType: "inline-size", ...style }}>
      <div style={{ position: "absolute", right: "-0.9%", top: "22%", width: "1.5%", height: "8%", borderRadius: 4, background: "#2b2e30" }} />
      <div style={{ position: "absolute", right: "-0.9%", top: "33%", width: "1.5%", height: "13%", borderRadius: 4, background: "#2b2e30" }} />
      <div
        style={{
          position: "absolute", inset: 0, borderRadius: "11% / 5.2%", background: "linear-gradient(160deg,#34383b,#141617)",
          padding: "2.6%", boxShadow: "0 3cqw 9cqw rgba(0,0,0,0.55), inset 0 0 0 1px rgba(255,255,255,0.08)",
        }}
      >
        <div style={{ position: "relative", width: "100%", height: "100%", borderRadius: "8.6% / 4.1%", overflow: "hidden", background: "#000" }}>
          <ScreenImage src={src} missing={missing} />
          <div style={{ position: "absolute", top: "1.4%", left: "50%", transform: "translateX(-50%)", width: "3.6%", aspectRatio: "1", borderRadius: "50%", background: "#050505", boxShadow: "0 0 0 2px rgba(255,255,255,0.05)" }} />
        </div>
      </div>
    </div>
  );
}

type FrameComp = (p: FrameProps) => React.ReactElement;

/* ------------------------------------------------------------------ */
/* Caption                                                             */
/* ------------------------------------------------------------------ */

/**
 * The graffiti face: Permanent Marker, falling through to Shantell Sans for
 * Cyrillic. The variation settings only affect Shantell (ExtraBold, informal).
 */
const MARKER: React.CSSProperties = {
  fontFamily: "var(--marker)", fontWeight: 400, fontStyle: "normal", color: T.accent, textTransform: "uppercase",
  letterSpacing: "0.01em", fontVariationSettings: "'wght' 800, 'INFM' 100, 'BNCE' 50", WebkitTextStroke: "var(--marker-stroke) currentColor",
};

/** A light stroke roughens the edges; Shantell is already heavy, so it gets less. */
const markerStroke = (locale: Locale) => ({ "--marker-stroke": locale === "mk" ? "0.008em" : "0.022em" }) as React.CSSProperties;

function Headline({ lines, size }: { lines: string[]; size: number }) {
  return (
    <div style={{ fontSize: size, fontWeight: 800, lineHeight: 1.02, letterSpacing: "-0.028em", color: T.fg, textShadow: "0 0.04em 0.3em rgba(0,0,0,0.35)" }}>
      {lines.map((line, i) => (
        <div key={i}>
          {line.split(/(\*[^*]+\*)/).map((seg, j) =>
            seg.startsWith("*") ? (
              <span key={j} style={{ ...MARKER, fontSize: "1.04em", display: "inline-block", transform: "rotate(-2.5deg) translateY(0.02em)", textShadow: "0 0 0.4em rgba(222,251,146,0.3)" }}>
                {seg.slice(1, -1)}
              </span>
            ) : (
              <span key={j}>{seg}</span>
            ),
          )}
        </div>
      ))}
    </div>
  );
}

/** Type scales with width, eased down on canvases shorter than the iPhone's 1:2.17. */
const typeScale = (cW: number, cH: number) => Math.min(1, cH / cW / 2.17);

function Caption({ copy, cW, cH }: { copy: SlideCopy; cW: number; cH: number }) {
  const u = cW * typeScale(cW, cH);
  return (
    <div style={{ textAlign: "center" }}>
      <div style={{ ...MARKER, fontSize: u * 0.046, letterSpacing: "0.08em", marginBottom: u * 0.018 }}>{copy.label}</div>
      <Headline lines={copy.headline} size={u * 0.108} />
      <div style={{ margin: `${u * 0.026}px auto 0`, maxWidth: u * 0.74, fontSize: u * 0.046, color: T.muted, fontWeight: 400, lineHeight: 1.28 }}>{copy.sub}</div>
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* Slides: one composition for all six, as in the carousel preview.    */
/* ------------------------------------------------------------------ */

type SlideProps = { cW: number; cH: number; locale: Locale; Frame: FrameComp; ratio: number; platform: "iphone" | "android" };

/** Caption block bottom for the tallest (3-line) headline. */
const captionBottom = (cW: number, cH: number) => cH * 0.05 + cW * typeScale(cW, cH) * 0.52;

/** Same phone size on every slide of a canvas, so the carousel stays even. */
function phoneWidth(cW: number, cH: number, ratio: number) {
  const free = cH - captionBottom(cW, cH) - cH * 0.035 - cH * 0.018;
  return Math.min(cW * 0.66, free * ratio);
}

const Canvas = ({ children, locale }: { children: React.ReactNode; locale: Locale }) => (
  <div style={{ width: "100%", height: "100%", position: "relative", overflow: "hidden", ...markerStroke(locale) }}>{children}</div>
);

function PhoneSlide({ cW, cH, locale, Frame, ratio, platform, index }: SlideProps & { index: number }) {
  const id = SHOTS[index];
  const pw = phoneWidth(cW, cH, ratio);
  const ph = pw / ratio;
  const bottom = cH * 0.018;
  return (
    <Canvas locale={locale}>
      <Backdrop cW={cW} cH={cH} i={index} />
      <div style={{ position: "absolute", top: cH * 0.05, left: cW * 0.05, right: cW * 0.05 }}>
        <Caption copy={COPY[locale].slides[id]} cW={cW} cH={cH} />
      </div>
      {/* lime rim light behind the phone */}
      <div
        style={{
          position: "absolute", width: pw * 1.25, height: ph * 0.9, left: (cW - pw * 1.25) / 2, bottom: bottom + ph * 0.05,
          background: "radial-gradient(closest-side, rgba(222,251,146,0.16), rgba(222,251,146,0) 100%)",
        }}
      />
      {/* contact shadow on the floor */}
      <div
        style={{
          position: "absolute", width: pw * 1.2, height: ph * 0.07, left: (cW - pw * 1.2) / 2, bottom: bottom - ph * 0.03,
          background: "radial-gradient(closest-side, rgba(0,0,0,0.7), rgba(0,0,0,0))",
        }}
      />
      <Frame src={shot(platform, locale, id)} missing={`${platform}/${locale}/${id}.png`} style={{ position: "absolute", width: pw, left: (cW - pw) / 2, bottom }} />
    </Canvas>
  );
}

function FeatureGraphic({ cW, cH, locale }: { cW: number; cH: number; locale: Locale }) {
  const c = COPY[locale];
  const pw = cH * 0.86 * IPHONE_RATIO;
  return (
    <Canvas locale={locale}>
      <Backdrop cW={cW} cH={cH} i={0} />
      <div style={{ position: "absolute", left: cW * 0.055, top: cH * 0.14, width: cW * 0.52 }}>
        <div style={{ display: "flex", alignItems: "center", gap: cW * 0.016 }}>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src={imageCache["/app-icon.png"]} alt="" style={{ width: cW * 0.064, height: cW * 0.064, borderRadius: cW * 0.015 }} />
          <div style={{ ...MARKER, fontSize: cW * 0.034, letterSpacing: "0.06em" }}>SilaFit</div>
        </div>
        <div style={{ marginTop: cH * 0.06 }}>
          <Headline lines={c.slides["get-started"].headline} size={cW * (locale === "mk" ? 0.063 : 0.07)} />
        </div>
        <div style={{ marginTop: cH * 0.045, fontSize: cW * 0.021, color: T.muted, fontWeight: 400, lineHeight: 1.3, maxWidth: cW * 0.42 }}>{c.fgTagline}</div>
      </div>
      <IPhone src={shot("iphone", locale, "nutrition")} missing={`${locale}/nutrition.png`} style={{ position: "absolute", width: pw, right: cW * 0.215, bottom: -cH * 0.1 }} />
      <IPhone src={shot("iphone", locale, "today")} missing={`${locale}/today.png`} style={{ position: "absolute", width: pw, right: cW * 0.035, bottom: -cH * 0.22 }} />
    </Canvas>
  );
}

/* ------------------------------------------------------------------ */
/* App Store header / search artwork: copy left, three phones right.   */
/* One layout for 16:9, 3:2 and the wide 2.33:1 header.                */
/* ------------------------------------------------------------------ */

const ARTWORK: Record<"ios-header" | "ios-search", { copy: SlideId; sub: (l: Locale) => string; phones: [SlideId, SlideId, SlideId] }> = {
  "ios-header": { copy: "today", sub: (l) => COPY[l].slides.today.sub, phones: ["set-logging", "today", "progress"] },
  "ios-search": { copy: "get-started", sub: (l) => COPY[l].fgTagline, phones: ["nutrition", "today", "splits"] },
};

function AppArtwork({ cW, cH, locale, kind }: { cW: number; cH: number; locale: Locale; kind: "ios-header" | "ios-search" }) {
  const a = ARTWORK[kind];
  const copy = COPY[locale].slides[a.copy];
  // Phone group: front phone plus two at 86%, overlapping; at most half the width.
  const pw = Math.min(cH * 0.8 * IPHONE_RATIO, (cW * 0.46) / 2.6);
  const ph = pw / IPHONE_RATIO;
  const back = pw * 0.86;
  const spread = pw * 0.5 + back * 0.38; // back phones show ~88% of their width
  const groupW = spread * 2 + back;
  const right = cW * 0.05;
  const cx = cW - right - groupW / 2;
  const cy = cH * 0.53;
  // Text column takes what the phones leave.
  const left = cW * 0.06;
  const colW = cx - groupW / 2 - left - cW * 0.03;
  const chars = Math.max(...copy.headline.map((l) => l.replace(/\*/g, "").length));
  const hs = Math.min(cH * 0.105, colW / (chars * 0.5));
  const phone = (id: SlideId, x: number, w: number, z: number) => (
    <IPhone key={id + x} src={shot("iphone", locale, id)} missing={`${locale}/${id}.png`} style={{ position: "absolute", width: w, left: x - w / 2, top: cy - w / IPHONE_RATIO / 2 + (w < pw ? -ph * 0.03 : ph * 0.02), zIndex: z }} />
  );
  return (
    <Canvas locale={locale}>
      <Backdrop cW={cW} cH={cH} i={0} />
      <div style={{ position: "absolute", left, width: colW, top: 0, bottom: 0, display: "flex", flexDirection: "column", justifyContent: "center" }}>
        <div style={{ display: "flex", alignItems: "center", gap: hs * 0.22 }}>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src={imageCache["/app-icon.png"]} alt="" style={{ width: hs * 0.95, height: hs * 0.95, borderRadius: hs * 0.22 }} />
          <div style={{ ...MARKER, fontSize: hs * 0.48, letterSpacing: "0.06em" }}>SilaFit</div>
        </div>
        <div style={{ marginTop: hs * 0.55 }}>
          <Headline lines={copy.headline} size={hs} />
        </div>
        <div style={{ marginTop: hs * 0.45, fontSize: hs * 0.32, color: T.muted, lineHeight: 1.3, maxWidth: colW * 0.9 }}>{a.sub(locale)}</div>
      </div>
      <div
        style={{
          position: "absolute", width: groupW * 1.3, height: ph * 1.1, left: cx - groupW * 0.65, top: cy - ph * 0.55,
          background: "radial-gradient(closest-side, rgba(222,251,146,0.14), rgba(222,251,146,0))",
        }}
      />
      {phone(a.phones[0], cx - spread, back, 1)}
      {phone(a.phones[2], cx + spread, back, 1)}
      {phone(a.phones[1], cx, pw, 2)}
    </Canvas>
  );
}

/* ------------------------------------------------------------------ */
/* Page                                                                */
/* ------------------------------------------------------------------ */

function Slide({ device, index, cW, cH, locale }: { device: Device; index: number; cW: number; cH: number; locale: Locale }) {
  if (device === "feature-graphic") return <FeatureGraphic cW={cW} cH={cH} locale={locale} />;
  if (device === "ios-header" || device === "ios-search") return <AppArtwork cW={cW} cH={cH} locale={locale} kind={device} />;
  const isIphone = device === "iphone";
  return <PhoneSlide index={index} cW={cW} cH={cH} locale={locale} Frame={isIphone ? IPhone : AndroidPhone} ratio={isIphone ? IPHONE_RATIO : ANDROID_RATIO} platform={isIphone ? "iphone" : "android"} />;
}

function Preview({ children, w, h }: { children: React.ReactNode; w: number; h: number }) {
  const ref = useRef<HTMLDivElement>(null);
  const [scale, setScale] = useState(0.2);
  useLayoutEffect(() => {
    const el = ref.current;
    if (!el) return;
    const ro = new ResizeObserver(() => setScale(el.clientWidth / w));
    ro.observe(el);
    return () => ro.disconnect();
  }, [w]);
  return (
    <div ref={ref} style={{ width: "100%", aspectRatio: `${w}/${h}`, position: "relative", overflow: "hidden", borderRadius: 4 }}>
      <div style={{ width: w, height: h, transform: `scale(${scale})`, transformOrigin: "top left", position: "absolute", top: 0, left: 0 }}>{children}</div>
    </div>
  );
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

export default function ScreenshotsPage() {
  const [ready, setReady] = useState(false);
  const [locale, setLocale] = useState<Locale>("en");
  const [device, setDevice] = useState<Device>("iphone");
  const [sizeIdx, setSizeIdx] = useState(0);
  const [exporting, setExporting] = useState<string | null>(null);
  const exportRefs = useRef<(HTMLDivElement | null)[]>([]);

  useEffect(() => {
    const q = new URLSearchParams(window.location.search);
    const d = q.get("device") as Device | null;
    const l = q.get("locale") as Locale | null;
    if (d && d in SIZES) setDevice(d);
    if (l && (LOCALES as readonly string[]).includes(l)) setLocale(l);
    const sz = Number(q.get("size"));
    if (sz > 0) setSizeIdx(sz);
    preloadAllImages().then(() => document.fonts.ready).then(() => setReady(true));
  }, []);

  const sizes = SIZES[device];
  const size = sizes[Math.min(sizeIdx, sizes.length - 1)];
  const count = isBanner(device) ? 1 : SHOTS.length;
  const slideId = (i: number) => (isBanner(device) ? device : SHOTS[i]);

  const capture = useCallback(async (el: HTMLElement, w: number, h: number) => {
    el.style.left = "0px";
    el.style.zIndex = "-1";
    // JPEG: both stores reject screenshots that carry an alpha channel,
    // and html-to-image's PNGs always do.
    const opts = { width: w, height: h, pixelRatio: 1, cacheBust: true, backgroundColor: "#000", quality: 0.95 };
    await toJpeg(el, opts); // warm-up pass: fonts/images
    const url = await toJpeg(el, opts);
    el.style.left = "-99999px";
    el.style.zIndex = "";
    return url;
  }, []);

  const download = (url: string, name: string) => {
    const a = document.createElement("a");
    a.href = url;
    a.download = name;
    a.click();
  };

  const exportCurrent = async (loc: Locale, s: Size) => {
    for (let i = 0; i < count; i++) {
      setExporting(`${loc.toUpperCase()} ${s.w}×${s.h} · ${i + 1}/${count}`);
      const el = exportRefs.current[i];
      if (!el) continue;
      const url = await capture(el, s.w, s.h);
      download(url, `silafit-${device}-${loc}-${s.w}x${s.h}-${String(i + 1).padStart(2, "0")}-${slideId(i)}.jpg`);
      await sleep(300);
    }
  };

  const exportAll = async () => {
    await exportCurrent(locale, size);
    setExporting(null);
  };

  /** Every locale × every size for this device. */
  const exportEverything = async () => {
    const startLocale = locale;
    const startSize = sizeIdx;
    for (const loc of LOCALES) {
      for (let si = 0; si < sizes.length; si++) {
        setLocale(loc);
        setSizeIdx(si);
        await sleep(600); // let the offscreen copies re-render
        await exportCurrent(loc, sizes[si]);
      }
    }
    setLocale(startLocale);
    setSizeIdx(startSize);
    setExporting(null);
  };

  if (!ready) return <p style={{ padding: 24 }}>Loading images and fonts…</p>;

  const missing = IMAGE_PATHS.filter((p) => p.includes(`/iphone/${locale}/`) && !imageCache[p]);

  const btn = (active: boolean): React.CSSProperties => ({
    padding: "5px 14px", borderRadius: 6, border: "none", cursor: "pointer", fontSize: 12, fontWeight: 600, whiteSpace: "nowrap",
    background: active ? "white" : "transparent", color: active ? "#172d30" : "#6b7280",
  });

  return (
    <div style={{ minHeight: "100vh", position: "relative", overflowX: "hidden" }}>
      <div style={{ position: "sticky", top: 0, zIndex: 50, background: "white", borderBottom: "1px solid #e5e7eb", display: "flex", alignItems: "center" }}>
        <div style={{ flex: 1, display: "flex", alignItems: "center", gap: 10, padding: "10px 16px", overflowX: "auto", minWidth: 0 }}>
          <span style={{ fontWeight: 800, fontSize: 14, whiteSpace: "nowrap" }}>SilaFit · Screenshots</span>
          <div style={{ display: "flex", gap: 4, background: "#f1f3f1", borderRadius: 8, padding: 4 }}>
            {LOCALES.map((l) => (
              <button key={l} style={btn(locale === l)} onClick={() => setLocale(l)}>
                {l.toUpperCase()}
              </button>
            ))}
          </div>
          <div style={{ display: "flex", gap: 4, background: "#f1f3f1", borderRadius: 8, padding: 4 }}>
            {(["iphone", "android", "feature-graphic", "ios-header", "ios-search"] as Device[]).map((d) => (
              <button key={d} style={btn(device === d)} onClick={() => { setDevice(d); setSizeIdx(0); }}>
                {({ iphone: "iPhone", android: "Android", "feature-graphic": "Feature graphic", "ios-header": "iOS header", "ios-search": "iOS search" } as Record<Device, string>)[d]}
              </button>
            ))}
          </div>
          {sizes.length > 1 && (
            <select value={sizeIdx} onChange={(e) => setSizeIdx(Number(e.target.value))} style={{ fontSize: 12, border: "1px solid #e5e7eb", borderRadius: 6, padding: "5px 10px" }}>
              {sizes.map((s, i) => (
                <option key={i} value={i}>
                  {s.label} — {s.w}×{s.h}
                </option>
              ))}
            </select>
          )}
          {missing.length > 0 && <span style={{ fontSize: 12, color: "#b45309", whiteSpace: "nowrap" }}>{locale.toUpperCase()}: {missing.length} of 6 captures missing</span>}
        </div>
        <div style={{ flexShrink: 0, display: "flex", gap: 8, padding: "10px 16px", borderLeft: "1px solid #e5e7eb" }}>
          <button onClick={exportAll} disabled={!!exporting} style={{ padding: "7px 16px", background: "#f1f3f1", color: "#172d30", border: "none", borderRadius: 8, fontSize: 12, fontWeight: 700, cursor: "pointer", whiteSpace: "nowrap" }}>
            Export view
          </button>
          <button onClick={exportEverything} disabled={!!exporting} style={{ padding: "7px 16px", background: exporting ? "#6b7f6f" : "#172d30", color: "#defb92", border: "none", borderRadius: 8, fontSize: 12, fontWeight: 700, cursor: "pointer", whiteSpace: "nowrap" }}>
            {exporting ? `Exporting… ${exporting}` : "Export EN+MK, all sizes"}
          </button>
        </div>
      </div>

      <div
        style={{
          display: "grid", columnGap: isBanner(device) ? 24 : 4, rowGap: 24, padding: 24,
          gridTemplateColumns: isBanner(device) ? "minmax(0, 1100px)" : "repeat(6, minmax(0, 1fr))",
        }}
      >
        {Array.from({ length: count }, (_, i) => (
          <div key={`${device}-${i}`}>
            <Preview w={size.w} h={size.h}>
              <Slide device={device} index={i} cW={size.w} cH={size.h} locale={locale} />
            </Preview>
            <div style={{ fontSize: 12, color: "#6b7280", marginTop: 6 }}>
              {String(i + 1).padStart(2, "0")} · {slideId(i)}
            </div>
          </div>
        ))}
      </div>

      {/* Full-resolution copies for export */}
      {Array.from({ length: count }, (_, i) => (
        <div
          key={`export-${device}-${i}`}
          ref={(el) => {
            exportRefs.current[i] = el;
          }}
          style={{ position: "absolute", left: -99999, top: 0, width: size.w, height: size.h, overflow: "hidden" }}
        >
          <Slide device={device} index={i} cW={size.w} cH={size.h} locale={locale} />
        </div>
      ))}
    </div>
  );
}
