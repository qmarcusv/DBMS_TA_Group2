# Clinical Spine MRI DBMS Project

> **Course:** Database Management Systems (CO3021) — Semester 261  
> **Institution:** Ho Chi Minh City University of Technology (HCMUT - VNU-HCM)  
> **Topic:** Clinical MRI Low Back Pain Data Pipeline, Relational Ingestion, and Full-Stack Database Engine Optimization  
> **Target Database Engine:** Microsoft SQL Server 2025 Enterprise / Developer Edition  

---

## 1. Project Overview & Provenance

This project implements an end-to-end clinical imaging database platform and database engine optimization benchmark using real-world medical data from Mendeley Data:
* **Dataset:** *A large dataset of lumbar spine MRI for low back pain pre-processing, segmentation, and detection* (doi: 10.17632/k57fr854j2.2).
* **Clinical Records:** 575 patients with radiological diagnoses and clinician notes extracted from Excel spreadsheets.
* **Imaging Scans:** 48,345 DICOM/IMA cross-sectional slices organized hierarchically across 515 imaging studies and multi-sequence pulse protocols (T1, T2 sagittal, T2 axial).
* **AI Embeddings:** 48,345 normalized 512-dimensional feature vectors extracted using a pretrained ResNet-18 deep convolutional neural network on CPU.

---

## 2. System Architecture & Storage Strategy

Medical imaging datasets present significant challenges for relational database buffer pools:
* **Storage Footprint:** Raw DICOM files consume ~13 GB on disk. Storing binary image data directly as `VARBINARY(MAX)` BLOBs inside SQL Server would cause severe buffer pool thrashing, rapid eviction of index/data pages from memory, and unmanageable database growth.
* **Hybrid Storage Architecture:** 
  * Structured clinical metadata and relative file paths (`NVARCHAR(500)`) are stored in Microsoft SQL Server (`SpineMRI_DBMS`), keeping the active database footprint compact at **53.6 MB**.
  * Raw physical slices (`.ima` / `.dcm`) reside on disk in structured subdirectories (`01_MRI_Data/`).
  * AI feature vectors are stored both as lightweight numerical float dimensions (`V_Dim1` – `V_Dim4`) for high-speed in-engine distance computations and complete 32-element JSON float arrays in `NVARCHAR(MAX)` for application interoperability.

```
                      +---------------------------------------+
                      | Raw Clinical Data (Mendeley Data)    |
                      | 575 Patients (Excel) + 48,345 Slices  |
                      +-------------------+-------------------+
                                          |
                                          v
                      +---------------------------------------+
                      | Python Preprocessing & AI Pipeline    |
                      | - 01_preprocess.py (Regex, Paths)     |
                      | - 02_extract_features.py (ResNet-18)  |
                      +-------------------+-------------------+
                                          |
                        +-----------------+-----------------+
                        |                                   |
                        v                                   v
             [Structured Metadata]                 [AI Feature Vectors]
             - clean_patients.csv (126 KB)         - clean_image_features.csv (15.8 MB)
             - clean_mri_scans.csv (8.9 MB)         (48,345 embeddings)
                        |                                   |
                        +-----------------+-----------------+
                                          |
                                          v
                      +---------------------------------------+
                      | Microsoft SQL Server 2025             |
                      | Database: SpineMRI_DBMS (53.6 MB)     |
                      |  * Patients (575 rows)                |
                      |  * MRI_Scans (48,345 rows)            |
                      |  * Image_Features (48,345 rows)       |
                      +-------------------+-------------------+
                                          |
                                          v
                      +---------------------------------------+
                      | Canonical Evaluation Queries          |
                      |  * Q1: Patient lookup & scan join     |
                      |  * Q2: T2 Sagittal pulse filtering    |
                      |  * Q3: Top-3 AI similarity retrieval  |
                      +---------------------------------------+
```

---

## 3. The Canonical Queries Contract (Q1, Q2, Q3)

All team roles evaluate the database engine against the same three standard queries defined in `scripts/sql/00_canonical_queries.sql`:

### Query 1: Patient Report & Complete Scan Retrieval
* **Clinical Purpose:** Given a target patient ID, retrieve clinical notes and all associated MRI slices.
* **Engine Focus:** Evaluates Clustered Index Seek on primary key vs. Table Scan, and verifies join selectivity (1-to-N join).
```sql
SELECT 
    p.PatientID, p.PatientName, p.ClinicalNotes,
    s.ScanID, s.SeriesDescription, s.ImagePath
FROM Patients p
INNER JOIN MRI_Scans s ON p.PatientID = s.PatientID
WHERE p.PatientID = '0001';
```

