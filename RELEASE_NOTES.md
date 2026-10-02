# Key Layout Manager 1.1

Move more of your Premiere setup between Macs, with safer backups and restores.

## What’s new

- **Transfer panel layouts.** Browse saved Premiere workspaces alongside keyboard layouts and source assignment presets, then drag, export, or restore them to another profile or Mac.
- **A fresh app icon.** Key Layout Manager has a new look that is easier to spot in your Dock and Applications folder.

## Improvements

- Backups preserve an existing ZIP if creating its replacement fails.
- Restoring or exporting a file onto itself no longer risks deleting the original.
- Failed and skipped restore items remain in the list so you can try again.
- Large backups load more reliably, and dragged files with matching names are staged separately.
- ZIP restores reject unsafe paths and symbolic links, and correctly handle filenames containing brackets or other pattern characters.
- Update checking can fall back to the backup feed if the main feed is unavailable.

## Using panel layouts

Save your arrangement in Premiere with **Window > Workspaces > Save as New Workspace** before exporting. Quit Premiere before restoring, then relaunch and choose the workspace from **Window > Workspaces**. Check the layout on the receiving Mac, especially if its Premiere version or monitor arrangement differs.

## Download and install

Download **KeyLayoutManager_1-1-0.zip**, unzip it, and move **KeyLayoutManager.app** to Applications. Existing users can choose **Check for Updates…** in the app menu.

Requires **macOS 14 or later** and an **Apple silicon Mac**. The app is Developer ID signed and notarized by Apple.
