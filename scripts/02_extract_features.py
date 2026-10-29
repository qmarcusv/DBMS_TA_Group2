import os
import sys
import json
import csv
import time
import numpy as np
import pandas as pd
from PIL import Image
import torch
import torchvision.models as models
import torchvision.transforms as transforms
import pydicom

if sys.stdout.encoding != 'utf-8':
    try:
        sys.stdout.reconfigure(encoding='utf-8')
    except Exception:
        pass

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
BASE_DIR = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
SCANS_CSV = os.path.join(BASE_DIR, "data", "clean_mri_scans.csv")
OUT_CSV = os.path.join(BASE_DIR, "data", "clean_image_features.csv")

def extract_features(batch_size=64):
    # Set CPU execution threads
    torch.set_num_threads(min(12, os.cpu_count() or 4))
    device = torch.device('cpu')
    
    # Load pretrained ResNet-18 feature extractor
    model = models.resnet18(weights=models.ResNet18_Weights.DEFAULT).to(device)
    model.eval()
    feature_extractor = torch.nn.Sequential(*list(model.children())[:-1]).to(device)

    # Input preprocessing
    transform = transforms.Compose([
        transforms.Resize((224, 224)),
        transforms.ToTensor(),
        transforms.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225])
    ])

    df_scans = pd.read_csv(SCANS_CSV)
    total_images = len(df_scans)
    print(f"[*] Processing {total_images} MRI scans on {device}...")

    # Resume capability check
    processed_scan_ids = set()
    file_exists = os.path.exists(OUT_CSV)
    if file_exists:
        try:
            df_existing = pd.read_csv(OUT_CSV, usecols=['ScanID'])
            processed_scan_ids = set(df_existing['ScanID'])
            print(f"[*] Found {len(processed_scan_ids)} existing features. Resuming...")
        except Exception:
            pass

    f_out = open(OUT_CSV, 'a' if file_exists and len(processed_scan_ids) > 0 else 'w', 
                 newline='', encoding='utf-8')
    fieldnames = ['ScanID', 'FeatureVector', 'V_Dim1', 'V_Dim2', 'V_Dim3', 'V_Dim4']
    writer = csv.DictWriter(f_out, fieldnames=fieldnames, quoting=csv.QUOTE_MINIMAL)
    if not file_exists or len(processed_scan_ids) == 0:
        writer.writeheader()
        f_out.flush()

    batch_tensors = []
    batch_scan_ids = []
    start_time = time.time()
    count_new = 0

    for idx, row in df_scans.iterrows():
        scan_id = idx + 1
        if scan_id in processed_scan_ids:
            continue

        rel_path = row['ImagePath']
        full_path = os.path.join(BASE_DIR, rel_path)

        try:
            ds = pydicom.dcmread(full_path)
            arr = ds.pixel_array.astype(float)
            min_val, max_val = arr.min(), arr.max()
            if max_val > min_val:
                arr = (arr - min_val) / (max_val - min_val) * 255.0
            else:
                arr = np.zeros_like(arr)
            img = Image.fromarray(arr.astype(np.uint8)).convert('RGB')
        except Exception:
            img = Image.new('RGB', (224, 224), color=(128, 128, 128))

        batch_tensors.append(transform(img))
        batch_scan_ids.append(scan_id)

        # Process mini-batch
        if len(batch_tensors) >= batch_size or (idx + 1) == total_images:
            stacked = torch.stack(batch_tensors).to(device)
            with torch.no_grad():
                embs = feature_extractor(stacked).squeeze(-1).squeeze(-1).cpu().numpy()

            for b_idx in range(len(batch_scan_ids)):
                emb = embs[b_idx]
                norm = np.linalg.norm(emb)
                if norm > 0:
                    emb = emb / norm

                writer.writerow({
                    'ScanID': batch_scan_ids[b_idx],
                    'FeatureVector': json.dumps([round(float(x), 5) for x in emb[:32].tolist()]),
                    'V_Dim1': round(float(emb[0]), 6),
                    'V_Dim2': round(float(emb[1]), 6),
                    'V_Dim3': round(float(emb[2]), 6),
                    'V_Dim4': round(float(emb[3]), 6)
                })
                count_new += 1

            f_out.flush()
            batch_tensors.clear()
            batch_scan_ids.clear()

            total_done = len(processed_scan_ids) + count_new
            if total_done % 1000 == 0 or total_done == total_images:
                elapsed = time.time() - start_time
                fps = count_new / elapsed if elapsed > 0 else 0
                pct = (total_done / total_images) * 100
                print(f"    Progress: {total_done}/{total_images} ({pct:.1f}%) | Speed: {fps:.1f} scans/s")

    f_out.close()
    print(f"[+] Feature extraction completed: {OUT_CSV}")

if __name__ == "__main__":
    extract_features()
