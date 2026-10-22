# Brutefist Addons

Source history for BrutefistCompanion 0.4.2, BrutefistGear 0.6.1 and BrutefistProfessions 0.1.0, imported from the installed beta client on October 21, 2026. Professions 0.2.0 was referenced in a previous chat but is not present in this import.

## Update the game

After publishing this repository as `Brigga72/BrutefistAddons` (public), double-click `Update Addons.cmd`, wait for success, then type `/reload` in game. The updater fetches main and copies only folders under addons/. It backs up existing addon folders under backups/ before overwriting. It does not modify WTF or saved settings. It retains untracked files in installed addon folders; a release removing source files may require a clean installation. A client restart may be needed for changes the game cannot reload.

To deploy the local checkout instead: `powershell -NoProfile -File .\Update-Addons.ps1 -Local`. Add `-Preview` to list destinations without writing to the game.

## Launch transition

Edit config.json: set activeProfile to forever and verify the forever folder. The supplied future path is `_forever_\addon`; verify that the launched game actually uses this folder before installing. Nonexistent destinations are rejected. Use `-Profile beta` or `-Profile forever` for a single run.

## Add or change an addon

Put each owned addon in addons/FolderName/ with FolderName.toc directly inside. Commit and push tested changes to main. The updater will discover these folders. Keep third-party addons in their existing manager unless you have arranged a separate update source; copying them here does not track their authors' updates.

## Restore

Close the game. Copy a backed-up addon folder from backups/TIMESTAMP/ over its installed folder. For an exact restore after files were added, first move the installed addon folder aside. Preserve the backup until verified.

## Publishing

Create an empty public GitHub repository named BrutefistAddons under Brigga72 (do not initialize README). This folder already has a local main branch and baseline commit. Push with `git push -u origin main`. Private repositories need authenticated download support before the updater can use them; this updater uses public downloads without embedded credentials.
