/*
================================================================================
  Edit_Finalize.ijm
  Triggered by: F2
================================================================================
  Opens the skeletonization pipeline on the current cell image, lets you
  manually edit the skeleton if needed, then collects all measurements and
  writes them to a per-folder Excel file.

  Controls (while editing — all done on the COMPOSITE window):
    Space  →  Re-skeletonize from your edits and refresh the composite preview
    Shift  →  Accept, collect data, advance to next image

  How to edit on the Composite:
    - The skeleton is shown in RED (channel 1). The cell image is in GREEN.
    - Make sure channel 1 is active (slider at bottom of Composite window).
    - Select the Brush tool. Set foreground to WHITE to draw new branches.
    - Set foreground to BLACK to erase unwanted branches.
    - You see exactly what you are adding/removing against the cell image.
    - Press Space to re-skeletonize and refresh — the composite updates in place.

  Data collected per cell:

  "Summary" sheet (one row per cell — easy-read overview):
    Cell_ID                   — crop number (1, 2, 3 …)
    Soma_Area_um2             — largest detected soma blob (µm²)
    Soma_Circularity          — soma roundness 0–1 (1=perfect circle; LPS→higher)
    Soma_AR                   — soma major/minor axis ratio (LPS→closer to 1)
    Soma_Solidity             — soma area / convex hull area (LPS→higher)
    Num_Branches              — total branches across all skeleton components
    Total_Branch_Length_um    — sum of all branch lengths (µm)
    Avg_Branch_Length_um      — mean branch length (µm)
    Max_Branch_Length_um      — longest single branch (µm)
    Num_Junctions             — junction voxel count
    Num_Endpoints             — end-point voxel count
    Num_Triple_Points         — triple-point count (3-way forks)
    Num_Quadruple_Points      — quadruple-point count (4-way forks)
    Ramification_Index        — Total_Branch_Length / Soma_Area (LPS→lower)
    Junction_Density          — Num_Junctions / Total_Branch_Length (LPS→lower)
    Endpoint_Density          — Num_Endpoints / Total_Branch_Length (LPS→lower)
    Avg_Span_Ratio            — mean (Euclidean_Distance / Branch_Length) per branch,
                                 0–1; high = straight processes (LPS→higher)
    Branch_Density            — Num_Branches / Soma_Area (LPS→lower)
    Complexity_Index          — (Num_Endpoints * Total_Branch_Length) / Soma_Area
                                 (compound ramification measure; LPS→lower)

  "Detailed" sheet (one row per branch — all data from Branch information table):
    Cell_ID                   — which cell this branch belongs to
    Skeleton_ID               — component index within the skeleton
    Branch_Length_um          — length of this individual branch (µm)
    V1x, V1y                  — start endpoint coordinates (µm)
    V2x, V2y                  — end endpoint coordinates (µm)
    Euclidean_Distance_um     — straight-line tip-to-tip distance (µm)
    Running_Average_Length_um — running average length up to this branch (µm)
    Branch_Type               — slab type code from Analyze Skeleton

  Output files saved per cell to the same folder as the input images:
    <name>-N(Skeleton).tif         — final edited skeleton (with scale bar)
    <name>-N(Tagged-Skeleton).tif  — colour-coded skeleton (with scale bar)
    <name>-N(Composite).tif        — red skeleton + green cell overlay (with scale bar)
    <name>-Data.xlsx               — Summary sheet (per cell) + Detailed sheet (per branch)

  NOTES:
    * Always close the Excel file before pressing Shift.
    * If your microglia channel is not FITC (channel 1), set MICROGLIA_CHANNEL
      below to the correct channel number (must match Skeletonize_And_Detect_Soma.ijm).
    * Pixel size is read from the image's own calibration (Image > Properties).
      If images were saved without calibration, measurements will fall back to pixels.
================================================================================
*/

// ── Tunable Parameters (keep in sync with Skeletonize_And_Detect_Soma.ijm) ───

// Channel: 1=FITC, 2=TRITC, 3=CY5
MICROGLIA_CHANNEL = 1;

