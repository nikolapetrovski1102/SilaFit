#!/usr/bin/env python3
"""Rate-limited Muscle & Strength catalog collector."""

from __future__ import annotations

import argparse
import asyncio
import csv
import hashlib
import json
import random
import re
import sys
import unicodedata
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable
from urllib.parse import parse_qsl, urlencode, urljoin, urlsplit, urlunsplit
from urllib.robotparser import RobotFileParser

from bs4 import BeautifulSoup, Tag
from playwright.async_api import Browser, BrowserContext, Page, Response, async_playwright


BASE_URL = "https://www.muscleandstrength.com"
WORKOUTS_URL = f"{BASE_URL}/workout-routines"
DIETS_URL = f"{BASE_URL}/diet-plans"
RECIPES_URL = f"{BASE_URL}/recipes"
WORKOUT_CATEGORY_PATHS = {
    "Women": "/workouts/women",
    "Muscle Building": "/workouts/muscle-building",
    "Fat Loss": "/workouts/fat-loss",
    "Men": "/workouts/men",
    "Strength": "/workouts/strength",
    "Abs": "/workouts/abs",
    "Full Body": "/workouts/full-body",
    "Sports Performance": "/workouts/sports",
    "Bodyweight": "/workouts/bodyweight",
    "Beginner": "/workouts/beginner",
    "At Home": "/workouts/home",
    "Celebrity": "/workouts/celebrity",
    "Cardio": "/workouts/cardio",
    "Chest": "/workouts/chest",
    "Back": "/workouts/back",
    "Biceps": "/workouts/biceps",
    "Shoulders": "/workouts/shoulders",
    "Legs": "/workouts/legs",
    "Triceps": "/workouts/triceps",
    "Glutes": "/workouts/other",
}
USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0 Safari/537.36"
)
WORKOUT_URL_PREFIXES = (f"{BASE_URL}/workouts/", f"{BASE_URL}/content/")

# The checklist deliberately uses shorter, product-facing titles. These entries
# resolve titles that are not exact matches for the source catalog. Exact title
# matches continue to resolve automatically.
WORKOUT_TITLE_URLS = {
    "P.H.U.L. (Power Hypertrophy Upper Lower)": f"{BASE_URL}/workouts/phul-workout",
    "6 Day Push/Pull/Legs (PPL) Split & Meal Plan": f"{BASE_URL}/workouts/6-day-powerbuilding-split-meal-plan",
    "M-F Workout Routine: 5 Day Body Part Split": f"{BASE_URL}/workouts/m-f-workout-routine",
    "10 Week Mass Building Program for Hardgainers": f"{BASE_URL}/workouts/10-week-mass-building-program.html",
    "5 Day Dumbbell Only Workout": f"{BASE_URL}/workouts/5-day-dumbbell-only-workout-split",
    "Dumbbell Only Workout: 4 Day Upper/Lower": f"{BASE_URL}/workouts/dumbbell-only-upper-lower-workout-routine",
    "3 Day Push/Pull/Legs (PPL) for Beginners": f"{BASE_URL}/workouts/3-day-PPL-workout-for-beginners",
    "8-Week Muscle Building Program for Adults 40+": f"{BASE_URL}/content/8-week-muscle-building-program-adults-40",
    "The Butt Builder Workout": f"{BASE_URL}/workouts/the-butt-builder.html",
    "Body Like A God: Bodyweight Muscle Building Plan": f"{BASE_URL}/workouts/body-god-complete-bodyweight-muscle-building-plan",
    "Michael B. Jordan Inspired Workout (Killmonger)": f"{BASE_URL}/workouts/michael-b-jordan-workout-program",
    "Chris Evans Inspired Workout (Captain America)": f"{BASE_URL}/workouts/chris-evans-workout-program",
    "Scarlett Johansson Inspired Workout (Black Widow)": f"{BASE_URL}/workouts/scarlett-johansson-workout-program",
    "Brie Larson Inspired Workout (Captain Marvel)": f"{BASE_URL}/workouts/brie-larson-workout-routine",
    "6 Week Navy SEAL Workout Routine": f"{BASE_URL}/workouts/6-week-navy-seal-workout-routine",
}


def clean_text(value: str | None) -> str | None:
    if value is None:
        return None
    cleaned = re.sub(r"\s+", " ", value).strip()
    return cleaned or None


def text_of(node: Tag | None) -> str | None:
    return clean_text(node.get_text(" ", strip=True)) if node else None


