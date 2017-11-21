# eBook Tools

This is a collection of bash shell scripts for automated and semi-automated organization and management of large ebook collections. It contains the following tools:

- `organize-ebooks.sh` is used to automatically organize folders with potentially huge amounts of unorganized ebooks. This is done by renaming the files with proper names and moving them to other folders:
  - By default it [searches](#searching-for-isbns-in-files) the supplied ebook files for [ISBNs](https://es.wikipedia.org/wiki/ISBN), downloads the book metadata (author, title, series, publication date, etc.) from online sources like Goodreads, Amazon and Google Books and renames the files according to a specified template.
  - If no ISBN is found, the script can optionally search for the ebooks online by their title and author, which are extracted from the filename or file metadata.
  - Optionally an additional file that contains all the gathered ebook metadata can be saved together with the renamed book so it can later be used for additional verification, indexing or processing.
  - Most ebook types are supported: `.epub`, `.mobi`, `.azw`, `.pdf`, `.djvu`, `.chm`, `.cbr`, `.cbz`, `.txt`, `.lit`, `.rtf`, `.doc`, `.docx`, `.pdb`, `.html`, `.fb2`, `.lrf`, `.odt`, `.prc` and potentially others. Even compressed ebooks in arbitrary archive files are supported. For example a `.zip`, `.rar` or other archive file that contains the `.pdf` or `.html` chapters of an ebook can be organized without a problem.
  - Optical character recognition ([OCR](https://en.wikipedia.org/wiki/Optical_character_recognition)) can be automatically used for`.pdf`, `.djvu` and image files when no ISBNs were found in them by the fast and straightforward conversion to `.txt`. This is very useful for scanned ebooks that only contain images or were badly OCR-ed in the first place.
  - Files are checked for corruption (zero-filled files, broken pdfs, corrupt archive, etc.) and corrupt files can optionally be moved to another folder.
  - Non-ebook documents, pamphlets and pamphlet-like documents like saved webpages, short pdfs, etc. can also be detected and optionally moved to another folder.

  [![asciicast](https://asciinema.org/a/147116.png)](https://asciinema.org/a/147116)
- `interactive-organizer.sh` can be used to interactively and manually organize ebook files quickly. A good use case is the organization of the files that could not be automatically organized by the `organize-ebooks.sh` script. It can also be used to semi-automatically verify the organized files by the above script and potentially reorganize some of them:
  - If `organize-ebooks.sh` was called with `--keep-metadata`, the interactive organizer compares the old filename with the new one and shows suspicious differences between the two. Wrongly renamed files can be interactively renamed with this script.
  - There is a quick mode that skips files with names that contain the all of the original filename's tokens. Differences due to [diacritical marks](https://en.wikipedia.org/wiki/Diacritic) and truncated words are handled intelligently. A list of allowed differences can be configured and interactively updated while organizing the books.
  - The script can restore files back to their original location or move them to one of many different pre-configurable output folders.
  - Ebooks can be converted to `.txt` and shown with `less` directly in the current terminal or they can be opened with an external viewer without exiting from the interactive organization.
  - Books can be semi-automatically renamed by looking up their metadata (by ISBN or title) online.

- `find-isbns.sh` tries to find [valid ISBNs](https://en.wikipedia.org/wiki/International_Standard_Book_Number#Check_digits) inside a file or in `stdin` if no file was specified. Searching for ISBNs in files uses progressively more resource-intensive methods until some ISBNs are found, see the documentation [below](#searching-for-isbns-in-files) for more details.
- `convert-to-txt.sh` converts the supplied file to a text file. It can optionally also use OCR for `.pdf`, `.djvu` and image files.
- `rename-calibre-library.sh` traverses a calibre library folder and renames all the book files in it by reading their metadata from calibre's `metadata.opf` files.
- `split-into-folders.sh` splits the supplied ebook files (and the accompanying metadata files if present) into folders with consecutive names that each contain the specified number of files.

All of the tools use a library file `lib.sh` that has useful functions for building other ebook management scripts. More details for the different script options and parameters can be found in the [Usage, options and configuration](#usage-options-and-configuration) section.


# Installation and dependencies

There are two ways you can install and use the tools in this repository - [directly](#shell-scripts) or via [docker images](#docker).

Since all of the tools are shell scripts, you should be able to use them directly from source in most up-to-date GNU/Linux distributions, as long as you have the needed dependencies installed. They should also be usable on other *nix systems like OS X and *BSD if you have the **GNU** versions of the dependencies installed or in the [Windows Subsystem for Linux](https://en.wikipedia.org/wiki/Windows_Subsystem_for_Linux).

However, since non-linux systems are officially unsupported and may have unexpected issues, [Docker](https://en.wikipedia.org/wiki/Docker_%28software%29) containers are the preferred way to use the scripts in those systems. The docker images may also be easier to use than the bare scripts on non-GNU linux distributions or on older linux distributions like some LTS releases.

## Shell scripts

To install and use the bare shell scripts, follow these steps:
1. Install the dependencies below.
2. Make sure that your system has a [UTF-8 locale](https://www.shellhacks.com/linux-define-locale-language-settings/).
3. Clone the repository or download a [release archive](https://github.com/na--/ebook-tools/releases) and extract it.
4. For convenience, you may want to add the scripts folder to the `PATH` environment variable.

You need recent versions of:
- `file`, `bash` 4.3+ and ***GNU*** `coreutils`, `awk`, `sed` and `grep`.
- [calibre](https://calibre-ebook.com/) **2.84+** for fetching metadata from online sources, conversion to txt (for ISBN searching) and ebook metadata extraction.
- [p7zip](https://sourceforge.net/projects/p7zip/) for ISBN searching in ebooks that are in archives.
- [Tesseract](https://github.com/tesseract-ocr/tesseract) for running OCR on books - version 4 gives better results even though it's still in alpha. OCR is disabled by default and another engine can be configured if preferred.
- Optionally [poppler](https://poppler.freedesktop.org), [catdoc](http://www.wagner.pp.ru/~vitus/software/catdoc/) and [DjVuLibre](http://djvu.sourceforge.net/) can be installed for faster than calibre's conversion of `.pdf`, `.doc` and `.djvu` files respectively to `.txt`.
- Optionally the [Goodreads](https://www.mobileread.com/forums/showthread.php?t=130638) and [WorldCat xISBN](https://github.com/na--/calibre-worldcat-xisbn-metadata-plugin) calibre plugins can be installed for better metadata fetching.

The scripts are only tested on linux, though they should work on any *nix system that has the needed dependencies. You can install everything needed with this command in Arch Linux:
  ```bash
  pacman -S file bash coreutils gawk sed grep calibre p7zip tesseract tesseract-data-eng python2-lxml poppler catdoc djvulibre
  ```

*Note: you can probably get much better OCR results by using the unstable 4.0 version of Tesseract. It is present in the [AUR](https://aur.archlinux.org/packages/tesseract-git/) or you can easily make a package like [this](https://github.com/na--/custom-archlinux-packages/blob/master/tesseract-4-bundle-git/PKGBUILD) yourself.*

Here is how to install the packages on Debian (and Debian-based distributions like Ubuntu):
  ```bash
  apt-get install file bash coreutils gawk sed grep calibre p7zip-full tesseract-ocr tesseract-ocr-osd tesseract-ocr-eng python-lxml poppler-utils catdoc djvulibre-bin
  ```
*Keep in mind that a lot of debian-based distributions do not have up-to-date packages and the scripts need calibre with a version of at least 2.84.*


## Docker

The docker image includes all of the needed dependencies, even the extra calibre plugins. There is an automatically built [docker image](https://hub.docker.com/r/ebooktools/scripts/) in the Docker Hub. You can pull it locally with `docker pull ebooktools/scripts`. You can also easily build the docker image yourself: simply clone this repository (or download the latest [release archive](https://github.com/na--/ebook-tools/releases) and extract it) and then run `docker build -t ebooktools/scripts:latest .` in the folder.

Here are some Docker-specific usage details:
- You can start a docker container with all the ebook tools by running `docker run -it -v /some/host/folder:/unorganized-books ebooktools/scripts:latest`. This will run a bash prompt that has all of the dependencies installed and all of the scripts already in the `PATH` so all the usage instructions bellow should apply. The contents of the host folder `/some/host/folder` *(the path to the folder on your machine that you want to organize)* will be mounted as the `/unorganized-books` folder in the container.
- You can use the `-v` option of `docker run` multiple times to mount several host folders in the container.
- Consider using the `--rm` option of `docker run` to clean up your containers after you are done with them.
- The default container user has an UID of 1000, but you can change it with the `--user` option of `docker run` or by editing the `Dockerfile` and rebuilding it yourself.
- You can run specific scripts directly instead of the bash terminal like this: `docker run -it [other-docker-run-options] ebooktools/scripts:latest organize-ebooks.sh [ebook-tools-script-options]`

For more Docker details, read the [docker](https://docs.docker.com/) documentation and [`docker run`](https://docs.docker.com/engine/reference/run/) reference specifically.

# Usage, options and configuration

Scripts that work with multiple files **recursively scan the supplied folders** and **assume that one file is one ebook**. **Ebooks that consist of multiple files should be compressed in a single file** archive. The archive type does not matter, it can be `.zip`, `.rar`, `.tar`, `.7z` and others - all supported archive types by `7zip` are fine.

All of the options documented below can either be passed to the scripts via command-line parameters or via environment variables. Command-line parameters supersede environment variables. Most parameters are not required and if nothing is specified, the default value will be used.

## General options

All of these options are part of the common library and may affect some or all of the scripts.

#### General control flags:

* `-v`, `--verbose`; env. variable `VERBOSE`; default value `false`

  Whether debug messages will be displayed on `stderr`. Passing the parameter or changing `VERBOSE` to `true` and piping the `stderr` to a file is useful for debugging or keeping a record of exactly what happens without cluttering and overwhelming the normal execution output.
* `-d`, `--dry-run`; env. variable `DRY_RUN`; default value `false`

  If this is enabled, no file rename/move/symlink/etc. operations will actually be executed.
* `-sl`, `--symlink-only`; env. variable `SYMLINK_ONLY`; default value `false`

  Instead of moving the ebook files, create symbolic links to them.

* `-km`, `--keep-metadata`; env. variable `KEEP_METADATA`; default value `false`

  Do not delete the gathered metadata for the organized ebooks, instead save it in an accompanying file together with each renamed book. It is very useful for semi-automatic verification of the organized files with `interactive-organizer.sh` or for additional verification, indexing or processing at a later date.

#### Options related to extracting ISBNs from files and finding metadata by ISBN:

* `-i=<value>`, `--isbn-regex=<value>`; env. variable `ISBN_REGEX`; see default value in `lib.sh`

  This is the regular expression used to match ISBN-like numbers in the supplied books. It is matched with `grep -P`, so look-ahead and look-behind can be used. Also it is purposefully a bit loose (i.e. it can match some non-ISBN numbers), since the found numbers will be checked for validity. Due to unicode handling, the default value is too long for the readme, you can find it in `lib.sh`.
* `--isbn-direct-grep-files=<value>`; env. variable `ISBN_DIRECT_GREP_FILES`; default value `^text/(plain|xml|html)$`

  This is a regular expression that is matched against the MIME type of the searched files. Matching files are searched directly for ISBNs, without converting or OCR-ing them to `.txt` first.
* `--isbn-ignored-files=<value>`; env. variable `ISBN_IGNORED_FILES`; see default value in `lib.sh`

  This is a regular expression that is matched against the MIME type of the searched files. Matching files are not searched for ISBNs beyond their filename. The default value is a bit long because it tries to make the scripts ignore `.gif` and `.svg` images, audio, video and executable files and fonts, you can find it in `lib.sh`.

* `--reorder-files-for-grep=<value>`; env. variables `ISBN_GREP_REORDER_FILES`, `ISBN_GREP_RF_SCAN_FIRST`, `ISBN_GREP_RF_REVERSE_LAST`; default values `true`, `400`, `50`

  These options specify if and how we should reorder the ebook text before searching for ISBNs in it. By default, the first 400 lines of the text are searched as they are, then the last 50 are searched in reverse and finally the remainder in the middle. This reordering is done to improve the odds that the first found ISBNs in a book text actually belong to that book (ex. from the copyright section or the back cover), instead of being random ISBNs mentioned in the middle of the book. No part of the text is searched twice, even if these regions overlap. If you use the command-line option, the format for `<value>` is `false` to disable the functionality or `first_lines,last_lines` to enable it with the specified values.

* `-mfo=<value>`, `--metadata-fetch-order=<value>`; env. variables `ISBN_METADATA_FETCH_ORDER`; default value `Goodreads,Amazon.com,Google,ISBNDB,WorldCat xISBN,OZON.ru`

  This option allows you to specify the online metadata sources and order in which the scripts will try searching in them for books by their ISBN. The actual search is done by calibre's `fetch-ebook-metadata` command-line application, so any custom calibre metadata [plugins](https://plugins.calibre-ebook.com/) can also be used. To see the currently available options, run `fetch-ebook-metadata --help` and check the description for the `--allowed-plugin` option.

#### Options for [OCR](https://en.wikipedia.org/wiki/Optical_character_recognition):

* `-ocr=<value>`, `--ocr-enabled=<value>`; env. variable `OCR_ENABLED`; default value `false`

  Whether to enable OCR for `.pdf`, `.djvu` and image files. It is disabled by default and can be used differently in two scripts:
  - `organize-ebooks.sh` can use OCR for finding ISBNs in scanned books. Setting the value to `true` will cause it to use OCR for books that failed to be converted to `.txt` or were converted to empty files by the simple conversion tools (`ebook-convert`, `pdftotext`, `djvutxt`). Setting the value to `always` will cause it to use OCR even when the simple tools produced a non-empty result, if there were no ISBNs in it.
  - `convert-to-txt.sh` can use OCR for the conversion to `.txt`. Setting the value to `true` will cause it to use OCR for books that failed to be converted to `.txt` or were converted to empty files by the simple conversion tools. Setting it to `always` will cause it to first try OCR-ing the books before trying the simple conversion tools.

* `-ocrop=<value>`, `--ocr-only-first-last-pages=<value>`; env. variable `OCR_ONLY_FIRST_LAST_PAGES`; default value `7,3` (except for `convert-to-txt.sh` where it's `false`)

  Value `n,m` instructs the scripts to convert only the first `n` and last `m` pages when OCR-ing ebooks. This is done because OCR is a slow resource-intensive process and ISBN numbers are usually at the beginning or at the end of books. Setting the value to `false` disables this optimization and is the default for `convert-to-txt.sh`, where we probably want the whole book to be converted.

* `-ocrc=<value>`, `--ocr-command=<value>`; env. variable `OCR_COMMAND`; default value `tesseract_wrapper`

  This allows us to define a hook for using custom OCR settings or software. The default value is just a wrapper that allows us to use both tesseract 3 and 4 with some predefined settings. You can use a custom bash function or shell script - the first argument is the input image (books are OCR-ed page by page) and the second argument is the file you have to write the output text to.

#### Options related to extracting and searching for non-ISBN metadata:

* `--token-min-length=<value>`; env. variable `TOKEN_MIN_LENGTH`; default value `3`

  When files and file metadata are parsed, they are split into words (or more precisely, either alpha or numeric tokens) and ones shorter than this value are ignored. By default, single and two character number and words are ignored.
* `--tokens-to-ignore=<value>`; env. variable `TOKENS_TO_IGNORE`; complex default value

  A regular expression that is matched against the filename/author/title tokens and matching tokens are ignored. The default regular expression includes common words that probably hinder online metadata searching like `book`, `novel`, `series`, `volume` and others, as well as probable publication years like (so `1999` is ignored while `2033` is not). You can see it in `lib.sh`.
* `-owis=<value>`, `--organize-without-isbn-sources=<value>`; env. variable `ORGANIZE_WITHOUT_ISBN_SOURCES`; default value `Goodreads,Amazon.com,Google`

  This option allows you to specify the online metadata sources in which the scripts will try searching for books by non-ISBN metadata (i.e. author and title). The actual search is done by calibre's `fetch-ebook-metadata` command-line application, so any custom calibre metadata [plugins](https://plugins.calibre-ebook.com/) can also be used. To see the currently available options, run `fetch-ebook-metadata --help` and check the description for the `--allowed-plugin` option.

  In contrast to searching by ISBNs, searching by author and title is done concurrently in all of the allowed online metadata sources. The number of sources is smaller because some metadata sources can be searched only by ISBN or return many false-positives when searching by title and author.

#### Options related to the input and output files:

* `-oft=<value>`, `--output-filename-template=<value>`; env. variable `OUTPUT_FILENAME_TEMPLATE`; default value:
    ```bash
    "${d[AUTHORS]// & /, } - ${d[SERIES]:+[${d[SERIES]}] - }${d[TITLE]/:/ -}${d[PUBLISHED]:+ (${d[PUBLISHED]%%-*})}${d[ISBN]:+ [${d[ISBN]}]}.${d[EXT]}"
    ```
  This specifies how the filenames of the organized files will look. It is a bash string that is evaluated so it can be very [flexible](http://www.tldp.org/LDP/abs/html/parameter-substitution.html) (and also potentially unsafe). The book metadata is present in a hashmap with name `d` and uppercase keys. When changing this parameter, keep in mind that you have to either escape the `$` symbols or wrap everything in single quotes like so:
    ```bash
    -oft='"${d[TITLE]} by ${d[AUTHORS]}.${d[EXT]}"'
    ```

  By default the organized files start with the comma-separated author name(s), followed by the book series name and number in square brackets (if present), followed by the book title, the year of publication (if present), the ISBN(s) (if present) and the original extension. Here are are how output filenames using the default template look:
    ```text
    Cory Doctorow - [Little Brother #1] - Little Brother (2008) [0765319853].pdf
    Cory Doctorow - [Little Brother #2] - Homeland (2013) [9780765333698].epub
    Eliezer Yudkowsky - Harry Potter and the Methods of Rationality (2015).epub
    Lawrence Lessig - Remix - Making Art and Commerce Thrive in the Hybrid Economy (2008) [9781594201721].djvu
    Rick Falkvinge - Swarmwise (2013) [1463533152].pdf
    ```


* `-ome=<value>`, `--output-metadata-extension=<value>`; env. variable `OUTPUT_METADATA_EXTENSION`; default value `meta`

  If `KEEP_METADATA` is enabled, this is the extension of the additional metadata file that is saved next to each newly renamed file.


#### Miscellaneous options

* `-fsf=<value>`, `--file-sort-flags=<value>`; env. variable `FILE_SORT_FLAGS`; default value `()` (an empty bash array)

  A list with the [sort options](https://www.gnu.org/software/coreutils/manual/html_node/sort-invocation.html) that will be used every time multiple files are processed (i.e. in every script except `convert-to-txt.sh`).
* `--debug-prefix-length=<value>`; env. variable `DEBUG_PREFIX_LENGTH`; default value `40`

  The length of the debug prefix used by the some scripts in the output when `VERBOSE` mode is enabled.


## Script usage and options

### `organize-ebooks.sh [<OPTIONS>] folder-to-organize [...]`

#### Description

This is probably the most versatile script in the repository. It can automatically organize folders with huge quantities of unorganized ebook files. This is done by extracting ISBNs and/or metadata from the ebook files, downloading their full and hopefully correct metadata from online sources and auto-renaming the unorganized files with full and correct names and moving them to specified folders. Is supports virtually all ebook types, including ebooks in arbitrary or even nested archives (like the other scripts, it assumes that one file is one ebook, even if it's a huge archive). OCR can be used for scanned ebooks and corrupt ebooks and non-ebook documents (pamphlets) can be separated in specified folders. Most of the general options and flags above affect how this script operates, but there are also some specific options for it.

#### Specific options for organizing files

* `-cco`, `--corruption-check-only`; env. variable `CORRUPTION_CHECK_ONLY`; default value `false`

  Do not organize or rename files, just check them for corruption (ex. zero-filled files, corrupt archives or broken `.pdf` files). Useful with the `OUTPUT_FOLDER_CORRUPT` option.

* `--tested-archive-extensions=<value>`; env. variable `TESTED_ARCHIVE_EXTENSIONS`; default value `^(7z|bz2|chm|arj|cab|gz|tgz|gzip|zip|rar|xz|tar|epub|docx|odt|ods|cbr|cbz|maff|iso)$`

  A regular expression that specifies which file extensions will be tested with `7z t` for corruption.

* `-owi`, `--organize--without--isbn`; env. variable `ORGANIZE_WITHOUT_ISBN`; default value `false`

  Specify whether the script will try to organize ebooks if there were no ISBN found in the book or if no metadata was found online with the retrieved ISBNs. If enabled, the script will first try to use calibre's `ebook-meta` command-line tool to extract the author and title metadata from the ebook file. The script will try searching the online metadata sources (`ORGANIZE_WITHOUT_ISBN_SOURCES`) by the extracted author & title and just by title. If there is no useful metadata or nothing is found online, the script will try to use the filename for searching.

* `-wii=<value>`, `--without-isbn-ignore=<value>`; env. variable `WITHOUT_ISBN_IGNORE`; complex default value

  This is a regular expression that is matched against lowercase filenames. All files that do not contain ISBNs are matched against it and matching files are ignored by the script, even if `ORGANIZE_WITHOUT_ISBN` is `true`. The default value is calibrated to match most periodicals (magazines, newspapers, etc.) so the script can ignore them.

* `--pamphlet-included-files=<value>`; env. variable `PAMPHLET_INCLUDED_FILES`; default value `\.(png|jpg|jpeg|gif|bmp|svg|csv|pptx?)$`

  This is a regular expression that is matched against lowercase filenames. All files that do not contain ISBNs and do not match `WITHOUT_ISBN_IGNORE` are matched against it and matching files are considered pamphlets by default. They are moved to `OUTPUT_FOLDER_PAMPHLETS` if set, otherwise they are ignored.
* `--pamphlet-excluded-files=<value>`; env. variable `PAMPHLET_EXCLUDED_FILES`; default value `\.(chm|epub|cbr|cbz|mobi|lit|pdb)$`

  This is a regular expression that is matched against lowercase filenames. If files do not contain ISBNs and match against it, they are NOT considered as pamphlets, even if they have a small size or number of pages.
* `--pamphlet-max-pdf-pages=<value>`; env. variable `PAMPHLET_MAX_PDF_PAGES`; default value `50`

  `.pdf` files that do not contain valid ISBNs and have a lower number pages than this are considered pamplets/non-ebook documents.
* `--pamphlet-max-filesize-kb=<value>`; env. variable `PAMPHLET_MAX_FILESIZE_KB`; default value `250`

  Other files that do not contain valid ISBNs and are below this size in KBs are considered pamplets/non-ebook documents.

#### Output options

* `-o=<value>`, `--output-folder=<value>`; env. variable `OUTPUT_FOLDER`; **default value is the current working directory** (check with `pwd`)

  The folder where ebooks that were renamed based on the ISBN metadata will be moved to.
* `-ofu=<value>`, `--output-folder-uncertain=<value>`; env. variable `OUTPUT_FOLDER_UNCERTAIN`; empty default value

  If `ORGANIZE_WITHOUT_ISBN` is enabled, this is the folder to which all ebooks that were renamed based on non-ISBN metadata will be moved to.
* `-ofc=<value>`, `--output-folder-corrupt=<value>`; env. variable `OUTPUT_FOLDER_CORRUPT`; empty default value

  If specified, corrupt files will be moved to this folder.
* `-ofp=<value>`, `--output-folder-pamphlets=<value>`; env. variable `OUTPUT_FOLDER_PAMPHLETS`; empty default value

  Is specified, pamphlets will be moved to this folder.


### `interactive-organizer.sh [<OPTIONS>] folder-to-organize [...]`

#### Description
This script can be used to manually organize ebook files quickly. It can also be used to semi-automatically verify the ebooks organized by `organize-ebooks.sh` if the `KEEP_METADATA` option was enabled so the new filenames can be compared with the old ones.

#### Options

* `-o=<value>`, `--output-folder=<value>`; env. variable `OUTPUT_FOLDERS`; default value `()` (an empty bash array)

  You can use this argument multiple times (or use the array environment variable) to specify different folders to which you can quickly move ebook files. The first specified folder is the default.
* `-qm`, `--quick-mode`; env. variable `QUICK_MODE`; default value `false`

  This mode is useful when `organize-ebooks.sh` was called with `--keep-metadata`. Ebooks that contain all of the tokens from the old file name in the new one are directly moved to the default output folder.
* `-cmbd=<value>`, `--custom-move-base-dir=<value>`; env. variable `CUSTOM_MOVE_BASE_DIR`; empty default value

  This option is used to specify a base directory in whose sub-folders files can more easily be moved during the interactive session because of tab autocompletion.
* `-robd=<value>`, `--restore-original-base-dir=<value>`; env. variable `RESTORE_ORIGINAL_BASE_DIR`; empty default value

  If you want to enable the option of restoring files to their original folders (or at least with the same folder structure), set this as the base path.
* `-ddm=<value>`, `--diacritic-difference-masking=<value>`; env. variable `DIACRITIC_DIFFERENCE_MASKINGS`; complex default value

  Which differences due to accents and other diacritical marks to be ignored when comparing tokens in `QUICK_MODE` and the interactive interface. The default value handles some basic cases like allowing letters like `á`, `à`, `â` and others instead of `a` and the reverse when comparing the old and new files.
* `-mpw`, `--match-partial-words`; env. variable `MATCH_PARTIAL_WORDS`; default value `false`

  Whether tokens from the old filenames that partially match in the new filename to be accepted by `QUICK_MODE` and the interactive interface.

### `find-isbns.sh [<OPTIONS>] [filename]`

This script tries to find [valid ISBNs](https://en.wikipedia.org/wiki/International_Standard_Book_Number#Check_digits) inside a file or in `stdin` if no file is specified. Searching for ISBNs in files uses progressively more resource-intensive methods until some ISBNs are found, see the documentation [below](#searching-for-isbns-in-files) for more details.

Some global options affect this script (especially the ones [related to extracting ISBNs from files](#options-related-to-extracting-isbns-from-files-and-finding-metadata-by-isbn)), but the only script-specific option is:
* `-irs=<value>`, `--isbn-return-separator=<value>`; env. variable `ISBN_RET_SEPARATOR`; default value `$'\n'` (a new line)

  This specifies the separator that will be used when returning any found ISBNs.

### `convert-to-txt.sh [<OPTIONS>] filename`

 This script converts the supplied file to a text file. It can optionally also use OCR for `.pdf`, `.djvu` and image files. There are no local options, but a some of the global options affect this script's behavior a lot, especially the [OCR ones](#options-for-ocr).

### `rename-calibre-library.sh [<OPTIONS>] calibre-folder [...]`

This script traverses a calibre library folder and renames all the book files in it by reading their metadata from calibre's `metadata.opf` files.

* `-o=<value>`, `--output-folder=<value>`; env. variable `OUTPUT_FOLDER`; the default value is the current working directory (check with `pwd`)

  This is the output folder the renamed books will be moved to.
* `-sm=<value>`, `--save-metadata=<value>`; env. variable `SAVE_METADATA`; default value `recreate`

  This specifies whether metadata files will be saved together with the renamed ebooks. Value `opfcopy` just copies calibre's `metadata.opf` next to each renamed file with a `OUTPUT_METADATA_EXTENSION` extension, while `recreate` saves a metadata file that is similar to the one `organize-ebooks.sh` creates. Any other value disables this function.

### `split-into-folders.sh [<OPTIONS>] folder-with-books [...]`

This script recursively scans the supplied folders for files and splits the found files (and the accompanying metadata files if present) into folders with consecutive names that each contain the specified number of files.

* `-o=<value>`, `--output-folder=<value>`; env. variable `OUTPUT_FOLDER`; the default value is the current working directory (check with `pwd`)

  The output folder in which all the new consecutively named folders will be created.
* `-sn=<value>`, `--start-number=<value>`; env. variable `START_NUMBER`; default value `0`

  The number of the first folder.
* `-fp=<value>`, `--folder-pattern=<value>`; env. variable `FOLDER_PATTERN`; default value `%05d000`

  The `printf` format string that specifies the pattern with which new folders will be created. By default it creates folders like `00000000, 00001000, 00002000, ...`.
* `-fpf=<value>`, `--files-per-folder=<value>`; env. variable `FILES_PER_FOLDER`; default value `1000`

  How many files should be moved to each folder.

## Implementation details

### Searching for ISBNs in files

There are several different ways that a specific file can be searched for ISBN numbers. Each step requires progressively more "expensive" operations. If at some point ISBNs are found, they are returned or used without trying the remaining strategies. The regular expression used for matching ISBNs is in `ISBN_REGEX` (in `lib.sh`) and all matched numbers are verified for correct ISBN [check numbers](https://en.wikipedia.org/wiki/International_Standard_Book_Number#Check_digits). These are the steps:
1. Check the supplied file name for ISBNs (the path is ignored).
2. If the [MIME type](https://en.wikipedia.org/wiki/MIME) of the file matches `ISBN_DIRECT_GREP_FILES`, search the file contents directly for ISBNs. If the MIME type matches `ISBN_IGNORED_FILES`, the search stops with no results.
3. Check the file metadata from calibre's `ebook-meta` tool for ISBNs.
4. Try to extract the file as an archive with `7z`. If successful, recursively repeat all of these steps for all the extracted files.
5. If the file is not an archive, try to convert it to a `.txt` file. Use calibre's `ebook-convert` unless a faster alternative is present - `pdftotext` from `poppler` for `.pdf` files, `catdoc` for `.doc` files or `djvutxt` for `.djvu` files.
6. If OCR is enabled and the simple conversion to `.txt` fails or if its result is empty try OCR-ing the file. If the result is non-empty but does not contain ISBNs and `OCR_ENABLED` is set to `always`, run OCR as well.


# Limitations

- Automatic organization can be slow - all the scripts are synchronous and single-threaded and metadata lookup by ISBN is not done concurrently. This is intentional so that the execution can be easily traced and so that the online services are not hammered by requests. If you want to optimize the performance, run multiple copies of the script **on different folders**.

- The default setting for `ISBN_METADATA_FETCH_ORDER` includes two non-standard metadata sources: Goodreads and WorldCat xISBN. For best results, install the plugins ([1](https://www.mobileread.com/forums/showthread.php?t=130638), [2](https://github.com/na--/calibre-worldcat-xisbn-metadata-plugin)) for them in calibre and fine-tune the settings for metadata sources in the calibre GUI.

# Roadmap

- Add hooks for different actions, for example the ability to call an external script for organizing an ebook instead of directly renaming/symlinking it.
- Add options for modifying different metadata fields before renaming the files.
- Add an option to specify the input filename format for more precise non-ISBN metadata extraction.
- Expand tests - cover all functions and add some whole script tests.
- Add an Arch Linux AUR package.
- Improve the docker image so there are no permission problems on mounted folders and no user with hardcoded UID 1000 (maybe like [this](https://denibertovic.com/posts/handling-permissions-with-docker-volumes/)).
- Or just maybe rewrite everything in a more portable (or at least saner) language than bash...

# Security and safety

Please keep in mind that this is beta-quality software. To avoid data loss, make sure that you have a backup of any files you want to organize. You may also want to run the scripts with the `--dry-run`  or `--symlink-only` option the first time to make sure that they would do what you expect them to do.

Also keep in mind that these shell scripts parse and extract complex arbitrary media and archive files and pass them to other external programs written in memory-unsafe languages. This is not very safe and specially-crafted malicious ebook files can probably compromise your system when you use these scripts. If you are cautious and want to organize untrusted or unknown ebook files, use something like [QubesOS](https://www.qubes-os.org/) or at least do it in a separate VM/jail/container/etc.

# License

These scripts are licensed under the GNU General Public License v3.0. For more details see the `LICENSE` file in the repository.
