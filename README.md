# eBook Tools

This is a collection of bash shell scripts for automated and semi-automated organization and management of large ebook collections. It contains the following tools:

- `organize-ebooks.sh` is used to automatically organize folders with potentially huge amounts of unorganized ebooks. This is done by renaming the files with proper names and moving them to other folders:
  - By default it searches the supplied ebook files for [ISBNs](https://es.wikipedia.org/wiki/ISBN), downloads the book metadata (author, title, series, publication date, etc.) from online sources like Goodreads, Amazon and Google Books and renames the files according to a specified template.
  - If no ISBN is found, the script can optionally search for the ebooks online by their title and author, which are extracted from the filename or file metadata.
  - Optionally an additional file that contains all the gathered ebook metadata can be saved together with the renamed book so it can later be used for additional verification, indexing or processing.
  - Most ebook types are supported: `.epub`, `.mobi`, `.azw`, `.pdf`, `.djvu`, `.chm`, `.cbr`, `.cbz`, `.txt`, `.lit`, `.rtf`, `.doc`, `.docx`, `.pdb`, `.html`, `.fb2`, `.lrf`, `.odt`, `.prc` and potentially others. Even compressed ebooks in arbitrary archive files are supported. For example a `.zip`, `.rar` or other archive file that contains `.pdf` or `.html` chapters of an ebook can be organized without a problem.
  - Optical character recognition ([OCR](https://en.wikipedia.org/wiki/Optical_character_recognition)) can be automatically used for`.pdf`, `.djvu` and image files when no ISBNs were found in them by the fast and straightforward conversion to `.txt`. This is very useful for scanned ebooks that contain only images or were badly OCR-ed in the first place.
  - Files are checked for corruption (zero-filled files, broken pdfs, corrupt archive, etc.) and can optionally be moved to another folder.
  - Non-ebook documents, pamphlets and pamphlet-like documents like saved webpages, short pdfs, etc. can be detected and optionally moved to another folder.
- `interactive-organizer.sh` can be used to interactively and manually organize ebook files quickly. A good use case is the organization of the files that could no be automatically organized by the `organize-ebooks.sh` script. It can also be used to semi-automatically verify (and potentially reorganize) the automatically organized files by the above script:
  - If `organize-ebooks.sh` was called with `--keep-metadata`, the interactive organizer compares the old filename with the new one and shows suspicious differences between the two. Wrongly renamed files can be interactively renamed with this script.
  - There is a quick mode that skips files with names that contain the all of the original filename's tokens. Differences due to [diacritical marks](https://en.wikipedia.org/wiki/Diacritic) and truncated words are handled intelligently. A list of allowed differences can be configured and interactively updated while organizing the books.
  - The script can restore files back to their original location or move them to one of many different pre-configurable output folders.
  - Ebooks can be converted to `.txt` and shown with `less` directly in the current terminal or they can be opened with an external viewer without exiting from the interactive organization.

- `find-isbns.sh`
- `convert-to-txt.sh`
- `rename-calibre-library.sh`
- `split-into-folders.sh`

All of the tools use a library file `lib.sh` that has useful functions for building other ebook management scripts.

<!---
## Demo

TODO: screencast
--->

## Requirements and dependencies

You need recent versions of:
- GNU `bash`, `coreutils`, `awk`, `sed` and `grep`
- [Calibre](https://calibre-ebook.com/) for fetching metadata from online sources, conversion to txt (for ISBN searching) and ebook metadata extraction
- [p7zip](https://sourceforge.net/projects/p7zip/) for ISBN searching in ebooks that in archives
- [Tesseract](https://github.com/tesseract-ocr/tesseract) for running OCR on books; OCR is disabled by default and another engine can be configured if preferred
- Optionally [poppler](https://poppler.freedesktop.org), [catdoc](http://www.wagner.pp.ru/~vitus/software/catdoc/) and [DjVuLibre](http://djvu.sourceforge.net/) can be installed for faster than Calibre's conversion of .pdf, .doc and .djvu files respectively to .txt
- [xpath](https://metacpan.org/release/XML-XPath) for reading calibre's .opf metadata files in `rename-calibre-library.sh`

The scripts are only tested on linux, though they should work on any *nix system that has the needed dependencies. You can install everything needed with this command in Archlinux:
```bash
sudo pacman -S bash gawk sed grep calibre p7zip tesseract tesseract-data-eng perl-xml-xpath poppler catdoc djvulibre
```

*Note: you can probably get much better OCR results by using the unstable 4.0 version of Tesseract. It is present in the [AUR](https://aur.archlinux.org/packages/tesseract-git/) or you can easily make a package like [this](https://github.com/na--/custom-archlinux-packages/blob/master/tesseract-4-bundle-git/PKGBUILD) yourself*

## Installation

Just clone the repository or download a [release](https://github.com/na--/ebook-tools/releases) archive.


# Usage, options and configuration

## General options

TODO

## Script usage and options

### `organize-ebooks.sh`

TODO: description, options, examples, demo screencast

### `interactive-organizer.sh`

TODO: description, options, options inside the interactive session, demo screencast

### `find-isbns.sh`

TODO: description, options, example with fetch-ebook-metadata

### `convert-to-txt.sh`

TODO: description, options

### `rename-calibre-library.sh`

TODO: description, options, demo screencast

### `split-into-folders.sh`

TODO: description, options

# Security and safety

Please keep in mind that this is beta-quality software. To avoid data loss, make sure that you have a backup of any files you want to organize. You may also want to run the scripts with the `--dry-run`  or `--symlink-only` option the first time to make sure that they would do what you expect them to do.

Also keep in mind that these shell scripts parse and extract complex arbitrary media and archive files and pass them to other external programs written in memory-unsafe languages. This is not very safe and specially-crafted malicious ebook files can probably compromise your system when you use these scripts. If you are cautious and want to organize untrusted or unknown ebook files, use something like [QubesOS](https://www.qubes-os.org/) or at least do it in a separate VM/jail/container/etc.

# License

These scripts are licensed under the GNU General Public License v3.0. For more details see the `LICENSE` file in the repository.