# Analytics and ad platforms decorate links in the live DOM before the collector
# reads their href, so a plain pagination link like "/workouts/women?page=1"
# arrives carrying Google's cross-domain linker (_gl) and GA4 client ids
# (_ga, _ga_<measurement-id>). Requesting those decorated URLs both looks
# abnormal to the source site's bot protection -- which answers them with a
# Cloudflare verification page -- and gives each paginated page a different
# cache key, so pagination is re-fetched on every run instead of resuming.
# Strip them before any request is made.
TRACKING_PARAM_PREFIXES = ("utm_", "_ga", "_gl")
TRACKING_PARAMS = frozenset({"gclid", "fbclid", "msclkid", "mc_cid", "mc_eid", "igshid"})


def strip_tracking_params(url: str) -> str:
    parsed = urlsplit(url)
    if not parsed.query:
        return url
    pairs = parse_qsl(parsed.query, keep_blank_values=True)
    kept = [
        (key, value)
        for key, value in pairs
        if key not in TRACKING_PARAMS
        and not any(key.startswith(prefix) for prefix in TRACKING_PARAM_PREFIXES)
    ]
    if len(kept) == len(pairs):
        return url
    return urlunsplit(
        (parsed.scheme, parsed.netloc, parsed.path, urlencode(kept, doseq=True), parsed.fragment)
    )


def absolute_url(value: str | None) -> str | None:
    if not value:
        return None
    return strip_tracking_params(urljoin(BASE_URL, value))


def field_text(soup: BeautifulSoup, field_name: str) -> str | None:
    return text_of(soup.select_one(f".field-name-{field_name}"))


def summary_value(soup: BeautifulSoup, label: str) -> str | None:
    """Read a Workout Summary value, including fields rendered as plain text."""
    wanted = clean_text(label)
    for row in soup.select(".node-stats-block li"):
        row_label = text_of(row.select_one(".row-label"))
        if row_label != wanted:
            continue
        copy = BeautifulSoup(str(row), "html.parser")
        label_node = copy.select_one(".row-label")
        if label_node:
            label_node.decompose()
        return text_of(copy)
    return None


def image_url(soup: BeautifulSoup) -> str | None:
    selectors = (
        ".node-image img",
        ".field-name-field-image img",
        ".field-name-field-feature-image img",
        "meta[property='og:image']",
    )
    for selector in selectors:
        node = soup.select_one(selector)
        if not node:
            continue
        value = node.get("data-src") or node.get("src") or node.get("content")
        if value:
            return absolute_url(str(value))
    return None


def canonical_url(soup: BeautifulSoup, fallback: str) -> str:
    canonical = soup.select_one("link[rel='canonical']")
    return absolute_url(canonical.get("href")) if canonical and canonical.get("href") else fallback


def parse_json_ld(soup: BeautifulSoup, wanted_type: str) -> dict[str, Any] | None:
    for node in soup.select("script[type='application/ld+json']"):
        try:
            value = json.loads(node.string or node.get_text())
        except (json.JSONDecodeError, TypeError):
            continue
        queue = value if isinstance(value, list) else [value]
        while queue:
            item = queue.pop(0)
            if not isinstance(item, dict):
                continue
            graph = item.get("@graph")
            if isinstance(graph, list):
                queue.extend(graph)
            types = item.get("@type", [])
            types = [types] if isinstance(types, str) else types
            if wanted_type in types:
                return item
    return None


def ordered_unique(values: Iterable[str]) -> list[str]:
    return list(dict.fromkeys(value for value in values if value))


def normalized_title(value: str) -> str:
    value = unicodedata.normalize("NFKD", value).encode("ascii", "ignore").decode()
    value = value.replace("'", "")
    return re.sub(r"[^a-z0-9]+", " ", value.lower()).strip()


def next_section_container(heading: Tag) -> Tag | None:
    """Return the first following grid before the next same-level heading."""
    for sibling in heading.next_siblings:
        if isinstance(sibling, Tag) and sibling.name == heading.name:
            return None
        if isinstance(sibling, Tag):
            if "grid-x" in sibling.get("class", []):
                return sibling
            grid = sibling.select_one(".grid-x")
            if grid:
                return grid
    return heading.find_next(class_="grid-x")


def parse_cards(
    container: Tag | BeautifulSoup,
    link_prefix: str | tuple[str, ...] | None = None,
) -> list[dict[str, Any]]:
    cards: list[dict[str, Any]] = []
    seen: set[str] = set()
    # Main-page cards use .has-attributes; taxonomy/category pages place the
    # same node fields directly inside .cell.
    for card in container.select(".has-attributes, .cell"):
        link = card.select_one(".node-title a[href]")
        if not link:
            continue
        url = absolute_url(str(link.get("href")))
        allowed_prefixes = (link_prefix,) if isinstance(link_prefix, str) else link_prefix
        if not url or url in seen or (allowed_prefixes and not url.startswith(allowed_prefixes)):
            continue
        seen.add(url)
        meta = [text_of(x) for x in card.select(".node-meta span")]
        image = card.select_one(".node-image img")
        cards.append(
            {
                "title": text_of(link),
                "url": url,
                "summary": text_of(card.select_one(".node-short-summary")),
                "tag": text_of(card.select_one(".node-tag")),
                "metadata": [x for x in meta if x],
                "image_url": absolute_url(
                    str(image.get("data-src") or image.get("src"))
                )
                if image
                else None,
            }
        )
    return cards


