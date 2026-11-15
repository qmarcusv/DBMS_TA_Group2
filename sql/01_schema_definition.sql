-- ============================================================================
-- DDL Schema Definition: SpineMRI_DBMS
-- Creates database, relational tables, constraints, and keys.
-- ============================================================================

USE master;
GO

IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = 'SpineMRI_DBMS')
BEGIN
    CREATE DATABASE SpineMRI_DBMS;
END
GO

USE SpineMRI_DBMS;
GO

-- Drop existing tables in dependency order
IF OBJECT_ID('dbo.Image_Features', 'U') IS NOT NULL DROP TABLE dbo.Image_Features;
IF OBJECT_ID('dbo.MRI_Scans', 'U') IS NOT NULL DROP TABLE dbo.MRI_Scans;
IF OBJECT_ID('dbo.Patients', 'U') IS NOT NULL DROP TABLE dbo.Patients;
GO

-- 1. Patients Table: Clinical reports and diagnosis status
CREATE TABLE Patients (
    PatientID VARCHAR(20) NOT NULL,
    PatientName NVARCHAR(100) NULL,
    ClinicalNotes NVARCHAR(MAX) NULL,
    DiagnosisStatus VARCHAR(20) DEFAULT 'Confirmed',
    CreatedAt DATETIME DEFAULT GETDATE(),
    CONSTRAINT PK_Patients PRIMARY KEY CLUSTERED (PatientID)
);
GO

-- 2. MRI_Scans Table: Slice metadata and disk file references
CREATE TABLE MRI_Scans (
    ScanID INT IDENTITY(1,1) NOT NULL,
    PatientID VARCHAR(20) NOT NULL,
    StudyInstanceUID VARCHAR(150) NULL,
    SeriesDescription NVARCHAR(255) NOT NULL,
    ImagePath NVARCHAR(500) NOT NULL,
    AcquisitionDate DATETIME DEFAULT GETDATE(),
    CONSTRAINT CK_Series_Valid CHECK (SeriesDescription NOT LIKE '%INVALID%'),
    CONSTRAINT PK_MRI_Scans PRIMARY KEY CLUSTERED (ScanID),
    CONSTRAINT FK_MRI_Scans_Patients FOREIGN KEY (PatientID) 
        REFERENCES Patients(PatientID) 
        ON DELETE CASCADE ON UPDATE CASCADE
);
GO

-- 3. Image_Features Table: Pretrained CNN feature embeddings
CREATE TABLE Image_Features (
    FeatureID INT IDENTITY(1,1) NOT NULL,
    ScanID INT NOT NULL UNIQUE,
    FeatureVector NVARCHAR(MAX) NOT NULL,
    V_Dim1 FLOAT NULL,
    V_Dim2 FLOAT NULL,
    V_Dim3 FLOAT NULL,
    V_Dim4 FLOAT NULL,
    CONSTRAINT PK_Image_Features PRIMARY KEY CLUSTERED (FeatureID),
    CONSTRAINT FK_Features_Scans FOREIGN KEY (ScanID) 
        REFERENCES MRI_Scans(ScanID) 
        ON DELETE CASCADE
);
GO

-- Display schema summary
SELECT 
    t.name AS TableName, 
    c.name AS ColumnName, 
    ty.name AS DataType, 
    c.max_length AS MaxLength,
    c.is_nullable AS IsNullable
FROM sys.tables t
JOIN sys.columns c ON t.object_id = c.object_id
JOIN sys.types ty ON c.user_type_id = ty.user_type_id
ORDER BY t.name, c.column_id;
GO
