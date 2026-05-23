#!/usr/bin/env python3
"""
PotreeConverter Cloud Run Job.

Downloads a LAS point cloud from GCS, converts it to Potree octree tiles
via PotreeConverter, uploads the tiles back to GCS, and marks the capture
as 'ready' in Supabase.

Usage (triggered by ft-api ODM status poller):
  python convert.py --capture-id <uuid>
"""

import argparse
import json
import logging
import os
import subprocess
import sys
import tempfile
from pathlib import Path

import httpx
from google.cloud import storage

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [potree-converter] %(levelname)s %(message)s",
)
log = logging.getLogger(__name__)

DRONE_BUCKET = os.environ["DRONE_BUCKET"]
SUPABASE_URL = os.environ["SUPABASE_URL"].rstrip("/")
SUPABASE_SERVICE_KEY = os.environ["SUPABASE_SERVICE_KEY"]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--capture-id", required=True)
    args = parser.parse_args()
    capture_id = args.capture_id

    log.info("Starting conversion for capture %s", capture_id)

    gcs = storage.Client()
    bucket = gcs.bucket(DRONE_BUCKET)

    with tempfile.TemporaryDirectory() as tmpdir:
        tmp = Path(tmpdir)
        las_path = tmp / "odm_pointcloud.las"
        tiles_dir = tmp / "tiles"
        tiles_dir.mkdir()

        _download_las(bucket, capture_id, las_path)
        _run_potree_converter(las_path, tiles_dir)
        _upload_tiles(bucket, capture_id, tiles_dir)
        gsd_cm = _fetch_gsd(bucket, capture_id)
        _update_supabase(capture_id, f"captures/{capture_id}/tiles/", gsd_cm)

    log.info("Capture %s is ready.", capture_id)


def _download_las(bucket, capture_id: str, dest: Path) -> None:
    blob_name = f"captures/{capture_id}/processed/odm_pointcloud.las"
    log.info("Downloading gs://%s/%s ...", DRONE_BUCKET, blob_name)
    bucket.blob(blob_name).download_to_filename(str(dest))
    log.info("Downloaded %.1f MB", dest.stat().st_size / 1_048_576)


def _run_potree_converter(las_path: Path, tiles_dir: Path) -> None:
    log.info("Running PotreeConverter...")
    result = subprocess.run(
        [
            "PotreeConverter",
            str(las_path),
            "-o", str(tiles_dir),
            "--output-format", "LAZ",
        ],
        capture_output=True,
        text=True,
        timeout=540,
    )
    if result.returncode != 0:
        log.error("PotreeConverter stderr:\n%s", result.stderr)
        sys.exit(1)
    log.info("PotreeConverter finished.")


def _upload_tiles(bucket, capture_id: str, tiles_dir: Path) -> None:
    prefix = f"captures/{capture_id}/tiles"
    log.info("Uploading tiles to gs://%s/%s/ ...", DRONE_BUCKET, prefix)
    uploaded = 0
    for tile_file in sorted(tiles_dir.rglob("*")):
        if tile_file.is_file():
            blob_name = f"{prefix}/{tile_file.relative_to(tiles_dir)}"
            bucket.blob(blob_name).upload_from_filename(str(tile_file))
            uploaded += 1
    log.info("Uploaded %d tile files.", uploaded)


def _fetch_gsd(bucket, capture_id: str) -> float | None:
    """Best-effort: read GSD from the ODM report JSON if available."""
    report_blob = bucket.blob(
        f"captures/{capture_id}/processed/odm_report/odm_report.json"
    )
    try:
        if report_blob.exists():
            report = json.loads(report_blob.download_as_text())
            gsd = report.get("processing_statistics", {}).get("gsd")
            if gsd is not None:
                log.info("GSD from ODM report: %.2f cm", gsd)
                return float(gsd)
    except Exception as exc:
        log.warning("Could not read GSD from ODM report: %s", exc)
    return None


def _update_supabase(capture_id: str, tiles_gcs_prefix: str, gsd_cm: float | None) -> None:
    payload: dict = {
        "status": "ready",
        "tiles_gcs_prefix": tiles_gcs_prefix,
    }
    if gsd_cm is not None:
        payload["metadata"] = {"gsd_cm": gsd_cm}

    headers = {
        "apikey": SUPABASE_SERVICE_KEY,
        "Authorization": f"Bearer {SUPABASE_SERVICE_KEY}",
        "Content-Type": "application/json",
        "Prefer": "return=minimal",
    }
    url = f"{SUPABASE_URL}/rest/v1/captures?id=eq.{capture_id}"
    log.info("Updating Supabase capture %s — status=ready ...", capture_id)
    with httpx.Client(timeout=30) as client:
        resp = client.patch(url, headers=headers, json=payload)
    if resp.status_code not in (200, 204):
        log.error("Supabase PATCH failed: %s %s", resp.status_code, resp.text)
        sys.exit(1)
    log.info("Supabase updated.")


if __name__ == "__main__":
    main()
