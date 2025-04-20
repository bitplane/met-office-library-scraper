#!/usr/bin/env python3
import os
import re
import sys
import json
import requests
from bs4 import BeautifulSoup
from urllib.parse import urljoin
from pathlib import Path
from tempfile import NamedTemporaryFile

def sanitize(name):
    return re.sub(r'[\\/:"*?<>|]+', '_', name).strip()

def save_json_atomic(data, path: Path):
    tmp = path.with_suffix(path.suffix + '.tmp')
    with open(tmp, 'w') as f:
        json.dump(data, f, indent=2)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, path)

def load_json(path: Path, default):
    if path.exists():
        return json.loads(path.read_text())
    return default

def scrape(start_url, start_folder):
    queue_file = Path('queue.json')
    seen_file  = Path('seen.json')

    # load or init
    raw_queue = load_json(queue_file, None)
    if raw_queue is None:
        queue = [{'path': Path(start_folder), 'url': start_url}]
    else:
        queue = [{'path': Path(item['path']), 'url': item['url']} for item in raw_queue]
        print(f"Loaded {len(queue)} items from {queue_file}")

    raw_seen = load_json(seen_file, None)
    if raw_seen is None:
        seen_urls = {start_url}
    else:
        seen_urls = set(raw_seen)
        print(f"Loaded {len(seen_urls)} URLs from {seen_file}")

    count = 0

    try:
        while queue:
            count += 1
            item = queue.pop()  # LIFO to keep list small
            url  = item['url']
            path = item['path']

            # skip if PDF already exists
            if str(path) != '.':
                pdf_file = path.with_suffix('.pdf')
                if pdf_file.exists():
                    continue

            print(f"[ ][F] Fetching: {url}")
            r = requests.get(url)
            r.raise_for_status()
            html = r.text
            soup = BeautifulSoup(html, 'html.parser')

            if "Object Type: Folder" in html or 'Complete Archive' in html:
                path.mkdir(parents=True, exist_ok=True)

                # sub‑folders/assets
                for div in soup.find_all('div', id=re.compile(r'post-\d+')):
                    a = div.select_one('a.new-primary')
                    if not a or not a.get('href'):
                        continue
                    href = urljoin(url, a['href'])
                    title = sanitize(a.get_text() or 'untitled')
                    if href not in seen_urls:
                        seen_urls.add(href)
                        queue.append({'path': path / title, 'url': href})

                # pagination
                for a in soup.select('a.page-numbers'):
                    href = urljoin(url, a.get('href'))
                    if href not in seen_urls:
                        seen_urls.add(href)
                        queue.append({'path': path, 'url': href})

            elif "Object Type: Asset" in html:
                dl = soup.select_one('a.fa-download')
                if dl and dl.get('href'):
                    download_url = urljoin(url, dl['href'])
                    pdf_file = path.with_suffix('.pdf')
                    print(f"[>][PDF] Downloading to {pdf_file}")
                    r2 = requests.get(download_url)
                    r2.raise_for_status()
                    path.parent.mkdir(parents=True, exist_ok=True)
                    with open(pdf_file, 'wb') as f:
                        f.write(r2.content)

            else:
                print(f"[!][?] Unknown object type at {url}", file=sys.stderr)

            # every 10 items, save state
            if count % 10 == 0:
                save_json_atomic(
                    [{'path': str(i['path']), 'url': i['url']} for i in queue],
                    queue_file
                )
                save_json_atomic(list(seen_urls), seen_file)

    except KeyboardInterrupt:
        print("\nInterrupted—saving state before exit…")
        save_json_atomic(
            [{'path': str(i['path']), 'url': i['url']} for i in queue],
            queue_file
        )
        save_json_atomic(list(seen_urls), seen_file)
        sys.exit(0)

    # final cleanup
    if queue:
        save_json_atomic(
            [{'path': str(i['path']), 'url': i['url']} for i in queue],
            queue_file
        )
    else:
        queue_file.unlink(missing_ok=True)

    save_json_atomic(list(seen_urls), seen_file)
    if not queue:
        seen_file.unlink(missing_ok=True)

    print("Done. Queue empty and state files cleaned up.")

if __name__ == '__main__':
    BASE_URL = "https://digital.nmla.metoffice.gov.uk/archive"
    scrape(BASE_URL, Path('.'))
