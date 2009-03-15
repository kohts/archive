PWD := $(shell pwd)

DOCBOOK_BASE = ${PWD}/../docbook
DOCBOOK = ${DOCBOOK_BASE}/*.docbook
MASTER = main.docbook

HTML_BASE = ${PWD}/../html
HTML_CHUNKED_BASE = ${PWD}/../html-chunked
FO_BASE = ${PWD}/../fo
PDF = "${PWD}/../ladygina-kohts - cihc.pdf"
FOP_BASE = ${PWD}/../fop

all: html html-chunked fo
all-html: html html-chunked

html: docbook-html-onechunk.xsl $(DOCBOOK)
	mkdir -p ${HTML_BASE}
	cd ${HTML_BASE} && ( if [ ! -h images ] ; then ln -s ../images ; fi )
	cd ${DOCBOOK_BASE} && xsltproc -o ${HTML_BASE}/index.html ${PWD}/docbook-html-onechunk.xsl ${MASTER}
	touch html

html-chunked: docbook-html-chunked.xsl $(DOCBOOK)
	mkdir -p ${HTML_CHUNKED_BASE}
	cd ${HTML_CHUNKED_BASE} && ( if [ ! -h images ] ; then ln -s ../images ; fi )
	cd ${DOCBOOK_BASE} && xsltproc --stringparam 'base.dir' ${HTML_CHUNKED_BASE}/ ${PWD}/docbook-html-chunked.xsl ${MASTER}
	touch html-chunked

fo: docbook-fo.xsl $(DOCBOOK)
	mkdir -p ${FO_BASE}
	cd ${DOCBOOK_BASE} && xsltproc -o ${FO_BASE}/index.fo ${PWD}/docbook-fo.xsl ${MASTER}
	touch fo

pdf: fo ${FOP_BASE}/fop.xconf
	cd ${FOP_BASE} && ( if [ ! -h images ] ; then ln -s ../images ; fi )
	cd ${FOP_BASE} && \
  export FOP_HYPHENATION_PATH=${FOP_BASE}/fop-hyph.jar && \
  fop -c fop.xconf ${FO_BASE}/index.fo -pdf ${PDF}
	touch pdf

clean-all-html: clean-html clean-html-chunked
clean-html:
	rm -rf ${HTML_BASE}
	rm -r html
clean-html-chunked:
	rm -rf ${HTML_CHUNKED_BASE}
	rm -r html-chunked

clean-all-pdf: clean-fo clean-pdf
clean-fo:
	rm -rf ${FO_BASE}
	rm -r fo
clean-pdf:
	rm -rf ${PDF}
	rm -r pdf

clean-status:
	rm -f html
	rm -f html-chunked
	rm -f fo
	rm -f pdf

.PHONY : clean
clean: clean-all-html clean-all-pdf
