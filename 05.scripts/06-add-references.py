#!/usr/bin/env python3
"""Verify a list of DOIs against CrossRef and append them to references.bib.

Every entry is fetched from the registry by DOI content negotiation, never
written from memory. The printed report shows the registry's title, venue and
year for each DOI so that a wrong DOI is visible before it is trusted, and an
existing key is skipped rather than duplicated.

Usage:
    python3 05.scripts/06-add-references.py            # report only
    python3 05.scripts/06-add-references.py --write    # append to references.bib
"""

import json
import re
import sys
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BIB = ROOT / "04.references" / "references.bib"

MAILTO = "seamusrobertmurphy@gmail.com"
UA = f"woolly-adelgid-signatures/0.1 (mailto:{MAILTO})"

# Retrieved by 05.scripts/05-literature-search.py and screened by hand. The note
# records what each one is cited for, so a reader can check the citation does
# the work claimed of it.
DOIS = {
    "10.1080/01431169508954591": "First remote sensing of balsam woolly adelgid damage, CASI, balsam fir",
    "10.1155/2010/498189": "Branch-level spectral discrimination of BWA-infested subalpine fir",
    "10.4039/n09-065": "Gouting incidence in relation to hardiness zone and crown class",
    "10.3390/f8070251": "Attribution of disturbance agents from intra-annual Landsat, 76-86%",
    "10.1016/j.rse.2022.112935": "Causal agent mapping, boreal and arctic North America",
    "10.1080/07038992.2023.2196356": "Attribute agent before severity, northern hardwood",
    "10.1016/j.rse.2021.112502": "Landscape context improves disturbance attribution",
    "10.1016/j.rse.2018.03.009": "L-band SAR separating windthrow from insect outbreak",
    "10.1007/s40725-019-00098-z": "Review of radar for bark beetle outbreak detection",
    "10.1016/j.rse.2020.112240": "Early detection of spruce bark beetle stress, new index",
    "10.1002/rse2.93": "Sentinel-2 green-attack mapping, Ips typographus",
    "10.1016/j.rse.2019.111264": "Dual-wavelength terrestrial lidar, early Ips detection",
    "10.1002/ecs2.3156": "Multidimensional structural characterisation of moderate disturbance",
    "10.2478/forj-2024-0022": "Recent review of remote sensing forest health assessment",
    "10.1016/j.foreco.2018.08.020": "Aerial detection survey accuracy; agent specificity degrades",
    "10.3390/rs12081304": "Simulated GEDI lidar detects HWA understorey structural change",
    "10.3390/f11050529": "Satellite evaluation of IDS severity estimates, 35-78% by method",
    "10.3390/rs10081184": "Independent accuracy assessment of IDS against Landsat/MODIS products",
    "10.1023/a:1010021629127": "Satellite classification of HWA-infested hemlock health, 1999",
    "10.1016/j.rse.2016.12.005": "Low-level HWA detection via Landsat partition modelling",
    "10.1093/forestscience/43.3.327": "Landsat TM change detection of hemlock health, 1997",
}


def fetch(url: str, accept: str) -> str:
    req = urllib.request.Request(url, headers={"User-Agent": UA,
                                               "Accept": accept})
    with urllib.request.urlopen(req, timeout=45) as r:
        return r.read().decode("utf-8", errors="replace")


def main() -> None:
    write = "--write" in sys.argv
    existing = BIB.read_text() if BIB.exists() else ""
    existing_dois = {d.lower() for d in re.findall(r"DOI=\{([^}]+)\}", existing)}

    entries = []
    for doi, note in DOIS.items():
        if doi.lower() in existing_dois:
            print(f"skip (already present)  {doi}")
            continue
        try:
            meta = json.loads(fetch(f"https://api.crossref.org/works/{doi}",
                                    "application/json"))["message"]
        except Exception as exc:
            print(f"FAIL  {doi}: {exc}")
            continue
        title = (meta.get("title") or [""])[0]
        venue = (meta.get("container-title") or ["?"])[0]
        year = meta.get("issued", {}).get("date-parts", [[None]])[0][0]
        print(f"ok    {doi}\n      {title[:88]}\n      {venue}, {year}\n"
              f"      cited for: {note}")

        if write:
            bib = fetch(f"https://doi.org/{doi}", "application/x-bibtex").strip()
            entries.append(f"% {note}\n{bib}")
        time.sleep(0.5)

    if write and entries:
        with open(BIB, "a") as fh:
            fh.write("\n\n" + "\n\n".join(entries) + "\n")
        print(f"\nappended {len(entries)} entries to {BIB}")


if __name__ == "__main__":
    main()
