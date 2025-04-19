#!/usr/bin/env python3
import os
import re
import sys
import time
import json
import requests
from bs4 import BeautifulSoup
from urllib.parse import urljoin
from pathlib import Path

def sanitize(name):
    return re.sub(r'[\\/:"*?<>|]+', '_', name).strip()

def scrape(start_url, start_folder):
    queue_file = Path('queue.json')
    # load saved queue if it exists
    if queue_file.exists():
        with open(queue_file, 'r') as f:
            raw = json.load(f)
        queue = [{'path': Path(item['path']), 'url': item['url']} for item in raw]
        print(f"Loaded {len(queue)} items from queue.json")
    else:
        queue = [{'path': Path(start_folder), 'url': start_url}]

    seen_urls = {item['url'] for item in queue}

    while queue:
        item = queue.pop(0)
        url = item['url']
        path = item['path']
        pdf_file = None
        if str(path) != '.':
            pdf_file = path.with_suffix('.pdf')
            if pdf_file.exists():
                # skip already-downloaded
                continue

        print(f"[ ][F] Fetching: {url}")
        r = requests.get(url)
        r.raise_for_status()
        html = r.text
        soup = BeautifulSoup(html, 'html.parser')

        if "Object Type: Folder" in html or 'Complete Archive' in html:
            path.mkdir(parents=True, exist_ok=True)

            # subfolders / assets
            for div in soup.find_all('div', id=re.compile(r'post-\d+')):
                a = div.select_one('a.new-primary')
                if not a or not a.get('href'):
                    continue
                href = urljoin(url, a['href'])
                title = sanitize(a.get_text() or 'untitled')
                if href not in seen_urls:
                    seen_urls.add(href)
                    queue.append({'path': path / title, 'url': href})

            # pagination links
            for a in soup.select('a.page-numbers'):
                href = urljoin(url, a.get('href'))
                if href not in seen_urls:
                    seen_urls.add(href)
                    queue.append({'path': path, 'url': href})

        elif "Object Type: Asset" in html:
            dl = soup.select_one('a.fa-download')
            if dl and dl.get('href'):
                download_url = urljoin(url, dl['href'])
                print(f"[>][PDF] Downloading to {pdf_file}")
                r2 = requests.get(download_url)
                r2.raise_for_status()
                path.parent.mkdir(parents=True, exist_ok=True)
                with open(pdf_file, 'wb') as f:
                    f.write(r2.content)
                time.sleep(0.5)
        else:
            print(f"[!][?] Unknown object type at {url}", file=sys.stderr)

        # persist queue
        with open(queue_file, 'w') as f:
            json.dump([
                {'path': str(item['path']), 'url': item['url']}
                for item in queue
            ], f, indent=2)

    print("Scrape complete, queue is empty.")
    # optionally remove queue.json when done
    queue_file.unlink(missing_ok=True)

if __name__ == '__main__':
    BASE_URL = "https://digital.nmla.metoffice.gov.uk/archive"
    scrape(BASE_URL, Path('.'))
