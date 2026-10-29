# Spine MRI DBMS Technical Report (`TA/report`)

This directory contains the LaTeX source and compiled PDF for the CO3021 Database Management Systems project:
**Clinical MRI Low Back Pain Data Pipeline, Relational Ingestion, and Full-Stack Database Engine Optimization**.

## Structure of the Report

- `main.tex`: Master LaTeX report document (`\documentclass[a4paper,10pt,oneside]{report}`) formatted with HCMUT official template styling, corporate headers/footers, and clean typography.
- `main.pdf`: Compiled production PDF report.
- `image/`: HCMUT logo and architecture diagrams.
- `source/`: Modular LaTeX source files:
  - `source/chapters/01-datapipeline-role1.tex`: Chapter 1 (Role 1) — Clinical MRI Data Pipeline, Storage Architecture, and Ingestion Engineering (Project Overview, Canonical Queries Contract, Storage Comparison, Schema DDL, Bulk Import, and ResNet-18 CPU Feature Extraction).

## Compilation

To compile from PowerShell:
```powershell
pdflatex -interaction=nonstopmode main.tex
pdflatex -interaction=nonstopmode main.tex
```
