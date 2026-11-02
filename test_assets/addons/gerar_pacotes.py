"""Gera os zips de teste de add-on nesta pasta. Rodar: python gerar_pacotes.py

olympus-teste.zip   válido: instala, ativa e mostra o catálogo
kodi.zip            add-on do Kodi: recusado com a mensagem própria
com-codigo.zip      tem um .py: recusado por arquivo não aceito
cortado.zip         zip quebrado: recusado como arquivo inválido
"""
import json
import pathlib
import zipfile

HERE = pathlib.Path(__file__).parent
FEED = "https://conde86projects.github.io/olympus-catalog"

MANIFEST = {
    "id": "olympus.teste.pacote",
    "name": "Pacote de teste",
    "version": "1.0.0",
    "author": "Olympus",
    "description": "Pacote de teste do Olympus, com um filme aberto.",
    "icon": "movie",
    "homepage": "https://conde86projects.github.io/olympus-catalog",
    "repository": "test_assets/addons",
    "permissions": ["catalog.read", "playback.open"],
    "supportedPlatforms": ["windows", "linux", "macos", "android"],
    "contentTypes": ["video"],
    "legalNotice": "Big Buck Bunny, Blender Foundation, licença CC-BY 3.0.",
}

CATALOG = {
    "items": [
        {
            "id": "big-buck-bunny",
            "title": "Big Buck Bunny",
            "subtitle": "Filme aberto, CC-BY 3.0",
            "sourceUrl": f"{FEED}/media/hls/big-buck-bunny/master.m3u8",
            "thumbnailUrl": f"{FEED}/images/big-buck-bunny.jpg",
            "duration": 596,
        }
    ]
}


def pack(name, files):
    with zipfile.ZipFile(HERE / name, "w", zipfile.ZIP_DEFLATED) as archive:
        for path, body in files.items():
            archive.writestr(zipfile.ZipInfo(path, (2026, 1, 1, 0, 0, 0)), body)


def main():
    addon = json.dumps(MANIFEST, ensure_ascii=False, indent=2)
    catalog = json.dumps(CATALOG, ensure_ascii=False, indent=2)
    pack("olympus-teste.zip", {"addon.json": addon, "catalog.json": catalog})
    pack("kodi.zip", {"addon.xml": '<addon id="plugin.video.teste"/>', "default.py": "pass\n"})
    pack("com-codigo.zip", {"addon.json": addon, "catalog.json": catalog, "main.py": "pass\n"})
    valid = (HERE / "olympus-teste.zip").read_bytes()
    (HERE / "cortado.zip").write_bytes(valid[: len(valid) // 2])


if __name__ == "__main__":
    main()
