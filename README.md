# eBook Tools

This is a collection of bash shell scripts for semi-automated organization and management of large ebook collections. It contains the following tools:

<!--- TODO: short description of each tools --->

- `organize-ebooks.sh`
- `interactive-organizer.sh`
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

TODO: description, options, demo screencast

### `find-isbns.sh`

TODO: description, options, example with fetch-ebook-metadata

### `convert-to-txt.sh`

TODO: description, options

### `rename-calibre-library.sh`

TODO: description, options, demo screencast

### `split-into-folders.sh`

TODO: description, options

# License

These scripts are licensed under the GNU General Public License v3.0. For more details see the `LICENSE` file in the repository.