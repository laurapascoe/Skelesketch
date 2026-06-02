/*
================================================================================
  Microglia Skeleton & Soma Analysis Suite
  for Fiji/ImageJ — Epifluorescence Images (bright cell, dark background)
================================================================================

SETUP
-----
1. Place the unzipped 'CustomMacros' folder here:
      Fiji.app > scripts > Plugins

2. Install dependencies via:
      Help > Update... > Manage Update Sites
   Enable ALL of the following, then Apply Changes and restart Fiji:
      - ImageJ
      - Fiji
      - Java-8
      - BoneJ
      - IJPB-plugins
      - Neuroanatomy
      - ResultsToExcel

3. Restart Fiji (close and reopen).

4. Run this README file once to install keyboard shortcuts:
      Plugins > CustomMacros > README

WORKFLOW
--------
  F1  →  Capture Images
          Open your full image, then press F1.
          Draw a rectangle around each cell and press Space to capture.
          Press Shift when done — files are saved automatically.
          Output filenames follow the pattern: BaseName-N.tif
          A scale bar is burned into each saved crop and the labeled overview.

  F2  →  Edit & Finalize
          Open a captured cell image, then press F2.
          The macro will skeletonize it and detect the soma automatically.
          Press Space to preview the skeleton overlay.
          Press Shift to accept, collect data, and advance to the next image.

CHANNEL SELECTION (multi-channel VSI exports)
---------------------------------------------
  If your image is a multi-channel export (e.g. FITC / TRITC / CY5), open
  Skeletonize_And_Detect_Soma.ijm and set MICROGLIA_CHANNEL to the channel
  number that contains your microglia stain:
      1 = FITC   (default)
      2 = TRITC
      3 = CY5

  To confirm the right channel: open your image in Fiji, go to
  Image > Color > Split Channels, and identify which channel shows the
  brightest microglia signal.

MICRON CALIBRATION
------------------
  The pipeline reads pixel size from the image's own calibration metadata
  (visible under Image > Properties). VSI files opened via Bio-Formats carry
  this automatically (e.g. 0.5119 µm/px as shown in Image Properties).

  All Excel output columns are in µm / µm² when calibration is detected.
  If calibration is missing, column headers switch to _px / _px2 as a reminder.

  To set calibration manually before pressing F2:
      Image > Properties → set Pixel Width, Pixel Height, and Unit to "microns"

EXCEL OUTPUT
------------
  Each batch writes one file: <BaseName>-Data.xlsx

  Sheet: "Summary"  (one row per cell)
    Cell_ID, Soma_Area_um2,
    Soma_Circularity, Soma_AR, Soma_Solidity,
    Num_Branches,
    Total_Branch_Length_um, Avg_Branch_Length_um, Max_Branch_Length_um,
    Num_Junctions, Num_Endpoints, Num_Triple_Points, Num_Quadruple_Points,
    Ramification_Index, Junction_Density, Endpoint_Density,
    Avg_Span_Ratio, Branch_Density, Complexity_Index

  Sheet: "Detailed"  (one row per branch — appended each cell)
    Cell_ID, Skeleton_ID, Branch_Length_um,
    V1x_um, V1y_um, V2x_um, V2y_um,
    Euclidean_Distance_um, Running_Avg_Length_um, Branch_Type

SCALE BAR ON SAVED IMAGES
--------------------------
  A scale bar is added to every saved .tif (crops, skeleton, tagged skeleton,
  composite). Default is 10 µm, white, lower-right corner.

  To change the scale bar size or style, open Edit_Finalize.ijm and adjust
  the variables at the top of the Tunable Parameters section:
      SCALEBAR_WIDTH_UM  — bar length in microns (default 10)
      SCALEBAR_HEIGHT    — bar thickness in pixels (default 4)
      SCALEBAR_FONT      — label font size (default 14)
      SCALEBAR_COLOR     — color string (default "White")
      SCALEBAR_LOCATION  — corner: "Lower Right", "Lower Left", etc.

  For crop images (F1), the same 10 µm default is used and is set directly
  in Capture_Images.ijm near the "Add scale bar" comment.

TROUBLESHOOTING — Soma Not Detected
-------------------------------------
  If the log prints "WARNING: No soma detected", try these in order:

  1. Verify the channel: set MICROGLIA_CHANNEL to the correct channel number.

  2. Lower SOMA_MIN_AREA (default 15): open Skeletonize_And_Detect_Soma.ijm
     and reduce to 10 or 5 if your soma appear small.

  3. Try a different SOMA_THRESHOLD_METHOD: "Li" or "Mean" can work better
     for images with uneven illumination.

  4. Check manually: Image > Adjust > Threshold → set method to Otsu,
     tick "Dark background", and confirm the soma region is highlighted.
     If it isn't, the signal may be too dim — try adjusting brightness/contrast
     before pressing F2.

TROUBLESHOOTING — No Skeleton / Poor Skeleton
----------------------------------------------
  1. Increase PROCESS_CLOSE_PASSES (default 3) to fill more gaps in processes.

  2. Reduce PROCESS_BG_RADIUS (default 50) if background subtraction is
     removing real process signal.

  3. Try PROCESS_THRESHOLD_METHOD = "Li" for images with low contrast.

  4. Reduce PRUNE_LENGTH_THRESHOLD (default 4) to keep shorter branch tips.

LPS vs PBS DISCRIMINATION — KEY METRICS
----------------------------------------
  Standard skeleton stats (branch count, total length, etc.) often fail to
  separate LPS-treated from PBS microglia on their own because they scale
  with cell size and image variability. The following derived metrics, now
  included in every Summary row, are the strongest discriminators:

  Ramification_Index  (Total_Branch_Length / Soma_Area)
    PBS (resting):  high — many long processes relative to a small soma.
    LPS (activated): low — processes retract, soma enlarges.
    → Usually the single best individual discriminator.

  Complexity_Index  ((Num_Endpoints × Total_Branch_Length) / Soma_Area)
    A compound measure; drops sharply with LPS activation.

  Junction_Density  (Num_Junctions / Total_Branch_Length)
    PBS cells have many branch points per µm — dense arborisation.
    LPS cells retain few, simple processes.

  Soma_Circularity  (0–1; 1 = perfect circle)
    LPS → rounder soma → higher circularity.
    PBS → irregular, processes pulling soma out → lower circularity.

  Soma_AR  (major axis / minor axis)
    LPS → closer to 1.0 (round).
    PBS → higher (elongated by process roots).

  Avg_Span_Ratio  (mean Euclidean_distance / Branch_length)
    0–1; 1 = straight, <1 = tortuous.
    Not always significant alone, but useful combined with other metrics.

  RECOMMENDED ANALYSIS WORKFLOW:
    1. Export the Summary sheet from PBS and LPS runs into one spreadsheet.
       Add a "Condition" column (PBS / LPS).
    2. Run a Mann-Whitney U or t-test on each metric across conditions.
    3. Ramification_Index and Complexity_Index usually show p < 0.05 first.
    4. For multivariate separation, run PCA or logistic regression on all
       derived metrics — they span complementary aspects of morphology.

NOTES
-----
  * Any changes to macro files require a Fiji restart to take effect.
  * Make sure the output Excel file is CLOSED before pressing Shift in F2,
    otherwise data cannot be written.
  * All tunable parameters are defined as named variables at the top of each
    macro file — no need to edit logic.
================================================================================
*/

run("Add Shortcut... ", "shortcut=F1 command=[Capture Images]");
run("Add Shortcut... ", "shortcut=F2 command=[Edit Finalize]");

print("Shortcuts installed: F1 = Capture Images | F2 = Edit Finalize");
