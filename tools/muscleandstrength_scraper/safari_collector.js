(async () => {
  const base = 'https://www.muscleandstrength.com';
  const bridge = 'http://127.0.0.1:8765/record';
  const token = 'silen-safari-import-2026';
  const categories = [
    ['Women', '/workouts/women'],
    ['Muscle Building', '/workouts/muscle-building'],
    ['Fat Loss', '/workouts/fat-loss'],
    ['Men', '/workouts/men'],
    ['Strength', '/workouts/strength'],
    ['Abs', '/workouts/abs'],
    ['Full Body', '/workouts/full-body'],
    ['Sports Performance', '/workouts/sports'],
    ['Bodyweight', '/workouts/bodyweight'],
    ['Beginner', '/workouts/beginner'],
    ['At Home', '/workouts/home'],
    ['Celebrity', '/workouts/celebrity'],
    ['Cardio', '/workouts/cardio'],
    ['Chest', '/workouts/chest'],
    ['Back', '/workouts/back'],
    ['Biceps', '/workouts/biceps'],
    ['Shoulders', '/workouts/shoulders'],
    ['Legs', '/workouts/legs'],
    ['Triceps', '/workouts/triceps'],
    ['Glutes', '/workouts/other'],
  ];
  const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
  const random = (min, max) => min + Math.random() * (max - min);
  let lastExternalRequest = 0;

  async function getHtml(url) {
    const remaining = random(15000, 25000) - (Date.now() - lastExternalRequest);
    if (remaining > 0) await sleep(remaining);
    console.log('Safari GET', url);
    const response = await fetch(url, {credentials: 'include', cache: 'no-store'});
    const html = await response.text();
    lastExternalRequest = Date.now();
    if (!response.ok || /cf-chl-|Just a moment|Performing security verification/i.test(html)) {
      throw new Error(`Verification response at ${url}; stopped without retrying`);
    }
    return html;
  }

  function parseCards(html) {
    const doc = new DOMParser().parseFromString(html, 'text/html');
    const records = [];
    const seen = new Set();
    for (const card of doc.querySelectorAll('.has-attributes, .cell')) {
      const link = card.querySelector('.node-title a[href]');
      if (!link) continue;
      const url = new URL(link.getAttribute('href'), base).href;
      if (!url.startsWith(`${base}/workouts/`) || seen.has(url)) continue;
      seen.add(url);
      records.push({
        title: link.textContent.trim().replace(/\s+/g, ' '),
        url,
        summary: card.querySelector('.node-short-summary')?.textContent.trim().replace(/\s+/g, ' ') || null,
        tag: card.querySelector('.node-tag')?.textContent.trim().replace(/\s+/g, ' ') || null,
        metadata: [...card.querySelectorAll('.node-meta span')].map(x => x.textContent.trim().replace(/\s+/g, ' ')).filter(Boolean),
      });
    }
    const next = doc.querySelector('.pager-next a[href]');
    return {records, next: next ? new URL(next.getAttribute('href'), base).href : null};
  }

  function encode(value) {
    const bytes = new TextEncoder().encode(JSON.stringify(value));
    let binary = '';
    for (let offset = 0; offset < bytes.length; offset += 0x8000) {
      binary += String.fromCharCode(...bytes.subarray(offset, offset + 0x8000));
    }
    return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  }

  async function send(dataset, id, value) {
    const encoded = encode(value);
    const size = 4000;
    const total = Math.ceil(encoded.length / size);
    for (let index = 0; index < total; index++) {
      const url = `${bridge}?token=${encodeURIComponent(token)}&dataset=${dataset}&id=${encodeURIComponent(id)}&index=${index}&total=${total}&data=${encoded.slice(index * size, (index + 1) * size)}`;
      await new Promise(resolve => {
        const image = new Image();
        image.onload = resolve;
        image.onerror = resolve;
        image.src = url;
      });
    }
  }

  const catalog = JSON.parse(localStorage.getItem('silenWorkoutCatalog') || '{}');
  let categoryIndex = Number(localStorage.getItem('silenWorkoutCategoryIndex') || '0');
  let resumePage = localStorage.getItem('silenWorkoutNextPage');

  for (; categoryIndex < categories.length; categoryIndex++) {
    const [categoryName, path] = categories[categoryIndex];
    let pageUrl = resumePage || new URL(path, base).href;
    const pagesSeen = new Set();
    while (pageUrl && !pagesSeen.has(pageUrl)) {
      pagesSeen.add(pageUrl);
      const parsed = parseCards(await getHtml(pageUrl));
      for (const card of parsed.records) {
        const existing = catalog[card.url] || {...card, source_categories: [], catalog_rank: Object.keys(catalog).length + 1};
        if (!existing.source_categories.includes(categoryName)) existing.source_categories.push(categoryName);
        catalog[card.url] = {...existing, ...card};
      }
      pageUrl = parsed.next;
      localStorage.setItem('silenWorkoutCatalog', JSON.stringify(catalog));
      localStorage.setItem('silenWorkoutNextPage', pageUrl || '');
      console.log(`Catalog ${categoryName}: ${Object.keys(catalog).length} unique workouts`);
    }
    resumePage = null;
    localStorage.setItem('silenWorkoutCategoryIndex', String(categoryIndex + 1));
    localStorage.removeItem('silenWorkoutNextPage');
    if (categoryIndex + 1 < categories.length) {
      const cooldown = random(90000, 120000);
      console.log(`Category cooldown ${Math.round(cooldown / 1000)}s`);
      await sleep(cooldown);
    }
  }

  const cards = Object.values(catalog).sort((a, b) => a.catalog_rank - b.catalog_rank);
  await send('workout_catalog', 'catalog', {__replace__: cards});
  let detailIndex = Number(localStorage.getItem('silenWorkoutDetailIndex') || '0');
  for (; detailIndex < cards.length; detailIndex++) {
    const card = cards[detailIndex];
    const html = await getHtml(card.url);
    await send('workout_html', `workout-${detailIndex}`, {
      ...card,
      catalog_summary: card.summary,
      catalog_tag: card.tag,
      catalog_metadata: card.metadata,
      html,
    });
    localStorage.setItem('silenWorkoutDetailIndex', String(detailIndex + 1));
    console.log(`Saved workout ${detailIndex + 1}/${cards.length}: ${card.title}`);
  }

  await send('manifest', 'manifest', {
    source: base,
    collected_at_utc: new Date().toISOString(),
    collection_browser: 'Safari',
    request_delay_seconds: {minimum: 15, maximum: 25},
    category_delay_seconds: {minimum: 90, maximum: 120},
    counts: {workouts: cards.length},
    workout_categories: categories.map(([name]) => name),
    workout_catalog_scope: 'All unique programs discoverable through the public workout category pages',
  });
  localStorage.setItem('silenWorkoutDone', '1');
  console.log(`SILEN SCRAPE COMPLETE: ${cards.length} workouts`);
})().catch(error => console.error('SILEN SCRAPE STOPPED:', error));