### Query 2: Filtered Scan Retrieval by Pulse Sequence (T2 Sagittal)
* **Clinical Purpose:** Radiologists specifically inspect T2-weighted sagittal series to diagnose spinal disc herniation and cord compression.
* **Engine Focus:** Evaluates multi-predicate filtering (`PatientID = '0001' AND SeriesDescription LIKE '%T2%SAG%'`), filtered index effectiveness, and cardinality estimation via statistics histograms.
```sql
SELECT 
    p.PatientID, p.PatientName, p.ClinicalNotes,
    s.ScanID, s.SeriesDescription, s.ImagePath
FROM Patients p
INNER JOIN MRI_Scans s ON p.PatientID = s.PatientID
WHERE p.PatientID = '0001'
  AND s.SeriesDescription LIKE '%T2%SAG%';
```

### Query 3: AI Feature Similarity Retrieval (Content-Based Image Retrieval)
* **Clinical Purpose:** Find the top-3 most visually and structurally similar MRI slices compared to a target slice (`ScanID = 1`).
* **Engine Focus:** Evaluates batch vector Euclidean distance calculations, Compute Scalar operators, Top-N Sort, and Rowstore vs. Columnstore performance.
```sql
DECLARE @TargetScanID INT = 1;
DECLARE @T1 FLOAT, @T2 FLOAT, @T3 FLOAT, @T4 FLOAT;

SELECT @T1 = V_Dim1, @T2 = V_Dim2, @T3 = V_Dim3, @T4 = V_Dim4 
FROM Image_Features WHERE ScanID = @TargetScanID;

SELECT TOP 3
    s.ScanID, s.PatientID, s.SeriesDescription, s.ImagePath,
    SQRT(
        SQUARE(f.V_Dim1 - @T1) + SQUARE(f.V_Dim2 - @T2) + 
        SQUARE(f.V_Dim3 - @T3) + SQUARE(f.V_Dim4 - @T4)
    ) AS EuclideanDistance
FROM Image_Features f
INNER JOIN MRI_Scans s ON f.ScanID = s.ScanID
WHERE f.ScanID <> @TargetScanID
ORDER BY EuclideanDistance ASC;
```

---

## 4. Quick Start: Restoring the Database

The complete database backup is provided at `data/SpineMRI_DBMS.bak` (53.6 MB) with 100% of all 575 patients, 48,345 scans, and 48,345 feature vectors already populated.

### Option A: Restore via T-SQL (Fastest — ~0.2 seconds)
Open SQL Server Management Studio (SSMS) or `sqlcmd` and execute:
```sql
USE master;
GO

RESTORE DATABASE SpineMRI_DBMS
FROM DISK = 'W:\MYSELF\HCMUT-university\Senior\HK_261\DBMS\BTL\TA\data\SpineMRI_DBMS.bak'
WITH REPLACE, RECOVERY;
GO

-- Verify table counts
USE SpineMRI_DBMS;
SELECT 'Patients' AS [Table], COUNT(*) AS [Rows] FROM Patients
UNION ALL
SELECT 'MRI_Scans', COUNT(*) FROM MRI_Scans
UNION ALL
SELECT 'Image_Features', COUNT(*) FROM Image_Features;
```
*(Adjust the file path in `FROM DISK = '...'` to match your local repository directory).*

### Option B: Restore via SSMS GUI
1. In SSMS Object Explorer, right-click **Databases** -> **Restore Database...**
2. Choose **Device**, click `...`, and add `TA/data/SpineMRI_DBMS.bak`.
3. In the **Options** page, check **Overwrite the existing database (WITH REPLACE)**.
4. Click **OK**.

---

## 5. Running the Pipeline from Scratch (Optional)

If you wish to re-run data cleaning, feature extraction, and ingestion:

### Prerequisites
* Windows 10/11 with Python 3.10+
* Microsoft SQL Server 2019/2022/2025
* Python dependencies:
  ```bash
  pip install torch torchvision pydicom pandas openpyxl pillow
  ```

### Step 1: Preprocessing DICOM Files and Notes
```bash
python scripts/01_preprocess.py
```
Outputs `data/clean_patients.csv` and `data/clean_mri_scans.csv`.