def find_heading(soup: BeautifulSoup, name: str, pattern: str) -> Tag | None:
    regex = re.compile(pattern, re.I)
    return next((h for h in soup.find_all(name) if regex.search(text_of(h) or "")), None)


def parse_popular_workout_cards(html: str) -> list[dict[str, Any]]:
    soup = BeautifulSoup(html, "html.parser")
    heading = find_heading(soup, "h2", r"^best workouts$")
    if not heading:
        raise ValueError("Could not find the Best Workouts section")
    container = next_section_container(heading)
    if not container:
        raise ValueError("Could not find workout cards after Best Workouts")
    cards = parse_cards(container, WORKOUT_URL_PREFIXES)
    for rank, card in enumerate(cards, 1):
        card["popularity_rank"] = rank
        card["popularity_window"] = "most downloaded in the past 24 hours"
    return cards


def parse_workout_cards(html: str) -> list[dict[str, Any]]:
    return parse_cards(BeautifulSoup(html, "html.parser"), WORKOUT_URL_PREFIXES)


def parse_diet_cards(html: str) -> list[dict[str, Any]]:
    soup = BeautifulSoup(html, "html.parser")
    heading = find_heading(soup, "h2", r"^diet guides$")
    container = next_section_container(heading) if heading else soup
    cards = parse_cards(container or soup, f"{BASE_URL}/diet-plans/")
    if not cards:
        cards = parse_cards(soup, f"{BASE_URL}/diet-plans/")
    return cards


def parse_recipe_category_urls(html: str) -> list[str]:
    soup = BeautifulSoup(html, "html.parser")
    heading = find_heading(soup, "h2", r"^recipe categories$")
    container = next_section_container(heading) if heading else soup
    urls: list[str] = []
    for link in (container or soup).select(".cell > a[href]"):
        url = absolute_url(str(link.get("href")))
        if url and url.startswith(f"{BASE_URL}/recipes/"):
            urls.append(url)
    return ordered_unique(urls)


def parse_recipe_cards(html: str) -> list[dict[str, Any]]:
    soup = BeautifulSoup(html, "html.parser")
    return parse_cards(soup)


def parse_next_page(html: str) -> str | None:
    soup = BeautifulSoup(html, "html.parser")
    link = soup.select_one(".pager-next a[href]")
    return absolute_url(str(link.get("href"))) if link else None


def parse_table(table: Tag) -> list[dict[str, str | None]]:
    rows = table.select("tr")
    if not rows:
        return []
    header_index = 0
    header_cells: list[Tag] = []
    for candidate_index, row in enumerate(rows):
        candidate_cells = row.find_all(["th", "td"], recursive=False)
        # Some legacy tables begin with one or more full-width title rows.
        # The actual Exercise/Sets/Reps header is the first multi-cell row.
        if len(candidate_cells) >= 2:
            header_index = candidate_index
            header_cells = candidate_cells
            break
    if not header_cells:
        return []
    headers = [text_of(cell) or f"column_{i + 1}" for i, cell in enumerate(header_cells)]
    parsed: list[dict[str, str | None]] = []
    for row in rows[header_index + 1:]:
        cells = row.find_all(["th", "td"], recursive=False)
        if len(cells) != len(headers):
            continue
        values = [text_of(cell) for cell in cells]
        if values == headers or all(not value for value in values):
            continue
        parsed.append(dict(zip(headers, values)))
    return parsed


def parse_article_sections(body: Tag | None) -> list[dict[str, Any]]:
    if not body:
        return []
    sections: list[dict[str, Any]] = []
    current: dict[str, Any] = {"heading": None, "text": [], "tables": [], "lists": []}
    for child in body.children:
        if not isinstance(child, Tag):
            continue
        if child.name in {"h2", "h3", "h4", "h5"}:
            if current["text"] or current["tables"] or current["lists"]:
                current["text"] = clean_text(" ".join(current["text"]))
                sections.append(current)
            current = {"heading": text_of(child), "text": [], "tables": [], "lists": []}
        elif child.name == "table":
            current["tables"].append(parse_table(child))
        elif child.find("table"):
            # Older workout pages wrap their responsive tables in one or more
            # divs instead of placing the table directly under the body field.
            current["tables"].extend(parse_table(table) for table in child.find_all("table"))
        elif child.name in {"ul", "ol"}:
            current["lists"].append([text_of(item) for item in child.find_all("li", recursive=False)])
        else:
            value = text_of(child)
            if value:
                current["text"].append(value)
    if current["heading"] is not None or current["text"] or current["tables"] or current["lists"]:
        current["text"] = clean_text(" ".join(current["text"]))
        sections.append(current)
    return sections


