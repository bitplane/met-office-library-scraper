echo d: $(find . -type f | wc -l) q: $(cat queue.json | grep http | sort | uniq | wc -l) | figlet
