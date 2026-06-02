/*
================================================================================
  Skeletonize_And_Detect_Soma.ijm
  Called internally by Edit_Finalize.ijm — do not run directly.
================================================================================
  Pipeline:
    1. Detect soma using a high percentile threshold — bright core only
    2. Mask soma out so it doesn't corrupt the skeleton
    3. Contrast-stretch the process image, threshold, skeletonize
    4. Produce a composite overlay for review
================================================================================
*/

// ── Tunable Parameters ───────────────────────────────────────────────────────

// --- Soma detection ---
// Soma is detected by thresholding only the TOP brightest pixels.
// SOMA_TOP_PERCENT = what fraction of the brightest pixels to keep (0–100).
// Lower = stricter / smaller soma mask. Start at 5, raise to 8 if soma missed.
SOMA_TOP_PERCENT = 5;

// Hard floor on the soma threshold intensity (0–255).
// The percentile threshold is clamped to this minimum so dim images
// cannot accidentally qualify faint debris as soma.
// Lower if the real soma is missed; raise if bright junk still gets through.
SOMA_ABS_MIN_INTENSITY = 175;

// Gaussian blur before soma thresholding — smooths the bright core into one blob.
SOMA_BLUR_RADIUS = 2;

// Pixels to erode the soma mask inward after detection.
// Trims away from process roots. 1 is usually right; set 0 if soma disappears.
SOMA_ERODE_PASSES = 1;

// Minimum soma area (px²).
SOMA_MIN_AREA = 80;

// Maximum soma area (px²). Set to ~2–3× your typical soma area.
SOMA_MAX_AREA = 4000;

// Circularity floor for soma — keeps only roundish blobs.
// 0.62 excludes elongated debris/process roots while accepting real soma.
// Lower toward 0.45 if the soma is irregularly shaped and being missed.
SOMA_CIRCULARITY_MIN = 0.62;

// --- Process skeletonization ---
// Contrast stretch saturation % before thresholding.
// Lower = more aggressive (lifts dim distal tips). 0.05 is very aggressive.
CONTRAST_SATURATE = 0.05;

// Threshold method for processes.
// "Li" captures thin dim structures well. Try "Otsu" if too much noise appears.
PROCESS_THRESHOLD_METHOD = "Li";

// Fixed threshold value to use instead of auto-threshold.
// Set to 0 to use auto (PROCESS_THRESHOLD_METHOD).
// Lower = more branches captured. Raise if too much background noise appears.
PROCESS_FIXED_THRESHOLD = 32;

// Gaussian blur before thresholding. Keep very low (0–0.5) for small images.
PROCESS_BLUR_SIGMA = 0;

// NO Close/Despeckle/Dilate/Erode — these fatten thin processes into blobs
// and cause the skeleton to trace loops instead of lines. Skeletonize directly
// from the thresholded mask. Use the brush tool in edit mode to fix gaps manually.
// Exception: 1 despeckle pass removes isolated noise pixels from the low threshold
// without fattening real processes (despeckle only removes fully isolated pixels).
PROCESS_DESPECKLE_PASSES = 1;

// Channel: 1=FITC, 2=TRITC, 3=CY5
MICROGLIA_CHANNEL = 1;

// ── End of Tunable Parameters ─────────────────────────────────────────────────

sourceName = getTitle();
zoom = getZoom() * 100;

// ── STEP 0: Normalise to 8-bit grayscale ─────────────────────────────────────
getDimensions(sw, sh, sc, ss, sf);
Stack.getDimensions(sw, sh, sc, ss, sf);

print("----------------------------------------");
print("Image: " + sourceName);
print("Dimensions: " + sw + " x " + sh + " px  |  Channels: " + sc);

if (sc > 1) {
    Stack.setChannel(MICROGLIA_CHANNEL);
    run("Duplicate...", "duplicate channels=" + MICROGLIA_CHANNEL);
    rename("work");
} else {
    run("Duplicate...", " ");
    rename("work");
}
selectWindow("work");
setOption("ScaleConversions", true);
run("8-bit");
run("Grays");