def exercise_rows(table: Any) -> list[dict[str, Any]]:
    """Return only rows from a table that actually describes exercises."""
    if not isinstance(table, list):
        return []
    return [
        row
        for row in table
        if isinstance(row, dict)
        and any(
            "exercise" in str(key).casefold() and clean_text(str(value or ""))
            for key, value in row.items()
        )
    ]


def normalize_workout_days(days: Iterable[dict[str, Any]]) -> list[dict[str, Any]]:
    """Keep workout definitions, not article/supporting tables or recovery prose.

    Source pages mix exercise prescriptions with meal plans, progression tables,
    FAQs, cardio prose, and recovery headings. Only exercise-bearing tables are
    useful as app workout days. Explicit rest/recovery sections are omitted even
    when they contain an optional add-on table; their exercises remain available
    in the source description without displacing a scheduled training day.
    """
    normalized: list[dict[str, Any]] = []
    for day in days:
        title = clean_text(str(day.get("title") or ""))
        if not title or re.search(r"\brest\b|active recovery", title, re.I):
            continue
        tables = [rows for table in day.get("exercise_tables") or [] if (rows := exercise_rows(table))]
        if not tables:
            continue
        normalized.append(
            {
                **day,
                "title": title,
                "exercise_tables": tables,
                "is_rest_day": False,
            }
        )
    return normalized


def main_body(soup: BeautifulSoup) -> Tag | None:
    return soup.select_one(".field-name-body > .field-items > .field-item") or soup.select_one(
        ".field-name-body"
    )


def parse_workout_detail(html: str, source_url: str) -> dict[str, Any]:
    soup = BeautifulSoup(html, "html.parser")
    body = main_body(soup)
    sections = parse_article_sections(body)
    candidate_days: list[dict[str, Any]] = []
    for section in sections:
        heading = section.get("heading")
        tables = section.get("tables") or []
        if heading and tables:
            candidate_days.append(
                {
                    "title": heading,
                    "notes": section.get("text"),
                    "exercise_tables": tables,
                    "is_rest_day": bool(re.search(r"\brest\b", heading, re.I)),
                }
            )
    days = normalize_workout_days(candidate_days)
    # Some programs encode the day name in the first table header instead of
    # using headings (for example, "Day 1 | Warm-Up | Working Set | Rest").
    if not days and body:
        for table in body.find_all("table"):
            first_row = table.select_one("tr")
            cells = first_row.find_all(["th", "td"], recursive=False) if first_row else []
            labels = [text_of(cell) for cell in cells]
            if not labels or not re.match(r"^day\s*\d+", labels[0] or "", re.I):
                continue
            day_title = labels[0]
            headers = ["Exercise", *labels[1:]]
            rows: list[dict[str, str | None]] = []
            for row in table.select("tr")[1:]:
                values = [text_of(cell) for cell in row.find_all(["th", "td"], recursive=False)]
                if len(values) == len(headers) and any(values):
                    rows.append(dict(zip(headers, values)))
            candidate_days.append(
                {
                    "title": day_title,
                    "notes": None,
                    "exercise_tables": [rows],
                    "is_rest_day": bool(
                        re.search(r"\brest\b", day_title or "", re.I)
                        or any(re.search(r"rest day", row.get("Exercise") or "", re.I) for row in rows)
                    ),
                }
            )
        days = normalize_workout_days(candidate_days)
    return {
        "title": text_of(soup.select_one("h1")),
        "url": canonical_url(soup, source_url),
        "summary": field_text(soup, "field-summary"),
        "main_goal": field_text(soup, "field-main-goal"),
        "workout_type": field_text(soup, "field-workout-type"),
        "experience_level": field_text(soup, "field-experience-level"),
        "days_per_week": field_text(soup, "field-days-per-week") or summary_value(soup, "Days Per Week"),
        "program_duration": summary_value(soup, "Program Duration"),
        "time_per_workout": summary_value(soup, "Time Per Workout"),
        "equipment_required": summary_value(soup, "Equipment Required"),
        "target_gender": summary_value(soup, "Target Gender"),
        "author": text_of(soup.select_one(".author-info")),
        "image_url": image_url(soup),
        "description_text": text_of(body),
        "description_html": str(body) if body else None,
        "sections": sections,
        "days": days,
    }


