-- ============================================================================
-- Data Ingestion Pipeline: Bulk Import
-- Ingests preprocessed CSVs into Patients, MRI_Scans, and Image_Features.
-- ============================================================================

USE SpineMRI_DBMS;
GO

SET NOCOUNT ON;

-- 1. Import Patients (Parent Table)
BULK INSERT Patients
FROM 'W:\MYSELF\HCMUT-university\Senior\HK_261\DBMS\BTL\TA\data\clean_patients.csv'
WITH (
    FIRSTROW = 2,
    FORMAT = 'CSV',
    FIELDQUOTE = '"',
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '0x0a',
    CODEPAGE = '65001',
    TABLOCK
);
GO

-- 2. Import MRI_Scans via View (Handling IDENTITY column auto-generation)
IF OBJECT_ID('dbo.vw_MRI_Scans_Import', 'V') IS NOT NULL 
    DROP VIEW dbo.vw_MRI_Scans_Import;
GO

CREATE VIEW dbo.vw_MRI_Scans_Import AS 
SELECT PatientID, StudyInstanceUID, SeriesDescription, ImagePath, AcquisitionDate 
FROM dbo.MRI_Scans;
GO

BULK INSERT dbo.vw_MRI_Scans_Import
FROM 'W:\MYSELF\HCMUT-university\Senior\HK_261\DBMS\BTL\TA\data\clean_mri_scans.csv'
WITH (
    FIRSTROW = 2,
    FORMAT = 'CSV',
    FIELDQUOTE = '"',
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '0x0a',
    CODEPAGE = '65001',
    TABLOCK
);
GO

DROP VIEW dbo.vw_MRI_Scans_Import;
GO

-- 3. Import Image_Features via View
IF OBJECT_ID('dbo.vw_Image_Features_Import', 'V') IS NOT NULL 
    DROP VIEW dbo.vw_Image_Features_Import;
GO

CREATE VIEW dbo.vw_Image_Features_Import AS 
SELECT ScanID, FeatureVector, V_Dim1, V_Dim2, V_Dim3, V_Dim4 
FROM dbo.Image_Features;
GO

BULK INSERT dbo.vw_Image_Features_Import
FROM 'W:\MYSELF\HCMUT-university\Senior\HK_261\DBMS\BTL\TA\data\clean_image_features.csv'
WITH (
    FIRSTROW = 2,
    FORMAT = 'CSV',
    FIELDQUOTE = '"',
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '0x0a',
    CODEPAGE = '65001',
    TABLOCK
);
GO

DROP VIEW dbo.vw_Image_Features_Import;
GO

-- Verification query
SELECT 'Patients' AS [Table], COUNT(*) AS [RowCount] FROM Patients
UNION ALL
SELECT 'MRI_Scans', COUNT(*) FROM MRI_Scans
UNION ALL
SELECT 'Image_Features', COUNT(*) FROM Image_Features;
GO