### Step 2: DDL Schema Creation
Execute `scripts/sql/01_schema_definition.sql` in SSMS to create tables, primary keys, and foreign keys.

### Step 3: ResNet-18 Feature Extraction
```bash
python scripts/02_extract_features.py
```
Extracts feature vectors for all 48,345 slices using ResNet-18 on CPU and writes `data/clean_image_features.csv`. Supports automatic checkpoint resuming.

### Step 4: Bulk Data Ingestion
Execute `scripts/sql/02_bulk_import.sql` in SSMS. Uses view-based bulk insertion to seamlessly manage identity columns and tablocks.

---

## 6. Repository Structure

```
TA/
├── .gitignore                      # Excludes raw images, archives, LaTeX build temp files
├── README.md                       # Project documentation and reproduction guide
├── Radiologists_Report.xlsx        # Raw clinician notes from Mendeley Data
├── data/
│   ├── SpineMRI_DBMS.bak           # Complete SQL Server database backup (53.6 MB)
│   ├── clean_patients.csv          # Cleaned patients table (575 rows, 126 KB)
│   ├── clean_mri_scans.csv         # Cleaned scans metadata table (48,345 rows, 8.9 MB)
│   └── clean_image_features.csv    # Deep learning feature vectors (48,345 rows, 15.8 MB)
├── scripts/
│   ├── 01_preprocess.py            # Cleans Excel notes and indexes DICOM directory tree
│   ├── 02_extract_features.py      # ResNet-18 CPU batch feature extraction pipeline
│   └── sql/
│       ├── 00_canonical_queries.sql    # Standard Q1, Q2, Q3 benchmark queries
│       ├── 01_schema_definition.sql    # DDL schema definition and constraints
│       └── 02_bulk_import.sql          # Bulk import pipeline with IDENTITY views
└── report/
    ├── main.tex                    # Master LaTeX report (HCMUT corporate style)
    ├── main.pdf                    # Compiled report PDF (10 pages)
    ├── README.md                   # LaTeX compilation guide
    ├── image/                      # HCMUT insignia and visual assets
    └── source/
        └── chapters/
            ├── 01-introduction.tex       # Chapter 1: Overview & Canonical Queries
            ├── 02-datapipeline-role1.tex # Chapter 2: Data Pipeline & Storage (Role 1)
            ├── 03-indexing-role2.tex     # Chapter 3: Indexing Structures (Role 2)
            ├── 04-query-opt-role3.tex    # Chapter 4: Query Optimization (Role 3)
            ├── 05-transactions-role4.tex # Chapter 5: Transactions & Recovery (Role 4)
            └── 06-concurrency-role5.tex  # Chapter 6: Concurrency Control (Role 5)
```

---

## 7. Role Division & Optimization Matrix

| Role | Core Domain | Scope in SpineMRI_DBMS | Key Deliverables & Benchmark Focus |
| :--- | :--- | :--- | :--- |
| **Role 1** | **Data Platform Lead** | Tasks 2, 3, 4, 5, 6 | Data cleaning, schema DDL, bulk ingestion, ResNet-18 AI pipeline, repository structure, technical report coordination. |
| **Role 2** | **Storage & Indexing** | Physical Database Engine | Non-clustered indexes on `SeriesDescription`, filtered index for `T2%SAG%`, Columnstore index on `Image_Features(V_Dim1..4)`, B-Tree depth analysis. |
| **Role 3** | **Query Processing** | Query Optimizer & Execution | Execution plan analysis across Q1–Q3, statistics histograms, Nested Loops vs. Hash Match joins, cardinality estimation, Compute Scalar vector costs. |
| **Role 4** | **Transaction & Logging** | ACID & WAL Engine | Write-Ahead Logging (WAL) internals, `sys.fn_dblog()`, Dirty Page flushing, CHECK constraint rollback validation, Crash recovery simulation. |
| **Role 5** | **Concurrency & Locks** | Lock Manager & Isolation | `sys.dm_tran_locks` monitoring, Dirty Read/Non-repeatable Read/Phantom Read reproduction across Read Committed, Snapshot, and Serializable isolation levels. |

---

## 8. Report Compilation

The project technical report is written in LaTeX conforming to the official HCMUT format.
To compile the PDF report:
```powershell
cd report
pdflatex -interaction=nonstopmode main.tex
pdflatex -interaction=nonstopmode main.tex
```
Output: `report/main.pdf` (10 pages, 0 compilation errors).