// --- Soma re-detection (must match Skeletonize_And_Detect_Soma.ijm) ---
SOMA_TOP_PERCENT     = 8;
SOMA_BLUR_RADIUS     = 2;
SOMA_ERODE_PASSES    = 1;
SOMA_MIN_AREA        = 15;
SOMA_MAX_AREA        = 50000;
SOMA_CIRCULARITY_MIN = 0.4;

// --- Branch length filter ---
// Branches shorter than this threshold are excluded from all reported statistics.
// This removes skeleton noise/stub artefacts without destroying the skeleton visually.
// Set to 0 to disable filtering (keep all branches).
// 5 µm is a reasonable default for microglia; raise to 8–10 if stubs persist.
MIN_BRANCH_LENGTH_UM = 5.0;

// Scale bar settings for saved images
SCALEBAR_WIDTH_UM  = 10;   // length of scale bar in microns
SCALEBAR_HEIGHT    = 4;    // thickness in pixels
SCALEBAR_FONT      = 14;   // label font size
SCALEBAR_COLOR     = "White";
SCALEBAR_LOCATION  = "Lower Right";

// ── End of Tunable Parameters ─────────────────────────────────────────────────

// ── Initialise ────────────────────────────────────────────────────────────────

officialName = getTitle();
officialName = officialName.substring(0, officialName.length() - 4);
rename(officialName);

// ── Read pixel calibration from the source image ──────────────────────────────
// getVoxelSize returns physical size per pixel and unit string.
// We use pixelWidth for linear conversions; pixelWidth² for area.
getVoxelSize(pixW, pixH, pixD, pixUnit);
if (pixUnit == "microns" || pixUnit == "µm" || pixUnit == "um") {
    calibrated   = true;
    px2um        = pixW;          // µm per pixel (linear)
    px2um2       = pixW * pixH;   // µm² per pixel² (area)
    unitLabel    = "um";
    print("Calibration: " + pixW + " µm/px  (area factor: " + px2um2 + " µm²/px²)");
} else {
    calibrated   = false;
    px2um        = 1;
    px2um2       = 1;
    unitLabel    = "px";
    print("WARNING: No µm calibration found — measurements will be in pixels.");
    print("  → Set pixel size via Image > Properties before pressing F2.");
}

// ── Robust filename parsing for VSI-style names with multiple dashes ──────────
indicator = officialName.lastIndexOf("-");
picNum    = parseInt(officialName.substring(indicator + 1, officialName.length()));

baseName = officialName.substring(0, indicator);
baseName = replace(baseName, ",\\s*$", "");
baseName = baseName.trim();

print("Base name: [" + baseName + "]  Cell #: " + picNum);

// Run skeletonization pipeline — produces: Skeleton, Composite
run("Skeletonize And Detect Soma");

// Close the separate Skeleton window — editing is done on the Composite instead.
if (isOpen("Skeleton")) {
    selectWindow("Skeleton");
    close();
}

if (!isOpen("Composite")) {
    print("WARNING: Composite did not open — check that the skeleton was produced.");
}

// Make sure the Composite is in front with channel 1 active for editing
if (isOpen("Composite")) {
    selectWindow("Composite");
    Stack.setChannel(1);
}

// ── Instructions ──────────────────────────────────────────────────────────────

print("========================================");
print("Image: " + officialName);
print("Edit on the COMPOSITE window (red = skeleton).");
print("  Channel 1 must be active (bottom slider).");
print("  WHITE brush = draw | BLACK brush = erase");
print("----------------------------------------");
print("  Space  → re-skeletonize and refresh preview");
print("  Shift  → collect data and continue");
print("  (Close Excel before pressing Shift!)");
print("========================================");

editing = true;

// ── Edit / Preview / Finalize Loop ───────────────────────────────────────────