// ── STEP 1: Soma Detection ────────────────────────────────────────────────────
// Strategy: threshold only the top N% brightest pixels — this isolates the
// bright soma core without pulling in dim process roots.

run("Duplicate...", " ");
rename("soma_detect");
selectWindow("soma_detect");
run("Gaussian Blur...", "sigma=" + SOMA_BLUR_RADIUS);

// Find the intensity value at the (100 - SOMA_TOP_PERCENT) percentile
getStatistics(imgArea, mean, imgMin, imgMax, std, histogram);
totalPx  = imgArea;
targetPx = totalPx * (SOMA_TOP_PERCENT / 100.0);
cumulative = 0;
somaThreshLow = imgMax;
for (i = 255; i >= 0; i--) {
    cumulative += histogram[i];
    if (cumulative >= targetPx) {
        somaThreshLow = i;
        i = -1; // break
    }
}
// Clamp: never let the threshold drop below the absolute minimum.
// This prevents dim images from qualifying faint debris as soma.
if (somaThreshLow < SOMA_ABS_MIN_INTENSITY) {
    print("Soma threshold clamped: percentile gave " + somaThreshLow +
          ", raised to SOMA_ABS_MIN_INTENSITY=" + SOMA_ABS_MIN_INTENSITY);
    somaThreshLow = SOMA_ABS_MIN_INTENSITY;
}
print("Soma threshold: " + somaThreshLow + " – 255" +
      "  (top " + SOMA_TOP_PERCENT + "% brightest pixels)");
setThreshold(somaThreshLow, 255);
setOption("BlackBackground", true);
run("Convert to Mask");
run("Fill Holes");

run("Set Measurements...", "area centroid shape redirect=None decimal=3");
run("Analyze Particles...",
    "size=" + SOMA_MIN_AREA + "-" + SOMA_MAX_AREA +
    " circularity=" + SOMA_CIRCULARITY_MIN + "-1.00 show=Masks display exclude clear");

somaArea  = 0;
somaCount = nResults;
largestIdx = -1;

if (somaCount > 0) {
    // Always keep only the single largest candidate — there is exactly one soma
    // per image. Discarding smaller blobs eliminates bright debris that passed
    // the circularity/size filters.
    for (r = 0; r < nResults; r++) {
        a = getResult("Area", r);
        if (a > somaArea) { somaArea = a; largestIdx = r; }
    }
    if (somaCount > 1) {
        print("Soma: " + somaCount + " candidate(s) found — keeping largest only (" +
              somaArea + " px²). Discarding " + (somaCount - 1) + " smaller blob(s).");
    } else {
        print("Soma detected — Area: " + somaArea + " px²");
    }
} else {
    somaArea = 0;
    print("WARNING: No soma detected.");
    print("  → Try raising SOMA_TOP_PERCENT (currently " + SOMA_TOP_PERCENT + ")");
    print("  → Try lowering SOMA_CIRCULARITY_MIN (currently " + SOMA_CIRCULARITY_MIN + ")");
    print("  → Try lowering SOMA_ABS_MIN_INTENSITY (currently " + SOMA_ABS_MIN_INTENSITY + ")");
}

// Rebuild the particle mask keeping only the largest blob.
// Analyze Particles with "show=Masks" already produced "Mask of soma_detect";
// if there were multiple candidates we need to blank all but the largest one.
selectWindow("soma_detect");
close();