def parse_diet_detail(html: str, source_url: str) -> dict[str, Any]:
    soup = BeautifulSoup(html, "html.parser")
    body = main_body(soup)
    return {
        "title": text_of(soup.select_one("h1")),
        "url": canonical_url(soup, source_url),
        "summary": field_text(soup, "field-summary"),
        "author": text_of(soup.select_one(".author-info")),
        "image_url": image_url(soup),
        "content_text": text_of(body),
        "content_html": str(body) if body else None,
        "sections": parse_article_sections(body),
    }


def normalize_instructions(value: Any) -> list[str]:
    if isinstance(value, str):
        return [clean_text(value)] if clean_text(value) else []
    if not isinstance(value, list):
        return []
    result: list[str] = []
    for item in value:
        if isinstance(item, str) and clean_text(item):
            result.append(clean_text(item) or "")
        elif isinstance(item, dict):
            text = clean_text(str(item.get("text") or item.get("name") or ""))
            if text:
                result.append(text)
    return result


def parse_recipe_detail(html: str, source_url: str) -> dict[str, Any]:
    soup = BeautifulSoup(html, "html.parser")
    body = main_body(soup)
    schema = parse_json_ld(soup, "Recipe") or {}
    ingredient_nodes = soup.select(".recipe-check-list li")
    ingredients = [text_of(node) for node in ingredient_nodes]
    ingredients = [value for value in ingredients if value]
    if not ingredients:
        ingredients = [clean_text(str(value)) for value in schema.get("recipeIngredient", [])]
        ingredients = [value for value in ingredients if value]

    instructions: list[str] = []
    if body:
        for listing in body.select("ol"):
            instructions.extend(text_of(item) or "" for item in listing.find_all("li", recursive=False))
    instructions = [value for value in instructions if value] or normalize_instructions(
        schema.get("recipeInstructions")
    )

    return {
        "title": text_of(soup.select_one("h1")) or clean_text(str(schema.get("name") or "")),
        "url": canonical_url(soup, source_url),
        "summary": field_text(soup, "field-summary")
        or clean_text(str(schema.get("description") or "")),
        "image_url": image_url(soup),
        "calories_kcal": field_text(soup, "field-recipe-calories"),
        "protein_g": field_text(soup, "field-recipe-protein"),
        "carbs_g": field_text(soup, "field-recipe-carbs"),
        "fat_g": field_text(soup, "field-recipe-fat"),
        "serving_suggestion": field_text(soup, "field-serving-suggestions")
        or clean_text(str(schema.get("recipeYield") or "")),
        "ingredients": ingredients,
        "instructions": instructions,
        "content_text": text_of(body),
        "content_html": str(body) if body else None,
        "sections": parse_article_sections(body),
    }


@dataclass
class CollectorConfig:
    output_dir: Path
    delay_min: float
    delay_max: float
    timeout_seconds: float
    retries: int
    refresh: bool
    headed: bool
    max_workouts: int | None
    max_diets: int | None
    max_recipes: int | None
    datasets: tuple[str, ...]
    category_delay_min: float
    category_delay_max: float
    workout_checklist: Path | None


class BotChallenge(RuntimeError):
    pass


class BrowserCollector:
    def __init__(self, config: CollectorConfig, browser: Browser, context: BrowserContext, page: Page):
        self.config = config
        self.browser = browser
        self.context = context
        self.page = page
        self.cache_dir = config.output_dir / ".cache"
        self.cache_dir.mkdir(parents=True, exist_ok=True)
        self._last_request_finished = 0.0

    def cache_path(self, url: str) -> Path:
        digest = hashlib.sha256(url.encode("utf-8")).hexdigest()
        return self.cache_dir / f"{digest}.html"

    async def wait_for_slot(self) -> None:
        loop = asyncio.get_running_loop()
        target_delay = random.uniform(self.config.delay_min, self.config.delay_max)
        remaining = target_delay - (loop.time() - self._last_request_finished)
        if remaining > 0:
            print(f"  waiting {remaining:.1f}s", flush=True)
            await asyncio.sleep(remaining)

    async def fetch(self, url: str) -> str:
        cache_path = self.cache_path(url)
        if cache_path.exists() and not self.config.refresh:
            print(f"cache {url}", flush=True)
            return cache_path.read_text(encoding="utf-8")

        last_error: Exception | None = None
        for attempt in range(1, self.config.retries + 1):
            await self.wait_for_slot()
            print(f"GET   {url} (attempt {attempt}/{self.config.retries})", flush=True)
            response: Response | None = None
            try:
                response = await self.page.goto(
                    url,
                    wait_until="domcontentloaded",
                    timeout=self.config.timeout_seconds * 1000,
                )
                status = response.status if response else 0
                # Cloudflare may return an initial 403 challenge and then reload
                # the tab after its browser check. Give that normal browser flow
                # time to finish before deciding whether the page failed.
                await self.page.wait_for_timeout(5000 if status == 403 else 750)
                title = await self.page.title()
                html = await self.page.content()
                if "Just a moment" in title or "cf-chl-" in html:
                    print(
                        "  browser verification is open; waiting locally without requesting another page",
                        flush=True,
                    )
                    for elapsed in range(5, 601, 5):
                        await self.page.wait_for_timeout(5000)
                        title = await self.page.title()
                        html = await self.page.content()
                        if "Just a moment" not in title and "cf-chl-" not in html:
                            print(f"  verification cleared after {elapsed}s", flush=True)
                            response = None  # the challenge may have reloaded internally
                            status = 200
                            break
                        if elapsed % 30 == 0:
                            print(f"  still waiting for verification ({elapsed}s)", flush=True)
                    else:
                        raise BotChallenge(
                            "Cloudflare challenge remained for 10 minutes; stopping without retrying"
                        )
                if status == 429 or status >= 500:
                    raise RuntimeError(f"server returned HTTP {status}")
                if status >= 400 and "<h1" not in html.lower():
                    raise RuntimeError(f"page returned HTTP {status}")
                cache_path.write_text(html, encoding="utf-8")
                self._last_request_finished = asyncio.get_running_loop().time()
                return html
            except Exception as exc:  # Playwright has several navigation exception types.
                last_error = exc
                self._last_request_finished = asyncio.get_running_loop().time()
                if isinstance(exc, BotChallenge):
                    break
                if attempt < self.config.retries:
                    backoff = min(60.0, 5.0 * (2 ** (attempt - 1))) + random.uniform(0, 2)
                    print(f"  {exc}; backing off {backoff:.1f}s", file=sys.stderr, flush=True)
                    await asyncio.sleep(backoff)
        raise RuntimeError(f"Failed to fetch {url}: {last_error}")


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    temporary.replace(path)


