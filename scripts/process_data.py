#!/usr/bin/env python3
"""
process_data.py (우아놀거리) - 행안부 LOCALDATA 노래연습장업·영화상영관·공연장 CSV(영업/정상)를 가공한다.
입력: data/raw/{karaoke_rooms,movie_theaters,performance_halls}.csv  출력: _rawdata/pl_{시도}.json, search_index.json
"""
import re, sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from lib_localdata import *  # noqa

sys.stdout.reconfigure(encoding="utf-8")
ROOT = Path(__file__).parent.parent
RAW = ROOT / "data" / "raw"
CATMETA = {"노래방": ("karaoke", "🎤"), "코인노래방": ("coin-karaoke", "🪙"), "영화관": ("cinema", "🎬"), "공연장": ("hall", "🎭")}


def addr_base(addr):
    toks = clean(addr).split()
    for k, t in enumerate(toks):
        if k >= 2 and re.match(r"^\d+(-\d+)?,?$", t):
            return " ".join(toks[:k + 1]).rstrip(",")
    return clean(addr)


def main():
    tf = make_transformer()
    records = []

    # 노래방 / 코인노래방
    for r in read_csv_rows(RAW / "karaoke_rooms.csv"):
        if clean(r.get("영업상태명")) != "영업/정상":
            continue
        name = clean(r.get("사업장명"))
        cat = "코인노래방" if "코인" in name else "노래방"
        rooms = int(num(r.get("노래방실수")))
        teen = int(num(r.get("청소년실수")))
        area = num(r.get("시설면적")) or num(r.get("소재지면적"))
        lat, lng = to_wgs(tf, r.get("좌표정보(X)"), r.get("좌표정보(Y)"))
        extras, hrows = [], []
        if rooms > 0:
            extras.append({"l": "노래방실 수", "v": f"{rooms}개"})
            hrows.append({"i": "🎤", "t": f"노래방실 {rooms}개"})
        if teen > 0:
            extras.append({"l": "청소년실 수", "v": f"{teen}개"})
        if area > 0:
            extras.append({"l": "시설 면적", "v": f"{area:.0f}㎡"})
        records.append(dict(name=name, cat=cat, road=r.get("도로명주소"), lot=r.get("지번주소"), tel=r.get("전화번호"),
                            permit=r.get("인허가일자"), upd=clean(r.get("최종수정시점"))[:10], lat=lat, lng=lng,
                            extras=extras, hrows=hrows, note=f"노래방실 {rooms}개" if rooms > 0 else ""))

    # 영화관: 같은 건물(도로명 번지)의 상영관 인허가를 한 곳으로 묶는다
    groups = {}
    for r in read_csv_rows(RAW / "movie_theaters.csv"):
        if clean(r.get("영업상태명")) != "영업/정상":
            continue
        road, lot = clean(r.get("도로명주소")), clean(r.get("지번주소"))
        base = addr_base(road or lot)
        if not base:
            continue
        g = groups.setdefault(base, {"rows": [], "road": road, "lot": lot})
        g["rows"].append(r)
    for base, g in groups.items():
        names = []
        for r in g["rows"]:
            n = clean(r.get("사업장명"))
            n = re.sub(r"\s+(?:\d+|[A-Za-z]|[가-힣]{0,6})관\s*$", "", n).strip()
            names.append(n)
        name = Counter(names).most_common(1)[0][0] or clean(g["rows"][0].get("사업장명"))
        first = min(g["rows"], key=lambda x: clean(x.get("인허가일자")) or "9999")
        lat, lng = to_wgs(tf, first.get("좌표정보(X)"), first.get("좌표정보(Y)"))
        screens = len(g["rows"])
        tel = next((clean(x.get("전화번호")) for x in g["rows"] if clean(x.get("전화번호"))), "")
        extras = [{"l": "상영관 수", "v": f"{screens}개"}]
        records.append(dict(name=name, cat="영화관", road=g["road"], lot=g["lot"], tel=tel, permit=first.get("인허가일자"),
                            upd=max((clean(x.get("최종수정시점"))[:10] for x in g["rows"]), default=""), lat=lat, lng=lng,
                            extras=extras, hrows=[{"i": "🎬", "t": f"상영관 {screens}개"}], note=f"상영관 {screens}개"))

    # 공연장
    for r in read_csv_rows(RAW / "performance_halls.csv"):
        if clean(r.get("영업상태명")) != "영업/정상":
            continue
        lat, lng = to_wgs(tf, r.get("좌표정보(X)"), r.get("좌표정보(Y)"))
        area = num(r.get("시설면적")) or num(r.get("소재지면적"))
        extras = [{"l": "시설 면적", "v": f"{area:.0f}㎡"}] if area > 0 else []
        records.append(dict(name=clean(r.get("사업장명")), cat="공연장", road=r.get("도로명주소"), lot=r.get("지번주소"), tel=r.get("전화번호"),
                            permit=r.get("인허가일자"), upd=clean(r.get("최종수정시점"))[:10], lat=lat, lng=lng, extras=extras, hrows=[], note=""))

    finalize(records, ROOT / "_rawdata", "pl", ROOT, CATMETA)


if __name__ == "__main__":
    main()