somasMaskName = "Mask of soma_detect";
if (isOpen(somasMaskName)) {
    selectWindow(somasMaskName);
    rename("soma_mask");

    // If more than one candidate was found, keep only the largest ROI.
    if (somaCount > 1 && largestIdx >= 0) {
        // Re-run Analyze Particles into the ROI manager to get individual ROIs.
        selectWindow("soma_mask");
        run("Duplicate...", " ");
        rename("soma_mask_tmp");
        roiManager("reset");
        run("Analyze Particles...",
            "size=" + SOMA_MIN_AREA + "-" + SOMA_MAX_AREA +
            " circularity=" + SOMA_CIRCULARITY_MIN + "-1.00 add exclude clear");
        // Blank the mask, then fill only the largest ROI back in.
        selectWindow("soma_mask");
        run("Select All");
        setForegroundColor(0, 0, 0);
        fill();
        run("Select None");
        if (roiManager("count") > largestIdx) {
            roiManager("select", largestIdx);
            setForegroundColor(255, 255, 255);
            fill();
            run("Select None");
        }
        roiManager("reset");
        close("soma_mask_tmp");
    }
} else {
    selectWindow("work");
    run("Duplicate...", " ");
    run("Multiply...", "value=0");
    rename("soma_mask");
    print("WARNING: Soma mask creation failed — using blank mask.");
}

selectWindow("soma_mask");
for (e = 0; e < SOMA_ERODE_PASSES; e++) { run("Erode"); }

close("Results");

// ── STEP 2: Isolate Processes ─────────────────────────────────────────────────
selectWindow("work");
run("Duplicate...", " ");
rename("processes");

imageCalculator("Subtract create", "processes", "soma_mask");
selectWindow("Result of processes");
rename("processes_no_soma");
close("processes");

// Contrast-stretch to lift dim distal processes
selectWindow("processes_no_soma");
run("Enhance Contrast", "saturated=" + CONTRAST_SATURATE);
run("Apply LUT");
print("Contrast stretch: saturated=" + CONTRAST_SATURATE + "%");

if (PROCESS_BLUR_SIGMA > 0) {
    run("Gaussian Blur...", "sigma=" + PROCESS_BLUR_SIGMA);
}

// Threshold
if (PROCESS_FIXED_THRESHOLD > 0) {
    setThreshold(PROCESS_FIXED_THRESHOLD, 255);
    print("Process threshold: fixed=" + PROCESS_FIXED_THRESHOLD);
} else {
    setAutoThreshold(PROCESS_THRESHOLD_METHOD + " dark no-reset");
    getThreshold(pLow, pHigh);
    print("Process threshold: " + pLow + " – " + pHigh +
          "  (method: " + PROCESS_THRESHOLD_METHOD + ")");
    if (pLow < 0 || (pLow == 0 && pHigh == 255)) {
        print("WARNING: threshold degenerate — try PROCESS_FIXED_THRESHOLD=30");
    }
}
setOption("BlackBackground", true);
run("Convert to Mask");
for (d = 0; d < PROCESS_DESPECKLE_PASSES; d++) { run("Despeckle"); }

// ── STEP 3: Skeletonize ───────────────────────────────────────────────────────
// Single skeletonize — no prune step. At small image sizes (< 200px),
// "shortest branch" pruning removes real fine process tips, not just noise.
// Manual cleanup with the brush tool is more reliable for this image size.
run("Skeletonize (2D/3D)");
rename("Skeleton");

// ── STEP 4: Composite Preview ─────────────────────────────────────────────────
run("Analyze Skeleton (2D/3D)", "prune=none");
close("Results");

if (isOpen("Tagged skeleton")) {
    selectWindow(sourceName);
    getDimensions(sw2, sh2, sc2, ss2, sf2);
    if (sc2 > 1) {
        Stack.setChannel(MICROGLIA_CHANNEL);
        run("Duplicate...", "duplicate channels=" + MICROGLIA_CHANNEL);
    } else {
        run("Duplicate...", " ");
    }
    setOption("ScaleConversions", true);
    run("8-bit");
    run("Grays");
    rename("source_8bit");

    run("Merge Channels...",
        "c1=[Tagged skeleton] c2=[source_8bit] create keep");
    close("Tagged skeleton");
    close("source_8bit");
    if (isOpen("Composite")) {
        selectWindow("Composite");
        run("Set... ", "zoom=" + zoom + " x=0 y=0");
    }
}

selectWindow(sourceName);
run("Set... ", "zoom=" + zoom + " x=0 y=0");
selectWindow("Skeleton");
run("Set... ", "zoom=" + zoom + " x=0 y=0");

close("soma_mask");
close("processes_no_soma");
close("work");
