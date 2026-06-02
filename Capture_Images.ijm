/*
================================================================================
  Capture_Images.ijm
  Triggered by: F1
================================================================================
  Lets you draw rectangles around individual microglia cells on a base image,
  saving each crop as a numbered .tif. Also saves a labeled overview and the
  original base image into an organized folder.

  Controls:
    Space  →  Capture the current rectangle selection
    Shift  →  Finish capturing and close

  Output files saved to: <chosen directory>/<imageName>-Images/
    <name>-1.tif, <name>-2.tif, ...  (individual cell crops, with scale bar)
    <name>-Labeled.tif               (overview with numbered annotations + scale bar)
    <name>-Base.tif                  (original image)
================================================================================
*/

setTool("rectangle");

// Derive a clean base name from the open image title (strip extension)
officialName = getTitle();
officialName = officialName.substring(0, officialName.length() - 4);

// Duplicate base image and create a labeled RGB copy for annotations
run("Duplicate...", " ");
rename(officialName + "-Labeled");
location = getDirectory("Select a directory to save the captured images");
folder = location + officialName + "-Images";
File.makeDirectory(folder);
run("RGB Color");

// ── Capture loop ─────────────────────────────────────────────────────────────
num   = 1;
stop  = false;

print("========================================");
print("Draw a rectangle around each cell.");
print("  Space  → capture selection");
print("  Shift  → finish and save");
print("========================================");

while (!stop) {
    interruptMacro = isKeyDown("shift");
    captureMacro   = isKeyDown("space");

    // CAPTURE: save the selected crop and annotate the labeled image
    if (captureMacro == true) {
        setBatchMode("hide");
        getSelectionBounds(x, y, w, h);

        run("Duplicate...", " ");

        // ── Add scale bar to each crop ────────────────────────────────────────
        // Uses image calibration (microns) when available; falls back to pixels.
        getVoxelSize(vw, vh, vd, vunit);
        if (vunit == "microns" || vunit == "µm" || vunit == "um") {
            scaleUnit = "micron";
        } else {
            scaleUnit = vunit;
        }
        // Scale bar = ~20% of image width, snapped to a round micron value
        run("Scale Bar...",
            "width=10 height=4 thickness=4 font=14 color=White background=None " +
            "location=[Lower Right] bold overlay");

        saveAs("Tiff", folder + "/" + officialName + "-" + num + ".tif");
        close();

        setBatchMode("exit and display");
        print("Captured: " + officialName + "-" + num);

        // Draw rectangle outline + label number onto the Labeled image
        setFont("SansSerif", 28, "antialiased");
        setColor("red");
        drawRect(x, y, w, h);
        drawString("" + num, x + (2 * w / 5), y + (3 * h / 4));

        setKeyDown("none");
        num++;
        wait(400);
    }

    // STOP: add scale bar to labeled overview, save both overview images and exit
    if (interruptMacro == true) {
        setKeyDown("none");

        // Scale bar on labeled overview
        run("Scale Bar...",
            "width=10 height=4 thickness=4 font=14 color=White background=None " +
            "location=[Lower Right] bold overlay");

        saveAs("Tiff", folder + "/" + officialName + "-Labeled.tif");
        close();
        saveAs("Tiff", folder + "/" + officialName + "-Base.tif");
        close();

        print("Done — " + (num - 1) + " cell(s) captured.");
        stop = true;
        wait(1000);
        close("Log");
        break;
    }
}

showMessage(
    "Capture complete!\n" +
    (num - 1) + " cell image(s) saved.\n\n" +
    "Open each cell image and press [F2] to begin skeletonization.\n\n" +
    "Files saved to:\n" + folder
);
