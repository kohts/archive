PWD := $(shell pwd)

DOCBOOK_BASE = ${PWD}/../docbook
MASTER = main.docbook
DOCBOOOK = ${MASTER} prolog.docbook

HTML_BASE = ${PWD}/../html
HTML_CHUNKED_BASE = ${PWD}/../html-chunked
FO_BASE = ${PWD}/../fo
PDF = "${PWD}/../ladygina-kohts - cihc.pdf"
FONTS_BASE = ${PWD}/../fonts

all: html html-chunked fo

html: docbook-html-onechunk.xsl
	mkdir -p ${HTML_BASE}
	cd ${HTML_BASE} && ln -s ../images
	cd ${DOCBOOK_BASE} && xsltproc -o ${HTML_BASE}/index.html ${PWD}/docbook-html-onechunk.xsl ${MASTER}

html-chunked: docbook-html-chunked.xsl
	mkdir -p ${HTML_CHUNKED_BASE}
	cd ${HTML_CHUNKED_BASE} && ln -s ../images
	cd ${DOCBOOK_BASE} && xsltproc --stringparam 'base.dir' ${HTML_CHUNKED_BASE}/ ${PWD}/docbook-html-chunked.xsl ${MASTER}

fo: docbook-fo.xsl
	mkdir -p ${FO_BASE}
	cd ${DOCBOOK_BASE} && xsltproc -o ${FO_BASE}/index.fo ${PWD}/docbook-fo.xsl ${MASTER}

pdf:
	cd ${FONTS_BASE} && fop -c fop.xconf ${FO_BASE}/index.fo -pdf ${PDF}

clean-html:
	rm -rf ${HTML_BASE}

clean-html-chunked:
	rm -rf ${HTML_CHUNKED_BASE}

clean-pdf:
	rm -rf ${FO_BASE}
	rm -rf ${PDF}

clean: clean-html clean-html-chunked clean-pdf