async def verify_robots(collector: BrowserCollector) -> None:
    try:
        html = await collector.fetch(f"{BASE_URL}/robots.txt")
    except Exception as exc:
        print(f"warning: robots.txt was unavailable ({exc}); using conservative pacing", file=sys.stderr)
        return
    soup = BeautifulSoup(html, "html.parser")
    text = soup.get_text("\n", strip=True)
    if "User-agent:" not in text:
        print("warning: robots.txt returned a browser challenge; using conservative pacing", file=sys.stderr)
        return
    parser = RobotFileParser()
    parser.set_url(f"{BASE_URL}/robots.txt")
    parser.parse(text.splitlines())
    for url in (WORKOUTS_URL, DIETS_URL, RECIPES_URL):
        if not parser.can_fetch(USER_AGENT, url):
            raise RuntimeError(f"robots.txt disallows collection of {url}")


async def discover_workouts(collector: BrowserCollector) -> dict[str, dict[str, Any]]:
    catalog_path = collector.config.output_dir / "workout_catalog.json"
    discovered: dict[str, dict[str, Any]] = {}
    if catalog_path.exists() and not collector.config.refresh:
        loaded = json.loads(catalog_path.read_text(encoding="utf-8"))
        discovered = {
            item["url"]: item
            for item in loaded
            if isinstance(item, dict) and item.get("url")
        }
    landing_html = await collector.fetch(WORKOUTS_URL)
    for card in parse_popular_workout_cards(landing_html):
        record = discovered.setdefault(
            card["url"],
            {**card, "source_categories": [], "catalog_rank": len(discovered) + 1},
        )
        record.update({key: value for key, value in card.items() if value is not None})

    for category_index, (category_name, path) in enumerate(WORKOUT_CATEGORY_PATHS.items()):
        page_url: str | None = absolute_url(path)
        seen_pages: set[str] = set()
        while page_url and page_url not in seen_pages:
            seen_pages.add(page_url)
            html = await collector.fetch(page_url)
            for card in parse_workout_cards(html):
                url = card["url"]
                record = discovered.setdefault(
                    url,
                    {**card, "source_categories": [], "catalog_rank": len(discovered) + 1},
                )
                if category_name not in record["source_categories"]:
                    record["source_categories"].append(category_name)
            write_json(catalog_path, list(discovered.values()))
            page_url = parse_next_page(html)
        print(f"  discovered {len(discovered)} unique workouts after {category_name}", flush=True)
        if category_index + 1 < len(WORKOUT_CATEGORY_PATHS):
            cooldown = random.uniform(
                collector.config.category_delay_min,
                collector.config.category_delay_max,
            )
            print(f"  category cooldown {cooldown:.1f}s", flush=True)
            await asyncio.sleep(cooldown)

    return discovered


