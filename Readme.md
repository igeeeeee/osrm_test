# セットアップ
Dockerをインソールしてください。環境はWSL想定。ポート5000が空いているようにしてください（普通は大丈夫なはず）。


```bash
chmod +x build.sh
```

```bash
./build.sh
```

# 起動
```bash
docker run --rm -it -p 5000:5000 -v "$PWD:/data" ghcr.io/project-osrm/osrm-backend:v5.27.1 osrm-routed --algorithm mld /data/extract/kanto_mainland.osrm
```

# テスト
別のシェルを開いて
```bash
curl "http://localhost:5000/nearest/v1/driving/139.7670,35.6814?number=1"
```
"code":"Ok"みたいなのが返ってくればOK
