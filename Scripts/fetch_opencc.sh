#!/bin/sh
# Downloads the OpenCC data files that the Chinese converter needs.
#
# The raw.githubusercontent.com route returns 404 for the (large) phrase
# dictionaries in this environment, so they are fetched through the git blob
# API instead.
set -e

DIR=/home/shupian/opencc
mkdir -p "$DIR"
cd "$DIR"

fetch_blob() {
    name="$1"
    if [ -s "$name.txt" ]; then
        echo "[ok] $name.txt already there"
        return 0
    fi
    sha=$(curl -fsSL --max-time 180 \
        "https://api.github.com/repos/BYVoid/OpenCC/contents/data/dictionary/$name.txt" \
        | python3 -c 'import json,sys;print(json.load(sys.stdin)["sha"])')
    curl -fsSL --max-time 600 \
        "https://api.github.com/repos/BYVoid/OpenCC/git/blobs/$sha" -o "$name.blob.json"
    python3 -c "import json,base64;b=json.load(open('$name.blob.json'));open('$name.txt','wb').write(base64.b64decode(b['content']))"
    rm -f "$name.blob.json"
    echo "[ok] $name.txt downloaded"
}

for name in STCharacters TSCharacters STPhrases TSPhrases; do
    fetch_blob "$name"
done

wc -lc STCharacters.txt TSCharacters.txt STPhrases.txt TSPhrases.txt
