import os
import sys
import re
import csv
import pandas as pd
from datetime import datetime

if sys.stdout.encoding != 'utf-8':
    try:
        sys.stdout.reconfigure(encoding='utf-8')
    except Exception:
        pass

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
BASE_DIR = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
MRI_DIR = os.path.join(BASE_DIR, "01_MRI_Data")
REPORT_FILE = os.path.join(BASE_DIR, "Radiologists_Report.xlsx")
DATA_DIR = os.path.join(BASE_DIR, "data")
os.makedirs(DATA_DIR, exist_ok=True)

def clean_text(val):
    if pd.isna(val):
        return "No clinical notes"
    s = re.sub(r'[\r\n]+', ' ; ', str(val))
    return re.sub(r'\s+', ' ', s).strip()

def preprocess():
    # 1. Clean clinical notes
    df_raw = pd.read_excel(REPORT_FILE)
    df_raw['PatientID'] = df_raw['Patient ID'].dropna().astype(int).apply(lambda x: f"{x:04d}")
    df_raw['ClinicalNotes'] = df_raw["Clinician's Notes"].apply(clean_text)
    df_raw['PatientName'] = df_raw['PatientID'].apply(lambda x: f"Patient_{x}")
    df_raw['DiagnosisStatus'] = 'Confirmed'
    df_raw['CreatedAt'] = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    df_patients = df_raw[['PatientID', 'PatientName', 'ClinicalNotes', 'DiagnosisStatus', 'CreatedAt']].drop_duplicates(subset=['PatientID'])
    patients_csv = os.path.join(DATA_DIR, "clean_patients.csv")
    df_patients.to_csv(patients_csv, index=False, encoding='utf-8', quoting=csv.QUOTE_MINIMAL)
    print(f"[+] Saved: {patients_csv} ({len(df_patients)} rows)")

    # 2. Parse recursive MRI directory tree: PatientID / StudyUID / SeriesDesc / *.ima
    scans = []
    valid_pids = set(df_patients['PatientID'])
    
    for p_folder in sorted(os.listdir(MRI_DIR)):
        p_path = os.path.join(MRI_DIR, p_folder)
        if not os.path.isdir(p_path) or p_folder not in valid_pids:
            continue
            
        for study_folder in os.listdir(p_path):
            study_path = os.path.join(p_path, study_folder)
            if not os.path.isdir(study_path):
                continue
                
            for series_folder in os.listdir(study_path):
                series_path = os.path.join(study_path, series_folder)
                if not os.path.isdir(series_path):
                    continue
                    
                for f in os.listdir(series_path):
                    if f.lower().endswith(('.ima', '.dcm')):
                        scans.append({
                            'PatientID': p_folder,
                            'StudyInstanceUID': study_folder,
                            'SeriesDescription': series_folder,
                            'ImagePath': f"01_MRI_Data/{p_folder}/{study_folder}/{series_folder}/{f}",
                            'AcquisitionDate': datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                        })

    df_scans = pd.DataFrame(scans)
    scans_csv = os.path.join(DATA_DIR, "clean_mri_scans.csv")
    df_scans.to_csv(scans_csv, index=False, encoding='utf-8', quoting=csv.QUOTE_MINIMAL)
    print(f"[+] Saved: {scans_csv} ({len(df_scans)} scans)")

if __name__ == "__main__":
    preprocess()
