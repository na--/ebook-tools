FROM debian:sid-slim

ENTRYPOINT ["bash"]

RUN apt-get update && \
    apt-get --no-install-recommends -y install file less bash coreutils gawk sed grep calibre p7zip-full tesseract-ocr tesseract-ocr-osd tesseract-ocr-eng python-lxml poppler-utils catdoc djvulibre-bin locales curl ca-certificates && \
    rm -rf /var/lib/apt/lists/* && \
    localedef -i en_US -c -f UTF-8 en_US.UTF-8 && \
    useradd -mUs /usr/bin/bash -u 1000 user && \
    mkdir /ebook-tools && \
    chown user:user /ebook-tools

WORKDIR /ebook-tools

ENV LANG="en_US.UTF-8" PATH="${PATH}:/ebook-tools"

USER user

RUN curl 'https://www.mobileread.com/forums/attachment.php?attachmentid=163537' > goodreads.zip && \
    sha256sum 'goodreads.zip' | grep -q 'c44f88222017aaad0aa1a674e69f46b309198269c7f13ebd671ae942052d45a8' && \
    calibre-customize --add-plugin goodreads.zip && \
    rm goodreads.zip && \
    curl -L 'https://github.com/na--/calibre-worldcat-xisbn-metadata-plugin/archive/0.1.zip' > worldcat.zip && \
    sha256sum worldcat.zip | grep -q 'bedddcd736382baf95fed2c38698ded15b0d8fbd8085bacd1a4b4766e972dd4d' && \
    7z x worldcat.zip && \
    calibre-customize --build-plugin calibre-worldcat-xisbn-metadata-plugin-0.1/ && \
    rm -rf worldcat.zip calibre-worldcat-xisbn-metadata-plugin-0.1

COPY . /ebook-tools