def checklist_workout_cards(checklist_path: Path, catalog_path: Path) -> list[dict[str, Any]]:
    if not checklist_path.exists():
        raise FileNotFoundError(f"Workout checklist not found: {checklist_path}")
    catalog = json.loads(catalog_path.read_text(encoding="utf-8")) if catalog_path.exists() else []
    by_title = {
        normalized_title(item.get("title") or ""): item
        for item in catalog
        if isinstance(item, dict) and item.get("title") and item.get("url")
    }
    by_url = {
        item["url"]: item
        for item in catalog
        if isinstance(item, dict) and item.get("url")
    }

    with checklist_path.open(newline="", encoding="utf-8-sig") as source:
        rows = list(csv.DictReader(source))
    if not rows or "Program Name" not in rows[0]:
        raise ValueError("Workout checklist must contain a 'Program Name' column")

    cards: list[dict[str, Any]] = []
    seen_urls: set[str] = set()
    for rank, row in enumerate(rows, start=1):
        import_title = clean_text(row.get("Program Name"))
        if not import_title:
            raise ValueError(f"Checklist row {rank + 1} has no Program Name")
        source_url = WORKOUT_TITLE_URLS.get(import_title)
        catalog_item = by_url.get(source_url) if source_url else by_title.get(normalized_title(import_title))
        if catalog_item:
            source_url = catalog_item["url"]
        if not source_url:
            raise ValueError(
                f"Could not match checklist workout {import_title!r}; add its source URL to WORKOUT_TITLE_URLS"
            )
        if source_url in seen_urls:
            raise ValueError(f"Checklist maps more than one row to {source_url}")
        seen_urls.add(source_url)
        card = dict(catalog_item or {})
        card.update(
            {
                "title": card.get("title") or import_title,
                "url": source_url,
                "summary": card.get("summary") or clean_text(row.get("Notes")),
                "tag": card.get("tag"),
                "metadata": card.get("metadata") or [
                    value for value in (clean_text(row.get("Reads")), clean_text(row.get("Comments"))) if value
                ],
                "source_categories": card.get("source_categories") or [],
                "catalog_rank": rank,
                "import_title": import_title,
            }
        )
        cards.append(card)
    return cards


async def collect_workouts(collector: BrowserCollector) -> list[dict[str, Any]]:
    if collector.config.workout_checklist:
        cards = checklist_workout_cards(
            collector.config.workout_checklist,
            collector.config.output_dir / "workout_catalog.json",
        )
    else:
        cards_by_url = await discover_workouts(collector)
        cards = list(cards_by_url.values())
    if collector.config.max_workouts is not None:
        cards = cards[:collector.config.max_workouts]

    output = collector.config.output_dir / "workouts.json"
    existing: dict[str, dict[str, Any]] = {}
    if output.exists() and not collector.config.refresh:
        loaded = json.loads(output.read_text(encoding="utf-8"))
        existing = {item["url"]: item for item in loaded if isinstance(item, dict) and item.get("url")}
    records: list[dict[str, Any]] = []
    for card in cards:
        detail = existing.get(card["url"])
        if detail is None or any(detail.get(key) is None for key in ("target_gender", "equipment_required", "time_per_workout")):
            detail = parse_workout_detail(await collector.fetch(card["url"]), card["url"])
        detail.update(
            {
                "popularity_rank": card.get("popularity_rank"),
                "popularity_window": card.get("popularity_window"),
                "catalog_rank": card.get("catalog_rank"),
                "source_categories": card.get("source_categories", []),
                "catalog_summary": card["summary"],
                "catalog_tag": card["tag"],
                "catalog_metadata": card["metadata"],
            }
        )
        if card.get("import_title"):
            detail["source_title"] = detail.get("source_title") or detail.get("title")
            detail["title"] = card["import_title"]
        records.append(detail)
        write_json(output, records)
    return records


async def collect_diets(collector: BrowserCollector) -> list[dict[str, Any]]:
    cards = parse_diet_cards(await collector.fetch(DIETS_URL))
    if collector.config.max_diets is not None:
        cards = cards[: collector.config.max_diets]
    records: list[dict[str, Any]] = []
    for card in cards:
        detail = parse_diet_detail(await collector.fetch(card["url"]), card["url"])
        detail["catalog_summary"] = card["summary"]
        records.append(detail)
        write_json(collector.config.output_dir / "diets.json", records)
    return records