while (editing) {
    previewMacro  = isKeyDown("space");
    finishedMacro = isKeyDown("shift");

    // ── PREVIEW ───────────────────────────────────────────────────────────────
    if (previewMacro == true) {
        setKeyDown("none");
        zoom = getZoom() * 100;

        selectWindow("Composite");
        Stack.setChannel(1);
        run("Duplicate...", "duplicate channels=1");
        setOption("ScaleConversions", true);
        run("8-bit");
        run("Grays");
        run("Skeletonize (2D/3D)");
        rename("Skeleton_edit");

        run("Analyze Skeleton (2D/3D)", "prune=none");
        if (isOpen("Results")) { close("Results"); }
        if (isOpen("Branch information")) { close("Branch information"); }

        if (isOpen("Tagged skeleton")) {
            selectWindow(officialName);
            getDimensions(pv_w, pv_h, pv_c, pv_s, pv_f);
            if (pv_c > 1) {
                Stack.setChannel(MICROGLIA_CHANNEL);
                run("Duplicate...", "duplicate channels=" + MICROGLIA_CHANNEL);
            } else {
                run("Duplicate...", " ");
            }
            setOption("ScaleConversions", true);
            run("8-bit");
            run("Grays");
            rename("preview_source");

            close("Composite");
            close("Skeleton_edit");
            run("Merge Channels...",
                "c1=[Tagged skeleton] c2=[preview_source] create keep");
            close("Tagged skeleton");
            close("preview_source");

            selectWindow("Composite");
            Stack.setChannel(1);
            run("Set... ", "zoom=" + zoom + " x=0 y=0");
        } else {
            close("Skeleton_edit");
        }
        wait(400);
    }

    // ── FINALIZE ──────────────────────────────────────────────────────────────
    if (finishedMacro == true) {
        setKeyDown("none");
        showMessage("Reminder: Close the Excel file now if it is open, then click OK.");

        zoom = getZoom() * 100;

        // ── Extract final skeleton from Composite channel 1 ───────────────────
        selectWindow("Composite");
        Stack.setChannel(1);
        run("Duplicate...", "duplicate channels=1");
        setOption("ScaleConversions", true);
        run("8-bit");
        run("Grays");
        run("Multiply...", "value=255");
        run("Skeletonize (2D/3D)");
        rename(officialName + "(Skeleton)");

        // ── Save Composite with scale bar ─────────────────────────────────────
        if (isOpen("Composite")) {
            selectWindow("Composite");
            // Flatten to RGB so scale bar bakes in visibly across both channels
            run("Flatten");
            rename("Composite_flat");
            run("Scale Bar...",
                "width=" + SCALEBAR_WIDTH_UM +
                " height=" + SCALEBAR_HEIGHT +
                " thickness=" + SCALEBAR_HEIGHT +
                " font=" + SCALEBAR_FONT +
                " color=" + SCALEBAR_COLOR +
                " background=None location=[" + SCALEBAR_LOCATION + "] bold overlay");
            saveAs("Tiff", File.directory + officialName + "(Composite).tif");
            close();
            close("Composite");
        }

        // ── Soma re-measurement ────────────────────────────────────────────────
        selectWindow(officialName);
        getDimensions(sf_w, sf_h, sf_c, sf_s, sf_f);
        if (sf_c > 1) {
            Stack.setChannel(MICROGLIA_CHANNEL);
            run("Duplicate...", "duplicate channels=" + MICROGLIA_CHANNEL);
        } else {
            run("Duplicate...", " ");
        }
        setOption("ScaleConversions", true);
        run("8-bit");
        rename("soma_final");

        run("Gaussian Blur...", "sigma=" + SOMA_BLUR_RADIUS);

        getStatistics(sf_area, sf_mean, sf_min, sf_max, sf_std, sf_hist);
        sf_targetPx   = sf_area * (SOMA_TOP_PERCENT / 100.0);
        sf_cumulative = 0;
        sf_threshLow  = sf_max;
        for (i = 255; i >= 0; i--) {
            sf_cumulative += sf_hist[i];
            if (sf_cumulative >= sf_targetPx) {
                sf_threshLow = i;
                i = -1;
            }
        }
        setThreshold(sf_threshLow, 255);
        setOption("BlackBackground", true);
        run("Convert to Mask");
        run("Fill Holes");
        for (e = 0; e < SOMA_ERODE_PASSES; e++) { run("Erode"); }

        // Measure in calibrated units if available — include shape descriptors
        run("Set Measurements...", "area shape fit redirect=None decimal=4");
        run("Analyze Particles...",
            "size=" + SOMA_MIN_AREA + "-" + SOMA_MAX_AREA +
            " circularity=" + SOMA_CIRCULARITY_MIN + "-1.00 show=Nothing display exclude clear");

        somaArea_raw   = 0;
        somaCirc_raw   = 0;
        somaAR_raw     = 1;
        somaSolid_raw  = 1;
        somaBestRow    = -1;
        if (nResults > 0) {
            for (r = 0; r < nResults; r++) {
                a = getResult("Area", r);
                if (a > somaArea_raw) {
                    somaArea_raw  = a;
                    somaBestRow   = r;
                }
            }
            if (somaBestRow >= 0) {
                somaCirc_raw  = getResult("Circ.",    somaBestRow);
                somaAR_raw    = getResult("AR",        somaBestRow);
                somaSolid_raw = getResult("Solidity",  somaBestRow);
            }
        }
        close("soma_final");
        close("Results");

        // Convert soma area to µm² (Analyze Particles already returns calibrated
        // area when the image is calibrated, so multiply only when falling back)
        if (calibrated) {
            somaArea_um2  = somaArea_raw;   // already in µm² from Analyze Particles
        } else {
            somaArea_um2  = somaArea_raw;   // in px² — column header will say px²
        }
        // Shape descriptors are dimensionless — no unit conversion needed
        somaCirc   = somaCirc_raw;
        somaAR     = somaAR_raw;
        somaSolid  = somaSolid_raw;

        // ── Skeleton analysis ──────────────────────────────────────────────────
        selectWindow(officialName + "(Skeleton)");
        run("Analyze Skeleton (2D/3D)", "prune=none show");

        // ── Save Tagged skeleton with scale bar ───────────────────────────────
        if (isOpen("Tagged skeleton")) {
            selectWindow("Tagged skeleton");
            run("Scale Bar...",
                "width=" + SCALEBAR_WIDTH_UM +
                " height=" + SCALEBAR_HEIGHT +
                " thickness=" + SCALEBAR_HEIGHT +
                " font=" + SCALEBAR_FONT +
                " color=" + SCALEBAR_COLOR +
                " background=None location=[" + SCALEBAR_LOCATION + "] bold overlay");
            saveAs("Tiff", File.directory + officialName + "(Tagged-Skeleton).tif");
            close();
        }

        if (isOpen("Tagged Skeleton"))        { close("Tagged Skeleton"); }
        if (isOpen("Longest shortest paths")) { close("Longest shortest paths"); }

        // ── Aggregate summary stats from Results table (per skeleton component) ─
        numBranches  = 0;
        numJunctions = 0;
        numEndpoints = 0;
        numTriple    = 0;
        numQuad      = 0;
        maxBranchLen_raw = 0;

        if (isOpen("Results")) {
            selectWindow("Results");
            nSkels = nResults;
            for (r = 0; r < nSkels; r++) {
                numBranches  += getResult("# Branches", r);
                numJunctions += getResult("# Junctions", r);
                numEndpoints += getResult("# End-point voxels", r);
                numTriple    += getResult("# Triple points", r);
                numQuad      += getResult("# Quadruple points", r);
                mb = getResult("Maximum Branch Length", r);
                if (mb > maxBranchLen_raw) maxBranchLen_raw = mb;
            }
            close("Results");
        }

        // ── Collect per-branch data from Branch information table ─────────────
        // Build arrays then write to Detailed sheet.
        // Columns available: Skeleton ID | Branch length | V1 x | V1 y |
        //                    V2 x | V2 y | Euclidean distance | running average |
        //                    branch type
        totalBranchLen_raw = 0;

        branchCount_detail = 0;
        branchSkelID       = newArray(0);
        branchLen_arr      = newArray(0);
        branchV1x          = newArray(0);
        branchV1y          = newArray(0);
        branchV2x          = newArray(0);
        branchV2y          = newArray(0);
        branchEuclid       = newArray(0);
        branchRunAvg       = newArray(0);
        branchType         = newArray(0);

        if (isOpen("Branch information")) {
            selectWindow("Branch information");
            nBI = Table.size;
            branchCount_detail = nBI;

            branchSkelID = newArray(nBI);
            branchLen_arr = newArray(nBI);
            branchV1x     = newArray(nBI);
            branchV1y     = newArray(nBI);
            branchV2x     = newArray(nBI);
            branchV2y     = newArray(nBI);
            branchEuclid  = newArray(nBI);
            branchRunAvg  = newArray(nBI);
            branchType    = newArray(nBI);

            for (r = 0; r < nBI; r++) {
                branchSkelID[r] = Table.get("Skeleton ID",          r);
                bl              = Table.get("Branch length",         r);
                branchLen_arr[r] = bl * px2um;                        // → µm
                totalBranchLen_raw += bl;
                branchV1x[r]    = Table.get("V1 x",                 r) * px2um;
                branchV1y[r]    = Table.get("V1 y",                 r) * px2um;
                branchV2x[r]    = Table.get("V2 x",                 r) * px2um;
                branchV2y[r]    = Table.get("V2 y",                 r) * px2um;
                branchEuclid[r] = Table.get("Euclidean distance",   r) * px2um;
                branchRunAvg[r] = Table.get("running average length",r) * px2um;
                branchType[r]   = Table.get("branch type",          r);
            }
            close("Branch information");
        }

        // ── Branch length filter ───────────────────────────────────────────────
        // Drop branches shorter than MIN_BRANCH_LENGTH_UM from all reported
        // statistics. Each removed terminal branch (branch type 1 = slab-end)
        // also removes one endpoint, so Num_Endpoints is decremented for those.
        // Junction/triple/quad point counts are topology-derived and left as-is.
        removedBranches  = 0;
        removedEndpoints = 0;

        if (MIN_BRANCH_LENGTH_UM > 0 && branchCount_detail > 0) {
            // Build filtered arrays
            kept_SkelID   = newArray(branchCount_detail);
            kept_Len      = newArray(branchCount_detail);
            kept_V1x      = newArray(branchCount_detail);
            kept_V1y      = newArray(branchCount_detail);
            kept_V2x      = newArray(branchCount_detail);
            kept_V2y      = newArray(branchCount_detail);
            kept_Euclid   = newArray(branchCount_detail);
            kept_RunAvg   = newArray(branchCount_detail);
            kept_Type     = newArray(branchCount_detail);
            keptCount     = 0;

            for (r = 0; r < branchCount_detail; r++) {
                if (branchLen_arr[r] >= MIN_BRANCH_LENGTH_UM) {
                    kept_SkelID[keptCount]  = branchSkelID[r];
                    kept_Len[keptCount]     = branchLen_arr[r];
                    kept_V1x[keptCount]     = branchV1x[r];
                    kept_V1y[keptCount]     = branchV1y[r];
                    kept_V2x[keptCount]     = branchV2x[r];
                    kept_V2y[keptCount]     = branchV2y[r];
                    kept_Euclid[keptCount]  = branchEuclid[r];
                    kept_RunAvg[keptCount]  = branchRunAvg[r];
                    kept_Type[keptCount]    = branchType[r];
                    keptCount++;
                } else {
                    removedBranches++;
                    // Branch type 1 = slab-end (terminal branch with one free endpoint).
                    // Each removed terminal branch loses one endpoint from the count.
                    if (branchType[r] == 1) { removedEndpoints++; }
                }
            }

            // Replace working arrays with filtered versions
            branchCount_detail = keptCount;
            branchSkelID  = Array.slice(kept_SkelID,  0, keptCount);
            branchLen_arr = Array.slice(kept_Len,     0, keptCount);
            branchV1x     = Array.slice(kept_V1x,     0, keptCount);
            branchV1y     = Array.slice(kept_V1y,     0, keptCount);
            branchV2x     = Array.slice(kept_V2x,     0, keptCount);
            branchV2y     = Array.slice(kept_V2y,     0, keptCount);
            branchEuclid  = Array.slice(kept_Euclid,  0, keptCount);
            branchRunAvg  = Array.slice(kept_RunAvg,  0, keptCount);
            branchType    = Array.slice(kept_Type,    0, keptCount);

            if (removedBranches > 0) {
                print("Branch filter (" + MIN_BRANCH_LENGTH_UM + " µm threshold): " +
                      removedBranches + " branch(es) removed, " +
                      removedEndpoints + " endpoint(s) removed.");
            }
        }

        // Recompute summary stats directly from filtered branch arrays.
        // branchLen_arr values are already in µm (multiplied by px2um when read),
        // so sum and compare directly — no px round-trip needed.
        numBranches_filtered = branchCount_detail;
        totalBranchLen_um    = 0;
        maxBranchLen_um      = 0;
        for (r = 0; r < branchCount_detail; r++) {
            totalBranchLen_um += branchLen_arr[r];
            if (branchLen_arr[r] > maxBranchLen_um) {
                maxBranchLen_um = branchLen_arr[r];
            }
        }
        numBranches  = numBranches_filtered;
        numEndpoints = numEndpoints - removedEndpoints;
        if (numEndpoints < 0) { numEndpoints = 0; }

        if (numBranches > 0) { avgBranchLen_um = totalBranchLen_um / numBranches; }
        else                  { avgBranchLen_um = 0; }

        // ── Derived morphology metrics ─────────────────────────────────────────
        // These are the key LPS-vs-PBS discriminators.

        // Ramification Index: total process length normalised to soma size.
        // Resting (PBS) cells are highly ramified → high value.
        // Activated (LPS) cells retract processes → low value.
        if (somaArea_um2 > 0) {
            ramificationIndex = totalBranchLen_um / somaArea_um2;
        } else { ramificationIndex = 0; }

        // Junction Density: branching complexity per unit length.
        // Ramified cells have many branch points relative to their total length.
        if (totalBranchLen_um > 0) {
            junctionDensity  = numJunctions  / totalBranchLen_um;
            endpointDensity  = numEndpoints  / totalBranchLen_um;
        } else {
            junctionDensity  = 0;
            endpointDensity  = 0;
        }

        // Average Span Ratio: mean(Euclidean_distance / Branch_length) across branches.
        // 1 = perfectly straight; < 1 = tortuous/curving.
        // LPS cells retain fewer, straighter stub processes → higher span ratio.
        spanRatioSum = 0;
        spanRatioN   = 0;
        for (r = 0; r < branchCount_detail; r++) {
            if (branchLen_arr[r] > 0) {
                spanRatioSum += (branchEuclid[r] / branchLen_arr[r]);
                spanRatioN++;
            }
        }
        if (spanRatioN > 0) { avgSpanRatio = spanRatioSum / spanRatioN; }
        else                 { avgSpanRatio = 0; }

        // Branch Density: number of branches per unit soma area.
        if (somaArea_um2 > 0) {
            branchDensity = numBranches / somaArea_um2;
        } else { branchDensity = 0; }

        // Complexity Index: compound measure combining branching and length vs soma.
        // (Num_Endpoints × Total_Length) / Soma_Area — drops sharply with LPS activation.
        if (somaArea_um2 > 0) {
            complexityIndex = (numEndpoints * totalBranchLen_um) / somaArea_um2;
        } else { complexityIndex = 0; }

        // ── Console log ───────────────────────────────────────────────────────
        print("----------------------------------------");
        print("Cell " + picNum + " summary (branches >= " + MIN_BRANCH_LENGTH_UM + " µm):");
        print("  Soma area:          " + somaArea_um2    + " " + unitLabel + "²");
        print("  Soma circularity:   " + somaCirc);
        print("  Soma aspect ratio:  " + somaAR);
        print("  Soma solidity:      " + somaSolid);
        print("  Branches:           " + numBranches);
        print("  Total length:       " + totalBranchLen_um + " " + unitLabel);
        print("  Avg branch len:     " + avgBranchLen_um   + " " + unitLabel);
        print("  Max branch len:     " + maxBranchLen_um   + " " + unitLabel);
        print("  Junctions:          " + numJunctions);
        print("  Endpoints:          " + numEndpoints);
        print("  Triple points:      " + numTriple);
        print("  Quadruple points:   " + numQuad);
        print("  Ramification index: " + ramificationIndex);
        print("  Junction density:   " + junctionDensity);
        print("  Endpoint density:   " + endpointDensity);
        print("  Avg span ratio:     " + avgSpanRatio);
        print("  Branch density:     " + branchDensity);
        print("  Complexity index:   " + complexityIndex);

        // ── Write Summary sheet (one row per cell) ────────────────────────────
        if (isOpen("Results")) { close("Results"); }

        if (calibrated) {
            setResult("Cell_ID",                   0, picNum);
            setResult("Soma_Area_um2",             0, somaArea_um2);
            setResult("Soma_Circularity",          0, somaCirc);
            setResult("Soma_AR",                   0, somaAR);
            setResult("Soma_Solidity",             0, somaSolid);
            setResult("Num_Branches",              0, numBranches);
            setResult("Total_Branch_Length_um",    0, totalBranchLen_um);
            setResult("Avg_Branch_Length_um",      0, avgBranchLen_um);
            setResult("Max_Branch_Length_um",      0, maxBranchLen_um);
            setResult("Num_Junctions",             0, numJunctions);
            setResult("Num_Endpoints",             0, numEndpoints);
            setResult("Num_Triple_Points",         0, numTriple);
            setResult("Num_Quadruple_Points",      0, numQuad);
            setResult("Ramification_Index",        0, ramificationIndex);
            setResult("Junction_Density",          0, junctionDensity);
            setResult("Endpoint_Density",          0, endpointDensity);
            setResult("Avg_Span_Ratio",            0, avgSpanRatio);
            setResult("Branch_Density",            0, branchDensity);
            setResult("Complexity_Index",          0, complexityIndex);
        } else {
            // Uncalibrated: keep px labels so the reader knows the unit
            setResult("Cell_ID",                   0, picNum);
            setResult("Soma_Area_px2",             0, somaArea_um2);
            setResult("Soma_Circularity",          0, somaCirc);
            setResult("Soma_AR",                   0, somaAR);
            setResult("Soma_Solidity",             0, somaSolid);
            setResult("Num_Branches",              0, numBranches);
            setResult("Total_Branch_Length_px",    0, totalBranchLen_um);
            setResult("Avg_Branch_Length_px",      0, avgBranchLen_um);
            setResult("Max_Branch_Length_px",      0, maxBranchLen_um);
            setResult("Num_Junctions",             0, numJunctions);
            setResult("Num_Endpoints",             0, numEndpoints);
            setResult("Num_Triple_Points",         0, numTriple);
            setResult("Num_Quadruple_Points",      0, numQuad);
            setResult("Ramification_Index",        0, ramificationIndex);
            setResult("Junction_Density",          0, junctionDensity);
            setResult("Endpoint_Density",          0, endpointDensity);
            setResult("Avg_Span_Ratio",            0, avgSpanRatio);
            setResult("Branch_Density",            0, branchDensity);
            setResult("Complexity_Index",          0, complexityIndex);
        }
        updateResults();
        selectWindow("Results");

        pathway = File.directory + baseName + "-Data.xlsx";
        run("Read and Write Excel",
            "no_count_column file=[" + pathway + "] " +
            "sheet=[Summary] " +
            "dataset_label=[]");
        close("Results");
        print("Excel summary written: " + pathway);

        // ── Write Detailed sheet (one row per branch) ─────────────────────────
        if (branchCount_detail > 0) {
            if (isOpen("Results")) { close("Results"); }

            for (r = 0; r < branchCount_detail; r++) {
                setResult("Cell_ID",                  r, picNum);
                setResult("Skeleton_ID",              r, branchSkelID[r]);
                if (calibrated) {
                    setResult("Branch_Length_um",         r, branchLen_arr[r]);
                    setResult("V1x_um",                   r, branchV1x[r]);
                    setResult("V1y_um",                   r, branchV1y[r]);
                    setResult("V2x_um",                   r, branchV2x[r]);
                    setResult("V2y_um",                   r, branchV2y[r]);
                    setResult("Euclidean_Distance_um",    r, branchEuclid[r]);
                    setResult("Running_Avg_Length_um",    r, branchRunAvg[r]);
                } else {
                    setResult("Branch_Length_px",         r, branchLen_arr[r]);
                    setResult("V1x_px",                   r, branchV1x[r]);
                    setResult("V1y_px",                   r, branchV1y[r]);
                    setResult("V2x_px",                   r, branchV2x[r]);
                    setResult("V2y_px",                   r, branchV2y[r]);
                    setResult("Euclidean_Distance_px",    r, branchEuclid[r]);
                    setResult("Running_Avg_Length_px",    r, branchRunAvg[r]);
                }
                setResult("Branch_Type",              r, branchType[r]);
            }
            updateResults();
            selectWindow("Results");

            run("Read and Write Excel",
                "no_count_column file=[" + pathway + "] " +
                "sheet=[Detailed] " +
                "dataset_label=[]");
            close("Results");
            print("Excel detailed written: " + pathway + "  (" + branchCount_detail + " branches)");
        } else {
            print("No branch data to write to Detailed sheet.");
        }

        // ── Save skeleton with scale bar ──────────────────────────────────────
        selectWindow(officialName + "(Skeleton)");
        run("Scale Bar...",
            "width=" + SCALEBAR_WIDTH_UM +
            " height=" + SCALEBAR_HEIGHT +
            " thickness=" + SCALEBAR_HEIGHT +
            " font=" + SCALEBAR_FONT +
            " color=" + SCALEBAR_COLOR +
            " background=None location=[" + SCALEBAR_LOCATION + "] bold overlay");
        saveAs("Tiff", File.directory + officialName + "(Skeleton).tif");
        close();

        // ── Advance to next image or finish ───────────────────────────────────
        nextImg = File.directory + baseName + "-" + (picNum + 1) + ".tif";

        if (File.exists(nextImg)) {
            while (nImages > 0) { selectImage(nImages); close(); }
            open(nextImg);
            picNum++;

            waitForUser("Next image loaded: " + baseName + "-" + picNum +
                        "\n\nMake any brightness/contrast adjustments if needed," +
                        "\nthen click OK to skeletonize.");

            officialName = getTitle();
            officialName = officialName.substring(0, officialName.length() - 4);
            rename(officialName);
            indicator = officialName.lastIndexOf("-");
            picNum    = parseInt(officialName.substring(indicator + 1, officialName.length()));
            baseName  = officialName.substring(0, indicator);
            baseName  = replace(baseName, ",\\s*$", "");
            baseName  = baseName.trim();

            // Re-read calibration from new image
            getVoxelSize(pixW, pixH, pixD, pixUnit);
            if (pixUnit == "microns" || pixUnit == "µm" || pixUnit == "um") {
                calibrated = true;
                px2um      = pixW;
                px2um2     = pixW * pixH;
                unitLabel  = "um";
            } else {
                calibrated = false;
                px2um      = 1;
                px2um2     = 1;
                unitLabel  = "px";
            }

            run("Skeletonize And Detect Soma");

            if (isOpen("Skeleton")) {
                selectWindow("Skeleton");
                close();
            }
            if (isOpen("Composite")) {
                selectWindow("Composite");
                Stack.setChannel(1);
            }

            print("========================================");
            print("Image: " + officialName);
            print("  Space → refresh preview | Shift → collect data");
            print("========================================");

        } else {
            while (nImages > 0) { selectImage(nImages); close(); }
            editing = false;
            print("========================================");
            print("All images processed. Pipeline complete.");
            print("========================================");
            wait(500);
            close("Log");
            break;
        }
    }
}