async def discover_recipes(collector: BrowserCollector) -> dict[str, dict[str, Any]]:
    landing_html = await collector.fetch(RECIPES_URL)
    categories = parse_recipe_category_urls(landing_html)
    discovered: dict[str, dict[str, Any]] = {}

    for card in parse_recipe_cards(landing_html):
        url = card["url"]
        if url and not url.startswith(f"{BASE_URL}/recipes/"):
            continue
        discovered[url] = {**card, "categories": []}

    for category_url in categories:
        page_url: str | None = category_url
        seen_pages: set[str] = set()
        while page_url and page_url not in seen_pages:
            seen_pages.add(page_url)
            html = await collector.fetch(page_url)
            category_name = text_of(BeautifulSoup(html, "html.parser").select_one("h1")) or category_url.rsplit("/", 1)[-1]
            for card in parse_recipe_cards(html):
                url = card["url"]
                if not url or url == category_url:
                    continue
                record = discovered.setdefault(url, {**card, "categories": []})
                if category_name not in record["categories"]:
                    record["categories"].append(category_name)
                if collector.config.max_recipes is not None and len(discovered) >= collector.config.max_recipes:
                    return dict(list(discovered.items())[: collector.config.max_recipes])
            page_url = parse_next_page(html)
    return discovered


async def collect_recipes(collector: BrowserCollector) -> list[dict[str, Any]]:
    cards_by_url = await discover_recipes(collector)
    records: list[dict[str, Any]] = []
    for url, card in cards_by_url.items():
        detail = parse_recipe_detail(await collector.fetch(url), url)
        detail.update(
            {
                "categories": card.get("categories", []),
                "catalog_summary": card.get("summary"),
                "catalog_metadata": card.get("metadata", []),
            }
        )
        records.append(detail)
        write_json(collector.config.output_dir / "recipes.json", records)
    return records


async def run(config: CollectorConfig) -> None:
    config.output_dir.mkdir(parents=True, exist_ok=True)
    async with async_playwright() as playwright:
        # A persistent, ordinary browser profile avoids presenting every resume
        # as a brand-new client to the source site's bot protection.
        context = await playwright.chromium.launch_persistent_context(
            str(config.output_dir / ".browser-profile"),
            headless=not config.headed,
            user_agent=USER_AGENT,
            locale="en-US",
        )
        browser = context.browser
        page = context.pages[0] if context.pages else await context.new_page()
        collector = BrowserCollector(config, browser, context, page)
        try:
            await verify_robots(collector)
            workouts = await collect_workouts(collector) if "workouts" in config.datasets else read_existing(config.output_dir, "workouts")
            diets = await collect_diets(collector) if "diets" in config.datasets else read_existing(config.output_dir, "diets")
            recipes = await collect_recipes(collector) if "recipes" in config.datasets else read_existing(config.output_dir, "recipes")
        finally:
            await context.close()

    manifest = {
        "source": BASE_URL,
        "collected_at_utc": datetime.now(timezone.utc).isoformat(),
        "request_delay_seconds": {"minimum": config.delay_min, "maximum": config.delay_max},
        "counts": {"workouts": len(workouts), "diets": len(diets), "recipes": len(recipes)},
        "workout_categories": list(WORKOUT_CATEGORY_PATHS),
        "workout_catalog_scope": "All unique programs discoverable through the public workout category pages",
    }
    write_json(config.output_dir / "manifest.json", manifest)
    print(json.dumps(manifest, indent=2), flush=True)


def parse_args() -> CollectorConfig:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("data/scraped/muscleandstrength"),
    )
    parser.add_argument("--delay-min", type=float, default=12.0)
    parser.add_argument("--delay-max", type=float, default=20.0)
    parser.add_argument("--category-delay-min", type=float, default=60.0)
    parser.add_argument("--category-delay-max", type=float, default=90.0)
    parser.add_argument("--timeout", type=float, default=45.0, dest="timeout_seconds")
    parser.add_argument("--retries", type=int, default=3)
    parser.add_argument("--refresh", action="store_true")
    parser.add_argument("--headed", action="store_true")
    parser.add_argument("--max-workouts", type=int)
    parser.add_argument("--max-diets", type=int)
    parser.add_argument("--max-recipes", type=int)
    parser.add_argument(
        "--workout-checklist",
        type=Path,
        help="Import only the workouts in this CSV and use Program Name as each imported title.",
    )
    parser.add_argument(
        "--datasets", nargs="+", choices=("workouts", "diets", "recipes"),
        default=("workouts", "diets", "recipes"),
        help="Catalogs to refresh; omitted catalogs are retained from existing JSON.",
    )
    args = parser.parse_args()
    if args.delay_min < 0 or args.delay_max < args.delay_min:
        parser.error("delay values must satisfy 0 <= --delay-min <= --delay-max")
    if args.category_delay_min < 0 or args.category_delay_max < args.category_delay_min:
        parser.error("category delay values must satisfy 0 <= minimum <= maximum")
    if args.retries < 1:
        parser.error("--retries must be at least 1")
    args.datasets = tuple(args.datasets)
    return CollectorConfig(**vars(args))


def read_existing(output_dir: Path, dataset: str) -> list[dict[str, Any]]:
    path = output_dir / f"{dataset}.json"
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else []


if __name__ == "__main__":
    asyncio.run(run(parse_args()))
